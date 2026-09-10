# frozen_string_literal: true

# Fuime: admit a marketing-site waitlist address into the app.
#
# G1 (docs/fuime/TEEN_GROWTH_GAPS.md): warm leads sat in Redis and an admin
# CSV. The site promised "one email when it's your turn" and nothing sent it.
# This is that email — a login-ready link that uses the existing Login /
# ProcessLoginService machinery, not a second auth system.
#
# The link is `User.signed_id` (14 days, purpose :waitlist_invite). Clicking
# it proves inbox control the same way a 6-digit login code does;
# WaitlistInvitesController then marks the email factor on a Login and
# completes the session. New users still land on the name / phone /
# "I'm 13 or older" onboarding page. Cohort, if any, lives on the Redis
# stamp and is copied into the session on click.
#
# Cohort is optional and resolved through Fuime::Cohort.for_code, the same
# gate the application form uses. An expired or archived code is refused
# here so ops cannot stamp a dead event onto fifty inboxes.
module Fuime
  class WaitlistInviteService
    class Error < StandardError; end

    INVITE_EXPIRES_IN = 14.days
    SIGNED_ID_PURPOSE = :waitlist_invite
    MAX_BATCH = 25

    Result = Struct.new(:email, :user, :token, :cohort, keyword_init: true)

    def initialize(invited_by:, cohort_code: nil)
      @invited_by = invited_by
      @cohort_code = cohort_code.to_s.strip.presence
    end

    def invite!(email)
      normalized = email.to_s.strip.downcase
      raise Error, "email is blank" if normalized.blank?
      raise Error, "waitlist store is not configured" unless WaitlistRoster.configured?

      roster = WaitlistRoster.new
      raise Error, "#{normalized} is not on the waitlist" unless roster.member?(normalized)

      cohort = resolve_cohort
      user = User.create_with(creation_method: :waitlist).find_or_create_by!(email: normalized)
      token = self.class.generate_token(user:)

      begin
        WaitlistMailer.invite(user:, token:, cohort:).deliver_now
      rescue => e
        Rails.error.report(e, handled: true, context: { email: normalized })
        raise Error, "couldn't send the invite email. try again in a moment."
      end
      roster.mark_invited(normalized, invited_by: @invited_by.email, cohort_code: cohort&.code)

      Result.new(email: normalized, user:, token:, cohort:)
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    rescue WaitlistRoster::ReadFailed, WaitlistRoster::WriteFailed => e
      raise Error, e.message
    end

    # Oldest uninvited first. Partial success is returned rather than rolled
    # back — a Redis stamp happens after the mail is sent, so undoing a
    # successful invite would leave someone with a working link and no record.
    def invite_next!(count:)
      n = Integer(count, exception: false)
      raise Error, "invite this many must be between 1 and #{MAX_BATCH}" unless n&.between?(1, MAX_BATCH)
      raise Error, "waitlist store is not configured" unless WaitlistRoster.configured?

      pending = WaitlistRoster.uninvited(WaitlistRoster.new.fetch[:signups])
      raise Error, "no uninvited addresses on the waitlist" if pending.empty?

      invited = []
      errors = []
      pending.first(n).each do |signup|
        invited << invite!(signup.email)
      rescue Error => e
        errors << "#{signup.email}: #{e.message}"
      end

      { invited:, errors: }
    end

    def self.generate_token(user:)
      user.signed_id(expires_in: INVITE_EXPIRES_IN, purpose: SIGNED_ID_PURPOSE)
    end

    # => [user, cohort_code] or nil. Nil for expired, tampered, and unknown
    # users alike — the accept page does not distinguish them. Cohort lives
    # on the Redis stamp, not in the token, so the URL stays a signed_id.
    def self.verify_token(token)
      user = User.find_signed(token, purpose: SIGNED_ID_PURPOSE)
      return nil unless user

      [user, WaitlistRoster.invite_stamp(user.email)&.cohort_code]
    end

    private

    def resolve_cohort
      return nil if @cohort_code.blank?

      # Same gate as the application form: live (not archived / expired).
      # Full or auto_approve-off codes still attach; CohortAdmission decides
      # at submit whether they skip the human gates.
      cohort = Cohort.for_code(@cohort_code)
      raise Error, "that cohort code is not admitting anyone right now" if cohort.nil?

      cohort
    end

  end
end
