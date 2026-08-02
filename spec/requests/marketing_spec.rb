# frozen_string_literal: true

require "rails_helper"

# FUIME-DISABLED: the /for/funders marketing pages.
#
# Upstream this file had 22 examples asserting the funders landing page renders,
# is indexable, and converts. Fuime 404s all three routes instead — see the
# FUIME-DISABLED note in MarketingController for why the copy could not simply
# be rebranded (JSON-LD claiming Hack Club's EIN as Fuime's legal identity,
# "backed by a 501(c)(3)", and platform totals HCB earned, all on a page that
# deliberately opts *in* to search indexing).
#
# These examples pin the disabled state, so re-enabling the pages trips a red
# suite rather than silently republishing false claims. When Fuime has its own
# funder story, recover the upstream examples from git history and adapt their
# copy assertions instead of writing them fresh.
RSpec.describe "Funders landing page", type: :request do
  it "does not serve the funders landing page" do
    get funders_path

    expect(response).to redirect_to(root_path)
  end

  it "does not serve the funders FAQ" do
    get funders_faq_path

    expect(response).to redirect_to(root_path)
  end

  it "does not accept funder inquiries" do
    post funder_inquiry_path, params: { email: "funder@example.com" }

    expect(response).to redirect_to(root_path)
  end

  # The strongest guarantee: none of the false claims can reach a visitor.
  it "never renders Hack Club's legal identity or charitable claims" do
    get funders_path
    follow_redirect!

    expect(response.body).not_to include("81-2908499")
    expect(response.body).not_to include("The Hack Foundation")
    expect(response.body).not_to include("Deploy your capital as grants")
  end
end
