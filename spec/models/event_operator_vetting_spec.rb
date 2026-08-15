# frozen_string_literal: true

require "rails_helper"

# Fuime: vetting, at the model layer.
#
# Manual approval of every operator is the compensating control that makes the
# rest of the product defensible — under Connect, for letting minors sell at all;
# under merchant-of-record, for Fuime being the legal seller of what they sell.
# So the two things that have to be true of it are tested here rather than only
# through a controller: that an unapproved venture genuinely cannot take money,
# and that a decision is reconstructable afterwards.
RSpec.describe Event, "operator vetting" do
  describe "the default" do
    # The FACTORY defaults to approved so unrelated specs are not silently
    # testing this gate (see spec/factories/event_factory.rb). The COLUMN must
    # not, or the control exempts everyone it exists to check.
    it "is unvetted for a venture created without one" do
      expect(described_class.new.operator_vetting_status).to eq("unvetted")
    end

    it "is unvetted straight from the database, bypassing the factory" do
      event = create(:event)
      event.update_column(:operator_vetting_status, described_class.operator_vetting_statuses["unvetted"])

      expect(event.reload).to be_operator_vetting_unvetted
    end
  end

  describe "#accepts_payments?" do
    let(:event) { create(:event) }
    let!(:account) { create(:stripe_connected_account, :ready, event:) }

    it "is true for a vetted venture whose account is ready" do
      expect(event.reload.accepts_payments?).to be(true)
    end

    # The whole point. Before vetting was folded in, an unreviewed venture with a
    # connected account could take real money from real customers.
    it "is false for a venture nobody has approved" do
      event.update!(operator_vetting_status: :unvetted)

      expect(event.accepts_payments?).to be(false)
    end

    it "is false for a suspended venture even though its account still works" do
      event.update!(operator_vetting_status: :suspended)

      expect(account.reload).to be_ready_for_payments
      expect(event.accepts_payments?).to be(false)
    end

    it "goes back to true when a suspension is lifted" do
      event.update!(operator_vetting_status: :suspended)
      expect(event.accepts_payments?).to be(false)

      event.update!(operator_vetting_status: :approved)

      expect(event.accepts_payments?).to be(true)
    end

    # Vetting is an additional gate, never a substitute for one. An approved
    # venture with nowhere for money to land still cannot be paid.
    it "still requires a ready account, approval notwithstanding" do
      account.destroy!

      expect(event.reload.accepts_payments?).to be(false)
    end
  end

  describe "#selling_blockers" do
    # Not memoised, deliberately: eligibility depends on who holds a position,
    # which changes without the event being saved. A stale "yes" here is a
    # payment Fuime was not entitled to take.
    it "reflects a change made since the last call" do
      event = create(:event)
      expect(event.selling_blockers).to be_empty

      event.update!(operator_vetting_status: :suspended)

      expect(event.selling_blockers).not_to be_empty
    end
  end

  describe "#record_vetting_decision!" do
    let(:event) { create(:event, :unvetted) }
    let(:reviewer) { create(:user, :make_admin) }

    it "records the decision, the reviewer and the time" do
      freeze_time do
        event.record_vetting_decision!(status: :approved, by: reviewer, notes: "Talked to the parent")

        expect(event.reload).to be_operator_vetting_approved
        expect(event.operator_vetted_by).to eq(reviewer)
        expect(event.operator_vetted_at).to eq(Time.current)
      end
    end

    it "stamps the note with who wrote it" do
      event.record_vetting_decision!(status: :approved, by: reviewer, notes: "Looks legitimate")

      expect(event.reload.operator_vetting_notes).to include("Looks legitimate")
      expect(event.operator_vetting_notes).to include(reviewer.name)
    end

    # The reason a venture was approved in September is the context for
    # suspending it in November, and it is the training data for the risk model
    # that replaces this queue. Overwriting would discard exactly that.
    it "keeps earlier notes when a venture is re-decided" do
      event.record_vetting_decision!(status: :approved, by: reviewer, notes: "First pass, fine")
      event.record_vetting_decision!(status: :suspended, by: reviewer, notes: "Selling something else now")

      notes = event.reload.operator_vetting_notes
      expect(notes).to include("First pass, fine")
      expect(notes).to include("Selling something else now")
    end

    it "puts the newest note first" do
      event.record_vetting_decision!(status: :approved, by: reviewer, notes: "OLDER")
      event.record_vetting_decision!(status: :suspended, by: reviewer, notes: "NEWER")

      notes = event.reload.operator_vetting_notes
      expect(notes.index("NEWER")).to be < notes.index("OLDER")
    end

    it "accepts a decision with no note without writing an empty one" do
      event.record_vetting_decision!(status: :approved, by: reviewer)

      expect(event.reload.operator_vetting_notes).to be_nil
    end

    it "does not lose existing notes to a later note-less decision" do
      event.record_vetting_decision!(status: :approved, by: reviewer, notes: "Keep me")
      event.record_vetting_decision!(status: :suspended, by: reviewer)

      expect(event.reload.operator_vetting_notes).to include("Keep me")
    end

    it "refuses a status outside the enum" do
      expect { event.record_vetting_decision!(status: :vibes, by: reviewer) }
        .to raise_error(ArgumentError)

      expect(event.reload).to be_operator_vetting_unvetted
    end

    it "immediately stops a suspended venture selling" do
      create(:stripe_connected_account, :ready, event:)
      event.record_vetting_decision!(status: :approved, by: reviewer)
      expect(event.reload.accepts_payments?).to be(true)

      event.record_vetting_decision!(status: :suspended, by: reviewer, notes: "Chargebacks")

      expect(event.reload.accepts_payments?).to be(false)
    end
  end
end
