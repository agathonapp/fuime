# frozen_string_literal: true

# Fuime: the API a venture's own software talks to.
#
# ── Who this is for ─────────────────────────────────────────────────────────
#
# A 16-year-old with a site on Replit, a Discord bot, or an agent answering their
# customers. They agree a price with somebody in a conversation and need a link
# that takes that exact amount. Before this, the only way to be paid an arbitrary
# amount was for a human to open the storefront and type it.
#
# ── Deliberately not Api::V4 ────────────────────────────────────────────────
#
# `Api::V4::ApplicationController` is Doorkeeper OAuth over a USER's whole
# account, with Pundit policies underneath. Both of those are wrong here — see
# CreateFuimeApiKeys. This authenticates a `Fuime::ApiKey`, which speaks for
# exactly one venture and can do exactly one category of thing, so there is no
# `current_user` and nothing for Pundit to answer about.
#
# ── The venture is never a parameter ────────────────────────────────────────
#
# `current_event` comes off the key and nothing else. There is no `event_id` in
# any route or body here, so there is no version of this API where a caller
# names the venture it wants to act on — which is what makes a leaked key's blast
# radius provably one business rather than one business plus whatever it can be
# talked into typing.
module Fuime
  module Api
    module V1
      class BaseController < ActionController::API
        before_action :authenticate_key!

        # A JSON API answering a program: no CSRF token to check, and an HTML
        # error page would be unparseable to the caller.
        rescue_from ActiveRecord::RecordNotFound, with: :not_found
        rescue_from ActionController::ParameterMissing, with: :bad_request

        private

        attr_reader :current_key

        def current_event
          @current_event ||= current_key.event
        end

        # Bearer token, or the raw key.
        #
        # Both accepted because half the world writes `Authorization: Bearer <k>`
        # and the other half pastes the key alone, and an agent framework's HTTP
        # client does whichever its author chose. Refusing the second spelling
        # buys no security — the credential is identical — and costs a teenager
        # an afternoon.
        def presented_key
          header = request.headers["Authorization"].to_s.strip
          return header.delete_prefix("Bearer").strip if header.downcase.start_with?("bearer")

          header
        end

        def authenticate_key!
          @current_key = ::Fuime::ApiKey.authenticate(presented_key)
          return if @current_key.present?

          # One message for every failure — missing, malformed, unknown, revoked.
          # See Fuime::ApiKey.authenticate: distinguishing them tells a caller
          # probing the key space when it has found a real one.
          render json: {
            error: "invalid_key",
            message: "That key isn't valid. Check it, or make a new one in your " \
                     "venture's settings under Developer."
          }, status: :unauthorized
        end

        # Every write here asks for money in a child's name, so the eligibility
        # gate is re-asked at the moment of the request rather than trusted from
        # whenever the key was minted. A venture suspended an hour ago must not
        # still be able to issue payable links through a key nobody thought to
        # revoke.
        #
        # `Event#selling_blockers` names operators and states their ages, so the
        # strings never cross this boundary — the caller may be a program on a
        # stranger's server. It gets the fact, not the reasons.
        def require_selling_venture!
          return if current_event.accepts_payments?

          render json: {
            error: "not_accepting_payments",
            message: "This venture can't take payments right now. Sign in to Fuime " \
                     "to see what's needed."
          }, status: :conflict
        end

        def not_found
          render json: { error: "not_found" }, status: :not_found
        end

        def bad_request(exception)
          render json: { error: "bad_request", message: exception.message },
                 status: :bad_request
        end

      end
    end
  end
end
