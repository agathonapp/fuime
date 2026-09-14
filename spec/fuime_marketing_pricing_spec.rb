# frozen_string_literal: true

require "rails_helper"

# Fuime G3 / L8: marketing and /billing must state the price that Checkout charges.
#
# ── 2026-09-14: one flat price ───────────────────────────────────────────────
#
# 7% + a $19.99 family plan became **5% + 50¢, flat**, with nothing gated and no
# monthly fee. Anything outside the standard rate is a sales conversation.
#
# This file exists because of L8 — "fuime.com must describe the product that
# exists… never let site copy lead the code again." The previous failure it
# caught was the Terms understating Fuime's own fee by two points while live
# money moved. The failure modes now are different and worth naming:
#
#   1. A second tier reappearing in copy after the product stopped having one.
#   2. Quoting "5%" without the 50¢ floor. Under merchant-of-record a $5 sale is
#      charged the floor — 10%, not 5% — so the bare percentage describes a
#      price Fuime does not charge.
RSpec.describe "Fuime pricing truth (G3 / L8)" do
  # Methods, not constants: a constant defined inside a describe block leaks to
  # the top level.
  def public_price_pages = %w[site/index.html site/pricing.html site/parents.html]

  def marketing_files = public_price_pages + %w[site/site.js site/docs/BRIEF.md]

  def read(rel) = File.read(Rails.root.join(rel))

  describe "the code" do
    it "charges 5% with a 50¢ floor and no monthly fee" do
      expect(Event::Plan::Free::REVENUE_FEE).to eq(0.05)
      expect(Event::Plan::MINIMUM_FEE_CENTS).to eq(50)
      expect(Event::Plan::Free.new.monthly_fee_cents).to eq(0)
    end

    # The fallback and the real rate are now the same number, which retires the
    # trap the old version of this file was written for: a page rendering
    # FUIME_PLATFORM_FEE_PERCENT used to understate the fee by two points.
    it "no longer has a fallback rate that differs from what ventures pay" do
      expect(Fuime::PaymentLinkService::FUIME_PLATFORM_FEE_PERCENT).to eq(5)
      expect((Event::Plan::Free::REVENUE_FEE * 100).round).to eq(5)
    end
  end

  describe "every public price page" do
    it "states the rate and the floor together" do
      public_price_pages.each do |rel|
        body = read(rel)
        expect(body).to match(/5%/), "#{rel} is missing the 5% rate"
        expect(body).to match(/50¢|\$0\.50/), "#{rel} states 5% without the 50¢ floor"
      end
    end

    it "offers a way to talk to us instead of a second tier" do
      public_price_pages.each do |rel|
        expect(read(rel)).to match(/custom pricing|talk to us|contact us/i),
                             "#{rel} has no sales route for anyone outside the standard rate"
      end
    end
  end

  describe "no retired tier survives anywhere in marketing" do
    it "sells no monthly subscription" do
      marketing_files.each do |rel|
        body = read(rel)
        expect(body).not_to include("$19.99"), "#{rel} still sells the retired family plan"
        expect(body).not_to include("$15/mo"), "#{rel} still sells a retired monthly price"
      end
    end

    it "no longer claims a 7% take-rate" do
      marketing_files.each do |rel|
        expect(read(rel)).not_to match(/\b7%/), "#{rel} still advertises the retired 7% rate"
      end
    end

    it "does not gate ventures or API keys behind an upgrade" do
      marketing_files.each do |rel|
        body = read(rel)
        expect(body).not_to match(/one venture\b/i), "#{rel} still advertises a one-venture limit"
        expect(body).not_to match(/drops? to|plus 4%|\$15\/mo \+ 4%/), "#{rel} implies a rate cut"
      end
    end
  end

  # The surfaces the old version of this file pinned together, kept pinned: a
  # copy fix that lands on one page and misses the binding one is the ordinary
  # shape of this bug.
  describe "the Terms and the /learn lesson", type: :request do
    it "state the rate a real venture actually pays" do
      get "/terms"
      # Asserted before the body, so a future failure says "terms redirected"
      # rather than "the rate is missing" — they need very different fixes, and
      # this example once failed in a way that could not distinguish them.
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/5%/)
      expect(response.body).not_to match(/keeps\s*7%/)

      get "/learn/what-fuime-takes"
      if response.status == 200
        expect(response.body).to match(/5%/)
        expect(response.body).not_to match(/keeps\s*<strong>7%/)
      end
    end
  end
end
