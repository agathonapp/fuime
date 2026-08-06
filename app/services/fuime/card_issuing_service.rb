# frozen_string_literal: true

# Fuime: issue a business-expense card on a venture's own Stripe account.
#
# Every call carries `stripe_account:`, so the card is issued against the family's
# balance by the family's own account. Fuime is not the issuer and does not hold the
# funds behind it, which is the same posture as the rest of the money stack
# (CLAUDE.md L1).
#
# ── What this service refuses to do, and why ────────────────────────────────
#
# 1. It will not issue a card on a venture whose Stripe account was not CREATED for
#    cards. `controller` is create-only, so a payments-only venture can never gain
#    Issuing; pretending otherwise would fail at Stripe with a message no family
#    could act on. See Fuime::ConnectOnboardingService::PROFILES.
#
# 2. It will not issue a card to someone who has not accepted the card terms. Stripe
#    has a first-class field for this —
#    `individual.card_issuing.user_terms_acceptance` — so the acceptance is reported
#    to Stripe rather than merely logged in Fuime's database. A card held by someone
#    who accepted nothing is not an authorized user, it is just a person holding a
#    card.
#
# 3. It will not mark a card as commercially restricted unless Stripe echoes the
#    category allowlist back. See Fuime::CardSpendPolicy for why the allowlist is the
#    mechanism that makes "business purchases only" true rather than aspirational; a
#    card that silently lost its controls must be visible as such.
#
# 4. It will not let a minor be the Accountholder. VentureCardholder validates this
#    too; it is checked in both places because it is the assertion the whole
#    arrangement rests on.
module Fuime
  class CardIssuingService
    class Error < StandardError; end
    class CardsNotAvailable < Error; end
    class TermsNotAccepted < Error; end
    class MissingBillingAddress < Error; end
    class ControlsNotApplied < Error; end

    # Stripe requires a full billing address for an Issuing cardholder. Fuime cannot
    # invent one, so the caller supplies it and this is the shape expected.
    REQUIRED_ADDRESS_KEYS = %i[line1 city state postal_code].freeze

    # A default ceiling so a card is never issued unlimited. Deliberately modest:
    # this is a teenager's first business card, and the guardian raises it
    # deliberately rather than discovering the limit was open.
    DEFAULT_SPENDING_LIMIT_CENTS = 25_000
    DEFAULT_INTERVAL = "monthly"

    def initialize(event:)
      @event = event
    end

    # Register a person with Stripe as a cardholder on this venture's account.
    #
    # Idempotent on (event, user): returns the existing row when there is one, which
    # matters because a guardian re-running the flow must not create a second Stripe
    # Cardholder and split the card history in two.
    #
    # The local row is written BEFORE the Stripe call, same reasoning as
    # StripeConnectedAccount: a crash in between leaves a retryable row with a null
    # stripe_id rather than a Stripe object Fuime cannot reconcile.
    def find_or_create_cardholder!(user:, role:, billing_address:, phone_number: nil, terms_ip: nil, terms_user_agent: nil)
      ensure_cards_available!
      validate_address!(billing_address)

      existing = VentureCardholder.find_by(event: @event, user:)
      return existing if existing&.stripe_id.present?

      record = existing || VentureCardholder.create!(event: @event, user:, role: role.to_s)

      # Accepted locally first so the timestamp reported to Stripe is the one Fuime
      # can evidence, rather than "now" computed inside the API payload.
      record.accept_terms!(ip: terms_ip, user_agent: terms_user_agent) unless record.terms_accepted?

      cardholder = Stripe::Issuing::Cardholder.create(
        cardholder_params(record:, billing_address:, phone_number:),
        request_options.merge(idempotency_key: "fuime_cardholder_#{record.id}")
      )
      record.sync_from_stripe!(cardholder)
      record
    rescue Stripe::StripeError => e
      raise Error, "Stripe couldn't register this cardholder: #{e.message}"
    end

    # Issue a virtual card to a registered cardholder.
    #
    # Virtual only: a physical card mailed to a minor raises delivery and signature
    # questions that are not answered yet, and shipping one would be a decision
    # disguised as a default.
    def issue_card!(cardholder:, spending_limit_cents: DEFAULT_SPENDING_LIMIT_CENTS, interval: DEFAULT_INTERVAL)
      ensure_cards_available!

      unless cardholder.terms_accepted?
        raise TermsNotAccepted,
              "#{cardholder.user.name.presence || 'This cardholder'} hasn't accepted the card terms yet."
      end

      if cardholder.status != "active"
        raise CardsNotAvailable,
              "Stripe hasn't activated this cardholder yet. #{cardholder.issuance_blockers.to_sentence}"
      end

      record = VentureCard.create!(
        venture_cardholder: cardholder,
        card_type: VentureCard::VIRTUAL,
        spending_limit_cents:,
        spending_limit_interval: interval
      )

      card = Stripe::Issuing::Card.create(
        card_params(cardholder:, spending_limit_cents:, interval:),
        request_options.merge(idempotency_key: "fuime_card_#{record.id}")
      )

      record.sync_from_stripe!(card)

      # The allowlist is the compliance control, so a card that reached Stripe
      # without it is not a usable card. Raising rolls nothing back at Stripe — the
      # card exists — so it is cancelled first rather than left live and unrestricted.
      unless record.commercial_controls_applied?
        cancel_card!(record)
        raise ControlsNotApplied,
              "Stripe did not apply Fuime's business-purchase restrictions to this card, " \
              "so it was cancelled rather than left unrestricted."
      end

      record
    rescue Stripe::StripeError => e
      raise Error, "Stripe couldn't issue this card: #{e.message}"
    end

    # Change the guardian's limit on an existing card.
    def update_spending_limit!(card:, spending_limit_cents:, interval: DEFAULT_INTERVAL)
      updated = Stripe::Issuing::Card.update(
        card.stripe_id,
        { spending_controls: spending_controls(spending_limit_cents:, interval:) },
        request_options
      )
      card.sync_from_stripe!(updated)
      card
    rescue Stripe::StripeError => e
      raise Error, "Stripe couldn't update this card's limit: #{e.message}"
    end

    # Freeze a card. Reversible, unlike #cancel_card!.
    #
    # Stripe models this as `status: "inactive"`, which is distinct from "canceled" —
    # cancellation is permanent and a new card has to be issued. A lost card should be
    # frozen, not cancelled, so the distinction is preserved rather than collapsed into
    # one "disable" action.
    def freeze_card!(card)
      set_status!(card, "inactive")
    end

    def unfreeze_card!(card)
      set_status!(card, "active")
    end

    def set_status!(card, status)
      updated = Stripe::Issuing::Card.update(card.stripe_id, { status: }, request_options)
      card.sync_from_stripe!(updated)
      card
    rescue Stripe::StripeError => e
      raise Error, "Stripe couldn't update this card: #{e.message}"
    end

    def cancel_card!(card)
      return card if card.stripe_id.blank?

      cancelled = Stripe::Issuing::Card.update(
        card.stripe_id, { status: "canceled" }, request_options
      )
      card.sync_from_stripe!(cancelled)
      card
    rescue Stripe::StripeError => e
      # Logged rather than raised: this runs inside the failure path of #issue_card!,
      # and masking the original error with a cancellation error would hide why the
      # card was being cancelled in the first place.
      Rails.logger.error("[Fuime] could not cancel card #{card.stripe_id}: #{e.message}")
      card
    end

    private

    def account
      # Cards are issued on the account that holds the funds, which inside a school
      # programme is the school's. See Event#payment_account.
      @account ||= @event.payment_account
    end

    def ensure_cards_available!
      if account.blank? || !account.cards_profile?
        raise CardsNotAvailable,
              "This venture's Stripe account wasn't created with card support. Stripe can't add " \
              "it to an existing account, so the venture would need to be set up again."
      end

      unless account.ready_for_cards?
        raise CardsNotAvailable,
              "Stripe hasn't enabled card issuing on this venture yet."
      end
    end

    def validate_address!(address)
      address ||= {}
      missing = REQUIRED_ADDRESS_KEYS.reject { |k| address[k].present? || address[k.to_s].present? }
      return if missing.empty?

      raise MissingBillingAddress,
            "Stripe needs a full billing address for a cardholder. Missing: #{missing.join(', ')}."
    end

    def cardholder_params(record:, billing_address:, phone_number:)
      user = record.user

      {
        type: "individual",
        name: user.name.presence || user.email,
        email: user.email,
        # Stripe uses this for 3-D Secure challenges. Absent is allowed; a card that
        # cannot pass 3DS simply fails those specific online purchases.
        **(phone_number.presence ? { phone_number: } : {}),
        status: "active",
        billing: { address: normalize_address(billing_address) },
        individual: {
          first_name: user.first_name.presence || user.name.to_s.split.first.presence || "Unknown",
          last_name: user.last_name.presence || user.name.to_s.split.last.presence || "Unknown",
          **(user.birthday.present? ? { dob: dob_for(user) } : {}),
          # Stripe's own field for the Authorized User / Accountholder terms. This is
          # what makes the acceptance a fact Stripe holds rather than a claim in
          # Fuime's database.
          card_issuing: {
            user_terms_acceptance: {
              date: record.terms_accepted_at.to_i,
              **(record.terms_accepted_ip.present? ? { ip: record.terms_accepted_ip } : {})
            }
          }
        },
        metadata: {
          fuime_event_id: @event.id,
          fuime_user_id: user.id,
          fuime_role: record.role,
          fuime_terms_version: record.terms_version
        }
      }
    end

    def card_params(cardholder:, spending_limit_cents:, interval:)
      {
        cardholder: cardholder.stripe_id,
        currency: "usd",
        type: VentureCard::VIRTUAL,
        status: "active",
        spending_controls: spending_controls(spending_limit_cents:, interval:),
        metadata: {
          fuime_event_id: @event.id,
          fuime_user_id: cardholder.user_id,
          fuime_role: cardholder.role
        }
      }
    end

    # `allowed_categories` and not `blocked_categories`: Stripe accepts one or the
    # other, and an allowlist fails closed. See Fuime::CardSpendPolicy.
    def spending_controls(spending_limit_cents:, interval:)
      {
        allowed_categories: CardSpendPolicy.allowed_categories,
        spending_limits: [
          { amount: spending_limit_cents, interval: interval }
        ]
      }
    end

    def dob_for(user)
      { day: user.birthday.day, month: user.birthday.month, year: user.birthday.year }
    end

    def normalize_address(address)
      address = address.symbolize_keys
      {
        line1: address[:line1],
        line2: address[:line2],
        city: address[:city],
        state: address[:state],
        postal_code: address[:postal_code],
        country: address[:country].presence || "US"
      }.compact
    end

    # See Fuime::ConnectOnboardingService for why the API key is always explicit.
    def request_options
      { api_key: StripeService.secret_key, stripe_account: account.stripe_id }
    end

  end
end
