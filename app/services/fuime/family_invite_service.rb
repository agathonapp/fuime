# frozen_string_literal: true

# Fuime: the link that lets a parent-first teen into their own account.
#
# A parent sets the family up before the teen has ever opened Fuime, so the
# teen's stub account exists with nothing in it. This mints the token that
# email carries: open it, and you are signed in as that teen on that device.
#
# ── Why a signed id and not a column ─────────────────────────────────────────
#
# Same shape as `Fuime::WaitlistInviteService`: `User#signed_id` is a signed,
# expiring, purpose-scoped payload, so there is no token table, nothing to
# rotate, nothing to leak from the database, and an expired link cannot be
# revived by anybody — including us. Clicking it is inbox control, which is the
# same proof a login code asks for; `Fuime::FamilyInvitesController` then
# finishes the session through the ordinary `Login` machinery (2FA included),
# so this is not a second authentication system.
#
# The token is minted INSIDE the mailer and appears nowhere else — no view, no
# flash, no session, no log line. The parent cannot see it, which is the point:
# a parent holding their teen's sign-in link could act as them.
module Fuime
  class FamilyInviteService
    JOIN_EXPIRES_IN = 7.days
    SIGNED_ID_PURPOSE = :family_join

    def self.generate_token(user:)
      user.signed_id(expires_in: JOIN_EXPIRES_IN, purpose: SIGNED_ID_PURPOSE)
    end

    # The user, or nil for an expired, tampered or wrong-purpose token.
    def self.verify_token(token)
      return nil if token.blank?

      ::User.find_signed(token, purpose: SIGNED_ID_PURPOSE)
    end

  end
end
