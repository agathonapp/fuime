# frozen_string_literal: true

require "rails_helper"

# Fuime: the price list, pinned.
#
# Pricing is two dials — a monthly subscription and a percentage of money in —
# and the second one changed meaning entirely under merchant-of-record: Fuime is
# the seller, so Stripe's 2.9% + 30¢ now comes out of Fuime's balance instead of
# the family's. A rate that was fine as a platform cut can be loss-making as a
# margin, which is why the economics are asserted here and not just the numbers.
#
# The ladder (founder's decision, 2026-08-14):
#
#     Free      $0.00/mo  +  7%
#     Standard  $15.00/mo +  5%
#     Pro       $19.99/mo +  3%
# Stripe's own rate. At the top level rather than inside the describe block for
# two reasons that pull the same way: `def margin_cents` below cannot close over
# a local, and Lint/ConstantDefinitionInBlock refuses a constant assigned inside
# a block.
STRIPE_PERCENT = 0.029
STRIPE_FIXED_CENTS = 30

RSpec.describe Event::Plan, "pricing" do
  # Stripe's US card rate. Not read from config because nothing in the app stores
  # it — it is Stripe's price, and it is here so the margin assertions below say
  # what they mean.

  def margin_cents(rate, amount_cents)
    (rate * amount_cents) - (STRIPE_PERCENT * amount_cents) - STRIPE_FIXED_CENTS
  end

  describe "the ladder" do
    it "prices Free at 7% with no subscription" do
      plan = Event::Plan::Free.new

      expect(plan.revenue_fee).to eq(0.07)
      expect(plan.monthly_fee_cents).to eq(0)
    end

    it "prices Standard at 5% plus $15/mo" do
      plan = Event::Plan::Standard.new

      expect(plan.revenue_fee).to eq(0.05)
      expect(plan.monthly_fee_cents).to eq(1500)
    end

    it "prices Pro at 3% plus $19.99/mo" do
      plan = Event::Plan::Pro.new

      expect(plan.revenue_fee).to eq(0.03)
      expect(plan.monthly_fee_cents).to eq(1999)
    end

    it "keeps Standard as the fallback rate, so an unplanned venture is not free" do
      expect(Event::Plan::FALLBACK_REVENUE_FEE).to eq(Event::Plan::Standard.new.revenue_fee)
    end
  end

  # The bug this file exists to prevent. Eleven plans subclass Standard and only
  # Free and Pro state their own price — so an unguarded monthly_fee_cents on
  # Standard silently bills $15/mo to every plan that exists BECAUSE somebody is
  # not paying the standard price.
  describe "plans that must never be billed a subscription" do
    {
      "Event::Plan::FeeWaived"           => "a fee waiver that still charged $15/mo is not a waiver",
      "Event::Plan::Terminated"          => "billing a terminated plan is billing an ex-customer",
      "Event::Plan::SpendOnly"           => "no money comes in, so there is nothing to subscribe to",
      "Event::Plan::CardsOnly"           => "same",
      "Event::Plan::ScGoogleGrant"       => "a grant-funded plan",
      "Event::Plan::FivePercent"         => "legacy HCB fiscal sponsorship rate",
      "Event::Plan::TenPercent"          => "legacy HCB fiscal sponsorship rate",
      "Event::Plan::ThreePointFive"      => "legacy HCB fiscal sponsorship rate",
      "Event::Plan::TwoPointNinePercent" => "legacy HCB fiscal sponsorship rate",
    }.each do |class_name, why|
      it "does not charge #{class_name.demodulize} a monthly fee — #{why}" do
        expect(class_name.constantize.new.monthly_fee_cents).to eq(0)
      end
    end
  end

  # ── The economics ─────────────────────────────────────────────────────────
  #
  # Under MoR the margin per sale is (rate − 2.9%) × amount − 30¢. Below a
  # break-even ticket size that is NEGATIVE, and the break-even moves sharply as
  # the rate approaches Stripe's own.
  describe "per-sale margin under merchant-of-record" do
    it "earns on a typical small sale at the Free rate" do
      expect(margin_cents(0.07, 2_000)).to be > 0 # $20 sale
    end

    it "earns on a typical small sale at the Standard rate" do
      expect(margin_cents(0.05, 2_000)).to be > 0
    end

    # Documented rather than asserted-as-desirable. Pro's 3% leaves 0.1% over
    # Stripe, so its break-even is $300 and the $19.99 subscription is the only
    # thing making the tier work. If this ever starts passing at a small amount,
    # somebody has changed the rate and should know it changed the model too.
    it "LOSES money on a small sale at the Pro rate, which the subscription must cover" do
      expect(margin_cents(0.03, 2_000)).to be < 0   # $20 sale loses money
      expect(margin_cents(0.03, 10_000)).to be < 0  # so does $100
      expect(margin_cents(0.03, 40_000)).to be > 0  # only above ~$300 does it earn
    end

    it "puts Pro's break-even at about $300" do
      break_even = STRIPE_FIXED_CENTS / (Event::Plan::Pro::REVENUE_FEE - STRIPE_PERCENT)

      expect(break_even).to be_within(1_00).of(300_00)
    end
  end

  # ── The minimum fee ───────────────────────────────────────────────────────
  #
  # Event#fuime_fee_cents_on applies `max(rate × amount, MINIMUM_FEE_CENTS)` so a
  # small sale still covers Stripe's fixed 30¢. It applies ONLY under
  # merchant-of-record, where that 30¢ is Fuime's own cost.
  describe "the minimum fee" do
    def fee_on(plan_type, cents)
      create(:event, plan_type:).fuime_fee_cents_on(cents)
    end

    context "when Fuime is the seller of record", :merchant_of_record do
      it "floors a small sale at the minimum" do
        # $5 at 5% is 25¢, which does not cover Stripe's 30¢ alone.
        expect(fee_on(Event::Plan::Standard, 5_00)).to eq(Event::Plan::MINIMUM_FEE_CENTS)
      end

      it "leaves a normal sale on the percentage" do
        expect(fee_on(Event::Plan::Standard, 100_00)).to eq(5_00)
      end

      it "turns a $5 sale from a loss into a gain" do
        expect(margin_cents(0.05, 5_00)).to be < 0
        expect(Event::Plan::MINIMUM_FEE_CENTS - (STRIPE_PERCENT * 5_00) - STRIPE_FIXED_CENTS).to be > 0
      end

      # A fee waiver must stay a waiver. The floor is a minimum on a charge, not
      # a reason to start charging someone who pays nothing.
      it "never reintroduces a fee for a fee-waived venture" do
        expect(fee_on(Event::Plan::FeeWaived, 5_00)).to eq(0)
      end

      # Otherwise the floor exceeds the payment and the operator's payable goes
      # negative on a sale they made.
      it "never charges more than the sale itself" do
        expect(fee_on(Event::Plan::Standard, 30)).to eq(30)
      end
    end

    context "when the guardian is the merchant (Connect)" do
      # Under Connect, Stripe bills the FAMILY, so a floor would not recover a
      # Fuime cost — it would be a surcharge on the smallest sellers on top of a
      # Stripe fee they already pay. 50¢ from Fuime plus ~45¢ from Stripe on a $5
      # sale is 19%.
      it "does not apply the floor" do
        expect(fee_on(Event::Plan::Standard, 5_00)).to eq(25)
      end
    end
  end

  # ── What the floor does NOT fix ───────────────────────────────────────────
  #
  # Recorded because it is counter-intuitive and was the whole reason the floor
  # was introduced. A minimum only bites while `rate × amount` is below it, so it
  # rescues small sales — and Pro's problem is not small sales, it is that 3% is
  # a tenth of a point above Stripe's own 2.9% at EVERY size.
  describe "the floor does not rescue Pro" do
    def margin_with_floor(rate, amount_cents)
      fee = [(rate * amount_cents).round, Event::Plan::MINIMUM_FEE_CENTS].max
      fee - (STRIPE_PERCENT * amount_cents) - STRIPE_FIXED_CENTS
    end

    it "still loses money across the whole ordinary range of a teen sale" do
      [10_00, 20_00, 50_00, 100_00].each do |amount|
        expect(margin_with_floor(0.03, amount)).to be < 0,
                                                   "expected Pro to still lose on a $#{amount / 100} sale"
      end
    end

    it "would need an implausible minimum to break even at Pro's rate" do
      # Solving max(rate·A, F) >= 2.9%·A + 30 for all A gives
      # F >= 30 / (1 - 0.029/rate).
      required = STRIPE_FIXED_CENTS / (1 - (STRIPE_PERCENT / 0.03))

      expect(required).to be > 900 # over $9.00 minimum per sale
    end

    it "needs only a modest minimum at the Standard and Free rates" do
      expect(STRIPE_FIXED_CENTS / (1 - (STRIPE_PERCENT / 0.05))).to be < 75
      expect(STRIPE_FIXED_CENTS / (1 - (STRIPE_PERCENT / 0.07))).to be < 55
    end
  end
end
