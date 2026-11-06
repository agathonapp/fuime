# frozen_string_literal: true

module Fuime
  # Fuime: may a stranger make an account? Closed until the waitlist is let in.
  #
  # Founder's call, 2026-10-01: fuime.com becomes a waitlist and the app stops
  # taking sign-ups "until we onboard ppl". What closes is the public door —
  # LoginsController#create minting a User for any address typed into it, and
  # ExportsController doing the same from a public form. Nothing else changes:
  #
  #   * Anyone with a User row signs in exactly as before.
  #   * Every invite path creates the User BEFORE it mails the link —
  #     Fuime::WaitlistInviteService, the family setup wizard, the guardian
  #     invite, OrganizerPositionInviteService — so an invited person arrives at
  #     the door as an existing user and walks through it.
  #
  # That is why closing sign-ups and onboarding people from the waitlist are the
  # same switch: /admin/waitlist "Invite" is the way in.
  #
  # Someone without an account is sent to the waitlist on fuime.com's landing
  # page (site/index.html#join). The site owns sign-ups to the list; the app
  # only reads the roster and stamps invites onto it.
  #
  # An env var, read here and nowhere else, for the reason Features#new_ledger?
  # gives: the safe answer has to be what an unconfigured environment means, and
  # opening the doors is a launch — a one-line change to render.yaml that someone
  # reviews — not a checkbox in a web UI.
  module Signups
    ENV_KEY = "FUIME_SIGNUPS_OPEN"

    class << self
      # The word "true", case-insensitively, and nothing else (see
      # Features.enabled? for why not `.present?`).
      def open?
        ENV[ENV_KEY].to_s.strip.downcase == "true"
      end

      def closed?
        !open?
      end

      # The waitlist form on the landing page. `account_none` tells the site the
      # visitor tried to sign in with an address that has no account, so it
      # can say so. FUIME_SITE_ORIGIN points it at a local or preview site.
      def waitlist_url(account_none: false)
        origin = ENV["FUIME_SITE_ORIGIN"].presence || "https://fuime.com"
        "#{origin.chomp("/")}/#{"?account=none" if account_none}#join"
      end

    end
  end
end
