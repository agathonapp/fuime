# frozen_string_literal: true

# Fuime: ask Stripe to pull money from a school's bank account into that school's own
# Stripe balance, so Fuime::SchoolAwardService has something to award.
#
# ── ⚠️ UNVERIFIED, and read this before trusting the button ─────────────────
#
# Whether a connected account created with `controller.losses.payments = "stripe"`
# (the `:payments_only` profile — every account Fuime has ever made) may create
# top-ups through the API is **documentation-derived and has never been run against
# Stripe**, in any mode. Stripe's top-up documentation is written for platform
# balances; applying it to a Stripe-liability connected account is an inference.
#
# This repo has been wrong about exactly this class of assumption twice — see the
# bugs list in docs/fuime/STRIPE_PASS.md, both of which were invisible until code
# actually ran. Verify with `rake fuime:stripe_pass:fund` before telling a school this
# works.
#
# **If Stripe refuses, the feature still works.** A business office can add funds from
# the Stripe Dashboard, Stripe fires `topup.succeeded`, and Fuime::ConnectFundingRecorder
# posts the ledger credit exactly the same way. This service is the convenience; the
# recorder is the feature. That is why the failure mode here is a clear message rather
# than a broken page.
#
# ── Why Fuime is not in this flow ───────────────────────────────────────────
#
# The API call is made with `stripe_account:` set to the school's connected account, so
# the debit is from the school's bank to the school's Stripe balance. Fuime's platform
# balance is not a party to it. This is the difference between a top-up and a
# Stripe::Transfer, and it is the whole reason the latter is never used (L1).
module Fuime
  class SchoolFundingService
    class Error < StandardError; end
    class NotASchoolVenture < Error; end
    class AccountNotReady < Error; end
    class StripeRefused < Error; end

    # Stripe's own floor for a top-up, and a sane one: an ACH pull costs the same to
    # process whether it moves $1 or $10,000.
    MINIMUM_CENTS = 1_00

    def initialize(event:)
      @event = event
    end

    # Returns the SchoolFunding row. Its status stays "pending" until Stripe says
    # otherwise — this never marks its own work succeeded. See SchoolFunding.
    def fund!(amount_cents:, requested_by:, description: nil)
      amount_cents = amount_cents.to_i

      unless @event.institutionally_sponsored?
        raise NotASchoolVenture,
              "#{@event.name} isn't a school programme, so it can't be funded by top-up."
      end

      if amount_cents < MINIMUM_CENTS
        raise Error, "The smallest top-up is #{ActionController::Base.helpers.number_to_currency(MINIMUM_CENTS / 100.0)}."
      end

      # Event#payment_account IS the StripeConnectedAccount, not an event owning one.
      # Deliberately the school's OWN account rather than the resolved-up-the-tree
      # one: a school is the top of its tree and owns its account outright, and
      # topping up an ancestor's balance from a descendant's page would put money
      # somewhere the person clicking did not intend.
      account = @event.stripe_connected_account
      if account.blank? || account.stripe_id.blank?
        raise AccountNotReady,
              "#{@event.name} has no Stripe account yet, so there is nowhere to add funds."
      end

      funding = ::SchoolFunding.create!(
        event: @event,
        amount_cents:,
        requested_by:,
        status: "pending"
      )

      topup = create_topup!(account:, amount_cents:, description:, funding:)

      # Claim the Stripe id immediately. If the webhook beats this update — which it
      # can, Stripe delivers fast — Fuime::ConnectFundingRecorder will have created a
      # SECOND row keyed on the topup id, because this one had no id to find. Resolved
      # by deleting the duplicate rather than by leaving two rows for one movement.
      existing = ::SchoolFunding.where(stripe_topup_id: topup.id).where.not(id: funding.id).first
      if existing.present?
        funding.update!(stripe_topup_id: nil)
        existing.update!(requested_by: existing.requested_by || requested_by)
        funding.destroy!
        return existing
      end

      funding.update!(stripe_topup_id: topup.id)
      funding
    end

    private

    def create_topup!(account:, amount_cents:, description:, funding:)
      Stripe::Topup.create(
        {
          amount: amount_cents,
          currency: "usd",
          description: description.presence || "Fuime programme funding",
          # Shows on the school's own bank statement. Stripe truncates at 22
          # characters, so this is deliberately short rather than descriptive.
          statement_descriptor: "FUIME FUNDING"
        },
        { stripe_account: account.stripe_id }
      )
    rescue Stripe::StripeError => e
      # Keep the row. A business office asking "why did nothing happen?" deserves a
      # record with the reason on it, and deleting the evidence of a failed attempt is
      # how a support conversation becomes archaeology.
      funding.update!(
        status: "failed",
        failure_code: e.try(:code),
        failure_message: e.message
      )

      Rails.logger.error(
        "[Fuime] top-up refused for school #{@event.id} (#{account.stripe_id}): #{e.message}"
      )

      raise StripeRefused,
            "Stripe would not start this top-up: #{e.message}. " \
            "A school administrator can add funds directly from the Stripe Dashboard instead — " \
            "Fuime will record it either way."
    end

  end
end
