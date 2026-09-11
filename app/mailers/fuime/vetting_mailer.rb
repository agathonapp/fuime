# frozen_string_literal: true

module Fuime
  # Fuime: the email the product has promised since vetting shipped and never
  # sent. app/views/fuime/_selling_blockers.html.erb tells an unvetted venture
  # "We'll email you when yours is approved"; until this class existed nothing
  # did, and a founder found out by reloading the page.
  #
  # One moment — operator_vetting_status becoming `approved` — and two messages
  # for it, chosen by Event#record_vetting_decision! from where the venture came:
  #
  #   unvetted / rejected → approved   #approved    "publish your first offer"
  #   suspended           → approved   #reinstated  "approved to sell again"
  #
  # The split exists because a suspended venture was already trading. Nothing
  # unpublishes its offers on suspension (Fuime::Offer's only `unpublish!` caller
  # is the operator's own button); the storefront just withholds the Buy button
  # while Event#accepts_payments? is false. So when the suspension lifts, those
  # offers are back on sale by themselves, and "publish your first offer" would
  # be false to a founder with three live ones.
  #
  # Sent whether a human clicked Approve in /admin/operator_vetting or
  # Fuime::CohortAdmission vouched for a whole room at once.
  #
  # Recipients are the venture's managers, not its point of contact: under the
  # deferred-onboarding flow `point_of_contact` is the activating admin
  # (Event::Application#activate_event!), so mailing them would tell Fuime staff
  # about a decision Fuime staff just made.
  #
  # Most recipients are minors. Both are transactional notices about their own
  # venture (L7) and say nothing about money held anywhere — approval is
  # permission to sell, not a balance.
  class VettingMailer < ApplicationMailer
    def approved(event:)
      prepare(event)

      # Same From/Reply-To reasoning as GuardianshipMailer#invite: no-reply is the
      # documented sending mailbox; the reply address is a real inbox.
      mail(
        to: manager_addresses,
        reply_to: OPERATIONS_EMAIL,
        subject: "#{event.name} is approved — publish your first offer"
      ) do |format|
        format.html
        format.text
      end
    end

    def reinstated(event:)
      prepare(event)

      # Whether there is anything to come back on sale. Published offers survive
      # a suspension (see the class note), so this is what decides between "your
      # offers are back on sale" and "you can publish an offer now".
      @published_offers = event.fuime_offers.published.exists?

      mail(
        to: manager_addresses,
        reply_to: OPERATIONS_EMAIL,
        subject: "#{event.name} is approved to sell again"
      ) do |format|
        format.html
        format.text
      end
    end

    private

    def prepare(event)
      @event = event
      @offers_url = fuime_offers_url(event_slug: event.slug)
      @support_email = OPERATIONS_EMAIL

      # Vetting is one of the gates, not the whole of them. Under
      # merchant-of-record the launch scope (services-only, the operator age
      # floor) can still refuse; under Connect a ready connected account is also
      # needed. Fuime::Offer refuses to publish for a venture that cannot take
      # payments, so "you can publish now" is only written when it is true (L8).
      @can_publish = event.accepts_payments?
    end

    # Everyone holding a manager-or-above position. `organizer_positions` is
    # acts_as_paranoid, so a removed manager is excluded by the default scope;
    # `manager_access` is the role-hierarchy scope from OrganizerPosition::HasRole.
    # An event with no managers yields an empty list, which
    # ApplicationMailer.deliver_mail turns into "send nothing".
    def manager_addresses
      @event.organizer_positions.manager_access.includes(:user).map do |position|
        position.user.email_address_with_name
      end
    end

  end
end
