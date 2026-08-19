# frozen_string_literal: true

# Fuime: "whose key is this, and can it sell right now?"
#
#   GET /api/fuime/v1/me
#
# The endpoint an agent calls first. Two reasons it exists rather than making the
# caller infer both from a failed POST:
#
#   * a teenager wiring up a key needs one request that says "yes, this is your
#     key, and it is your business" — a 201 that creates a real payment link is a
#     bad way to find out you pasted the wrong key;
#   * `can_sell` lets an agent say "I can't take payments yet" in conversation
#     instead of generating a link that will 409, or worse, telling a customer to
#     pay at a URL that shows them a dead page.
#
# It reports the fact and not the reasons. `Event#selling_blockers` names
# operators and states their ages; that is for the operator and their guardian,
# never for a program running on someone else's server.
module Fuime
  module Api
    module V1
      class VentureController < BaseController
        def show
          render json: {
            venture: {
              name: current_event.name,
              slug: current_event.slug,
              storefront_url: ::Rails.application.routes.url_helpers
                                     .fuime_storefront_url(slug: current_event.slug),
              can_sell: current_event.accepts_payments?,
              currency: "usd"
            },
            key: {
              name: current_key.name,
              display: current_key.display,
              created_at: current_key.created_at.iso8601
            }
          }
        end

      end
    end
  end
end
