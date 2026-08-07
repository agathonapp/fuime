# frozen_string_literal: true

class GuardianshipPolicy < ApplicationPolicy
  # Any signed-in user may open their own guardian overview. It lists only the
  # guardianships they hold, so an adult with none simply sees an empty state —
  # there is nothing to authorize beyond being signed in, and gating on
  # `is_guardian?` would 403 a parent whose invite is still pending, which is
  # exactly when they most want to look.
  def index?
    user.present?
  end

  # Teen can create a guardianship invite (inviting their parent).
  #
  # `is_minor?` is nil (not false) when no birthday is recorded, which is the
  # normal state during onboarding — a teen who hasn't set a birthday yet still
  # needs to be able to invite a guardian. Only block users known to be adults.
  def new?
    user.present? && user.is_minor? != false
  end

  def create?
    new?
  end

  # Guardian can view their invite
  def show?
    user.present? && record.guardian == user
  end

  # Guardian can accept the invitation
  def accept?
    user.present? && record.guardian == user && record.pending?
  end

  # Everyone the agreement binds may read it back: the guardian who signed, the
  # minor it covers, and admins handling support.
  def record?
    return false if user.blank?

    user.admin? || record.guardian == user || record.minor == user
  end

  # Withdrawing consent belongs to the adult who gave it, plus Fuime admins for
  # support cases. Deliberately NOT the minor: a teen must not be able to remove
  # their own supervision, which is the whole point of the control.
  def revoke?
    return false if user.blank?
    return false if record.revoked?

    user.admin? || record.guardian == user
  end

  # Same authority as revoking — whoever can end a guardianship can re-send its
  # invite. The minor is included here because chasing an unresponsive parent is
  # their problem to solve, and a resend only ever re-mails the same guardian.
  def resend_invite?
    return false if user.blank?
    return false unless record.pending?

    user.admin? || record.guardian == user || record.minor == user
  end

end
