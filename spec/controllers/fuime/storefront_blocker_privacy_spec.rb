# frozen_string_literal: true

require "rails_helper"

# Fuime: the public storefront must never explain why a venture cannot sell.
#
# Event#selling_blockers produces strings like "Jane Doe is 15." and "Jane Doe
# needs a parent or guardian on the account." They exist so an operator and their
# guardian can fix the problem. The storefront is a public, unauthenticated URL a
# teenager shares with customers — publishing a child's age there, or announcing
# that Fuime suspended their business, is a disclosure with no upside.
#
# This is easy to regress: the blockers are already computed for that page (the
# pay form is gated on them), so rendering them is a one-line "helpful" change.
# These examples are the thing that stops it.
#
# The operator-facing side is covered by spec/controllers/fuime/payouts_controller_spec.rb
# and the partial at app/views/fuime/_selling_blockers.html.erb.
RSpec.describe Fuime::StorefrontsController, "blocker privacy", type: :controller do
  render_views

  # Pinned name and a pinned age, because the assertions match rendered HTML.
  let(:operator) { create(:user, :minor_with_guardian, full_name: "Maya Operator", birthday: 15.years.ago.to_date) }
  let(:event) { create(:event, name: "Maya Prints", slug: "maya-prints", is_public: true, organizers: [operator]) }
  let!(:account) { create(:stripe_connected_account, :ready, event:) }

  # Sanity: if this ever renders a pay form, the examples below are vacuous.
  def expect_no_pay_form
    expect(response.body).not_to include(fuime_storefront_pay_path(slug: event.slug))
  end

  # Assertions run against the UNESCAPED page, so a leak cannot hide behind HTML
  # entities. "Maya Operator is 15." rendered through `<%= %>` is byte-different
  # from the raw blocker string, and a plain `not_to include` would pass while the
  # age sat in the markup in plain sight.
  def rendered_text
    CGI.unescapeHTML(response.body)
  end

  context "when the venture is suspended" do
    before { event.update!(operator_vetting_status: :suspended) }

    it "renders without saying it was suspended" do
      get :show, params: { slug: event.slug }

      expect(response).to have_http_status(:ok)
      expect_no_pay_form
      expect(rendered_text).not_to match(/suspended/i)
    end

    it "does not name the operator's age" do
      get :show, params: { slug: event.slug }

      expect(rendered_text).not_to match(/\bis 15\b/)
    end

    # The pre-existing copy asserted a specific reason ("a parent or guardian
    # still needs to finish setting up"). Once vetting could also be the cause,
    # that sentence became a confident statement of the wrong thing — the account
    # here is fully ready.
    it "does not blame the guardian for a Fuime decision" do
      get :show, params: { slug: event.slug }

      expect(rendered_text).not_to match(/parent or guardian still needs/i)
    end
  end

  context "when the venture is merely unreviewed" do
    before { event.update!(operator_vetting_status: :unvetted) }

    it "says nothing about approval" do
      get :show, params: { slug: event.slug }

      expect(response).to have_http_status(:ok)
      expect_no_pay_form
      expect(rendered_text).not_to match(/not been approved|approv/i)
    end
  end

  context "when the launch scope is what blocks it", :merchant_of_record do
    before { event.update!(business_category: "food") }

    # These blockers are the most disclosive of all — they name people and ages.
    it "leaks neither the category refusal nor the operator's age" do
      get :show, params: { slug: event.slug }

      expect(response).to have_http_status(:ok)
      expect(rendered_text).not_to match(/service and digital businesses/i)
      expect(rendered_text).not_to include("Maya Operator is")
      expect(rendered_text).not_to match(/\bis 15\b/)
    end

    # Belt and braces: whatever the blockers happen to say, none of them should
    # appear verbatim. This keeps the guarantee true if the wording changes.
    it "renders none of the blocker strings verbatim" do
      blockers = event.selling_blockers
      expect(blockers).not_to be_empty, "precondition: this venture should be blocked"

      get :show, params: { slug: event.slug }

      blockers.each do |blocker|
        expect(rendered_text).not_to include(blocker), "storefront leaked: #{blocker}"
      end
    end
  end

  # The other half of the guarantee: when nothing is wrong, the page still works.
  # A privacy control that silently breaks the happy path is a worse bug than the
  # one it prevents.
  context "when the venture is fine" do
    it "still renders the pay form" do
      get :show, params: { slug: event.slug }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(fuime_storefront_pay_path(slug: event.slug))
    end
  end
end
