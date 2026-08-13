# frozen_string_literal: true

require "rails_helper"

# Fuime: the payouts page speaks to two legally different parties, and until now it
# only knew how to speak to one.
#
# A school venture has no guardian by design, so every guardian sentence on this page
# was false there — "Your guardian has to approve this", an "Ask my guardian" button,
# and an invite-your-guardian link that could never resolve the request. Worse, the
# request it produced was one nobody but a Fuime admin could approve.
#
# `render_views` is the point of this file: these are view-layer regressions, and a
# controller spec without it would pass while the page still said the wrong thing.
# Same approach as spec/controllers/fuime/payment_setups_school_copy_spec.rb.
RSpec.describe Fuime::PayoutsController do
  include SessionSupport

  render_views

  def stub_balance(available_cents)
    allow(Stripe::Balance).to receive(:retrieve).and_return(
      Stripe::Balance.construct_from(available: [{ currency: "usd", amount: available_cents }])
    )
  end

  # On a shared school account, stubbing Stripe's balance is not enough to make a
  # request possible: the amount is capped at the VENTURE's own ledger balance, so
  # that one student cannot withdraw another's revenue. A venture with no settled
  # income has $0 available however much the school holds — which is the cap working,
  # and the reason this helper exists rather than a bigger stub.
  def credit_venture!(event, cents)
    ct = create(:canonical_transaction, amount_cents: cents, date: Date.current, memo: "Sale")
    create(:canonical_event_mapping, canonical_transaction: ct, event:)
  end

  describe "a student venture inside a school programme" do
    let(:school_tree) { build_school_tree }
    let(:school)  { school_tree[0] }
    let(:venture) { school_tree[2] }

    let!(:school_account) { create(:stripe_connected_account, :ready, event: school) }
    let!(:guide)   { create_school_manager(school) }
    let!(:student) { create_student(venture) }

    before { stub_balance(50_000) }

    it "asks the school rather than a guardian who does not exist" do
      create_session(student, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("Ask the school")
      expect(response.body).not_to include("Ask my guardian")
      expect(response.body).not_to match(/Your guardian has to approve/)
    end

    # The student's own money, not the programme's. The old copy claimed this figure
    # was "what Stripe says can be sent today", which on a shared account is the whole
    # school's balance.
    it "describes the balance as the venture's own earnings" do
      # Needs actual earnings: with nothing on the ledger the sentence is
      # correctly "You haven't earned anything yet."
      credit_venture!(venture, 25_000)
      create_session(student, verified: true)

      get :index, params: { event_slug: venture.slug }

      # Fuime::PayablesLedger#owed_sentence branches on who actually pays. On a
      # shared school account the SCHOOL settles with the student directly and
      # Fuime is not the rail, so "Fuime owes you" would name the wrong debtor.
      expect(response.body).to match(/has earned and not yet spent/)
      expect(response.body).to match(/Ask the school to pay it out/)
      expect(response.body).not_to match(/Fuime owes you/)
    end

    it "offers reinvesting as an option rather than only cashing out" do
      create_session(student, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to match(/don't have to take it out/i)
    end

    # No bank fields anywhere: the school already has what it needs, and holding a
    # minor's account number to hand back to them is the data CLAUDE.md L4 says not to
    # keep.
    it "asks where the money should go without asking for bank details" do
      create_session(student, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("Where should it go?")
      expect(response.body).to match(/don't put your account number here/i)
      expect(response.body).not_to match(/routing number/i)
    end

    it "shows the guide an approvable request instead of a dead end" do
      credit_venture!(venture, 10_000)
      request = Fuime::PayoutService.new(event: venture)
                                    .request!(amount_cents: 4_000, requested_by: student,
                                              destination_note: "my own account")

      create_session(guide, verified: true)
      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("waiting for approval")
      expect(response.body).to include("my own account")
      expect(response.body).to include(fuime_payout_approve_path(event_slug: venture.slug, id: request.id))
    end

    it "gives the school a way to record that it actually paid" do
      credit_venture!(venture, 10_000)
      service = Fuime::PayoutService.new(event: venture)
      request = service.request!(amount_cents: 4_000, requested_by: student)
      service.approve!(request:, approver: guide)

      create_session(guide, verified: true)
      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("Approved, not yet paid")
      expect(response.body).to include("Mark as paid")
      expect(response.body).to include(fuime_payout_settle_path(event_slug: venture.slug, id: request.id))
    end

    # "Sent to your bank" for a transfer the school has merely authorised would be a
    # straight falsehood.
    it "does not claim an approved transfer has reached a bank" do
      credit_venture!(venture, 10_000)
      service = Fuime::PayoutService.new(event: venture)
      request = service.request!(amount_cents: 4_000, requested_by: student)
      service.approve!(request:, approver: guide)

      create_session(student, verified: true)
      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("school is paying it")
      expect(response.body).not_to include("Sent to your bank")
    end

    it "does not tell the student to invite a guardian" do
      credit_venture!(venture, 10_000)
      Fuime::PayoutService.new(event: venture)
                          .request!(amount_cents: 4_000, requested_by: student)

      create_session(student, verified: true)
      get :index, params: { event_slug: venture.slug }

      expect(response.body).to match(/Waiting on the school to approve/)
      expect(response.body).not_to include("Invite your guardian")
    end
  end

  # The family path must be untouched, word for word.
  describe "a family venture" do
    let(:venture) { create(:event) }
    let(:minor) { create(:user, :minor) }
    let(:guardian) { create(:user, birthday: 40.years.ago.to_date) }
    let!(:account) { create(:stripe_connected_account, :ready, event: venture, owner: guardian) }

    before do
      create(:organizer_position, event: venture, user: minor)
      create(:guardianship, :active, guardian:, minor:)
      stub_balance(50_000)
    end

    it "still asks the guardian" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to include("Ask my guardian")
      expect(response.body).to match(/Your guardian has to approve this/)
      # The family shape: Fuime IS the seller of record and the payer, so the
      # sentence names Fuime and commits to the payout date.
      expect(response.body).to match(/Fuime owes you/)
    end

    it "still describes payouts as going to the guardian's bank" do
      create_session(minor, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).to match(/bank account\s+the parent or guardian connected/)
    end

    it "offers no settlement step, because Stripe says when the money landed" do
      create_session(guardian, verified: true)

      get :index, params: { event_slug: venture.slug }

      expect(response.body).not_to include("Mark as paid")
    end
  end
end
