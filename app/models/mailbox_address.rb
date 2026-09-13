# frozen_string_literal: true

# == Schema Information
#
# Table name: mailbox_addresses
#
#  id           :bigint           not null, primary key
#  aasm_state   :string           not null
#  address      :string           not null
#  discarded_at :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_mailbox_addresses_on_address  (address) UNIQUE
#  index_mailbox_addresses_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class MailboxAddress < ApplicationRecord
  DISCRIMINATOR_LENGTH = 4 # currently, 4 is enough to avoid most collisions, however this can be increased later

  # Fuime: this was hardcoded to "hcb.gg" — Hack Club's domain.
  #
  # Every receipt-forwarding address Fuime generated therefore ended in someone
  # else's domain, which is not a branding slip: mail a founder sends to it
  # reaches Hack Club's ingress, not Fuime's, so the receipts either vanish or
  # land in a third party's inbox. Prime Directive 4.
  #
  # Fuime has no inbound mail domain yet (no MX, and `config.action_mailbox`
  # points at a SendGrid ingress nobody has pointed at us), so the default is
  # nil and `.configured?` is false — the UI hides the feature rather than
  # advertising an address that silently drops mail. Set FUIME_MAILBOX_DOMAIN
  # once inbound mail actually resolves here and it comes back on its own.
  LEGACY_EMAIL_DOMAIN = "hcb.gg"

  # Generation and validation keep working exactly as upstream when the env var
  # is unset. That split matters: `EMAIL_DOMAIN` feeds `VALIDATION_REGEX`, which
  # `ApplicationMailbox.routing` interpolates at class-definition time, so making
  # it nil would change inbound routing and refuse to mint any address at all —
  # which is what an earlier version of this change did, breaking two mailbox
  # specs. Whether Fuime *has* an inbound domain is a UI question, not a storage
  # one, so only `.configured?` answers it and only the views consult it.
  EMAIL_DOMAIN = ENV.fetch("FUIME_MAILBOX_DOMAIN", LEGACY_EMAIL_DOMAIN)

  # True only when Fuime has been given a domain it actually receives mail on.
  # The views hide the whole feature when this is false, so no founder is ever
  # handed an address that silently drops their receipts.
  def self.configured?
    ENV["FUIME_MAILBOX_DOMAIN"].present?
  end

  # Existing rows were minted under the legacy domain and must keep validating,
  # or any later save of an inherited address fails on a format check for a
  # domain it predates. New addresses are generated under EMAIL_DOMAIN only.
  ACCEPTED_EMAIL_DOMAINS = [EMAIL_DOMAIN, LEGACY_EMAIL_DOMAIN].compact.freeze

  VALIDATION_REGEX = /\A[a-z]+\.\d{#{DISCRIMINATOR_LENGTH}}@(?:#{ACCEPTED_EMAIL_DOMAINS.map { |d| Regexp.escape(d) }.join("|")})\z/

  belongs_to :user
  validates :user, uniqueness: { scope: [:aasm_state, :user_id, :discarded_at], message: "can only have one mailbox address previewed/active at a time" }

  validates :address, presence: true, uniqueness: true
  validates_email_format_of :address, if: :address_changed?
  validates :address, format: { with: VALIDATION_REGEX, message: "must conform to correct format" }

  before_validation do
    self.address = self.class.generate_address if self.address.blank?
  end

  include AASM

  aasm timestamps: true do
    state :previewed, initial: true
    state :activated, :discarded

    event :mark_activated do
      transitions from: :previewed, to: :activated
    end

    event :mark_discarded do
      transitions from: :activated, to: :discarded
    end
  end

  def identifier
    address.split("@")&.first
  end

  def domain
    address.split("@")&.last
  end

  def self.generate_address
    high_end = 10**DISCRIMINATOR_LENGTH - 1
    discriminator = rand(1..high_end).to_s.rjust(DISCRIMINATOR_LENGTH, "0")

    animal = Faker::Creature::Animal.name.downcase.gsub(/[^a-z]/, "")

    identifier = "#{animal}.#{discriminator}"
    address = "#{identifier}@#{EMAIL_DOMAIN}"

    return self.generate_address if self.exists?(address:)

    address
  end

end
