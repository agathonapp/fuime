# frozen_string_literal: true

class GuardianshipPolicy < ApplicationPolicy
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
end
