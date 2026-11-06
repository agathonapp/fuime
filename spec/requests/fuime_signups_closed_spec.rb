# frozen_string_literal: true

require "rails_helper"

# Fuime::Signups: while sign-ups are closed nobody can make an account through a
# public door, everybody who has one still signs in, an invited person — whose
# User every invite path creates before mailing the link — walks through, and
# anyone else is sent to the waitlist on fuime.com's landing page.
RSpec.describe "sign-ups closed", :signups_closed, type: :request do
  let(:waitlist) { "https://fuime.com/#join" }
  let(:waitlist_no_account) { "https://fuime.com/?account=none#join" }

  before { ENV.delete("FUIME_SITE_ORIGIN") }

  describe Fuime::Signups do
    it "is closed unless the switch says exactly true" do
      expect(described_class).to be_closed

      ["false", "1", "yes", ""].each do |value|
        ENV[described_class::ENV_KEY] = value
        expect(described_class).to be_closed, "#{value.inspect} opened sign-ups"
      end

      ENV[described_class::ENV_KEY] = " TRUE "
      expect(described_class).to be_open
    end

    it "points at the landing page's waitlist, or the site FUIME_SITE_ORIGIN names" do
      expect(described_class.waitlist_url).to eq(waitlist)
      expect(described_class.waitlist_url(account_none: true)).to eq(waitlist_no_account)

      ENV["FUIME_SITE_ORIGIN"] = "http://localhost:4000/"
      expect(described_class.waitlist_url).to eq("http://localhost:4000/#join")
    end
  end

  describe "GET /users/auth?signup=true" do
    it "sends the visitor to the waitlist on fuime.com" do
      get auth_users_path(signup: true)

      expect(response).to redirect_to(waitlist)
    end

    it "sends a parent arriving to set up a family there too" do
      get auth_users_path(signup: true, return_to: "/setup/parent")

      expect(response).to redirect_to(waitlist)
    end
  end

  describe "GET /users/auth" do
    it "still signs people in, and points newcomers at the waitlist" do
      get auth_users_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in to Fuime")
      expect(response.body).to include(%(href="#{waitlist}"))
    end
  end

  describe "POST /logins" do
    def sign_in_with(email)
      post logins_path, params: { email:, login: { return_to: "/" } }
    end

    it "makes no account for an address that has none, and leaves for the waitlist" do
      email = "stranger-#{SecureRandom.hex(4)}@example.invalid"

      expect { sign_in_with(email) }.not_to(change { [User.count, Login.count] })

      # Rendered, not redirected: Turbo submits this form with fetch, which
      # cannot follow a redirect to another origin. 422 is what Turbo renders.
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(data-controller="navigate"))
      expect(response.body).to include(%(data-navigate-url-value="#{waitlist_no_account}"))
      expect(response.body).to include(%(href="#{waitlist_no_account}"))
      expect(response.body).to include(email)
    end

    it "refuses the application form's door the same way" do
      email = "applicant-#{SecureRandom.hex(4)}@example.invalid"

      expect {
        post logins_path, params: { email:, login: { purpose: "application" } }
      }.not_to change(User, :count)

      expect(response.body).to include(waitlist_no_account)
    end

    it "lets an existing user sign in, however they type their address" do
      user = create(:user, email: "already-here-#{SecureRandom.hex(4)}@example.invalid")

      expect { sign_in_with("  #{user.email.upcase} ") }.to change { user.logins.count }.by(1)

      expect(response).to redirect_to(email_login_path(user.logins.last))
    end

    it "lets in someone admitted from the waitlist" do
      invited = create(:user, creation_method: :waitlist)

      expect { sign_in_with(invited.email) }.to change { invited.logins.count }.by(1)
      expect(response).not_to have_http_status(:unprocessable_content)
    end

    it "lets in a guardian a teen invited, whose account the invite created" do
      guardian = User.create!(email: "guardian-#{SecureRandom.hex(4)}@example.invalid")

      expect { sign_in_with(guardian.email) }.to change { guardian.logins.count }.by(1)
    end
  end

  describe "the public export form" do
    let(:event) { create(:event, is_public: true, publishes_ledger: true) }

    before { allow_any_instance_of(Export::Event::Transactions::Csv).to receive(:async?).and_return(true) }

    it "makes no account for an address that has none" do
      expect {
        get transactions_exports_path(event: event.slug, format: :csv, email: "export-#{SecureRandom.hex(4)}@example.invalid")
      }.not_to(change { [User.count, Export.count] })

      expect(response).to redirect_to(collect_email_exports_path(file_extension: "csv", event_slug: event.slug))
      expect(flash[:error]).to include("sign-ups aren't open yet")
    end

    it "still mails an export to an address that has an account" do
      user = create(:user)

      expect {
        get transactions_exports_path(event: event.slug, format: :csv, email: user.email)
      }.to change(Export, :count).by(1)

      expect(Export.last.requested_by).to eq(user)
    end
  end

  describe "when sign-ups are open" do
    before { ENV[Fuime::Signups::ENV_KEY] = "true" }

    it "makes the account exactly as before" do
      email = "opened-#{SecureRandom.hex(4)}@example.invalid"

      expect { post logins_path, params: { email:, login: { return_to: "/" } } }.to change(User, :count).by(1)

      get auth_users_path(signup: true)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Start your business on Fuime")
    end
  end
end
