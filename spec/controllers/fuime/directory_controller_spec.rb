# frozen_string_literal: true

require "rails_helper"

# Fuime: the public directory.
#
# Two things are under test and only one of them is ordinary. The ordinary half is
# that the right businesses appear. The other half is that this page stays a
# LISTING and never becomes a DISPATCH — no ranking, no ratings, no Fuime-set
# prices, no work routed to anyone.
#
# That is a legal boundary rather than a design preference: the brief's own
# mitigation for the worker-classification risk is "operators control their own
# pricing, clients and hours — we never route work to them or set rates", and a
# directory that ranks or scores is doing exactly that. A rule like that survives
# in a codebase only if something fails when it is broken, which is what the last
# describe block is for. See MOR_MIGRATION_PLAN §8.3 D2.
RSpec.describe Fuime::DirectoryController, type: :controller do
  render_views

  # Pinned names: these assertions match rendered HTML, and a Faker name with an
  # apostrophe is escaped in the output. Same trap as storefronts_controller_spec.
  # Attributes are set at CREATE rather than by updating afterwards. Flipping
  # `is_public` on an existing event fires an after_update_commit that mails a
  # transparency notice and falls back to `User.system_user`, a row the test
  # database has no reason to contain — so the update path fails for reasons that
  # have nothing to do with the directory.
  def listable(name:, slug:, category: "services", **attrs)
    event = create(:event, {
      name:, slug:, business_category: category,
      is_public: true, is_indexable: true
    }.merge(attrs))
    create(:stripe_connected_account, :ready, event:)
    event
  end

  describe "who appears" do
    it "lists a vetted venture that can take payments" do
      listable(name: "Maya Design", slug: "maya-design")

      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Maya Design")
      expect(response.body).to include(fuime_storefront_path(slug: "maya-design"))
    end

    # #accepts_payments? folds vetting in, so these fall out of the directory
    # without a second rule that could drift from the first.
    it "hides a venture nobody has approved" do
      listable(name: "Unreviewed Co", slug: "unreviewed-co").update!(operator_vetting_status: :unvetted)

      get :index

      expect(response.body).not_to include("Unreviewed Co")
    end

    it "hides a suspended venture" do
      listable(name: "Suspended Co", slug: "suspended-co").update!(operator_vetting_status: :suspended)

      get :index

      expect(response.body).not_to include("Suspended Co")
    end

    # A listing that leads to a dead payment form is worse than no listing.
    it "hides a venture with no connected account" do
      create(:event, name: "No Account Co", slug: "no-account-co",
                     business_category: "services", is_public: true, is_indexable: true)

      get :index

      expect(response.body).not_to include("No Account Co")
    end

    it "hides private, non-indexable, demo and hidden ventures" do
      listable(name: "Private Co", slug: "private-co", is_public: false)
      listable(name: "Noindex Co", slug: "noindex-co", is_indexable: false)
      listable(name: "Demo Co", slug: "demo-co", demo_mode: true)
      listable(name: "Hidden Co", slug: "hidden-co", hidden_at: Time.current)

      get :index

      ["Private Co", "Noindex Co", "Demo Co", "Hidden Co"].each do |name|
        expect(response.body).not_to include(name)
      end
    end
  end

  describe "filtering and ordering" do
    it "filters by category" do
      listable(name: "Servicey Co", slug: "servicey-co", category: "services")
      listable(name: "Crafty Co", slug: "crafty-co", category: "crafts")

      get :index, params: { category: "crafts" }

      expect(response.body).to include("Crafty Co")
      expect(response.body).not_to include("Servicey Co")
    end

    it "ignores a category outside the known set rather than filtering on it" do
      listable(name: "Servicey Co", slug: "servicey-co")

      get :index, params: { category: "'; DROP TABLE events; --" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Servicey Co")
    end

    it "orders alphabetically on request" do
      listable(name: "Zeta Co", slug: "zeta-co")
      listable(name: "Alpha Co", slug: "alpha-co")

      get :index, params: { order: "name" }

      expect(response.body.index("Alpha Co")).to be < response.body.index("Zeta Co")
    end

    # Asserted through BEHAVIOUR rather than through an ivar: what matters is that
    # an unrecognised ordering cannot make the page order by something Fuime does
    # not offer, and the newest-first default is observable in the output.
    it "falls back to the neutral default for an unknown ordering" do
      listable(name: "Alpha Co", slug: "alpha-co")
      listable(name: "Zeta Co", slug: "zeta-co") # created last, so newest

      get :index, params: { order: "highest_rated" }

      expect(response).to have_http_status(:ok)
      expect(response.body.index("Zeta Co")).to be < response.body.index("Alpha Co")
    end
  end

  # ── The boundary ──────────────────────────────────────────────────────────
  describe "stays a listing, never a dispatch" do
    before { listable(name: "Maya Design", slug: "maya-design") }

    # Every ordering offered must be neutral by construction. If someone adds
    # "most popular" or "highest rated", this fails — which is the point.
    it "offers only neutral orderings" do
      expect(described_class::ORDERINGS.keys).to contain_exactly("newest", "name")
    end

    it "shows no ratings, reviews or performance metrics" do
      get :index

      expect(response.body).not_to match(/\brating|\breview|\bstars?\b|response rate|completion rate|acceptance rate/i)
    end

    it "promotes nobody" do
      get :index

      expect(response.body).not_to match(/featured|top rated|recommended|best match|verified pro/i)
    end

    # Operators price themselves, on their own storefront. A price on a Fuime
    # index is Fuime quoting on their behalf.
    it "quotes no prices" do
      get :index

      expect(response.body).not_to match(/\$\d|per hour|hourly rate|starting at/i)
    end

    it "says plainly that Fuime does not assign work or set rates" do
      get :index

      expect(response.body).to match(/does not assign work, set rates, or rank/i)
    end
  end

  # The directory is public, so the same rule as the storefront applies: it lists
  # BUSINESSES. A minor's identity is not directory data.
  describe "privacy" do
    it "names no operator and states no age" do
      operator = create(:user, :minor_with_guardian, full_name: "Maya Operator", birthday: 15.years.ago.to_date)
      event = listable(name: "Maya Design", slug: "maya-design")
      create(:organizer_position, event:, user: operator)

      get :index

      expect(response.body).to include("Maya Design")
      expect(response.body).not_to include("Maya Operator")
      # The shape an age actually takes in Fuime copy (Event#selling_blockers
      # renders "Maya Operator is 15."). A bare /\b15\b/ matches SVG path data in
      # the page chrome and proves nothing.
      expect(response.body).not_to match(/is 15\b/)
    end
  end
end
