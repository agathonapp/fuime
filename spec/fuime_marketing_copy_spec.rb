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

  # site/index.html is the stealth front door since 2026-11-06: the mark and
  # nothing else, so it makes no claim to disclose against. The block below
  # requires the disclosure the moment it mentions banking again.
  it "keeps the standing L5 disclosure on every public page" do
    public_pages.each do |rel|
      next if rel == "site/index.html"

      body = File.read(Rails.root.join(rel))
      expect(body).to include("financial technology company, not a bank"), "#{rel} lost the standing disclosure"
    end
  end

  # /start answered a cacheable "308 → /" for weeks, so a browser that saw it
  # may send a visitor to the dive no matter what server.js says now. Every
  # CTA points at /get-started, which has never been anything but a 307 into
  # the app's sign-up.
  # site/index.html is excluded: since 2026-11-06 it is a stealth page with no
  # call to action at all. It is pinned by the block below instead.
  it "points every call to action at /get-started and never at /start" do
    public_pages.each do |rel|
      body = File.read(Rails.root.join(rel))
      expect(body).not_to include('href="/start"'), "#{rel} still links to /start"
      next if rel == "site/index.html"

      expect(body).to include('href="/get-started"'), "#{rel} has no /get-started call to action"
    end
  end

  # The front door. A stealth page since 2026-11-06 (the full page waits at
  # site/legacy/index-agent-2026-11.html); these rules hold whatever it grows
  # back into. Mirrored offline by checkFrontDoor in site/test/copy-guard.mjs.
  describe "the front door (site/index.html)" do
    let(:body) { File.read(Rails.root.join("site/index.html")) }

    # Fuime::Signups sends a sign-in that finds no account to /?account=none#join.
    it "keeps the target the app redirects to" do
      expect(body).to include('id="join"')
      expect(body).to include("data-account-none")
    end

    it "carries the not-a-bank disclosure whenever it mentions banking" do
      next unless body.match?(/\bbank/i)

      expect(body).to include("financial technology company, not a bank")
    end

    it "makes no claim the business cannot back yet" do
      expect(body).not_to match(/\bAPY\b/i), "quotes an APY"
      expect(body).not_to match(/\$\s?250,?000|250k/i), "quotes an FDIC insurance amount"
      expect(body).not_to match(/trusted by|testimonial|customers love|businesses use fuime/i),
                          "claims social proof Fuime does not have"
    end

    it "uses no em-dashes" do
      expect(body).not_to include("\u2014")
    end
  end
end
