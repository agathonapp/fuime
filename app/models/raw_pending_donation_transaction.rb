# frozen_string_literal: true

# == Schema Information
#
# Table name: raw_pending_donation_transactions
#
#  id                      :bigint           not null, primary key
#  amount_cents            :integer
#  date_posted             :date
#  state                   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  donation_transaction_id :string
#
class RawPendingDonationTransaction < ApplicationRecord
  monetize :amount_cents

  def date
    date_posted
  end

  def memo
    fuime_payment? ? "Payment" : "Donation"
  end

  # Fuime: Stripe Checkout payments recorded by Fuime::PaymentWebhookHandler.
  def fuime_payment?
    donation_transaction_id.to_s.start_with?("fuime_")
  end

  def likely_event_id
    # Fuime: rows created from Stripe Checkout payments use a synthetic
    # "fuime_<stripe_id>" key and have no Donation record — they are mapped to
    # their event directly by Fuime::PaymentWebhookHandler. Guard against the
    # nil so the shared pipeline doesn't raise on them.
    @likely_event_id ||= donation&.event&.id
  end

  def donation
    @donation ||= ::Donation.find_by(id: donation_transaction_id)
  end

end
