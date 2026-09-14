# frozen_string_literal: true

require "rails_helper"

# Fuime L8: fuime.com must describe the product that exists.
#
# Fuime went live as merchant-of-record on 2026-08-20/21. For weeks afterwards
# the marketing pages kept saying "private beta", "test mode" and "no real money
# moves yet", described a guardian-owned Stripe account that was never built as
# "the plan", and offered a waitlist ("early access", "your turn") for an app
# anyone could already sign up to. Every one of those is a sentence a visitor,
# a parent or a regulator can hold against the site. This pins the phrases so
# the next copy pass cannot bring them back.
#
# Prices are pinned separately in spec/fuime_marketing_pricing_spec.rb; do not
# fold them in here.
RSpec.describe "Fuime marketing copy truth (L8)" do
  # Every page server.js serves, and the list is the guard: these checks are
  # hardcoded rather than globbed, so a page missing from here escapes ALL of
  # them — it may say "private beta", quote a retired rate, drop the not-a-bank
  # disclosure and ship no sign-up CTA, and the suite stays green.
  #
  # Keep in step with PUBLIC_FILES in site/server.js, with `public_pages` in
  # site/test/copy-guard.mjs (which replicates these assertions offline, for a
  # machine with no gem bundle), and with the page list in
  # site/test/server.test.mjs. Four lists, one fact — the marketing site has no
  # build step, so there is nowhere better to put it.
  public_pages = %w[
    site/index.html
    site/parents.html
    site/pricing.html
    site/payment-links.html
    site/subscriptions.html
    site/books.html
    site/taxes.html
    site/api.html
    site/merchant-of-record.html
    site/why-has-fuime-charged-me.html
    site/for/tutoring.html
    site/for/photo-video.html
    site/for/lawn-care.html
    site/for/schools.html
    site/compare.html
    site/compare/venmo.html
    site/compare/paddle.html
    site/compare/waiting.html
    site/roadmap.html
    site/faq.html
  ]

  # Matched case-insensitively against the whole file, HTML comments included:
  # a comment ships to the browser too, and a stale one is how the next edit
  # inherits the stale claim.
  banned_phrases = [
    "payments are not live",
    "no real money moves",
    "test mode",
    "early access",
    "your turn",
    "onboarding the first businesses",
    "not something running today"
  ]

  public_pages.each do |rel|
    it "#{rel} does not describe a beta, a queue, or an architecture that is not running" do
      body = File.read(Rails.root.join(rel)).downcase
      banned_phrases.each do |phrase|
        expect(body).not_to include(phrase), "#{rel} still says #{phrase.inspect}"
      end
    end
  end

  it "keeps the standing L5 disclosure on every public page" do
    public_pages.each do |rel|
      body = File.read(Rails.root.join(rel))
      expect(body).to include("financial technology company, not a bank"), "#{rel} lost the standing disclosure"
    end
  end

  # /start answered a cacheable "308 → /" for weeks, so a browser that saw it
  # may send a visitor to the dive no matter what server.js says now. Every
  # CTA points at /get-started, which has never been anything but a 307 into
  # the app's sign-up.
  it "points every call to action at /get-started and never at /start" do
    public_pages.each do |rel|
      body = File.read(Rails.root.join(rel))
      expect(body).to include('href="/get-started"'), "#{rel} has no /get-started call to action"
      expect(body).not_to include('href="/start"'), "#{rel} still links to /start"
    end
  end
end
