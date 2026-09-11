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
  # Everything server.js will serve as a page: the dive at /, its scroll
  # variant, and the three closed-but-on-disk marketing pages (CLOSED in
  # site/server.js bounces them to / today, and they come back as-is).
  public_pages = %w[
    site/start.html
    site/start-scroll.html
    site/index.html
    site/parents.html
    site/pricing.html
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
