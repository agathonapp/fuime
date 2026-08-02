# frozen_string_literal: true

require "rails_helper"

# FUIME-DISABLED: the fiscal sponsorship and verification letter endpoints.
#
# Both were reachable GETs linked from every organization's Documents page, and
# both rendered a PDF on Hack Club letterhead: their logo, a real Hack Club
# employee's scanned signature, and EIN 81-2908499.
#
#   - The fiscal sponsorship letter asserted "The Hack Foundation (d.b.a. Hack
#     Club) is acting as the nonprofit fiscal sponsor for <business>". Fuime is
#     not a fiscal sponsor and holds no 501(c)(3) status, so no truthful Fuime
#     version of this document exists — it was disabled, not rebranded.
#   - The verification letter went further, attesting a fund "in good standing
#     with Column N.A., a Member of the FDIC" and printing the account and
#     routing numbers. That is a bank-verification letter, the kind handed to a
#     landlord or a bank, and Fuime can substantiate none of it.
#
# The half-finished M3 rebrand had made this worse rather than better: the
# contact line was rewritten to support@fuime.com while the letterhead, EIN and
# signature stayed Hack Club's, so a recipient verifying the claim would reach
# Fuime about an assertion only Hack Club could make.
#
# The routes are removed while the controller actions, templates and
# DocumentPolicy entries remain (CLAUDE.md Rule 2: disable, don't delete). These
# examples pin the disabled state so restoring the routes trips a red suite.
RSpec.describe "Document letters", type: :request do
  let(:event) { create(:event) }

  # Routes are removed, so the path helpers no longer exist and these must be
  # written as raw URLs.
  #
  # Request specs go through the full middleware stack, which converts an
  # unrecognised path into a 404 response rather than letting
  # ActionController::RoutingError escape. Asserting on the status is also the
  # better test: it checks what a client actually receives.
  def expect_no_route(path)
    get path

    expect(response).to have_http_status(:not_found)
    expect { Rails.application.routes.recognize_path(path) }
      .to raise_error(ActionController::RoutingError)
  end

  it "does not route the fiscal sponsorship letter" do
    expect_no_route("/#{event.slug}/fiscal_sponsorship_letter.pdf")
  end

  it "does not route the fiscal sponsorship letter preview" do
    expect_no_route("/#{event.slug}/fiscal_sponsorship_letter.png")
  end

  it "does not route the verification letter" do
    expect_no_route("/#{event.slug}/verification_letter.pdf")
  end

  it "does not route the verification letter preview" do
    expect_no_route("/#{event.slug}/verification_letter.png")
  end

  # Guards the named routes specifically: a future `resources :documents` change
  # that re-adds member routes would be caught here even if the URLs shifted.
  it "defines no route helpers for either letter" do
    expect(Rails.application.routes.named_routes.names.map(&:to_s))
      .not_to include(
        a_string_matching(/fiscal_sponsorship_letter/),
        a_string_matching(/verification_letter/)
      )
  end
end
