# frozen_string_literal: true

# Fuime: a key a venture hands to a program, so software can sell for it.
#
# See CreateFuimeApiKeys for why this is not `ApiToken`, why the plaintext is
# never stored, and why the authority is deliberately narrow (ask for money;
# never move it, never read the ledger, never leave this venture).
#
# == Schema Information
#
# Table name: fuime_api_keys
#
#  id               :bigint           not null, primary key
#  last4            :string           not null
#  last_used_at     :datetime
#  name             :string           not null
#  request_count    :integer          default(0), not null
#  revoked_at       :datetime
#  token_bidx       :string           not null
#  token_ciphertext :text             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  created_by_id    :bigint           not null
#  event_id         :bigint           not null
#
# Indexes
#
#  index_fuime_api_keys_on_created_by_id  (created_by_id)
#  index_fuime_api_keys_on_event_id       (event_id)
#  index_fuime_api_keys_on_token_bidx     (token_bidx) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (event_id => events.id)
#
module Fuime
  class ApiKey < ApplicationRecord
    self.table_name = "fuime_api_keys"

    belongs_to :event
    belongs_to :created_by, class_name: "User"
    has_many :offers, class_name: "Fuime::Offer", foreign_key: :fuime_api_key_id,
                      inverse_of: :fuime_api_key, dependent: :nullify

    has_encrypted :token
    blind_index :token

    # `fuime_sk_` — "secret key", and prefixed for the reason Stripe and GitHub
    # prefix theirs: secret scanners match on the prefix, so a key pasted into a
    # public repository can be found and killed by machine before a person
    # notices. A bare random string is unscannable and therefore silently leaks.
    PREFIX = "fuime_sk_"
    TOKEN_BYTES = 32

    MAX_NAME_LENGTH = 60
    # Per venture. Not a resource limit — three keys is already more integrations
    # than a teenager has, and an account accumulating dozens is either confused
    # or compromised. The cap makes the second case visible while it is still
    # small.
    MAX_LIVE_KEYS = 10

    validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }

    scope :live, -> { where(revoked_at: nil) }
    scope :recent_first, -> { order(created_at: :desc) }

    # Mint a key, returning the record AND the one and only copy of its plaintext.
    #
    # Two values, deliberately, rather than stashing the plaintext on the
    # instance: an attribute that sometimes holds a live secret is an attribute
    # that eventually reaches a log line, an error report or a serializer. The
    # caller has to hold it consciously and hand it straight to the view that
    # shows it once.
    def self.mint!(event:, created_by:, name:)
      plaintext = "#{PREFIX}#{SecureRandom.urlsafe_base64(TOKEN_BYTES)}"

      key = create!(
        event:,
        created_by:,
        name: name.to_s.strip.presence || "API key",
        token: plaintext,
        last4: plaintext.last(4)
      )

      [key, plaintext]
    end

    # The venture this key speaks for, or nil.
    #
    # Nil for anything wrong — unknown key, revoked key, malformed key — and
    # never an exception carrying which of those it was. A caller distinguishing
    # "no such key" from "revoked key" hands an attacker a probe that says when
    # they have guessed a real one.
    #
    # Compared through the blind index rather than by decrypting the table, so
    # this stays one indexed lookup however many keys exist.
    def self.authenticate(presented)
      presented = presented.to_s.strip
      return nil unless presented.start_with?(PREFIX)

      key = live.find_by(token: presented)
      return nil if key.nil?

      key.record_use!
      key
    end

    def revoked?
      revoked_at.present?
    end

    def revoke!
      update!(revoked_at: Time.current) unless revoked?
    end

    # "fuime_sk_••••a9f2"
    def display
      "#{PREFIX}••••#{last4}"
    end

    # Usage stamped without validations or timestamps.
    #
    # `update_columns` because this runs on every authenticated request and must
    # not fire callbacks, touch `updated_at` (which would make "changed" and
    # "used" indistinguishable), or fail a request because an unrelated
    # validation on the row started failing.
    def record_use!
      update_columns(last_used_at: Time.current, request_count: request_count + 1)
    end

  end
end
