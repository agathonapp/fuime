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
      authorize @event, :api_keys?

      load_index
    end

    def create
      authorize @event, :manage_api_keys?

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

      # ── Rendered here, not redirected to ──────────────────────────────────
      #
      # This used to `redirect_to` with the plaintext in
      # `flash[:fuime_fresh_api_key]`, so the key could be shown once on the next
      # page. The app has no `session_store` initializer, so the session is Rails'
      # default COOKIE store: that serialized a live credential into the browser's
      # cookie jar, wrote it to disk, and replayed it to the server on the following
      # request. Encrypted with `secret_key_base` — which is the value in the
      # COMMITTED `config/credentials.yml.enc` unless the deploy sets
      # SECRET_KEY_BASE, and a secret whose confidentiality rests on a second
      # unfixed finding is not confidential.
      #
      # It also contradicted `Fuime::ApiKey.mint!`, which hands the plaintext back
      # as a second return value rather than storing it on the instance precisely so
      # it can never reach "a log line, an error report or a serializer". The flash
      # is a serializer.
      #
      # Rendering the page that shows the key IN the response that created it means
      # there is nothing to carry: the secret exists in one response body and in no
      # cookie, cache, or log. A server-side cache would have worked too and was
      # tried first — but `Rails.cache` is `:null_store` in test and in development
      # without `tmp/caching-dev.txt`, so the key would silently never appear
      # outside production. A feature that only works where it cannot be tested is
      # not a fix.
      #
      # The cost, stated: a browser refresh re-POSTs and mints a second key.
      # Bounded by MAX_LIVE_KEYS, visible in the list, and revocable — a cheaper
      # failure than a credential in a cookie.
      flash.now[:success] = "Key created. Copy it now — you won't be able to see it again."
      load_index
      @fresh_key = plaintext
      render :index
    end

    def destroy
      authorize @event, :manage_api_keys?

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

    # Shared by #index and by #create, which renders the same page rather than
    # redirecting to it. One method so the two cannot drift into showing different
    # things.
    def load_index
      @keys = @event.fuime_api_keys.live.recent_first
      @can_manage = policy(@event).manage_api_keys?
      # The links programs have made, so an operator can see what their own
      # software has been asking people for. This is the screen where a runaway
      # agent becomes visible, so it is not hidden behind the key list.
      @links = @event.fuime_offers.unlisted.made_by_program
                     .includes(:fuime_api_key).order(created_at: :desc).limit(50)

      # Only ever set by #create, in the same request that minted it. Never carried
      # across a redirect — see the note there.
      @fresh_key = nil
    end

    def set_event
      @event = Event.friendly.find(params[:event_slug])
    end

  end
end
