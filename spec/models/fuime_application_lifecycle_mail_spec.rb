# frozen_string_literal: true

require "rails_helper"

# Fuime: what a founder is told in the minutes after they finish /setup.
#
# ── What used to land ───────────────────────────────────────────────────────
#
# One tap on the wizard's last screen ran `mark_submitted!` → (no agreement is
# configured, so) `mark_under_review!` → `Fuime::FounderAdmission` →
# `mark_approved!` → `activate_event!`, and each of those three transitions
# mailed. Within seconds a thirteen-year-old received:
#
#   1. "Your Fuime application is under review" — "you'll hear from us within
#      2 business days". Nobody was going to write; they were already in.
#   2. "[Action Needed] <name> has been approved" — "before we can activate your
#      business, you'll need to sign the Fuime agreement. Go to your application
#      status page to sign." `FUIME_DOCUSEAL_TEMPLATE_ID` is unset, so
#      `send_contract` returns nil, the status page renders no signing step, and
#      there is nothing to sign anywhere in the product. An instruction marked
#      Action Needed that cannot be carried out.
#   3. "[<name>] Welcome to Fuime!" — the only one of the three that was true,
#      and the one that arrived last.
#
# The rational response to reading (1) and (2) is to stop and wait for a
# signature request. That is the opposite of what the product had just done, and
# it happened at the single highest-intent moment in the funnel.
#
# ── What this file pins ─────────────────────────────────────────────────────
#
# Admission sends ONE mail. A genuine queue still says so. And the agreement
# mail is tied to an agreement existing, not to the approval transition.
RSpec.describe "the mail a founder gets after submitting" do
  let(:teen) { create(:user, :attested_teen, full_name: "Nova Lin") }

  # The shape the /setup wizard produces: teen-led, a trade, a parent's email.
  def submittable_application(user: teen)
    create(
      :event_application,
      user:,
      teen_led: true,
      name: "Nova Dog Walking",
      description: "I walk dogs after school.",
      business_category: "services",
      address_country: "US",
      cosigner_email: "parent-lifecycle@example.com"
    )
  end

  # `mark_submitted!` sets a flag that `after_commit` turns into admission, so
  # the real sequence only runs when the write actually commits.
  def submit!(application)
    application.mark_submitted!
    ::Fuime::FounderAdmission.new(application: application.reload).call
  end

  # `:merchant_of_record` is production (render.yaml) and is the configuration in
  # which a founder is admitted without a parent having done anything — under
  # Connect `#activation_blockers` refuses a guardianless minor, which is the
  # "somebody really is waiting" case below.
  describe "when the founder is admitted on the spot", :merchant_of_record do
    let(:application) { submittable_application }

    it "never sends the agreement mail, because there is no agreement" do
      expect(Event::Plan::Standard.new.contract_available?)
        .to be(false), "this example describes the unconfigured-DocuSeal state"

      expect { submit!(application) }
        .not_to have_enqueued_mail(Event::ApplicationMailer, :approved)

      expect(application.reload).to be_approved
    end

    it "sends the welcome mail" do
      expect { submit!(application) }
        .to have_enqueued_mail(Event::ApplicationMailer, :activated).once
    end

    # The queue mail is still ENQUEUED here — it is deliberately deferred and
    # re-checked rather than suppressed at the call site, so that every caller
    # of `mark_under_review!` gets the same treatment without knowing about it.
    # The example below is the one that matters: what it does when it runs.
    it "delivers nothing when the deferred queue mail finally runs" do
      submit!(application)

      expect(application.reload).not_to be_under_review

      mail = Event::ApplicationMailer.with(application:).under_review
      expect(mail.message).to be_a(ActionMailer::Base::NullMail)
      expect { mail.deliver_now }.not_to(change { ActionMailer::Base.deliveries.count })
    end

    it "is one mail in total, and it is the true one" do
      # Created first, and the queue drained by TIME rather than with a bare
      # `perform_enqueued_jobs { }` block. Two things go wrong with the block
      # form, and both are the harness rather than the product:
      #
      #   - `after_create_commit` schedules the abandoned-draft reminders, which
      #     the block would run the instant they are enqueued, while the record
      #     is still legitimately a draft — a fortnight collapsed into a
      #     millisecond.
      #   - The block ignores `wait:`, so the deferred queue mail would run
      #     BEFORE admission advances the state, which is the exact race
      #     `QUEUE_MAIL_DELAY` exists to remove. Testing with the delay discarded
      #     would test a system we do not ship.
      #
      # Five minutes is past `QUEUE_MAIL_DELAY` and nowhere near the day-1
      # reminder, so what runs here is precisely what a founder receives.
      application
      ActionMailer::Base.deliveries.clear

      submit!(application)
      perform_enqueued_jobs(at: 5.minutes.from_now)

      subjects = ActionMailer::Base.deliveries.map(&:subject)

      # Anything addressed to the guardian is a different conversation; this is
      # about what the FOUNDER reads.
      founder_mail = ActionMailer::Base.deliveries.select { |m| m.to.include?(teen.email) }

      expect(founder_mail.size).to eq(1), "founder received: #{subjects.inspect}"
      expect(founder_mail.first.subject).to include("Welcome to Fuime")
      expect(subjects).not_to include(a_string_matching(/Action Needed/))
      expect(subjects).not_to include(a_string_matching(/under review/i))
    end
  end

  describe "when somebody really is waiting on a human" do
    let(:application) { submittable_application }

    # The Connect guardian gate, an admin-held application, a second venture on
    # Free — anything that leaves the record resting in `under_review`.
    before do
      allow_any_instance_of(Event::Application)
        .to receive(:activation_blockers)
        .and_return(["you already have a business on the Free plan"])
    end

    it "still tells them they are in a queue" do
      submit!(application)

      expect(application.reload).to be_under_review

      expect { Event::ApplicationMailer.with(application:).under_review.deliver_now }
        .to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(ActionMailer::Base.deliveries.last.subject).to include("under review")
    end
  end

  describe "the approval mail once an agreement exists" do
    let(:application) { submittable_application }

    it "goes out when `send_contract` produces something to sign" do
      contract = instance_double(Contract::FiscalSponsorship, present?: true)
      allow_any_instance_of(Event::Application).to receive(:send_contract).and_return(contract)
      allow_any_instance_of(Event::Application).to receive(:contract).and_return(nil)

      application.mark_submitted!
      application.mark_under_review! if application.may_mark_under_review?

      expect { application.mark_approved! }
        .to have_enqueued_mail(Event::ApplicationMailer, :approved).once
    end
  end
end
