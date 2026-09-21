# frozen_string_literal: true

# == Schema Information
#
# Table name: fuime_incidents
#
#  id                  :bigint           not null, primary key
#  ack_token           :string           not null
#  acknowledged_at     :datetime
#  auto_resolved       :boolean          default(FALSE), not null
#  check_name          :string           not null
#  detail              :jsonb            not null
#  escalation_position :integer          default(0), not null
#  key                 :string           not null
#  last_paged_at       :datetime
#  opened_at           :datetime         not null
#  page_count          :integer          default(0), not null
#  resolved_at         :datetime
#  severity            :integer          default(1), not null
#  status              :integer          default(0), not null
#  title               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  acknowledged_by_id  :bigint
#
# Indexes
#
#  index_fuime_incidents_on_ack_token                          (ack_token) UNIQUE
#  index_fuime_incidents_on_acknowledged_by_id                 (acknowledged_by_id)
#  index_fuime_incidents_on_status_and_severity_and_opened_at  (status,severity,opened_at)
#  index_fuime_incidents_one_open_per_key                      (key) UNIQUE WHERE (resolved_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (acknowledged_by_id => users.id)
#
module Fuime
  # Fuime: something is broken, and whether anybody has picked it up yet.
  #
  # See the migration header for why an incident is a row rather than an email.
  # This class holds the two decisions that make the difference between a pager
  # and a mailing list: when to page AGAIN, and when to page somebody ELSE.
  #
  # ── Severity is about consequence, not about volume ────────────────────────
  #
  #   sev1 — money or the law is moving the wrong way, or the product is down
  #          for everybody. Rings a phone at 3am. The test for putting a check
  #          here is whether you would genuinely want to be woken, because a
  #          sev1 that turns out not to be worth waking for is how the next real
  #          one gets slept through.
  #   sev2 — one venture or one pipeline is broken, and every hour it stays
  #          broken costs somebody something. Pages, but respects the night.
  #   sev3 — a queue is growing or a deadline is approaching. Tomorrow's digest.
  #
  # ── Why re-detection does not re-page immediately ──────────────────────────
  #
  # A check on a 5-minute schedule that pages on every run is a denial of
  # service against its own reader. `page_due?` throttles to the severity's
  # repeat interval, and stops entirely once somebody has acknowledged — because
  # after acknowledgement the alert has done its whole job, and continuing to
  # send is how the acknowledger learns to silence the channel instead.
  class Incident < ApplicationRecord
    self.table_name = "fuime_incidents"

    belongs_to :acknowledged_by, class_name: "User", optional: true
    has_many :notifications, class_name: "Fuime::IncidentNotification", dependent: :destroy,
                             inverse_of: :incident

    enum :severity, { sev3: 0, sev2: 1, sev1: 2 }, prefix: true
    enum :status, { open: 0, acknowledged: 1, resolved: 2 }, prefix: true

    validates :key, :check_name, :title, :opened_at, :ack_token, presence: true

    scope :live, -> { where(resolved_at: nil) }
    scope :unacknowledged, -> { live.where(acknowledged_at: nil) }
    scope :by_urgency, -> { order(severity: :desc, opened_at: :asc) }

    before_validation :assign_ack_token, on: :create

    # How long an unacknowledged incident waits before it pages again, and
    # before it climbs to the next person on the roster.
    #
    # Ten minutes for a sev1 is deliberately short: the failure this subsystem
    # was built for is a page that silently did not arrive, and a second attempt
    # ten minutes later is the cheapest possible cover for it. An hour for a
    # sev2 assumes somebody is awake and busy, not asleep.
    REPAGE_AFTER = { "sev1" => 10.minutes, "sev2" => 1.hour, "sev3" => 1.day }.freeze
    ESCALATE_AFTER = { "sev1" => 15.minutes, "sev2" => 2.hours, "sev3" => nil }.freeze

    def self.repage_interval(severity) = REPAGE_AFTER.fetch(severity.to_s, 1.hour)

    # Raise or refresh the one open incident for this problem.
    #
    # The uniqueness is enforced by a partial index rather than by this method
    # alone, because two sweep runs overlapping is normal (a slow check, a
    # worker restart) and the loser of that race must not create a duplicate
    # incident that then pages independently forever.
    def self.raise!(key:, check_name:, title:, severity:, detail: {})
      now = Time.current

      existing = live.find_by(key:)
      if existing
        # An escalating problem re-raises the severity but never lowers it: a
        # check that flaps between sev2 and sev1 should be treated as the sev1
        # it reached until a human closes it.
        new_severity = [severities.fetch(existing.severity), severities.fetch(severity.to_s)].max
        existing.update!(title:, detail:, severity: severities.key(new_severity))
        return existing
      end

      create!(key:, check_name:, title:, severity:, detail:, opened_at: now, status: :open)
    rescue ActiveRecord::RecordNotUnique
      # Lost the race with a concurrent sweep. The other run's row is the one
      # that counts; returning it keeps the caller's contract.
      live.find_by(key:)
    end

    # The detector stopped seeing the problem.
    #
    # Auto-resolution is recorded as such rather than looking like a human
    # closing it, because a check that opens and auto-resolves repeatedly is
    # itself a bug — usually a threshold set at the noise floor — and it is
    # invisible if the rows are indistinguishable.
    def self.auto_resolve!(key:)
      incident = live.find_by(key:)
      return nil unless incident

      incident.update!(status: :resolved, resolved_at: Time.current, auto_resolved: true)
      incident
    end

    # ── What a page is allowed to say ──────────────────────────────────────
    #
    # A page travels over a third party — a push relay, a carrier, a voice
    # network — and lands on a lock screen. Fuime's incidents name ventures run
    # by minors and carry amounts, so the rule is that the page says what BROKE
    # and never who it happened to. The detail lives behind the admin login, one
    # tap away.
    #
    # `private:` is not "is this sensitive" — everything here is. It is "is the
    # relay authenticated", which Fuime::Oncall::Responder#push_private? answers.
    # An ntfy topic with no token is world-readable by anyone who guesses the
    # name, so on that channel even the title is withheld and the page is reduced
    # to a severity and a link.
    def page_title(private: false)
      return "Fuime #{severity.upcase}" unless private

      "#{severity.upcase} · #{title}"
    end

    def page_text(private: false)
      lines = []
      lines << title if private
      lines << "Opened #{opened_at.utc.strftime('%H:%M UTC')} · #{check_name.humanize}"
      # The ack link is a capability: anyone holding it can silence this
      # incident's repaging. That is an acceptable trade on an authenticated
      # relay and not on a public one, so it is withheld exactly where the title
      # is — and it can only ever acknowledge, never resolve.
      lines << (private ? ack_url : console_url)
      lines.join("\n")
    end

    # Read aloud by Twilio. Written to be HEARD: no ids, no URLs, no
    # punctuation a speech engine stumbles over, and the consequence before the
    # cause because the first half-second of a 3am call is always lost.
    def page_spoken
      "This is a Fuime severity #{severity.delete_prefix('sev')} alert. " \
        "#{title.gsub(/[^a-zA-Z0-9 .,]/, ' ').squeeze(' ')}. " \
        "Check the Fuime admin on call page."
    end

    def ack_url
      routes.oncall_ack_url(token: ack_token, **url_options)
    rescue
      console_url
    end

    def console_url
      routes.oncall_admin_index_url(**url_options)
    rescue
      "https://#{url_options[:host]}/admin/oncall"
    end

    def sev1? = severity_sev1?
    def sev2? = severity_sev2?
    def sev3? = severity_sev3?

    def acknowledge!(user: nil)
      return false unless status_open?

      update!(status: :acknowledged, acknowledged_at: Time.current, acknowledged_by: user)
    end

    def resolve!(user: nil)
      return false if status_resolved?

      update!(status: :resolved, resolved_at: Time.current,
              acknowledged_by: acknowledged_by || user, auto_resolved: false)
    end

    def live? = resolved_at.nil?

    # Whether the pager should send now.
    #
    # Acknowledgement stops paging outright. That is the contract that makes
    # acknowledging worth doing: if a page keeps arriving after you have said "I
    # am on it", the only remaining way to stop it is to mute the channel, and a
    # muted channel is what the next incident arrives on.
    def page_due?(now: Time.current)
      return false unless live?
      return false unless status_open?
      return true if last_paged_at.nil?

      last_paged_at <= now - self.class.repage_interval(severity)
    end

    # Which rung of the roster this should be reaching now. Position 1 until the
    # escalation window passes unacknowledged, then one rung further per window.
    def target_escalation_position(now: Time.current)
      window = ESCALATE_AFTER[severity]
      return 1 if window.nil? || opened_at.nil?

      1 + ((now - opened_at) / window).floor.clamp(0, 5)
    end

    def age = Time.current - opened_at

    private

    def routes = Rails.application.routes.url_helpers

    # Falls back to the production host rather than raising: a page that cannot
    # build a URL should still be a page. A missing host is a configuration bug
    # to fix in daylight, not a reason to swallow a sev-1 at 3am.
    def url_options
      defaults = Rails.application.routes.default_url_options
      { host: defaults[:host].presence || "fuime.com", protocol: defaults[:protocol].presence || "https" }
    end

    def assign_ack_token
      self.ack_token ||= SecureRandom.urlsafe_base64(24)
    end

  end
end
