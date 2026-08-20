# frozen_string_literal: true

# Fuime: the POOLED-ACCOUNT SIMULATOR. Test mode only — see #simulator_mode?.
#
# Payments are taken on one pooled Fuime platform Stripe account; the paying
# business is identified by `fuime_event_id` in the Checkout/PaymentIntent
# metadata. That model is retired for production (CLAUDE.md L1): real payments
# are direct charges on a guardian-owned connected account and are recorded by
# Fuime::ConnectPaymentRecorder, which arrives on a different endpoint. This
# class survives because it exercises the ledger pipeline end to end without a
# connected account, which is useful in development and nowhere else.
#
# This handler feeds those payments into HCB's EXISTING ledger
# pipeline rather than reimplementing any of it (CLAUDE.md Rule 3):
#
#   RawPendingDonationTransaction   <- narrowest legitimate "money in" source
#     -> CanonicalPendingTransaction (creates HcbCode + ledger item on commit)
#       -> CanonicalPendingEventMapping (assigns it to the business)
#
# Donation is the correct analogue: an outside party sending money into an
# org. We do not touch the pipeline internals — only its public entry points.
#
# Idempotency: keyed on the Stripe object id. Replaying the same webhook does
# not double-post, which Stripe relies on since it retries on any non-2xx.
module Fuime
  class PaymentWebhookHandler
    class MissingEventError < StandardError; end
    # Raised only to carry a stack trace into error reporting — never to callers.
    # See #simulator_mode?.
    class LivePooledPaymentRefused < StandardError; end

    def initialize(event:)
      @stripe_event = event
    end

    def handle
      return nil unless simulator_mode?

      case @stripe_event.type
      # A Checkout payment fires BOTH checkout.session.completed and
      # payment_intent.succeeded, with different object ids. Keying idempotency
      # on the object id therefore posted the same payment to the ledger twice.
      # We handle payment_intent.succeeded only — it is the event that fires for
      # every payment (Checkout, Payment Link, or direct PaymentIntent) and
      # carries the settled amount.
      when "payment_intent.succeeded"
        record_payment(
          object: @stripe_event.data.object,
          amount_cents: @stripe_event.data.object.amount_received
        )
      when "checkout.session.completed"
        Rails.logger.info(
          "[Fuime] Ignoring checkout.session.completed for #{@stripe_event.data.object.id}; " \
          "the payment is recorded from payment_intent.succeeded"
        )
        nil
      # The failure half of the lifecycle. Without these, a refunded or disputed
      # payment stays on a teen's ledger as income and inflates the tax number
      # Fuime shows their family.
      when "charge.refunded"
        record_reversal(
          object: @stripe_event.data.object,
          amount_cents: @stripe_event.data.object.amount_refunded,
          kind: :refund
        )
      when "charge.dispute.created"
        dispute = @stripe_event.data.object
        record_reversal(
          object: dispute,
          amount_cents: dispute.amount,
          kind: :dispute,
          payment_intent_id: dispute.payment_intent
        )
      else
        Rails.logger.info("[Fuime] Ignoring webhook event: #{@stripe_event.type}")
        nil
      end
    end

    private

    # Fuime: this handler is a TEST-MODE SIMULATOR and nothing else.
    #
    # Everything below records a payment that landed in Fuime's OWN platform
    # balance and then credits a venture's ledger for it — which is precisely the
    # pooled-account model CLAUDE.md L1 retires. In production that is unlicensed
    # money transmission (18 U.S.C. § 1960, criminal) and aggregation outside
    # Connect, which also breaches Stripe's ToS. The production path is
    # Fuime::ConnectPaymentRecorder: direct charges on the guardian-owned account,
    # where Fuime takes an application fee and never touches the funds.
    #
    # The code is kept rather than deleted because it is the only end-to-end
    # exercise of the ledger pipeline that does not require a connected account,
    # which makes it genuinely useful in development. Keeping it *safe* means it
    # must be structurally impossible to run against real money — hence this
    # guard, rather than a comment asking future readers not to.
    #
    # Keyed on the EVENT's `livemode`, not on StripeService.mode. The event is the
    # authoritative statement about the money that actually moved; a
    # misconfiguration that pointed live webhooks at this endpoint while the app
    # believed it was in test mode is exactly the scenario worth failing closed on,
    # and consulting our own config would agree with the misconfiguration.
    def simulator_mode?
      # Fuime: under merchant-of-record this class is no longer a simulator — it
      # is the PRIMARY money-in path, and live events are exactly what it is for.
      #
      # The refusal below exists because money arriving in Fuime's platform balance
      # used to mean Fuime was holding a stranger's funds. Once Fuime is the legal
      # seller, the identical event means Fuime received its own revenue from its
      # own sale. Same balance, same webhook, different legal object — which is why
      # the gate is the flag rather than anything observable in the payload.
      #
      # FEATURE_MERCHANT_OF_RECORD cannot be set without the boot guard's counsel
      # memo (config/initializers/fuime_safety_check.rb check 6), so this cannot be
      # the thing that quietly re-enables pooled custody.
      return true if ::Fuime::Features.merchant_of_record?

      return true unless @stripe_event.respond_to?(:livemode)
      return true unless @stripe_event.livemode

      # Loud, because a live event reaching here means real customer money is
      # sitting in Fuime's platform balance and something upstream is badly
      # misconfigured. Refusing to write the ledger line does not un-take the
      # money — it stops Fuime from also representing itself as its custodian.
      Rails.error.report(
        LivePooledPaymentRefused.new(
          "Refused to record live-mode event #{@stripe_event.id} (#{@stripe_event.type}) through the " \
          "pooled-account simulator. Pooled custody is money transmission (CLAUDE.md L1); live payments " \
          "must arrive on the Connect endpoint as direct charges."
        ),
        handled: true,
        context: { stripe_event_id: @stripe_event.id, stripe_event_type: @stripe_event.type }
      )

      false
    end

    def record_payment(object:, amount_cents:)
      metadata = object.metadata
      event_id = metadata && metadata["fuime_event_id"]
      return nil if event_id.blank?
      return nil if amount_cents.to_i <= 0

      event = ::Event.find_by(id: event_id)
      unless event
        Rails.logger.warn("[Fuime] Webhook references unknown event_id=#{event_id}")
        return nil
      end

      # One ledger line per Stripe object, no matter how often Stripe retries.
      transaction_key = ::Fuime::VentureLedger.payment_key(object.id)

      existing = ::Fuime::VentureLedger.find_row(transaction_key)
      if existing
        Rails.logger.info("[Fuime] Webhook #{object.id} already recorded; skipping")
        return existing
      end

      ActiveRecord::Base.transaction do
        raw = ::RawPendingDonationTransaction.create!(
          donation_transaction_id: transaction_key,
          amount_cents: amount_cents.to_i,
          date_posted: Time.at(object.created).to_date
        )

        cpt = ::CanonicalPendingTransaction.create!(
          date: raw.date,
          memo: memo_for(object, event),
          amount_cents: raw.amount_cents,
          raw_pending_donation_transaction_id: raw.id,
          # NOT fronted. In HCB, `fronted` means the platform advances the org
          # spendable credit against money that hasn't settled — a balance-sheet
          # decision backed by Hack Club's reserves. Fuime has no reserves, and
          # Stripe settlement is T+2 with refund and chargeback risk after that,
          # so fronting here would let a teen spend money Fuime does not hold.
          fronted: false
        )

        ::CanonicalPendingEventMapping.create!(
          canonical_pending_transaction_id: cpt.id,
          event_id: event.id
        )

        Rails.logger.info(
          "[Fuime] Recorded payment #{object.id} for #{event.name}: " \
          "$#{amount_cents.to_i / 100.0} (cpt=#{cpt.id})"
        )

        record_platform_fee(object:, event:, gross_cents: raw.amount_cents)

        raw
      end
    end

    # Fuime's cut, posted as its own negative ledger line.
    #
    # The fee was previously only written into Stripe metadata, so a business's
    # ledger showed the gross payment and the teen's net was never reduced —
    # which also overstated the income the Tax Tracker reported to their family.
    # Posting it as a visible line means the ledger reconciles to what actually
    # lands, and the teen can see exactly what Fuime charged.
    #
    # Runs inside the caller's transaction: a payment and its fee post together
    # or not at all.
    def record_platform_fee(object:, event:, gross_cents:)
      fee_cents = platform_fee_cents(object, gross_cents, event)
      return nil if fee_cents <= 0

      fee_key = ::Fuime::VentureLedger.fee_key(object.id)
      existing = ::Fuime::VentureLedger.find_row(fee_key)
      return existing if existing

      raw = ::RawPendingDonationTransaction.create!(
        donation_transaction_id: fee_key,
        amount_cents: -fee_cents,
        date_posted: Time.at(object.created).to_date
      )

      cpt = ::CanonicalPendingTransaction.create!(
        date: raw.date,
        memo: fee_memo_for(event, fee_cents, gross_cents),
        amount_cents: raw.amount_cents,
        raw_pending_donation_transaction_id: raw.id,
        fronted: false
      )

      ::CanonicalPendingEventMapping.create!(
        canonical_pending_transaction_id: cpt.id,
        event_id: event.id
      )

      Rails.logger.info(
        "[Fuime] Recorded platform fee for #{event.name}: -$#{fee_cents / 100.0} (cpt=#{cpt.id})"
      )

      raw
    end

    # What the fee line says it charged — which must be what it actually charged.
    #
    # This read Fuime::PaymentLinkService::FUIME_PLATFORM_FEE_PERCENT, the HEADLINE
    # rate, on every venture. That constant is prose for the FAQ and the Terms; it
    # knows nothing about the venture's plan. A venture on Free (7%) was charged
    # $1.75 on a $25 sale and shown a line reading "Fuime platform fee (5%)" — the
    # right money under a wrong label, which is the more corrosive half, because the
    # label is what a teenager checks the maths against.
    #
    # Exactly the bug #platform_fee_cents was already fixed for once: the amount was
    # moved onto Event#fuime_fee_cents_on and the label was left behind. So this
    # reads the same plan the money came from.
    #
    # The floor gets its own wording rather than a computed percentage. When
    # Event::Plan::MINIMUM_FEE_CENTS bites, the effective rate on a $5 sale is 10%,
    # and printing "10.0%" would describe a rate Fuime does not charge and cannot be
    # found on any pricing page. Naming the minimum is both true and answers the
    # question the reader actually has.
    def fee_memo_for(event, fee_cents, gross_cents)
      percentage_fee = (gross_cents * event.revenue_fee).round

      if fee_cents > percentage_fee
        "Fuime platform fee (#{ActionController::Base.helpers.number_to_currency(fee_cents / 100.0)} minimum)"
      else
        # Event#revenue_fee, not plan.revenue_fee_label: inside a school programme
        # the school's terms govern and the student sub org's own plan says
        # something different. Same resolution the money used. See Event#billing_plan.
        "Fuime platform fee (#{ActionController::Base.helpers.number_to_percentage(event.revenue_fee * 100, precision: 1)})"
      end
    end

    # Prefer the fee Stripe recorded at checkout, so the ledger matches what the
    # payer was quoted even if the rate changes later. Fall back to computing it
    # for payments created before the fee was stamped into metadata.
    def platform_fee_cents(object, gross_cents, event)
      from_metadata = object.metadata && object.metadata["fuime_fee_cents"]
      fee = from_metadata.presence&.to_i
      fee = nil if fee&.negative?

      # Fuime: the fallback must agree with what the checkout actually charged, so
      # it goes through the same definition rather than re-deriving the number
      # from the headline percentage. That old fallback read
      # FUIME_PLATFORM_FEE_PERCENT — the *prose* rate — which ignored the
      # venture's plan entirely and knew nothing about the minimum, so a payment
      # arriving without fee metadata was billed at a different rate from one that
      # had it. See Event#fuime_fee_cents_on.
      fee ||= event.fuime_fee_cents_on(gross_cents)

      # Never let a bad metadata value claw back more than the payment.
      [fee, gross_cents].min
    end

    # Post a negative ledger line reversing a payment that was refunded or
    # disputed. Booked against the same business as the original payment, which
    # we locate via the originating payment intent.
    #
    # Idempotent on the reversal's own key, so Stripe retries — and the several
    # refund events a partially-refunded charge can emit — don't stack up.
    def record_reversal(object:, amount_cents:, kind:, payment_intent_id: nil)
      amount_cents = amount_cents.to_i
      return nil if amount_cents <= 0

      intent_id = payment_intent_id.presence || (object.respond_to?(:payment_intent) ? object.payment_intent : nil)
      if intent_id.blank?
        Rails.logger.warn("[Fuime] #{kind} #{object.id} has no payment_intent; cannot map to a business")
        return nil
      end

      original = ::Fuime::VentureLedger.find_row(::Fuime::VentureLedger.payment_key(intent_id))
      unless original
        Rails.logger.warn("[Fuime] #{kind} #{object.id} references unrecorded payment #{intent_id}; ignoring")
        return nil
      end

      event = event_for_raw(original)
      unless event
        Rails.logger.warn("[Fuime] #{kind} #{object.id}: original payment #{intent_id} has no event mapping")
        return nil
      end

      # A charge can be refunded in several increments; key on the cumulative
      # refunded amount so each distinct total posts exactly once. The intent id
      # is embedded so all reversals of one payment can be summed by prefix.
      reversal_key = ::Fuime::VentureLedger.reversal_key(
        intent_id:, kind:, object_id: object.id, amount_cents:
      )

      existing = ::Fuime::VentureLedger.find_row(reversal_key)
      if existing
        Rails.logger.info("[Fuime] #{kind} #{reversal_key} already recorded; skipping")
        return existing
      end

      # Reverse only what hasn't already been reversed, so a refund following a
      # partial refund doesn't claw back more than the original payment.
      already_reversed = reversed_cents_for(intent_id)
      outstanding = original.amount_cents - already_reversed
      reversal_cents = [amount_cents, outstanding].min

      if reversal_cents <= 0
        Rails.logger.info("[Fuime] #{kind} #{object.id}: payment #{intent_id} already fully reversed")
        return nil
      end

      ActiveRecord::Base.transaction do
        raw = ::RawPendingDonationTransaction.create!(
          donation_transaction_id: reversal_key,
          amount_cents: -reversal_cents,
          date_posted: Time.at(object.created).to_date
        )

        cpt = ::CanonicalPendingTransaction.create!(
          date: raw.date,
          memo: kind == :dispute ? "Disputed payment (chargeback)" : "Refunded payment",
          amount_cents: raw.amount_cents,
          raw_pending_donation_transaction_id: raw.id,
          fronted: false
        )

        ::CanonicalPendingEventMapping.create!(
          canonical_pending_transaction_id: cpt.id,
          event_id: event.id
        )

        Rails.logger.info(
          "[Fuime] Recorded #{kind} #{object.id} for #{event.name}: " \
          "-$#{reversal_cents / 100.0} (cpt=#{cpt.id})"
        )

        refund_platform_fee(
          object:, event:, intent_id:,
          reversal_cents:, gross_cents: original.amount_cents
        )

        raw
      end
    end

    # Give back Fuime's cut in proportion to what was refunded or charged back.
    #
    # Without this the fee is charged on money the business never kept: a fully
    # refunded payment would leave the teen's ledger negative by the fee, and a
    # chargeback would have them pay Fuime for the privilege of being defrauded.
    def refund_platform_fee(object:, event:, intent_id:, reversal_cents:, gross_cents:)
      return nil if gross_cents <= 0

      fee_raw = ::Fuime::VentureLedger.find_row(::Fuime::VentureLedger.fee_key(intent_id))
      return nil if fee_raw.nil?

      original_fee = fee_raw.amount_cents.abs
      return nil if original_fee <= 0

      # Proportional to this increment, then capped by whatever fee is left so
      # incremental refunds can never rebate more than was charged.
      rebate = (original_fee * reversal_cents / gross_cents.to_f).round
      already_rebated = fee_rebated_cents_for(intent_id)
      rebate = [rebate, original_fee - already_rebated].min
      return nil if rebate <= 0

      rebate_key = ::Fuime::VentureLedger.fee_rebate_key(
        intent_id:, object_id: object.id, reversal_cents:
      )
      existing = ::Fuime::VentureLedger.find_row(rebate_key)
      return existing if existing

      raw = ::RawPendingDonationTransaction.create!(
        donation_transaction_id: rebate_key,
        amount_cents: rebate,
        date_posted: Time.at(object.created).to_date
      )

      cpt = ::CanonicalPendingTransaction.create!(
        date: raw.date,
        memo: "Fuime platform fee refunded",
        amount_cents: raw.amount_cents,
        raw_pending_donation_transaction_id: raw.id,
        fronted: false
      )

      ::CanonicalPendingEventMapping.create!(
        canonical_pending_transaction_id: cpt.id,
        event_id: event.id
      )

      Rails.logger.info(
        "[Fuime] Refunded platform fee for #{event.name}: +$#{rebate / 100.0} (cpt=#{cpt.id})"
      )

      raw
    end

    # ── Ledger keys are NOT defined here ────────────────────────────────────
    #
    # They all delegate to Fuime::VentureLedger, which is the single owner of the
    # key scheme. That matters for a specific reason: the Connect money-in path
    # (Fuime::ConnectPaymentRecorder) posts with the SAME keys on purpose, so that
    # if a Stripe webhook endpoint is ever misconfigured to receive both platform
    # and connected-account events, a payment delivered twice produces one ledger
    # line instead of two. If this class kept its own copies of these strings, one
    # of them could be changed without the other and that protection would
    # disappear silently. See VentureLedger's header.
    #
    # The posting bodies above are still duplicated between the two handlers. That
    # is accepted rather than overlooked: this class serves the pooled-account
    # simulator, which L1 retires to test mode permanently, so it is code with a
    # scheduled end. The keys are shared because getting them wrong double-posts
    # real money; the boilerplate is not, because it is going away.
    def fee_rebate_key_prefix(intent_id)
      ::Fuime::VentureLedger.fee_rebate_key_prefix(intent_id)
    end

    def fee_rebated_cents_for(intent_id)
      ::Fuime::VentureLedger.fee_rebated_cents_for(intent_id)
    end

    def reversal_key_prefix(intent_id)
      ::Fuime::VentureLedger.reversal_key_prefix(intent_id)
    end

    # Total already reversed against a payment intent, as a positive number.
    def reversed_cents_for(intent_id)
      ::Fuime::VentureLedger.reversed_cents_for(intent_id)
    end

    def event_for_raw(raw)
      ::Fuime::VentureLedger.event_for_row(raw)
    end

    def memo_for(object, event)
      description = object.respond_to?(:description) ? object.description : nil
      description.presence || "Payment to #{event.name}"
    end

  end
end
