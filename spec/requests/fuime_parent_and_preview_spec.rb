# frozen_string_literal: true

require "rails_helper"

# Fuime: two reported breakages in the family flow.
RSpec.describe "the parent flow and the founder's own pay page", :merchant_of_record, type: :request do
  def sign_in(user)
    post logins_path, params: { email: user.email, login: { purpose: "" } }
    login = Login.order(:id).last
    post email_login_path(login)
    code = LoginCode.active.where(user:).order(:id).last
    post complete_login_path(login), params: { method: "email", login_code: code.code }
    expect(User::Session.where(user:)).to exist, "login failed for #{user.email}"
  end

  let(:guardian) { create(:user, birthday: 40.years.ago.to_date, verified: true) }
  let(:teen) { create(:user, birthday: 15.years.ago.to_date, verified: true) }
  let!(:venture) { create(:event, name: "Maya's Prints", organizers: [teen], is_public: true) }

  # A guardian has NO organizer position by design, so User#events — which the
  # home page read — returned nothing. The parent signed the agreement and their
  # home page listed no businesses at all, with no route to the one they had
  # just taken legal responsibility for.
  describe "a parent's home page" do
    before { Guardianship.create!(guardian:, minor: teen, status: :active) }

    it "lists the venture they signed for" do
      sign_in(guardian)

      get root_path

      expect(response.body).to include(ERB::Util.html_escape("Maya's Prints"))
      expect(response.body).to match(/Businesses you oversee/i)
    end

    # Not their business — they oversee it. The distinction is the legal framing
    # of the product (L2) and the page should not blur it.
    it "does not call it theirs" do
      sign_in(guardian)

      get root_path

      oversee_section = response.body.split("Businesses you oversee").last
      expect(oversee_section).to include("the young founder runs them")
    end

    it "shows nothing to an adult who signed for nobody" do
      stranger = create(:user, birthday: 40.years.ago.to_date, verified: true)
      sign_in(stranger)

      get root_path

      expect(response.body).not_to match(/Businesses you oversee/i)
    end

    # Oversight follows the ward's team membership; a revoked guardianship ends
    # it, which is what the agreement promises the minor in return.
    it "stops listing it once the guardianship is revoked" do
      Guardianship.for_guardian(guardian).update_all(status: Guardianship.statuses[:revoked])
      sign_in(guardian)

      get root_path

      expect(response.body).not_to include(ERB::Util.html_escape("Maya's Prints"))
    end
  end

  # A founder could publish a product and never see what they had made: pressing
  # Buy on their own page bounced them with a message about somebody else's
  # purchase, which reads as "your page is broken".
  #
  # FUIME (2026-09-15): first fixed with a preview card ("This is your pay
  # page… you can't buy from yourself"), which was the right shape only while the
  # buyer-age rule existed to bounce them. That rule is gone — see
  # Fuime::CheckoutsController#refuse_minor_buyer — so the founder now gets the
  # real button on their own page, and these examples assert that instead. The
  # `does not give them a way to actually pay` example is deliberately inverted
  # rather than deleted: it is now the assertion that they DO have one.
  describe "a founder looking at their own pay page" do
    # `Fuime::Offer#publish!` refuses while the venture cannot sell, so a
    # `:published` offer silently stays a draft unless the venture is actually
    # able to take payments. Stubbed rather than built: these examples are about
    # what the pay page renders, not about onboarding.
    before do
      allow_any_instance_of(Event).to receive(:selling_blockers).and_return([])
      allow_any_instance_of(Event).to receive(:show_public_pay_button?).and_return(true)
    end

    let!(:offer) do
      create(:fuime_offer, event: venture, name: "Poster print", price_cents: 25_00,
                           aasm_state: :published)
    end

    it "shows them exactly what their customers see" do
      sign_in(teen)

      get fuime_payment_page_path(event_slug: venture.slug, offer: offer.to_param)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pay $25.00")
      # No preview card standing in for the button any more.
      expect(response.body).not_to include("This is your pay page")
      expect(response.body).not_to match(/can't buy from yourself/i)
    end

    # Inverted on 2026-09-15. The founder gets a working form, posting to the
    # same endpoint a customer's does — which is the whole point of letting them
    # see their own page.
    it "gives them a real, working pay form" do
      sign_in(teen)

      get fuime_payment_page_path(event_slug: venture.slug, offer: offer.to_param)

      expect(response.body).to include(fuime_storefront_pay_path(slug: venture.slug))
      # The price is still the operator's, carried by the offer token rather than
      # an amount field the buyer could edit.
      expect(response.body).to include(offer.to_param)
      expect(response.body).not_to include("name=\"amount\"")
    end

    it "shows a signed-out customer the same button" do
      get fuime_payment_page_path(event_slug: venture.slug, offer: offer.to_param)

      expect(response.body).not_to include("This is your pay page")
      expect(response.body).to include("Pay $25.00")
    end
  end
end
