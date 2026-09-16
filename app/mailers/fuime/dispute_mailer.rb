# frozen_string_literal: true

module Fuime
  # Fuime: tell somebody a chargeback arrived.
  #
  # Under merchant of record the dispute is against **Fuime LLC** — Fuime's name
  # is on the buyer's statement, Fuime's terms of sale governed the purchase, and
  # Fuime is the party the card network expects to answer. A dispute nobody
  # answers by its deadline is lost by default and Fuime pays it. Before this
  # mailer, `charge.dispute.created` reversed the ledger and told no human being
  # at all.
  #
  # Two audiences, deliberately different mail:
  #
  #   ops_alert       → Fuime. Has a deadline and an action. Sent immediately,
  #                     at any hour, because the clock is Stripe's not ours.
  #   operator_notice → the teenager whose payable just moved. No action, and
  #                     inside Fuime::MinorMailWindow (L7) because most
  #                     recipients are minors and this is not an emergency for
  #                     them — Fuime responds, not the founder.
  class DisputeMailer < ApplicationMailer
    # Where a chargeback lands at Fuime. One definition for every operational
    # alert — see ApplicationMailer.ops_recipients for why there is exactly one.
    def self.ops_address
      ApplicationMailer.ops_recipients
    end

    def ops_alert
      @dispute = params[:dispute]
      @event = @dispute.event
      @stripe_url = @dispute.stripe_dashboard_url
      @admin_url = fuime_disputes_admin_index_url

      mail(
        to: self.class.ops_address,
        subject: ops_subject
      ) do |format|
        format.html
        format.text
      end
    end

    # Sent on the opening of a real dispute only — never on an early warning,
    # which may never become a chargeback, and never on the close, which is
    # covered by the payable moving back. One mail per event, and it exists
    # because the alternative is a teenager watching what they are owed fall by
    # $40 with no explanation anywhere in the product.
    def operator_notice
      @dispute = params[:dispute]
      @event = @dispute.event
      @support_email = OPERATIONS_EMAIL
      @payouts_url = fuime_payouts_url(event_slug: @event.slug)

      mail(
        to: manager_addresses,
        reply_to: OPERATIONS_EMAIL,
        subject: "A customer disputed a payment to #{@event.name}"
      ) do |format|
        format.html
        format.text
      end
    end

    private

    def ops_subject
      amount = ApplicationController.helpers.render_money(@dispute.amount_cents)
      case @dispute.status
      when "warning_closed"
        # An inquiry that closed is not a dispute Fuime "won" — nothing was ever
        # taken, and calling it a win would teach the reader to skim these.
        "[Inquiry closed] #{amount} · #{@event.name}"
      when *::Fuime::Dispute::WON_STATUSES
        "[Dispute won] #{amount} · #{@event.name}"
      when *::Fuime::Dispute::LOST_STATUSES
        "[Dispute LOST] #{amount} · #{@event.name}"
      else
        prefix = @dispute.early_warning? ? "Early warning" : "ACTION NEEDED"
        "[#{prefix}] #{amount} chargeback · #{@event.name} · #{@dispute.reason_label}"
      end
    end

    # Same reasoning as Fuime::VettingMailer: managers, not the point of contact,
    # which under deferred onboarding is the activating Fuime admin.
    def manager_addresses
      @event.organizer_positions.manager_access.includes(:user).map do |position|
        position.user.email_address_with_name
      end
    end

  end
end
