# frozen_string_literal: true

# Fuime: /learn — how to start the business, and what the money does once it
# starts.
#
# Two halves, deliberately on one surface:
#
#   Templates — Fuime::ServiceCatalog, the same ten starter templates the
#               application flow offers, made browsable BEFORE signing up. Each
#               one carries things to list, where the first customers come from,
#               and what goes wrong in that particular trade.
#   Lessons   — Fuime::Playbook, the money that is the same in every trade: what
#               a customer's payment turns into, how to arrive at a price, what
#               tax was never yours, what a chargeback does.
#
# ── Why this is public ──────────────────────────────────────────────────────
#
# The templates already exist inside the funnel, behind a sign-up, at the moment
# somebody has to answer "what is your business" — which is the worst possible
# moment to be reading them for the first time. Somebody deciding whether to
# start at all is exactly who this is for, and they do not have an account yet.
#
# Indexable for the same reason (`INDEXABLE_CONTROLLER_PATHS` in
# ApplicationController). Nothing here names a venture, an operator or an
# amount — it is written content only, so the usual objection to indexing a page
# about minors does not apply. No page in this controller may ever render a
# venture's data; see the request spec.
#
# ── The `?venture=` parameter ───────────────────────────────────────────────
#
# The only dynamic thing here. A signed-in founder arriving from their own org
# nav carries their venture slug, which turns each "thing to list" on a template
# page into a link that opens the new-offer form with the name already filled in
# and the price box empty. Resolved through the same policy the offers page uses,
# and silently dropped when it does not check out — a bad or borrowed slug makes
# the page render as the public version rather than raising, because this page is
# reachable by people who are not signed in at all.
class LearnController < ApplicationController
  skip_before_action :signed_in_user
  skip_before_action :redirect_to_onboarding
  skip_after_action :verify_authorized # nothing here is a record anybody owns

  before_action :set_venture

  def index
    # `sellable` rather than `services`: a template for something a venture may
    # not currently be created under is an advert for a dead end.
    @services = Fuime::ServiceCatalog.sellable
    @lessons = Fuime::Playbook.lessons
  end

  # One lesson from Fuime::Playbook.
  def show
    @lesson = Fuime::Playbook.find(params[:slug])
    return redirect_to learn_path unless @lesson

    @other_lessons = Fuime::Playbook.lessons - [@lesson]
  end

  # One starter template from Fuime::ServiceCatalog.
  def template
    @service = Fuime::ServiceCatalog.find(params[:slug])

    # Scoped to `sellable` and not just `find`, so a service that stops being
    # offerable stops being linkable in the same commit.
    return redirect_to learn_path unless @service && Fuime::ServiceCatalog.sellable.include?(@service)

    @lessons = Fuime::Playbook.lessons
  end

  private

  # The venture whose new-offer form the "add this" links should point at, or nil.
  #
  # nil is an ordinary outcome, not an error: signed out, no slug, a slug for a
  # venture that does not exist, or one the current user may not price. Every
  # one of those renders the same public page — see the class header.
  def set_venture
    slug = params[:venture].presence
    return if slug.nil? || !signed_in?

    # Rescued rather than checked: FriendlyId raises RecordNotFound for a slug
    # nobody owns, which Rails turns into a 404 — and a 404 is the wrong answer
    # on a public reading page that somebody reached with a stale link in the
    # query string. The page is fine; only the pre-fill links are not.
    event = begin
      Event.friendly.find(slug)
    rescue ActiveRecord::RecordNotFound
      nil
    end
    return if event.nil?

    # `manage_offers?` and not `offers?`: the links write into the pricing form,
    # and a guardian who may read the offers page is deliberately not somebody
    # who sets their kid's rates (see Fuime::OffersController).
    @venture = event if policy(event).manage_offers?
  end

end
