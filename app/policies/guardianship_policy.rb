# frozen_string_literal: true

class GuardianshipPolicy < ApplicationPolicy
  # Teen can create a guardianship invite (inviting their parent)
  def new?
    user.present? && user.is_minor?
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
