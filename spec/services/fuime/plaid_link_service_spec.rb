# frozen_string_literal: true

require "rails_helper"

# Fuime: connecting a payout destination through Plaid.
#
# Two properties this file exists to protect, in order of how much they matter:
#
#   1. **The account and routing numbers never cross this boundary.** Plaid will
#      hand them over for the asking — `/auth/get` on an Item created with the
#      `auth` product returns them — so "we don't store credentials" is a claim
#      about code that must be tested, not a comment. The Item token being
#      *capable* of that call is the whole point (an originator will need it one
#      day); Fuime making it is what must never happen.
#
#   2. **A connection either verifies or fails loudly.** Fuime::PayableAssessment
#      reads `usable`, which is `verified` only, so a row left `pending` after a
#      cheerful success message means an operator is skipped from every payout
#      run while believing they are set up. AASM reverts a failed save and
#      returns false rather than raising, which is exactly how that happens.
#
# The Plaid client is stubbed. The real API was exercised against Plaid's sandbox
# on 2026-08-16 — link token, public token exchange, accounts and identity all
# returned what this file asserts the shapes of; see SETUP_NOTES.
RSpec.describe Fuime::PlaidLinkService do
  let(:event) { create(:event) }
  let(:user) { create(:user, birthday: 40.years.ago.to_date) }
  let(:service) { described_class.new(event:, user:) }

  let(:checking) do
    Plaid::AccountBase.new(account_id: "acc_checking", mask: "0000",
                           name: "Plaid Checking", type: "depository", subtype: "checking")
  end
  let(:credit_card) do
    Plaid::AccountBase.new(account_id: "acc_credit", mask: "9999",
                           name: "Plaid Credit Card", type: "credit", subtype: "credit card")
  end

  let(:item) { Plaid::Item.new(item_id: "item_abc", institution_name: "First Platypus Bank") }

  let(:exchange_response) do
    Plaid::ItemPublicTokenExchangeResponse.new(access_token: "access-sandbox-xyz", item_id: "item_abc")
  end

  let(:identity_owner) { Plaid::Owner.new(names: ["Alberta Bobbeth Charleson"]) }
  let(:identity_account) do
    Plaid::AccountIdentity.new(account_id: "acc_checking", owners: [identity_owner],
                               type: "depository", subtype: "checking")
  end

  let(:client) { instance_double(Plaid::PlaidApi) }

  before do
    allow(described_class).to receive(:client).and_return(client)
    allow(described_class).to receive(:configured?).and_return(true)

    allow(client).to receive(:item_public_token_exchange).and_return(exchange_response)
    allow(client).to receive(:accounts_get)
      .and_return(Plaid::AccountsGetResponse.new(accounts: [checking, credit_card], item:))
    allow(client).to receive(:identity_get)
      .and_return(Plaid::IdentityGetResponse.new(accounts: [identity_account], item:))
  end

  def plaid_error(code: "INVALID_INPUT", display_message: nil)
    body = { error_code: code, error_message: "internal detail nobody should see" }
    body[:display_message] = display_message if display_message
    Plaid::ApiError.new(code: 400, response_body: body.to_json)
  end

  # ── The property that matters most ─────────────────────────────────────────
  describe "not holding bank credentials" do
    it "never asks Plaid for the account and routing numbers" do
      # `auth_get` is the call that returns the digits. Stubbing it to raise
      # means a future refactor that reaches for it fails this spec rather than
      # quietly starting to hold credentials.
      allow(client).to receive(:auth_get).and_raise("Fuime must never call /auth/get")

      service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking")

      expect(client).not_to have_received(:auth_get)
    end

    it "stores the Item token encrypted rather than in the clear" do
      record = service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking")

      expect(record.provider_access_token).to eq("access-sandbox-xyz")

      # The column the database actually holds. If someone drops `has_encrypted`,
      # the plaintext appears here and this fails.
      raw = Fuime::PayoutMethod.connection.select_value(
        "SELECT provider_access_token_ciphertext FROM fuime_payout_methods WHERE id = #{record.id}"
      )
      expect(raw).to be_present
      expect(raw).not_to include("access-sandbox-xyz")
    end

    it "has nowhere to put the digits even if Plaid volunteered them" do
      expect(Fuime::PayoutMethod.column_names).not_to include("account_number", "routing_number")
    end
  end

  describe "#link_token" do
    it "asks Plaid for a token scoped to accounts that can receive a payout" do
      expect(client).to receive(:link_token_create) do |request|
        expect(request.products).to eq(["auth"])
        expect(request.optional_products).to eq(["identity"])
        expect(request.account_filters.depository.account_subtypes).to eq(%w[checking savings])
        expect(request.country_codes).to eq(["US"])
        Plaid::LinkTokenCreateResponse.new(link_token: "link-sandbox-1", expiration: 4.hours.from_now,
                                           request_id: "req_1")
      end

      expect(service.link_token).to eq("link-sandbox-1")
    end

    # Plaid's own guidance: this identifier must not be PII.
    it "identifies the user to Plaid without sending PII" do
      expect(client).to receive(:link_token_create) do |request|
        expect(request.user.client_user_id).to eq("fuime_user_#{user.id}")
        expect(request.user.client_user_id).not_to include(user.email)
        Plaid::LinkTokenCreateResponse.new(link_token: "link-sandbox-1", request_id: "req_1")
      end

      service.link_token
    end

    it "raises something a family can read when Plaid refuses" do
      allow(client).to receive(:link_token_create).and_raise(plaid_error)

      expect { service.link_token }.to raise_error(described_class::Error, /try again in a moment/)
    end
  end

  describe "#connect!" do
    it "records a verified destination against the venture" do
      record = service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking")

      expect(record).to be_verified
      expect(record).to be_usable
      expect(record.event).to eq(event)
      expect(record.added_by).to eq(user)
      expect(record.provider).to eq(Fuime::PayoutMethod::PLAID)
      expect(record.provider_reference).to eq("item_abc")
      expect(record.provider_account_id).to eq("acc_checking")
      expect(record.institution_name).to eq("First Platypus Bank")
      expect(record.last4).to eq("0000")
      expect(record.display_name).to eq("First Platypus Bank ••0000")
    end

    # The gate this whole page exists to clear. Under MoR a venture with no
    # usable destination is skipped from every payout run with a stated reason,
    # so "verified" is the difference between being paid and silently not.
    it "makes the venture payable" do
      expect(event.fuime_payout_methods.usable).to be_empty

      service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking")

      expect(event.reload.fuime_payout_methods.usable.count).to eq(1)
    end

    it "records the name the bank reports, as a fraud signal for whoever reviews the run" do
      record = service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking")

      expect(record.account_holder_name).to eq("Alberta Bobbeth Charleson")
    end

    # `identity` is an OPTIONAL product. A bank that does not support it must not
    # be a bank an operator cannot get paid from — the cost of the failure is a
    # missing fraud signal, which is Fuime's problem and not theirs.
    it "still connects when the bank will not report the account holder" do
      allow(client).to receive(:identity_get).and_raise(plaid_error(code: "PRODUCT_NOT_READY"))

      record = service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking")

      expect(record).to be_verified
      expect(record.account_holder_name).to be_nil
    end

    # The model refuses a nine-digit run in a name column. That value comes from a
    # third party, so the service drops it rather than failing the connection over
    # somebody else's data hygiene.
    it "drops an account holder name that looks like a credential" do
      allow(client).to receive(:identity_get).and_return(
        Plaid::IdentityGetResponse.new(
          accounts: [Plaid::AccountIdentity.new(account_id: "acc_checking",
                                                owners: [Plaid::Owner.new(names: ["Acct 021000021"])],
                                                type: "depository", subtype: "checking")],
          item:
        )
      )

      record = service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking")

      expect(record).to be_verified
      expect(record.account_holder_name).to be_nil
    end
  end

  describe "refusing an account that cannot be paid" do
    # A credit card cannot receive an ACH credit. Accepting one produces a
    # destination that fails at send time — weeks later, in a batch, to somebody
    # who was told they were set up.
    it "refuses a credit card" do
      expect { service.connect!(public_token: "public-sandbox-1", account_id: "acc_credit") }
        .to raise_error(described_class::Error, /checking or savings/)

      expect(event.fuime_payout_methods).to be_empty
    end

    # The account id arrives from a browser, so it is checked against the
    # accounts Plaid reports for the Item that was just exchanged. A forged id
    # cannot name an account on somebody else's Item — it can only fail here.
    it "refuses an account id that is not on the connected item" do
      expect { service.connect!(public_token: "public-sandbox-1", account_id: "acc_someone_else") }
        .to raise_error(described_class::Error, /couldn't find that account/)
    end

    it "refuses to guess when several accounts could be paid and none was chosen" do
      savings = Plaid::AccountBase.new(account_id: "acc_savings", mask: "1111", name: "Plaid Saving",
                                       type: "depository", subtype: "savings")
      allow(client).to receive(:accounts_get)
        .and_return(Plaid::AccountsGetResponse.new(accounts: [checking, savings], item:))

      expect { service.connect!(public_token: "public-sandbox-1", account_id: nil) }
        .to raise_error(described_class::Error, /pick which account/)
    end

    # Some institution flows omit the account id, and one unambiguous answer is
    # not a guess.
    it "takes the only payable account when Link named none" do
      allow(client).to receive(:accounts_get)
        .and_return(Plaid::AccountsGetResponse.new(accounts: [checking, credit_card], item:))

      record = service.connect!(public_token: "public-sandbox-1", account_id: nil)

      expect(record.provider_account_id).to eq("acc_checking")
    end

    it "refuses an empty public token without calling Plaid" do
      expect { service.connect!(public_token: "", account_id: "acc_checking") }
        .to raise_error(described_class::Error)

      expect(client).not_to have_received(:item_public_token_exchange)
    end
  end

  describe "one destination per venture" do
    # The partial unique index allows one live row. Connecting a new account has
    # to retire the old one, and the two halves are one fact — a crash between
    # them would leave a venture with no destination at all, having just been
    # told it had a new one.
    it "retires the previous destination rather than colliding with it" do
      old = create(:fuime_payout_method, :verified, event:, added_by: user)

      record = service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking")

      expect(old.reload).to be_removed
      expect(record).to be_verified
      expect(event.reload.fuime_payout_methods.live.count).to eq(1)
    end

    it "leaves the old destination alone when the new connection fails" do
      old = create(:fuime_payout_method, :verified, event:, added_by: user)

      expect { service.connect!(public_token: "public-sandbox-1", account_id: "acc_credit") }
        .to raise_error(described_class::Error)

      expect(old.reload).to be_verified
      expect(event.reload.fuime_payout_methods.usable.count).to eq(1)
    end
  end

  describe "what a family is told when Plaid says no" do
    # `display_message` is the field Plaid documents as safe to show an end user.
    # `error_message` is for developers and regularly names internal state.
    it "prefers Plaid's own words when they were written for a person" do
      allow(client).to receive(:item_public_token_exchange)
        .and_raise(plaid_error(display_message: "Your bank is temporarily unavailable."))

      expect { service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking") }
        .to raise_error(described_class::Error, "Your bank is temporarily unavailable.")
    end

    it "never leaks Plaid's developer message" do
      allow(client).to receive(:item_public_token_exchange).and_raise(plaid_error)

      expect { service.connect!(public_token: "public-sandbox-1", account_id: "acc_checking") }
        .to raise_error(described_class::Error) { |e|
          expect(e.message).not_to include("internal detail")
          expect(e.message).to match(/try connecting again/)
        }
    end
  end

  describe "configuration" do
    before do
      allow(described_class).to receive(:client).and_call_original
      allow(described_class).to receive(:configured?).and_call_original
    end

    around do |example|
      original = ENV.to_hash
      example.run
    ensure
      ENV.replace(original)
    end

    # The default is load-bearing. Plaid production connects REAL bank accounts,
    # and Fuime cannot pay one yet (§4.3 has no originator) — so a misconfigured
    # environment must never be the thing that promotes this to live banking.
    it "is sandbox unless production is asked for by name" do
      ENV.delete("PLAID_ENV")
      expect(described_class.env).to eq("sandbox")

      ENV["PLAID_ENV"] = ""
      expect(described_class.env).to eq("sandbox")

      # A typo is a typo, not a promotion.
      ENV["PLAID_ENV"] = "prod"
      expect(described_class.env).to eq("sandbox")

      ENV["PLAID_ENV"] = "production"
      expect(described_class.env).to eq("production")
    end

    it "reports itself unconfigured rather than raising at load time" do
      ENV.delete("PLAID_CLIENT_ID")
      ENV.delete("PLAID_SECRET")
      allow(Credentials).to receive(:fetch).and_return(nil)

      expect(described_class).not_to be_configured
      expect { described_class.client }.to raise_error(described_class::NotConfigured)
    end

    it "reads the flat environment names the deployment sets" do
      ENV["PLAID_CLIENT_ID"] = "client_1"
      ENV["PLAID_SECRET"] = "secret_1"

      expect(described_class.client_id).to eq("client_1")
      expect(described_class.secret).to eq("secret_1")
      expect(described_class).to be_configured
    end
  end
end
