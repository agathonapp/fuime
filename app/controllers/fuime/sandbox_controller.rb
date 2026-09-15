# frozen_string_literal: true

# Fuime: Sandbox Mode — where a founder rehearses a sale before a real customer
# ever clicks one.
#
# ── What problem this solves ────────────────────────────────────────────────
#
# Before this, the first time a teenager saw their own checkout work was when a
# real customer paid — or, more often, did not, because something about the link
# was wrong and nobody found out. There was no way to answer "does my pay link
# actually work?" short of charging your own card.
#
# So: switch Sandbox Mode on, open your real storefront, press Buy. Nothing
# reaches Stripe, nothing reaches the ledger, and you see the exact screens your
# customer will see. Fuime::CheckoutsController#sandbox_checkout? is where the
# diversion happens; Fuime::TestSale is what it writes.
#
# ── The thing to keep true ──────────────────────────────────────────────────
#
# Sandbox Mode changes what the OPERATOR's click does and nothing else. A
# customer's click is identical whether this is on or off. That is why the page
# below does not warn anyone that they are losing sales, and why nothing here
# needs to auto-expire: leaving it on is harmless, and a feature that punishes
# you for forgetting to turn it off is a feature teenagers will not use.
module Fuime
  class SandboxController < ApplicationController
    before_action :set_event

    def show
      authorize @event, :sandbox?

      @can_manage = policy(@event).manage_sandbox?
      # Whether a rehearsal can reach Stripe at all. False in an environment
      # given only live keys — the page says so rather than offering a button
      # whose click would fall through to the real payment path.
      @stripe_ready = ::StripeService.sandbox_available?
      @test_sales = @event.fuime_test_sales.includes(:user, :offer).newest_first.limit(50)
      @test_sale_count = @event.fuime_test_sales.count
      @published_offer = @event.fuime_offers.published.in_operator_order.first
    end

    def enable
      authorize @event, :manage_sandbox?

      @event.update_column(:sandbox_mode, true)
      redirect_to fuime_sandbox_path(event_slug: @event.slug),
                  flash: { success: "Sandbox Mode is on. Open your storefront and buy something — you won't be charged." }
    end

    def disable
      authorize @event, :manage_sandbox?

      @event.update_column(:sandbox_mode, false)
      redirect_to fuime_sandbox_path(event_slug: @event.slug),
                  flash: { success: "Sandbox Mode is off. Your Buy button now takes real payments again." }
    end

    # Throw the rehearsals away. `delete_all` rather than `destroy_all` because
    # there is nothing to cascade and nothing to audit — see Fuime::TestSale.
    def clear
      authorize @event, :manage_sandbox?

      count = @event.fuime_test_sales.delete_all
      redirect_to fuime_sandbox_path(event_slug: @event.slug),
                  flash: { success: "Cleared #{count} test #{"purchase".pluralize(count)}." }
    end

    private

    # `update_column` in #enable / #disable, not `update`: Event carries
    # validations about contracts, plans and slugs that a venture mid-onboarding
    # may not satisfy yet, and a founder who cannot save an unrelated field must
    # still be able to rehearse their checkout. The column is a boolean this
    # controller sets to a literal, so there is nothing here for a validation to
    # protect.
    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

  end
end
