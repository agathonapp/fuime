# frozen_string_literal: true

# Fuime: where an operator gets a key for their own software.
#
# The UI half of Fuime::ApiKey. Without this the API exists but is reachable only
# from a Rails console, which means it exists for Fuime and not for the teenager
# it was built for.
#
# ── Who may mint one ────────────────────────────────────────────────────────
#
# The operator, through `manage_offers?` — the same authority as setting a price,
# and deliberately the same. A key is the power to name an amount and ask a
# customer for it, which is pricing by another route; giving it a weaker gate
# than the pricing form would be a way around that form. It is NOT the payout
# gate: a key cannot move money, so the guardian's authority is not engaged.
#
# The guardian still sees every key and every link it made, the same way they see
# every offer and every sale. Visibility without control, exactly as on the
# offers screen.
module Fuime
  class ApiKeysController < ApplicationController
    before_action :set_event

    def index
      authorize @event, :offers?

      @keys = @event.fuime_api_keys.live.recent_first
      @can_manage = policy(@event).manage_offers?
      # The links programs have made, so an operator can see what their own
      # software has been asking people for. This is the screen where a runaway
      # agent becomes visible, so it is not hidden behind the key list.
      @links = @event.fuime_offers.unlisted.made_by_program
                     .includes(:fuime_api_key).order(created_at: :desc).limit(50)

      # Shown once, immediately after minting, and never again — it lives in the
      # flash rather than on the record because the record does not have it. See
      # Fuime::ApiKey.mint!.
      @fresh_key = flash[:fuime_fresh_api_key]
    end

    def create
      authorize @event, :manage_offers?

      if @event.fuime_api_keys.live.count >= ::Fuime::ApiKey::MAX_LIVE_KEYS
        return redirect_to fuime_api_keys_path(event_slug: @event.slug),
                           alert: "You already have #{::Fuime::ApiKey::MAX_LIVE_KEYS} keys. " \
                                  "Revoke one you're not using first."
      end

      _key, plaintext = ::Fuime::ApiKey.mint!(
        event: @event,
        created_by: current_user,
        name: params[:name]
      )

      redirect_to fuime_api_keys_path(event_slug: @event.slug),
                  flash: {
                    fuime_fresh_api_key: plaintext,
                    success: "Key created. Copy it now — you won't be able to see it again."
                  }
    end

    def destroy
      authorize @event, :manage_offers?

      key = @event.fuime_api_keys.live.find(params[:id])
      key.revoke!

      # The links it made are deliberately left alone. Revoking a key means "this
      # program can no longer ask for money"; it does not mean the $45 a customer
      # was already sent should stop working. Taking a link down is its own
      # action, on the link.
      redirect_to fuime_api_keys_path(event_slug: @event.slug),
                  notice: "#{key.name} revoked. Anything using it will stop working now."
    end

    private

    def set_event
      @event = Event.friendly.find(params[:event_slug])
    end

  end
end
