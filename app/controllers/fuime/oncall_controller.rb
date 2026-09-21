# frozen_string_literal: true

module Fuime
  # Fuime: the two on-call surfaces that must work without a session.
  #
  #   #ack     — one tap from a page, at 3am, on a phone that is not signed in.
  #   #health  — what an external monitor polls, from outside the app entirely.
  #
  # Both are deliberately outside the admin console, and for the same reason:
  # the moments they exist for are the moments when signing in is either
  # impossible or too slow to be worth it.
  class OncallController < ApplicationController
    skip_before_action :signed_in_user
    skip_after_action :verify_authorized

    # Acknowledge an incident from the notification.
    #
    # See the route comment for why this is unauthenticated. The narrow
    # capability is the whole security argument: this action can acknowledge and
    # nothing else. It does not resolve the incident, does not render the
    # detail, and does not enumerate — a wrong token is a 404 with no hint that
    # a right one exists.
    #
    # Acknowledging stops the repeat pages. It does not close anything: the
    # incident stays open, stays on the console, and stays in the digest until a
    # human resolves it or the check stops seeing the problem.
    def ack
      incident = ::Fuime::Incident.find_by(ack_token: params[:token])

      return render plain: "Unknown or expired acknowledgement link.", status: :not_found if incident.nil?

      if incident.status_open?
        incident.acknowledge!(user: current_user)
        Rails.logger.info("[Fuime::Oncall] #{incident.key} acknowledged from #{request.remote_ip}")
      end

      @incident = incident
      render :ack, layout: "application"
    end

    # The endpoint an external uptime monitor polls.
    #
    # ── Why this exists next to /up ───────────────────────────────────────
    #
    # `rails/health#show` answers 200 whenever a Puma worker can render a
    # template. That is a real signal — it catches a crash loop and a failed
    # boot — but it is also 200 while the database is unreachable for queries,
    # while Redis is down, and while no Sidekiq worker has existed for a day. An
    # external monitor watching only `/up` would have reported Fuime perfectly
    # healthy through an outage in which no sale reached any ledger.
    #
    # So this runs Check.infrastructure — the cheap, local, no-third-party
    # subset — and answers 503 when any of it reports a sev-1. Stripe is
    # deliberately NOT in that set: a slow third party must not be able to make
    # this app look down to a load balancer.
    #
    # It is a plain JSON body with no incident detail, because whoever is
    # polling it is unauthenticated by construction.
    def health
      findings = ::Fuime::Oncall::Check.infrastructure.flat_map do |klass|
        klass.new.call
      rescue => e
        [::Fuime::Oncall::Check::Finding.new(
          key: "health.check_failed.#{klass.check_name}",
          title: "#{klass.check_name} check raised #{e.class}",
          severity: :sev1, detail: {}
        )]
      end

      critical = findings.select { |f| f.severity.to_s == "sev1" }

      render json: {
        status: critical.any? ? "unhealthy" : "ok",
        checked_at: Time.current.iso8601,
        # Keys only. A key names a class of problem and reveals nothing about
        # any venture, person or amount.
        problems: findings.map(&:key)
      }, status: critical.any? ? :service_unavailable : :ok
    end

  end
end
