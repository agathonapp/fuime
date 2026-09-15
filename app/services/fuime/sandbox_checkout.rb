# frozen_string_literal: true

# Fuime: the return leg of a rehearsal — turning a completed Stripe test-mode
# Checkout Session into a Fuime::TestSale.
#
# ── Why this reads the session instead of waiting for a webhook ──────────────
#
# Stripe scopes webhook endpoints per mode: test-mode events go to endpoints
# registered in test mode, with their own signing secret. Fuime has one
# mode-agnostic `FUIME_STRIPE_WEBHOOK_SECRET`, so a test-mode delivery would
# fail signature verification against it — and adding a second endpoint and
# secret is a Stripe Dashboard change plus a deploy, for a code path whose whole
# job is to be visible immediately to a teenager.
#
# So the success URL carries `{CHECKOUT_SESSION_ID}` and we ask Stripe directly
# what happened. The founder is standing right there having just paid; there is
# nobody to be asynchronous for. Stripe is still the source of truth — this
# reads the session back rather than trusting the redirect.
#
# A webhook could be added later for robustness (a founder who closes the tab
# before redirecting). It would post through this same class.
#
# ── The two gates ───────────────────────────────────────────────────────────
#
# `livemode == false` is the important one, and it is why the real-Stripe
# version of Sandbox Mode is SAFER than the mock it replaced. It is Stripe's own
# assertion that no money moved, made by the payment processor rather than by
# our UI state — so even a bug that sent a live session id here could not turn a
# real payment into a discarded test row.
#
# `payment_status` guards the other direction: a session that was created but
# never paid is not a rehearsal anybody completed.
module Fuime
  class SandboxCheckout
    Result = Struct.new(:test_sale, :status, keyword_init: true) do
      def recorded? = status == :recorded
      def already? = status == :already_recorded
    end

    def initialize(event:, user:, session_id:)
      @event = event
      @user = user
      @session_id = session_id.to_s
    end

    # Returns a Result, never raises. This runs while rendering a page a founder
    # is already looking at, and a Stripe hiccup on the way back from a
    # successful test payment must degrade to "we couldn't confirm that" rather
    # than to an error page.
    def record!
      return Result.new(status: :ignored) if @session_id.blank?

      existing = ::Fuime::TestSale.find_by(stripe_checkout_session_id: @session_id)
      return Result.new(test_sale: existing, status: :already_recorded) if existing

      session = retrieve_session
      return Result.new(status: :unavailable) if session.nil?

      # Stripe says no money moved. Anything else is not ours to record here.
      return Result.new(status: :refused) unless session.livemode == false
      return Result.new(status: :unpaid) unless session.payment_status == "paid"
      # The session belongs to the venture it claims to. Without this, a session
      # id from one rehearsal could be replayed against another venture's page.
      return Result.new(status: :refused) unless session.metadata&.[]("fuime_event_id").to_s == @event.id.to_s

      Result.new(test_sale: create_test_sale!(session), status: :recorded)
    rescue ActiveRecord::RecordNotUnique
      # Two tabs, one session. The unique index is the arbiter; whoever lost
      # still gets to see the row.
      Result.new(test_sale: ::Fuime::TestSale.find_by(stripe_checkout_session_id: @session_id),
                 status: :already_recorded)
    rescue => e
      Rails.error.report(e)
      Result.new(status: :unavailable)
    end

    private

    def retrieve_session
      ::Stripe::Checkout::Session.retrieve(
        @session_id,
        { api_key: ::StripeService.sandbox_secret_key }
      )
    rescue ::Stripe::StripeError => e
      Rails.logger.warn("[Fuime] Could not retrieve sandbox session #{@session_id}: #{e.message}")
      nil
    end

    def create_test_sale!(session)
      offer_id = session.metadata&.[]("fuime_offer_id").presence
      ::Fuime::TestSale.create!(
        event: @event,
        user: @user,
        fuime_offer_id: offer_id,
        stripe_checkout_session_id: @session_id,
        amount_cents: session.amount_total,
        description: session.metadata&.[]("fuime_offer_name").presence ||
          "Payment to #{@event.name}",
        occurred_at: Time.current
      )
    end

  end
end
