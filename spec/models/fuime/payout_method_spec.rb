# frozen_string_literal: true

require "rails_helper"

# Fuime: where an operator's money goes.
#
# The property this file exists to protect is not the state machine — it is that
# **no bank credential ever lands in this table.** Fuime holding a minor's (or
# their guardian's) account and routing numbers creates exactly the store of
# sensitive data L4 says not to hold, and buys no capability: the originator
# needs them, Fuime does not.
#
# The realistic failure is not malice. It is a future integration cheerfully
# putting the account number in whichever column was to hand, because it had it.
RSpec.describe Fuime::PayoutMethod do
  let(:event) { create(:event) }
  let(:user) { create(:user, birthday: 40.years.ago.to_date) }

  def method_for(**attrs)
    described_class.new(event:, added_by: user, provider: described_class::PLAID, **attrs)
  end

  describe "no account numbers" do
    it "refuses one hidden in the provider reference" do
      record = method_for(provider_reference: "123456789012")

      expect(record).not_to be_valid
      expect(record.errors[:provider_reference].join).to match(/never the digits/)
    end

    it "refuses one hidden in the institution name" do
      expect(method_for(institution_name: "Chase 000123456789")).not_to be_valid
    end

    it "refuses one hidden in the account holder name" do
      expect(method_for(account_holder_name: "Vansh Jain 021000021")).not_to be_valid
    end

    it "accepts an ordinary provider token" do
      expect(method_for(provider_reference: "ba_1QxYzAbCdEfGh")).to be_valid
    end

    it "accepts an ordinary bank name" do
      expect(method_for(institution_name: "Chase")).to be_valid
    end

    # `last4` is what a page renders. The database refuses anything longer, so
    # the mistake cannot ship even if code tries.
    it "keeps last4 to the last few digits" do
      expect(method_for(last4: "1234")).to be_valid
      expect(method_for(last4: "123456789")).not_to be_valid
    end

    it "will not let a long number reach last4 even past the model" do
      record = method_for(last4: "123456789")

      expect { record.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    # The schema itself is the guarantee: a column that does not exist cannot be
    # filled in by a future integration in a hurry.
    it "has nowhere to put an account or routing number" do
      expect(described_class.column_names).not_to include("account_number", "routing_number")
    end
  end

  describe "the lifecycle" do
    it "starts pending and becomes usable only once verified" do
      record = create(:fuime_payout_method, event:, added_by: user)

      expect(record).to be_pending
      expect(record).not_to be_usable

      record.mark_verified!
      expect(record).to be_usable
      expect(record.verified_at).to be_present
    end

    it "can recover from a failed verification" do
      record = create(:fuime_payout_method, event:, added_by: user)
      record.mark_failed!

      expect { record.mark_verified! }.not_to raise_error
    end

    # Removed rather than destroyed: a payout already sent here references it,
    # and deleting the row leaves a payment nobody can trace to a bank.
    it "removes rather than deletes" do
      record = create(:fuime_payout_method, event:, added_by: user)
      record.mark_verified!
      record.remove!

      expect(described_class.find(record.id)).to be_present
      expect(described_class.live).to be_empty
      expect(described_class.usable).to be_empty
    end
  end

  describe "one destination per venture" do
    # "Which account?" is not a decision anybody should be making during a payout
    # run.
    it "refuses a second live destination" do
      create(:fuime_payout_method, event:, added_by: user)

      expect { create(:fuime_payout_method, event:, added_by: user) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a replacement once the old one is removed" do
      first = create(:fuime_payout_method, event:, added_by: user)
      first.remove!

      expect { create(:fuime_payout_method, event:, added_by: user) }.not_to raise_error
    end
  end

  describe "#display_name" do
    it "reads as a bank a person recognises" do
      expect(method_for(institution_name: "Chase", last4: "1234").display_name).to eq("Chase ••1234")
    end

    it "still says something when the provider gave no detail" do
      expect(method_for.display_name).to eq("Bank account")
    end
  end
end
