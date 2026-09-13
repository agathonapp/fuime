# frozen_string_literal: true

class Event
  class ApplicationMailer < ::ApplicationMailer
    before_action { @application = params[:application] }

    def confirmation
      mail to: @application.user.email_address_with_name, subject: "Thank you for applying to Fuime!"
    end

    # Sent `wait: Event::Application::QUEUE_MAIL_DELAY` after the transition, and
    # only if the application is still sitting in the queue by then.
    #
    # Fuime: `Fuime::FounderAdmission` moves an ordinary founder under_review →
    # approved → activated inside one request, so for most people this mail's
    # promise ("you'll hear from us within two business days") was already false
    # when it was written. A founder who is genuinely waiting on a human — the
    # Connect guardian gate, an unsigned agreement, an admin-held application —
    # is still under_review when this runs, and still gets told.
    #
    # Returning without calling `mail` yields ActionMailer::Base::NullMail, which
    # delivers nothing. That is the documented way to abort a mailer.
    def under_review
      return unless @application.reload.under_review?

      mail to: @application.user.email_address_with_name, subject: "Your Fuime application is under review"
    end

    # The one nudge for a founder who started and did not finish.
    #
    # Fuime: every tip here used to be upstream HCB's — a free donation page, a
    # reimbursement flow, physical and virtual debit cards with Apple Pay, and a
    # mobile app. Fuime has none of those: donations, reimbursements and cards
    # are off (`DisabledModules`, `Event::Plan::Free`) and there is no app. They
    # were advertising four products that do not exist, to a 13-to-17-year-old,
    # which L7 does not allow even when the products are real.
    #
    # What replaced them is the trade-off a founder is actually weighing at the
    # moment they abandoned the form, and each sentence is checkable against the
    # product they would come back to.
    def incomplete
      tips = [
        "You don't need a parent's signature to set up or to start selling — a parent signs before any money leaves Fuime for your bank.",
        "Every business on Fuime gets a storefront link you can put in a bio or a group chat. Customers pay on it with a card; no app to download.",
        "/learn has ten starter templates — what to list, where the first customers come from, and what tends to go wrong in that trade."
      ]
      @tip = tips[(params[:tip_number].to_i - 1) % tips.length]

      # Fuime: `/setup`, not the application status page. The wizard resumes a
      # draft at its first unfinished step from the DATABASE rather than the
      # session (Fuime::OnboardingController#start), so a teen who abandoned the
      # form on a phone and opened this mail on a laptop lands where they left
      # off instead of on a form with their answers missing. Its only other
      # caller — Event::ApplicationReminderJob — never runs for a founder who
      # already has a venture, which is the one case the status page would suit.
      @resume_url = setup_url

      # Not "[Action Needed]". Nothing is owed to Fuime here — the founder is
      # free to never come back, and a demand in the subject line of an
      # unsolicited reminder to a minor is the shape L7 is written against.
      mail to: @application.user.email_address_with_name,
           subject: "Your Fuime business is still a draft"
    end

    def rejected
      @rejection_message = params[:rejection_message]
      mail to: @application.user.email_address_with_name, subject: "Update on your Fuime application"
    end

    def activated
      mail to: @application.user.email_address_with_name, subject: "[#{@application.name}] Welcome to Fuime!"
    end

    def approved
      mail to: @application.user.email_address_with_name, subject: "[Action Needed] #{@application.name} has been approved"
    end

  end

end
