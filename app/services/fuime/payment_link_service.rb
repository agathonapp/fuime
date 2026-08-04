# frozen_string_literal: true

# Fuime: Generate Stripe Checkout sessions for a venture.
#
# ── What changed, and why it matters ─────────────────────────────────────────
#
# This used to create the session on Fuime's OWN Stripe account, with the
# venture's id in metadata so the ledger could work out whose money it was. That
# is the pooled-account model, and in production it is money transmission:
# Fuime would be accepting a stranger's payment, holding it, and paying it out
# later (CLAUDE.md L1, docs/fuime/LEGAL_RESEARCH.md §3).
#
# Now the session is created as a DIRECT CHARGE on the venture's own connected
# account, which the guardian owns. Consequences, all deliberate:
#
#   * the money never touches a Fuime balance — Stripe settles it to the family;
#   * the venture, not Fuime, is the merchant of record;
#   * refunds and disputes debit the venture's balance, not Fuime's, which is the
#     only charge type consistent with Stripe carrying negative-balance liability;
#   * Fuime's cut arrives as `application_fee_amount` rather than as a separate
#     ledger line Fuime has to compute and reconcile itself.
#
# The fee now reads `event.plan.revenue_fee` instead of a hardcoded 4%. The old
# constant silently ignored the plan, so a venture on the Founders plan — whose
# entire promise is 0% — was still being charged.
module Fuime
  class PaymentLinkService
    class NotAcceptingPayments < StandardError; end

    # The headline fee, for copy that is not scoped to a venture — the FAQ, the
    # Terms — and as a fallback when a webhook arrives without fee metadata.
    #
    # Derived from the plan fallback rather than restated, so there is one place
    # the number lives. It used to be a hardcoded `4` that every caller treated as
    # authoritative, including the per-payment fee calculation, which is how a
    # Founders-plan venture (0%) was charged anyway. Anything venture-specific
    # must read `event.plan.revenue_fee`; this is for prose only.
    FUIME_PLATFORM_FEE_PERCENT = (Event::Plan::FALLBACK_REVENUE_FEE * 100).round

    def initialize(event:, amount_cents:, description:)
      @event = event
      @amount_cents = amount_cents
      @description = description
    end

    def create_checkout_session(success_url:, cancel_url:)
      account = @event.stripe_connected_account

      # Belt and braces with Fuime::CheckoutsController, which checks the same
      # thing before it gets here. Without a connected account there is no
      # destination for the money, and creating the session on the platform
      # account instead is exactly the behaviour being removed.
      unless account&.ready_for_payments?
        raise NotAcceptingPayments,
              "Event #{@event.id} has no Stripe account ready to accept payments"
      end

      Stripe::Checkout::Session.create(
        {
          mode: "payment",
          line_items: [
            {
              price_data: {
                currency: "usd",
                product_data: {
                  name: @description,
                  description: "Payment to #{@event.name} via Fuime",
                },
                unit_amount: @amount_cents,
              },
              quantity: 1,
            },
          ],
          # Retained even though allocation no longer depends on it: connected
          # account events arrive with `event.account`, which is the reliable
          # join, but the metadata keeps a payment traceable to a venture from the
          # Stripe dashboard side and is what the existing ledger handler reads.
          metadata: metadata,
          payment_intent_data: {
            metadata: metadata,
            # Fuime's platform fee. Nested here because Checkout Sessions have no
            # top-level `application_fee_amount`. Omitted entirely when the fee is
            # zero — Stripe rejects a zero application fee, and a Founders-plan
            # venture legitimately has one.
            **(fee_cents.positive? ? { application_fee_amount: fee_cents } : {}),
            statement_descriptor_suffix: statement_descriptor,
          },
          success_url: success_url,
          cancel_url: cancel_url,
        },
        # `stripe_account` is what makes this a direct charge on the venture's
        # account rather than a charge on Fuime's. `api_key` is explicit because
        # the global Stripe.api_key is derived from Rails.env, not STRIPE_MODE
        # (see Fuime::ConnectOnboardingService for why that distinction bites).
        { api_key: StripeService.secret_key, stripe_account: account.stripe_id }
      )
    end

    # NOTE: `create_payment_link` used to live here — a Product + Price +
    # PaymentLink trio built on Fuime's own platform account, with no callers
    # anywhere in the app or specs. It was removed rather than migrated: dead code
    # that quietly creates a pooled-account payment link is a landmine, because the
    # first person to reach for "we already have a payment-link helper" would
    # reintroduce exactly the custody model this file just stopped doing. Rebuild
    # it against `stripe_account:` if reusable links are ever wanted.

    private

    # Reads the venture's plan rather than a constant, so a fee waiver actually
    # waives the fee. Rounded to whole cents; Stripe caps the application fee at
    # the captured amount anyway, but computing something larger would be a bug
    # worth not writing.
    def fee_cents
      @fee_cents ||= (@amount_cents * @event.plan.revenue_fee).round
    end

    def metadata
      {
        fuime_event_id: @event.id,
        fuime_event_name: @event.name,
        fuime_fee_cents: fee_cents,
      }
    end

    def statement_descriptor
      # Max 22 chars for statement descriptor
      "FUIME #{@event.short_name || @event.name}"[0..21].strip
    end

  end
end
