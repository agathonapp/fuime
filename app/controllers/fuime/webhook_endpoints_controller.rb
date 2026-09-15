module Fuime
  # Fuime: where a founder points Fuime at their own server.
  #
  # The UI half of Fuime::WebhookEndpoint. Without it the delivery machinery
  # exists but is reachable only from a Rails console — which means it exists for
  # Fuime and not for the founder it was built for. Same gap the API-keys screen
  # was created to close, and the same shape of fix.
  #
  # ── Who may add one ─────────────────────────────────────────────────────────
  #
  # `manage_api_keys?` — the same authority as minting a key, deliberately. An
  # endpoint is the power to send a venture's sale data to an address of your
  # choosing, which is at least as consequential as a read key. It is NOT the
  # payout gate: an endpoint cannot move money, so the guardian's authority is
  # not engaged. The guardian still SEES every endpoint, as they see every key
  # and every sale — visibility without control, as on the offers screen.
  class WebhookEndpointsController < ApplicationController
    before_action :set_event

    def index
      authorize @event, :api_keys?

      load_index
    end

    def create
      authorize @event, :manage_api_keys?

      endpoint = @event.fuime_webhook_endpoints.new(url: params[:url].to_s.strip,
                                                    description: params[:description])

      unless endpoint.save
        return redirect_to fuime_webhooks_path(event_slug: @event.slug),
                           alert: endpoint.errors.full_messages.to_sentence
      end

      # ── Shown in this response, never carried to the next ────────────────
      #
      # Exactly the reasoning in Fuime::ApiKeysController#create, and for the
      # same reason: the app has no session_store initializer, so the session is
      # Rails' default COOKIE store. Putting the signing secret in the flash
      # would serialize a live credential into the browser's cookie jar, write it
      # to disk, and replay it on the next request.
      #
      # Anyone holding this secret can forge sales into the founder's system, so
      # it is shown once, in the response that created it, and lives in no
      # cookie, cache or log.
      flash.now[:success] = "Endpoint added. Copy the signing secret now — " \
                            "you won't be able to see it again."
      load_index
      @fresh_secret = endpoint.secret

      respond_to do |format|
        format.html { render :index }
        format.turbo_stream
      end
    end

    # Disable rather than delete, so the delivery history survives — it is the
    # only evidence of what went wrong on an endpoint that broke at 2am.
    def destroy
      authorize @event, :manage_api_keys?

      endpoint = @event.fuime_webhook_endpoints.find(params[:id])
      endpoint.disable!(reason: "turned off by #{current_user.email}")

      redirect_to fuime_webhooks_path(event_slug: @event.slug),
                  notice: "Endpoint turned off. Fuime will stop sending to it."
    end

    private

    def set_event
      @event = Event.find_by!(slug: params[:event_slug])
    end

    def load_index
      @endpoints = @event.fuime_webhook_endpoints.order(created_at: :desc)
      # The last few attempts per endpoint: "did it arrive" is the only question
      # anybody has on this screen, and an endpoint with no answer to it is
      # indistinguishable from one that was never tried.
      @recent_deliveries = ::Fuime::WebhookDelivery
                           .where(fuime_webhook_endpoint_id: @endpoints.map(&:id))
                           .order(created_at: :desc)
                           .limit(20)
    end

  end
end
