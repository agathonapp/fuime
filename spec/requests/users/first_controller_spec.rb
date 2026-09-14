# frozen_string_literal: true

require "rails_helper"

# FUIME-DISABLED: the FIRST Robotics dashboard, its public landing page, and the
# team-invite request flow.
#
# `app/views/users/first` is not "a user's first venture" — it is upstream HCB's
# programme for FIRST Robotics (FRC/FTC/FLL) booster clubs, and none of it
# describes anything Fuime does:
#
#   - `/first/welcome` was PUBLIC (`skip_before_action :signed_in_user`) and
#     headed "FIRST on Fuime — the ultimate booster club for FRC, FTC and FLL
#     teams" under the Fuime logo, offering "501(c)(3) nonprofit status: become
#     part of Hack Club's legal entity". Fuime is a for-profit platform for teen
#     businesses; it cannot confer 501(c)(3) status and has no relationship with
#     FIRST or with Hack Club's legal entity.
#   - `GET /first` composed an advisor email reading "a nonprofit, Hack Club.
#     They run a service called Fuime", linked to
#     hackclub.com/fiscal-sponsorship/first/, and CC'd hcb-raffles@hackclub.com.
#   - It also surfaced three Hack Club "FIRST Worlds 2026" raffles.
#
# As with the fiscal sponsorship letters (spec/requests/documents_letters_spec.rb),
# rebranding would turn a true statement about Hack Club into a false one about
# Fuime, so the routes are removed while the controller, views and specs remain
# (CLAUDE.md Rule 2). These examples pin the disabled state, so restoring a route
# trips a red suite.
#
# Two actions deliberately stay routed and are exercised below:
# `verify_email` and `sign_out` are generic account actions that merely happen to
# live on this controller, and `application/_user_menu` renders both for
# signed-out and unverified visitors on every page.
RSpec.describe "Users::FirstController", type: :request do
  # The path helpers are gone, so these must be written as raw URLs. Request
  # specs run the full middleware stack, which turns an unrecognised path into a
  # 404 rather than letting ActionController::RoutingError escape — and asserting
  # on the status is the better test anyway, since it is what a client receives.
  def expect_no_route(verb, path)
    public_send(verb, path)

    expect(response).to have_http_status(:not_found)
    expect { Rails.application.routes.recognize_path(path, method: verb) }
      .to raise_error(ActionController::RoutingError)
  end

  describe "the removed FIRST Robotics routes" do
    # `/first` and `/first/team` do not 404: they now fall through to the event
    # slug route (`events#show` with id "first"), because "first" is a perfectly
    # ordinary venture slug. So the meaningful assertion is that they no longer
    # reach Users::FirstController, not that they are unrouted.
    def expect_not_first_controller(verb, path)
      recognized = Rails.application.routes.recognize_path(path, method: verb)
      expect(recognized[:controller]).not_to eq("users/first")
    rescue ActionController::RoutingError
      :unrouted # also acceptable — the path resolves to nothing at all
    end

    it "no longer serves the public FIRST landing page" do
      expect_no_route(:get, "/first/welcome")
    end

    it "no longer serves the raffle QR code" do
      expect_no_route(:get, "/first/macbook_qr_code")
    end

    it "no longer serves the FIRST dashboard" do
      expect_not_first_controller(:get, "/first")
    end

    it "no longer accepts a FIRST signup" do
      expect_not_first_controller(:post, "/first")
    end

    it "no longer serves the team lookup page" do
      expect_not_first_controller(:get, "/first/team")
    end

    it "no longer accepts an organization invite request" do
      expect_no_route(:post, "/first/request_org_invite")
    end
  end

  describe "the account actions that remain" do
    it "still routes POST /first/verify_email" do
      expect(Rails.application.routes.recognize_path("/first/verify_email", method: :post))
        .to include(controller: "users/first", action: "verify_email")
    end

    it "still routes DELETE /first/sign_out" do
      expect(Rails.application.routes.recognize_path("/first/sign_out", method: :delete))
        .to include(controller: "users/first", action: "sign_out")
    end

    # The original example signed a user up through `POST /first` to get a
    # session to sign out of, which is exactly the route that is now gone. The
    # cookie-clearing behaviour belongs to SessionsHelper#sign_out and is covered
    # there; what matters here is that the action is still reachable and still
    # sends the visitor somewhere sensible.
    it "signs out and redirects to the sign-in page" do
      delete "/first/sign_out"

      expect(response).to redirect_to(auth_users_path)
    end
  end
end
