# frozen_string_literal: true

require "rails_helper"

# Fuime: a parent's COPPA rights over a child's account (16 CFR 312.6).
#
# The two properties worth pinning are the ones that are easy to get wrong in
# opposite directions: an export that leaks somebody ELSE's data, and an erasure
# that destroys records Fuime is required to keep as merchant of record.
RSpec.describe "Parent data rights" do
  let(:guardian) { create(:user, full_name: "Dana Reyes") }
  let(:minor) { create(:user, :minor, full_name: "Sam Reyes") }
  let(:event) { create(:event, plan_type: Event::Plan::Standard) }
  let!(:guardianship) do
    create(:guardianship, :active, guardian:, minor:, agreement_signed_at: 2.days.ago,
                                   agreement_ip: "203.0.113.9")
  end

  before { create(:organizer_position, user: minor, event:) }

  describe Fuime::DataExportService do
    subject(:export) { described_class.new(user: minor).as_json }

    it "gives the parent the child's own account and consent record" do
      expect(export[:about][:name]).to eq("Sam Reyes")
      expect(export[:guardianships].first).to include(
        other_person: "Dana Reyes",
        agreement_version: Guardianship::CURRENT_AGREEMENT_VERSION,
        signed_from_ip: "203.0.113.9"
      )
    end

    it "lists the businesses the child is on" do
      expect(export[:businesses].map { |b| b[:name] }).to include(event.name)
    end

    # The rule the whole service is shaped around. A customer who bought a
    # $20 service from a 15-year-old did not consent to their name being handed
    # to that teenager's parent.
    it "describes sales without identifying who bought" do
      Fuime::Sale.create!(event:, amount_cents: 2_000, state: "CA", country: "US",
                          postal_code: "94110", occurred_at: 1.day.ago,
                          stripe_payment_intent_id: "pi_export_1")

      sale = export[:businesses].first[:sales].first
      expect(sale[:amount_cents]).to eq(2_000)
      expect(sale[:buyer_region]).to eq("CA, US")
      # Not the postal code: close enough to a household to identify one.
      expect(sale.values.map(&:to_s)).not_to include(a_string_matching(/94110/))
      expect(sale.keys).not_to include(:buyer_email, :buyer_name)
    end

    # A parent who cannot tell an omission from a gap cannot trust the document.
    it "says what it deliberately left out" do
      expect(export[:what_is_not_here].join(" ")).to match(/customers/i)
      expect(export[:what_is_not_here].join(" ")).to match(/identity documents/i)
    end
  end

  describe Fuime::DataErasureService do
    let(:admin) { create(:user, :make_admin) }
    let(:data_request) do
      Fuime::DataRequest.create!(requested_by: guardian, subject: minor, kind: :deletion, requested_at: Time.current)
    end

    subject(:service) { described_class.new(request: data_request, performed_by: admin) }

    it "overwrites every identifier and locks the account" do
      service.perform!
      minor.reload

      expect(minor.email).to eq("erased-#{minor.id}@deleted.fuime.invalid")
      expect(minor.full_name).to eq("Erased account")
      expect(minor.phone_number).to be_nil
      expect(minor).to be_locked
    end

    # The half that is not obvious, and the half a parent is told about in
    # writing: Fuime is the legal seller on every sale made through the platform,
    # so the sales ledger is Fuime's own accounting record, not the child's data.
    it "keeps the business's transaction records" do
      sale = Fuime::Sale.create!(event:, amount_cents: 5_000, occurred_at: 3.days.ago,
                                 stripe_payment_intent_id: "pi_erase_1")

      expect { service.perform! }.not_to change(Fuime::Sale, :count)
      expect(sale.reload.amount_cents).to eq(5_000)
    end

    it "records who carried it out, and what was kept" do
      service.perform!

      expect(data_request.reload).to be_status_fulfilled
      expect(data_request.fulfilled_by).to eq(admin)
      expect(data_request.resolution_notes).to match(/merchant of record/i)
    end

    # Not a refusal — a "not yet". An open dispute is a live claim against a sale
    # this account made, and Fuime cannot answer it after erasing who made it.
    it "refuses while a dispute against the account is open" do
      Fuime::Dispute.create!(event:, stripe_dispute_id: "dp_1", stripe_payment_intent_id: "pi_1",
                             amount_cents: 2_000, status: "needs_response", opened_at: Time.current)

      expect(service.blockers.first).to match(/open dispute/i)
      expect { service.perform! }.to raise_error(described_class::Refused)
      expect(minor.reload.full_name).to eq("Sam Reyes")
    end
  end

  describe Fuime::DataRequestMailer do
    it "renders the ops alert with the command that actions it" do
      data_request = Fuime::DataRequest.create!(requested_by: guardian, subject: minor,
                                                kind: :deletion, requested_at: Time.current)
      mail = described_class.with(data_request:).ops_alert

      expect(mail.subject).to include("Deletion request")
      expect(mail.body.encoded).to include("fuime:data_request:fulfil[#{data_request.id}]")
      # The promise the parent was given, restated to the person who has to keep it.
      expect(mail.body.encoded).to include(data_request.due_at.strftime("%B"))
    end
  end

  describe Fuime::DataRequest do
    it "promises a response date the product can quote back" do
      request = Fuime::DataRequest.create!(requested_by: guardian, subject: minor, kind: :deletion,
                                           requested_at: Time.current)

      expect(request.due_at).to be_within(1.minute).of(Fuime::DataRequest::RESPONSE_WINDOW_DAYS.days.from_now)
      expect(request).not_to be_overdue
    end
  end
end
