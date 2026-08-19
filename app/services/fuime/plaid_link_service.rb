# frozen_string_literal: true

module Fuime
  # Fuime: connecting an operator's payout destination through Plaid Link.
  #
  # Three calls, in order:
  #
  #   #link_token   → a short-lived token the browser hands to Plaid Link
  #   (the operator logs into their bank inside Plaid's own iframe)
  #   #connect!     → exchanges what Link returns for a verified Fuime::PayoutMethod
  #
  # ── ⚠️ What this deliberately cannot do ─────────────────────────────────────
  #
  # `/auth/get` is not called here and appears nowhere in this codebase. That
  # endpoint returns the account and routing numbers, and Fuime has no use for
  # them: the ORIGINATOR needs the digits, and Fuime is not the originator
  # (MOR_MIGRATION_PLAN §4.3 — Plaid verifies, Stripe/Slash/Mercury sends). What
  # is kept is the Item token and the account id, which is what
  # `/processor/token/create` takes on the day that question is answered.
  #
  # This is the difference between a payout destination and a stored credential,
  # and it is the whole reason the schema has no `account_number` column
  # (CreateFuimePayoutMethods, CLAUDE.md L4).
  #
  # ── Why `auth` is requested at Link time anyway ─────────────────────────────
  #
  # A Plaid Item can only be used for products it was created with. Requesting
  # `auth` makes the Item CAPABLE of being handed to an originator later; not
  # requesting it would mean every operator re-links the day a rail is chosen.
  # Capability at Plaid is not possession at Fuime — the numbers still never
  # cross this boundary.
  #
  # `identity` is optional rather than required. It is how `account_holder_name`
  # gets filled in, which is the cheapest fraud signal available (a payout
  # destination in a third party's name is exactly what a payout review looks
  # for) — but a bank that does not support it must not be a bank an operator
  # cannot get paid from, so a failure there degrades to a nil name and the
  # connection still verifies.
  #
  # ── Verification is the bank login, not a later event ───────────────────────
  #
  # Link's instant-auth flow means the operator has proven control of the
  # account by logging into it, so the row is `verified` when this returns
  # rather than sitting `pending` waiting for something. Micro-deposit flows
  # (`same-day-microdeposits`) are NOT enabled: they resolve days later through
  # a webhook, and Fuime has no Plaid webhook receiver. Offering a path that
  # silently never completes is worse than offering fewer banks.
  class PlaidLinkService
    class Error < StandardError; end

    # Raised when Plaid is not configured at all. Distinct from Error because
    # the caller shows a different page: this is an operator problem, not the
    # family's, and telling a teenager their bank refused them when Fuime simply
    # has no API key is a lie with a support ticket attached.
    class NotConfigured < Error; end

    SANDBOX = "sandbox"
    PRODUCTION = "production"

    # See the header. `auth` is capability for the originator; Fuime never reads
    # what it unlocks.
    PRODUCTS = ["auth"].freeze
    OPTIONAL_PRODUCTS = ["identity"].freeze

    COUNTRY_CODES = ["US"].freeze

    # Only accounts that can receive an ACH credit. A credit card, a mortgage or
    # a 401k cannot, and letting one be chosen produces a destination that fails
    # at send time — weeks later, in a batch, to somebody who has been told they
    # were set up. Link enforces this in its own UI through `account_filters`;
    # #connect! re-checks it server-side because the filter is a client-side
    # convenience and the account id arrives from a browser.
    PAYABLE_SUBTYPES = %w[checking savings].freeze
    PAYABLE_TYPE = "depository"

    class << self
      def client_id
        # The flat spelling is what the deployment actually sets. The nested one
        # is upstream HCB's (PlaidService), kept as a fallback so a machine
        # configured for the fork's ancestor still works rather than silently
        # having no Plaid at all.
        ::Credentials.fetch(:PLAID_CLIENT_ID, fallback: ::Credentials.fetch(:PLAID, :CLIENT_ID)).presence
      end

      def secret
        ::Credentials.fetch(:PLAID_SECRET, fallback: upstream_secret).presence
      end

      # sandbox unless someone says otherwise, and that default is load-bearing.
      #
      # Plaid's production environment connects REAL bank accounts. Fuime cannot
      # yet pay one (§4.3 has no originator), so a misconfigured environment
      # defaulting to production would collect live banking connections for
      # money that cannot move — the exact "the site describes a product that
      # does not exist" failure L8 exists to stop, with a family's bank at the
      # other end of it.
      #
      # Unknown spellings fall back to sandbox rather than raising, for the same
      # reason: a typo must not be the thing that promotes an environment.
      def env
        requested = ENV["PLAID_ENV"].to_s.strip.downcase
        requested == PRODUCTION ? PRODUCTION : SANDBOX
      end

      def sandbox?
        env == SANDBOX
      end

      def configured?
        client_id.present? && secret.present?
      end

      def client
        raise NotConfigured, "Plaid is not configured (PLAID_CLIENT_ID / PLAID_SECRET)" unless configured?

        configuration = ::Plaid::Configuration.new
        configuration.server_index = ::Plaid::Configuration::Environment[env]
        configuration.api_key["PLAID-CLIENT-ID"] = client_id
        configuration.api_key["PLAID-SECRET"] = secret

        ::Plaid::PlaidApi.new(::Plaid::ApiClient.new(configuration))
      end

      private

      # Upstream keys the secret by environment; Plaid retired `development`, so
      # only two of the three upstream names can still be right.
      def upstream_secret
        if env == PRODUCTION
          ::Credentials.fetch(:PLAID, :PRODUCTION_SECRET)
        else
          ::Credentials.fetch(:PLAID, :SANDBOX_SECRET)
        end
      end

    end

    def initialize(event:, user:)
      @event = event
      @user = user
    end

    # A token the browser hands to Plaid Link. Short-lived (four hours) and
    # single-use by design, so it is minted per page load and never cached.
    def link_token
      request = ::Plaid::LinkTokenCreateRequest.new(
        client_name: "Fuime",
        language: "en",
        country_codes: COUNTRY_CODES,
        # Plaid's own guidance is that this must not be PII. The database id is
        # meaningless outside Fuime, which is the point.
        user: ::Plaid::LinkTokenCreateRequestUser.new(client_user_id: "fuime_user_#{@user.id}"),
        products: PRODUCTS,
        optional_products: OPTIONAL_PRODUCTS,
        # Typed rather than a bare hash. The gem accepts either and serializes
        # both, but a hash stays a hash — so a misspelled key would sail through
        # to Plaid as an ignored filter, and the first sign of it would be an
        # operator connecting a credit card the UI was supposed to hide.
        account_filters: ::Plaid::LinkTokenAccountFilters.new(
          depository: ::Plaid::DepositoryFilter.new(account_subtypes: PAYABLE_SUBTYPES)
        )
      )

      client.link_token_create(request).link_token
    rescue ::Plaid::ApiError => e
      raise Error, plaid_message(e, "We couldn't start the bank connection just now. Please try again in a moment.")
    end

    # Everything after the operator finishes inside Plaid's iframe.
    #
    # `public_token` and `account_id` both arrive from the browser, so neither is
    # trusted: the token is exchanged with Plaid (which is what makes it real)
    # and the account id is checked against the accounts Plaid reports for the
    # resulting Item. A forged account id therefore cannot name an account on
    # somebody else's Item — it can only fail to be found on this one.
    #
    # Returns a verified Fuime::PayoutMethod.
    def connect!(public_token:, account_id:)
      raise Error, "Plaid didn't return a bank connection. Please try again." if public_token.blank?

      exchange = exchange_public_token(public_token)
      accounts = fetch_accounts(exchange.access_token)

      account = pick_account(accounts.accounts, account_id)
      ensure_payable!(account)

      persist!(
        access_token: exchange.access_token,
        item_id: exchange.item_id,
        account:,
        institution_name: accounts.item&.institution_name,
        account_holder_name: account_holder_name(exchange.access_token, account.account_id)
      )
    end

    private

    def client
      self.class.client
    end

    def exchange_public_token(public_token)
      client.item_public_token_exchange(
        ::Plaid::ItemPublicTokenExchangeRequest.new(public_token:)
      )
    rescue ::Plaid::ApiError => e
      raise Error, plaid_message(e, "That bank connection didn't complete. Please try connecting again.")
    end

    def fetch_accounts(access_token)
      client.accounts_get(::Plaid::AccountsGetRequest.new(access_token:))
    rescue ::Plaid::ApiError => e
      raise Error, plaid_message(e, "We connected to your bank but couldn't read the account. Please try again.")
    end

    # Which account the operator chose.
    #
    # Falls back to the only payable account when Link returned no id — some
    # institution flows omit it — but never GUESSES between several. Picking one
    # of two checking accounts on the operator's behalf is how money arrives
    # somewhere nobody chose, and a clear error beats a silent choice.
    def pick_account(accounts, account_id)
      accounts = Array(accounts)

      if account_id.present?
        found = accounts.find { |a| a.account_id == account_id }
        raise Error, "We couldn't find that account at your bank. Please try connecting again." if found.blank?

        return found
      end

      payable = accounts.select { |a| payable?(a) }
      return payable.first if payable.one?

      raise Error, "Please pick which account you'd like to be paid into."
    end

    def ensure_payable!(account)
      return if payable?(account)

      raise Error, "Payouts can only go to a checking or savings account. " \
                   "Please connect one of those instead."
    end

    def payable?(account)
      account.type.to_s == PAYABLE_TYPE && PAYABLE_SUBTYPES.include?(account.subtype.to_s)
    end

    # The name on the account, when the bank will tell us.
    #
    # Best-effort on purpose: `identity` is an optional product, so this is the
    # one call in the flow whose failure must not fail the connection. An
    # operator whose bank does not support it still gets paid; what is lost is a
    # fraud signal on a review page, which is Fuime's problem and not theirs.
    def account_holder_name(access_token, account_id)
      response = client.identity_get(::Plaid::IdentityGetRequest.new(access_token:))

      account = Array(response.accounts).find { |a| a.account_id == account_id }
      name = Array(account&.owners).flat_map { |owner| Array(owner.names) }.first

      # The model refuses a nine-digit run in this column. A name should never
      # contain one, but this value comes from a third party and the whole point
      # of that validation is that a credential can arrive in the nearest
      # available box — so drop it rather than fail the connection over it.
      return nil if name.to_s.match?(/\d{9,}/)

      name.presence
    rescue ::Plaid::ApiError, StandardError => e
      Rails.logger.info("[Fuime] identity lookup skipped for event #{@event.id}: #{e.class}")
      nil
    end

    # One live destination per venture, so connecting a new one retires the old.
    #
    # In a transaction because the partial unique index means the removal and the
    # insert are two halves of one fact — a crash between them leaves a venture
    # with no destination at all, having just been told it had a new one.
    def persist!(access_token:, item_id:, account:, institution_name:, account_holder_name:)
      ::Fuime::PayoutMethod.transaction do
        @event.fuime_payout_methods.live.each do |existing|
          raise Error, "We couldn't replace your existing payout account." unless existing.remove!
        end

        payout_method = @event.fuime_payout_methods.create!(
          added_by: @user,
          provider: ::Fuime::PayoutMethod::PLAID,
          provider_reference: item_id,
          provider_account_id: account.account_id,
          provider_access_token: access_token,
          institution_name: institution_name.presence,
          last4: account.mask.presence,
          account_holder_name:
        )

        # AASM is not whiny by default: a transition whose save fails validation
        # reverts the state and returns false rather than raising. Unchecked,
        # this would tell an operator they were set up while leaving the row
        # `pending` — which PayableAssessment reads as "no destination" and
        # silently skips them from every payout run.
        unless payout_method.mark_verified!
          raise Error, "We connected your bank but couldn't finish setting it up. Please try again."
        end

        payout_method
      end
    end

    # Plaid's own words when they are meant for a person, ours when they are not.
    #
    # `display_message` is the field Plaid documents as safe to show an end user;
    # `error_message` is for developers and regularly names internal state. Using
    # the second would put "PRODUCT_NOT_READY" in front of a family.
    def plaid_message(error, fallback)
      body = JSON.parse(error.response_body.to_s)
      code = body["error_code"]

      Rails.logger.warn("[Fuime] Plaid error #{code} for event #{@event.id}")

      body["display_message"].presence || fallback
    rescue JSON::ParserError, TypeError
      fallback
    end

  end
end
