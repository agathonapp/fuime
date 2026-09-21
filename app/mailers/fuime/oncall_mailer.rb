# frozen_string_literal: true

module Fuime
  # Fuime: the email arm of the pager.
  #
  # Email is the WEAKEST channel here and is included anyway, for two reasons
  # that have nothing to do with waking anybody:
  #
  #   * It is the durable record. Push relays keep nothing, a text is one line,
  #     and a voice call leaves no trace at all — but the mail sits in an inbox
  #     with the full detail attached, which is what a post-mortem, a chargeback
  #     representment or a Stripe review actually needs.
  #   * It is the channel that works when the others are not configured yet. A
  #     responder with only an email is not on call (Responder#pageable? says
  #     so), but they should still be told.
  #
  # Unlike the page over push or SMS, this one carries the full incident detail:
  # it is addressed to a named mailbox rather than broadcast to a relay, and the
  # same inbox already receives the daily digest with the same material in it.
  class OncallMailer < ApplicationMailer
    def page
      @incident = params.fetch(:incident)
      @responder = params[:responder]
      @detail = @incident.detail.presence || {}

      mail(
        to: @responder&.email.presence || ApplicationMailer.ops_recipients,
        subject: "[Fuime #{@incident.severity.upcase}] #{@incident.title}"
      ) do |format|
        format.html
        format.text
      end
    end

  end
end
