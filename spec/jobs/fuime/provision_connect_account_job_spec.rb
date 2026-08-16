# frozen_string_literal: true

require "rails_helper"

# Fuime: eager provisioning of the guardian-owned Stripe account.
#
# Stripe's `controller` property is create-only, so an account created for the
# wrong venture or in the wrong adult's name cannot be repaired — that family has
# to be onboarded again from scratch. Every example below is a case where this job
# must decline rather than guess.
RSpec.describe Fuime::ProvisionConnectAccountJob do
  let(:guardianship) { create(:guardianship, :active) }
  let(:guardian) { guardianship.guardian }
  let(:minor) { guardianship.minor }
  let(:venture) { create(:event) }

  def give_minor_the_venture
    create(:organizer_position, user: minor, event: venture)
  end

  def expect_no_provisioning
    expect(Fuime::ConnectOnboardingService).not_to receive(:new)
    described_class.perform_now(guardianship.id)
  end

  it "provisions an account for a venture the minor already runs" do
    give_minor_the_venture

    service = instance_double(Fuime::ConnectOnboardingService, find_or_create_account!: nil)
    expect(Fuime::ConnectOnboardingService)
      .to receive(:new).with(event: venture, guardian:).and_return(service)

    described_class.perform_now(guardianship.id)
  end

  it "does nothing for a guardianship revoked between enqueue and run" do
    give_minor_the_venture
    guardianship.revoke!

    # The guardian is no longer the responsible adult, so an account created in
    # their name would be wrong from the moment it existed.
    expect_no_provisioning
  end

  it "does nothing when the venture already has an account" do
    give_minor_the_venture
    create(:stripe_connected_account, event: venture, owner: guardian, stripe_id: "acct_existing")

    expect_no_provisioning
  end

  it "declines when more than one adult could be the owner" do
    give_minor_the_venture
    # A second teen with a different parent on the same venture. Picking `.first`
    # here is how one family ends up owning another family's payment account.
    other = create(:guardianship, :active)
    create(:organizer_position, user: other.minor, event: venture)

    expect_no_provisioning
  end

  it "never raises out of the job when Stripe fails" do
    give_minor_the_venture
    allow(Fuime::ConnectOnboardingService).to receive(:new).and_raise(Stripe::APIError.new("boom"))

    # A Stripe outage must not turn into a retry loop on behalf of a family who
    # has not asked for anything yet; the interactive path still works.
    expect { described_class.perform_now(guardianship.id) }.not_to raise_error
  end

  describe "Guardianship#accept!" do
    it "enqueues provisioning when a guardianship goes active" do
      pending_guardianship = create(:guardianship)

      expect { pending_guardianship.accept! }
        .to have_enqueued_job(described_class).with(pending_guardianship.id)
    end

    it "does not enqueue when acceptance is refused" do
      # A guardian whose age is unknown cannot sign, so there is no responsible
      # adult and nothing to provision an account in the name of.
      unknown_age = create(:guardianship)
      unknown_age.guardian.update_column(:birthday, nil)

      expect { unknown_age.reload.accept! }.not_to have_enqueued_job(described_class)
    end
  end
end
