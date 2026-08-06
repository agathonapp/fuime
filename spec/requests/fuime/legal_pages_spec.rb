# frozen_string_literal: true

require "rails_helper"

# Fuime: the pre-launch legal set.
#
# These pages exist because /privacy previously redirected to
# hackclub.com/privacy-and-terms/ and /faq to help.hcb.hackclub.com — Fuime
# pointing its own users at another organisation's documents, which is a
# misrepresentation and a blocker on the first real signup
# (docs/fuime/LAUNCH_SPEC.md §1.3).
#
# The assertions worth having here are not "the page renders" but "the page is
# reachable by someone who has no account" and "it never sends a user to Hack
# Club for Fuime's own terms". A regression on either is silent in the browser
# and expensive in a courtroom.
LEGAL_PATHS = {
  "privacy policy"     => "/privacy",
  "terms of service"   => "/terms",
  "guardian agreement" => "/guardian-agreement",
  "FAQ"                => "/faq",
}.freeze

RSpec.describe "Legal pages", type: :request do
  describe "reachability without an account" do
    # A parent reading the guardian agreement before accepting an emailed
    # invite has no Fuime account. If these require a session, the agreement is
    # only readable by someone who has already agreed to it.
    LEGAL_PATHS.each do |name, path|
      it "serves the #{name} to a signed-out visitor" do
        get path

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "no longer deferring to Hack Club" do
    it "serves Fuime's own privacy policy rather than redirecting off-site" do
      get "/privacy"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("hackclub.com/privacy-and-terms")
    end

    it "serves Fuime's own FAQ rather than redirecting to HCB's help site" do
      get "/faq"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("help.hcb.hackclub.com")
    end
  end

  describe "the guardian agreement" do
    # The published agreement and the one a guardian signs must be the same
    # text. They are the same partial, and this pins that: if the versioned
    # partial is renamed or the version constant moves without a matching file,
    # the page silently degrades to an apology instead of the terms.
    it "renders the current versioned agreement, not a fallback" do
      get "/guardian-agreement"

      expect(response.body).to include(Guardianship::CURRENT_AGREEMENT_VERSION)
      expect(response.body).to include("You are the responsible adult")
      expect(response.body).not_to include("We could not load the agreement text")
    end

    it "names a stand-in rather than rendering an empty subject" do
      get "/guardian-agreement"

      expect(response.body).to include("your child")
    end
  end

  # Every one of these pages previously wrote "Fuime" where a contracting party
  # belongs, so the documents named no counterparty at all — L2 makes the guardian
  # the principal obligor, and an obligor needs someone to be obligated to. The
  # entity is also the Stripe Connect platform account holder, so it is the party
  # a chargeback or an indemnity claim actually reaches.
  describe "naming the legal entity" do
    let(:entity) { Rails.configuration.constants.legal_entity_name }

    it "is configured" do
      expect(entity).to be_present
    end

    ["/terms", "/privacy", "/guardian-agreement"].each do |path|
      it "names the entity on #{path}" do
        get path

        expect(response.body).to include(entity)
      end
    end

    # The footer disclosure is the one a reader sees without clicking anything,
    # which is why 12 CFR 328.102(b)(3)(ii) reasoning put it there unconditionally
    # in the first place.
    it "names the entity in the standing footer disclosure" do
      get "/terms"

      expect(response.body).to include("Fuime is a product of #{entity}")
      expect(response.body).to include("not a bank")
    end
  end

  describe "search indexing" do
    # Terms nobody can find are terms nobody read. These are the pages that
    # should be indexable; most of the app deliberately is not.
    LEGAL_PATHS.each do |name, path|
      it "allows the #{name} to be indexed" do
        get path

        expect(response.headers["X-Robots-Tag"]).to be_nil
      end
    end
  end
end
