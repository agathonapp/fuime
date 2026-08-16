# frozen_string_literal: true

require "rails_helper"

# Fuime: the structural flags decide whether Fuime is a custodian.
#
# Every assertion here is really one assertion in different clothes: the safe
# answer must be what you get when nobody has said anything. A flag that fails
# open is worse than no flag, because it reads as a control in review and behaves
# as a default in production.
RSpec.describe Fuime::Features do
  # ENV is read directly rather than memoised (see the module's header — a
  # memoised flag cannot be tested and cannot be corrected without a restart), so
  # the specs set it and put it back.
  def with_env(key, value)
    had = ENV.key?(key)
    old = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    had ? ENV[key] = old : ENV.delete(key)
  end

  describe ".sponsor_banking?" do
    it "is false when the variable is unset" do
      with_env("FEATURE_SPONSOR_BANKING", nil) do
        expect(described_class.sponsor_banking?).to be(false)
      end
    end

    it "is true only for the word true" do
      with_env("FEATURE_SPONSOR_BANKING", "true") do
        expect(described_class.sponsor_banking?).to be(true)
      end
    end

    it "accepts the word true in any case, because deploy UIs mangle it" do
      ["TRUE", "True", " true "].each do |spelling|
        with_env("FEATURE_SPONSOR_BANKING", spelling) do
          expect(described_class.sponsor_banking?).to be(true), "expected #{spelling.inspect} to enable"
        end
      end
    end

    # The important half. `.present?` would pass every one of these.
    it "is false for every other value, including ones other tools treat as truthy" do
      ["false", "FALSE", "", "  ", "0", "1", "yes", "on", "enabled", "null"].each do |spelling|
        with_env("FEATURE_SPONSOR_BANKING", spelling) do
          expect(described_class.sponsor_banking?).to be(false), "expected #{spelling.inspect} NOT to enable"
        end
      end
    end
  end

  describe ".sponsor_banking!" do
    it "raises when custody is off" do
      with_env("FEATURE_SPONSOR_BANKING", nil) do
        expect { described_class.sponsor_banking! }.to raise_error(Fuime::Features::Disabled, /does not hold customer funds/)
      end
    end

    it "passes when custody is on" do
      with_env("FEATURE_SPONSOR_BANKING", "true") do
        expect(described_class.sponsor_banking!).to be(true)
      end
    end
  end

  describe ".card_issuing_permitted?" do
    # The matrix matters more than any single case: the interesting cell is
    # live-mode-without-custody, which is the state a careless STRIPE_MODE=live
    # would create and the one nothing in the codebase used to refuse.
    it "permits cards in test mode even without custody, so the demo still works" do
      with_env("FEATURE_SPONSOR_BANKING", nil) do
        allow(StripeService).to receive(:live?).and_return(false)

        expect(described_class.card_issuing_permitted?).to be(true)
      end
    end

    it "refuses cards in live mode without custody" do
      with_env("FEATURE_SPONSOR_BANKING", nil) do
        allow(StripeService).to receive(:live?).and_return(true)

        expect(described_class.card_issuing_permitted?).to be(false)
      end
    end

    it "permits cards in live mode once custody exists" do
      with_env("FEATURE_SPONSOR_BANKING", "true") do
        allow(StripeService).to receive(:live?).and_return(true)

        expect(described_class.card_issuing_permitted?).to be(true)
      end
    end
  end

  describe ".merchant_of_record?" do
    it "is false when the variable is unset" do
      with_env("FEATURE_MERCHANT_OF_RECORD", nil) do
        expect(described_class.merchant_of_record?).to be(false)
      end
    end

    it "is true only for the word true" do
      with_env("FEATURE_MERCHANT_OF_RECORD", "true") do
        expect(described_class.merchant_of_record?).to be(true)
      end
    end

    it "is false for every other value, including ones other tools treat as truthy" do
      ["false", "", "0", "1", "yes", "on"].each do |spelling|
        with_env("FEATURE_MERCHANT_OF_RECORD", spelling) do
          expect(described_class.merchant_of_record?).to be(false), "expected #{spelling.inspect} NOT to enable"
        end
      end
    end

    # The two structural flags are near-opposites and are easy to conflate:
    # custody is "Fuime holds your money", MoR is "the money is Fuime's own and we
    # owe you a payable". Neither implies the other, and a reader that leaked would
    # let one legal posture switch on the other's code paths.
    it "is independent of custody in both directions" do
      with_env("FEATURE_SPONSOR_BANKING", "true") do
        with_env("FEATURE_MERCHANT_OF_RECORD", nil) do
          expect(described_class.merchant_of_record?).to be(false)
        end
      end

      with_env("FEATURE_MERCHANT_OF_RECORD", "true") do
        with_env("FEATURE_SPONSOR_BANKING", nil) do
          expect(described_class.sponsor_banking?).to be(false)
        end
      end
    end
  end

  describe ".merchant_of_record!" do
    it "raises when Fuime is not configured as the seller" do
      with_env("FEATURE_MERCHANT_OF_RECORD", nil) do
        expect { described_class.merchant_of_record! }.to raise_error(Fuime::Features::Disabled, /not configured as the legal seller/)
      end
    end

    it "passes when it is" do
      with_env("FEATURE_MERCHANT_OF_RECORD", "true") do
        expect(described_class.merchant_of_record!).to be(true)
      end
    end
  end

  describe ".to_h" do
    it "reports every structural flag, so a boot log answers what mode this box is in" do
      with_env("FEATURE_SPONSOR_BANKING", nil) do
        with_env("FEATURE_MERCHANT_OF_RECORD", nil) do
          expect(described_class.to_h).to eq(
            "FEATURE_SPONSOR_BANKING"    => false,
            "FEATURE_MERCHANT_OF_RECORD" => false
          )
        end
      end
    end

    # Not redundant with the case above: the point is that to_h enumerates ALL
    # rather than a hardcoded pair, so a flag added later shows up in the boot log
    # without anyone remembering to add it here too.
    it "covers every flag in ALL" do
      expect(described_class.to_h.keys).to match_array(described_class::ALL)
    end
  end

  # Guards the list itself. A flag added to ALL without a reader, or a reader
  # added without registering in ALL, silently drops out of the boot log and the
  # admin display — which is where somebody looks to confirm what a box is doing.
  describe "ALL" do
    it "names only variables the module can actually read" do
      expect(described_class::ALL).to all(satisfy { |name| described_class.respond_to?(:enabled?) && name.start_with?("FEATURE_") })
    end
  end
end
