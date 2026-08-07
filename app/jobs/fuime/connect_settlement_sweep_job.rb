# frozen_string_literal: true

module Fuime
  # Scheduled wrapper for the settlement sweep — see the service header for why
  # this is a schedule and not a webhook handler (Stripe emits no per-charge
  # "funds became available" event).
  class ConnectSettlementSweepJob < ApplicationJob
    queue_as :low

    def perform
      Fuime::ConnectSettlementSweep.sweep_all
    end

  end
end
