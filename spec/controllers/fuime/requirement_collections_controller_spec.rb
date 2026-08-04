# frozen_string_literal: true

require "rails_helper"

# Fuime: the guardian's identity-collection screen.
#
# Two things are being asserted. First, that only the guardian reaches it — a teen must
# never be on a page asking for an adult's Social Security number, both because they
# cannot supply it and because asking invites them to go and find it. Second, that
# nothing sensitive survives the request: not in the rendered HTML, not in the flash, not
# in the database.
RSpec.describe Fuime::RequirementCollectionsController do
  include SessionSupport

  render_views

  let(:venture) { create(:event, name: "Maya Prints", slug: "mayas-prints") }
  let(:minor) { create(:user, :minor) }
  let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }

  let(:details_params) do
    {
      event_slug: venture.slug,
      first_name: "Dana", last_name: "Okafor", dob: "1986-04-17",
      ssn_last_4: "6789",
      line1: "1 Founders Way", city: "Austin", state: "TX", postal_code: "78701"
    }
  end

  before do
    create(:organizer_position, event: venture, user: minor)
    create(:guardianship, :active, guardian:, minor:)
  end

  def cards_account
    create(:stripe_connected_account, :cards_enabled, :ready, event: venture, owner: guardian)
  end

  def stub_stripe
    allow(Stripe::Account).to receive(:update).and_return(
      Stripe::Account.construct_from(
        id: venture.stripe_connected_account.stripe_id,
        charges_enabled: true, payouts_enabled: true, details_submitted: true, livemode: false,
        controller: { losses: { payments: "application" }, fees: { payer: "application" },
                      requirement_collection: "application", stripe_dashboard: { type: "none" }
},
        capabilities: { card_payments: "active", transfers: "active", card_issuing: "active" },
        requirements: {}
      )
    )
    allow(Stripe::File).to receive(:create).and_return(Stripe::File.construct_from(id: "file_abc"))
  end

  describe "GET #show" do
    before { cards_account }

    it "renders for the guardian" do
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Verify your identity")
    end

    # The disclosure is the artifact the consent record points at, so it has to be on the
    # page the consent is given on.
    it "shows the disclosure about what happens to the details" do
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).to include("They go to Stripe, not to us")
      expect(response.body).to include("never the image")
    end

    it "lists what Stripe is still asking for, in plain language" do
      venture.stripe_connected_account.update!(
        requirements: { "currently_due" => %w[individual.ssn_last_4 individual.verification.document],
                        "past_due"      => []
}
      )
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response.body).to include("last 4 digits")
      # Asserted without the apostrophe from "owner's": ERB escapes it to `&#39;` in the
      # rendered output, so matching the raw sentence fails for a reason unrelated to the
      # behaviour under test.
      expect(response.body).to match(/government-issued ID/i)
    end

    # The reason this page is guardian-only is stronger than usual: the details are the
    # guardian's own.
    it "refuses the teen who runs the venture" do
      create_session(minor, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response).not_to have_http_status(:ok)
    end

    it "refuses an unrelated adult" do
      create_session(create(:user, birthday: 30.years.ago.to_date), verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response).not_to have_http_status(:ok)
    end

    # A payments-only venture has Stripe collecting directly, so Fuime must not gather an
    # SSN it has no need for.
    it "redirects a payments-only venture away" do
      venture.stripe_connected_account.destroy!
      create(:stripe_connected_account, :ready, event: venture.reload, owner: guardian)
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(response).to redirect_to(fuime_payment_setup_path(event_slug: venture.slug))
      expect(flash[:alert]).to match(/collected by Stripe directly/i)
    end
  end

  describe "POST #create" do
    before do
      cards_account
      stub_stripe
    end

    it "forwards the details and records the verification" do
      create_session(guardian, verified: true)

      expect {
        post :create, params: details_params
      }.to change(GuardianVerification, :count).by(1)

      expect(response).to redirect_to(fuime_payment_setup_path(event_slug: venture.slug))
      expect(flash[:notice]).to match(/sent your details to Stripe/i)
    end

    it "records only field names, and the consent provenance" do
      create_session(guardian, verified: true)

      post :create, params: details_params

      record = GuardianVerification.last
      expect(record.fields_forwarded).to include("ssn_last_4", "dob", "address")
      expect(record.consent_ip).to be_present
      expect(record.doc_version_hash).to be_present
      expect(record.user).to eq(guardian)
    end

    # THE assertion. If any submitted value is persisted, the design has failed.
    it "persists no identity value" do
      create_session(guardian, verified: true)

      post :create, params: details_params

      serialized = GuardianVerification.last.attributes.to_json
      %w[6789 Okafor Dana 78701 1986].each do |secret|
        expect(serialized).not_to include(secret), "#{secret} was persisted"
      end
    end

    it "uploads a document to Stripe and keeps only the token" do
      create_session(guardian, verified: true)
      file = Rack::Test::UploadedFile.new(StringIO.new("fake-image"), "image/png", original_filename: "id.png")

      post :create, params: details_params.merge(id_document: file)

      record = GuardianVerification.last
      expect(record.vendor_ref).to eq("file_abc")
      expect(record.fields_forwarded).to include("id_document")
      expect(record.evidence_released_at).to be_present
    end

    it "refuses an empty submission with a usable message" do
      create_session(guardian, verified: true)

      post :create, params: { event_slug: venture.slug }

      expect(GuardianVerification.count).to eq(0)
      expect(flash[:alert]).to match(/at least one of the details/i)
    end

    # A re-rendered form would put the SSN into the HTML of an error page, so the
    # controller redirects instead. This pins that behaviour.
    it "redirects rather than re-rendering when Stripe rejects the details" do
      allow(Stripe::Account).to receive(:update)
        .and_raise(Stripe::InvalidRequestError.new("invalid ssn_last_4: 6789", nil))
      create_session(guardian, verified: true)

      post :create, params: details_params

      expect(response).to redirect_to(fuime_requirement_collection_path(event_slug: venture.slug))
      expect(flash[:alert]).not_to include("6789")
      expect(response.body).not_to include("6789")
    end

    it "does not let the teen submit an adult's details" do
      create_session(minor, verified: true)

      post :create, params: details_params

      expect(GuardianVerification.count).to eq(0)
    end
  end

  describe "the disclosure text" do
    # Stripe's US Issuing compliance rules require the commercial-purpose sentence
    # wherever the card program is described, and forbid the consumer-flavoured
    # phrasings. Checked against the rendered partial so a copy edit cannot drop one.
    it "satisfies Stripe's required and forbidden card copy" do
      cards_account
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      expect(Fuime::CardSpendPolicy.copy_violations(response.body)).to be_empty
    end

    # L5: no bank vocabulary while there is no partner bank.
    it "avoids the forbidden banking vocabulary" do
      cards_account
      create_session(guardian, verified: true)

      get :show, params: { event_slug: venture.slug }

      disclosure = response.body[/What happens to the details you enter.*?Send to Stripe/m].to_s

      expect(disclosure).to include("not a bank")
      expect(disclosure).not_to match(/\byour (bank|checking|savings) account with Fuime\b/i)
      expect(disclosure).not_to match(/\bFDIC-insured\b(?!\s+products)/i)
    end
  end
end
