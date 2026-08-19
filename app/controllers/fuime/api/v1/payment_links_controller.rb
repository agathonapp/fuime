# frozen_string_literal: true

# Fuime: pay links, created by a program.
#
#   POST   /api/fuime/v1/payment_links      make one
#   GET    /api/fuime/v1/payment_links      list this venture's
#   DELETE /api/fuime/v1/payment_links/:id  take one down
#
# Each link is an unlisted published `Fuime::Offer` — payable by its own URL,
# absent from the storefront. See AddListingToFuimeOffers for why that is one
# model and not two, and Fuime::Api::V1::BaseController for why the venture is
# never a parameter.
module Fuime
  module Api
    module V1
      class PaymentLinksController < BaseController
        before_action :require_selling_venture!, only: :create

        # Bounds on an endpoint a program drives.
        #
        # The floor matches Fuime::CheckoutsController's, so the two entry points
        # agree on what a payment is. The ceiling is the offer model's own
        # maximum, and it is doing real work here rather than being defensive
        # boilerplate: the caller is frequently a language model choosing a
        # number, and the failure mode of a misplaced decimal point is a
        # teenager's customer being asked for $450,000. A hard refusal is the
        # correct answer to that, not a clamp — silently charging $10,000 when
        # the caller said $450,000 is its own kind of wrong.
        MINIMUM_AMOUNT_CENTS = 1_00
        MAXIMUM_AMOUNT_CENTS = ::Fuime::Offer::MAXIMUM_PRICE_CENTS

        # How many live links one key may have outstanding. A runaway agent in a
        # retry loop is the expected failure, not an attacker, and this is what
        # keeps that from filling a teenager's dashboard with ten thousand rows
        # overnight.
        MAX_LIVE_LINKS_PER_KEY = 250

        def create
          amount_cents = parse_amount
          if amount_cents.nil?
            return render json: {
              error: "invalid_amount",
              message: "Send `amount` in dollars (45.00) or `amount_cents` (4500), " \
                       "between $1 and $10,000."
            }, status: :unprocessable_entity
          end

          if current_key.offers.live.count >= MAX_LIVE_LINKS_PER_KEY
            return render json: {
              error: "too_many_links",
              message: "This key has #{MAX_LIVE_LINKS_PER_KEY} live payment links. " \
                       "Take some down before making more."
            }, status: :conflict
          end

          offer = ::Fuime::Offer.for_amount!(
            event: current_event,
            price_cents: amount_cents,
            name: params[:name].presence || params[:description].presence || "Payment",
            description: params[:description].presence,
            unit_label: params[:unit_label].presence,
            created_via: "api",
            api_key: current_key
          )

          render json: serialize(offer), status: :created
        rescue ActiveRecord::RecordInvalid => e
          # The model's own messages, which are written for a person and are the
          # right thing for an agent to relay to the teenager who owns the key.
          render json: {
            error: "invalid_payment_link",
            message: e.record.errors.full_messages.join(". ")
          }, status: :unprocessable_entity
        end

        def index
          links = current_event.fuime_offers.unlisted.made_by_program
                               .order(created_at: :desc).limit(100)

          render json: { payment_links: links.map { |l| serialize(l) } }
        end

        # Take a link down.
        #
        # Archived rather than deleted, and archived rather than merely
        # unpublished: `Fuime::Offer`'s own header says a sold offer is referenced
        # by a ledger memo and a buyer's receipt, so the row has to survive. What
        # matters to the caller is that the URL stops taking money, and archiving
        # does that — both the payment page and the checkout resolve against
        # published offers only.
        #
        # Scoped to links THIS key made. A key that could take down another key's
        # links could take down the operator's own storefront by guessing tokens.
        def destroy
          link = current_key.offers.live.find_by(public_token: params[:id]) ||
                 current_key.offers.live.find_by(slug: params[:id])

          return not_found if link.nil?

          link.archive!
          render json: serialize(link)
        end

        private

        def serialize(offer)
          {
            id: offer.public_token!,
            url: ::Rails.application.routes.url_helpers.fuime_payment_page_url(
              event_slug: current_event.slug, offer: offer.to_param
            ),
            name: offer.name,
            description: offer.description,
            amount_cents: offer.price_cents,
            # Dollars alongside cents because the caller is often a model
            # generating a sentence for a customer, and making it divide by 100
            # is making it do arithmetic it is bad at.
            amount: format("%.2f", offer.price_cents / 100.0),
            currency: "usd",
            status: offer.aasm_state,
            created_at: offer.created_at.iso8601
          }
        end

        # `amount` in dollars or `amount_cents` in cents.
        #
        # Cents wins when both are sent, because a caller that computed cents did
        # so deliberately, and a dollars field alongside it is more likely to be
        # a leftover than a correction.
        #
        # Deliberately strict about what a number is. `to_i` would read "forty
        # five" as 0 and "45abc" as 45, and this value becomes what a stranger is
        # charged — so anything that is not cleanly a number is refused rather
        # than coerced into a plausible-looking amount nobody chose.
        def parse_amount
          if params[:amount_cents].present?
            cents = Integer(params[:amount_cents].to_s.strip, exception: false)
            return nil if cents.nil?

            return in_range(cents)
          end

          return nil if params[:amount].blank?

          # "$45.00" and "45" both, since a model writing JSON often includes the
          # currency symbol it was about to show a customer.
          cleaned = params[:amount].to_s.strip.delete("$,")
          decimal = BigDecimal(cleaned, exception: false)
          return nil if decimal.nil?

          in_range((decimal * 100).round)
        end

        def in_range(cents)
          return nil if cents < MINIMUM_AMOUNT_CENTS || cents > MAXIMUM_AMOUNT_CENTS

          cents
        end

      end
    end
  end
end
