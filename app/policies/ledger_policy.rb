# frozen_string_literal: true

class LedgerPolicy < ApplicationPolicy
  # Fuime: closed for everyone, auditors included, until the rewritten ledger
  # stops rendering an empty page for a venture that has taken money. The
  # auditor branch was unconditional, so staff saw it regardless of any flag —
  # which is how it was found. See Fuime::Features.new_ledger?.
  def show?
    return false unless ::Fuime::Features.new_ledger?

    user&.auditor? || (OrganizerPosition.role_at_least?(user, record.event, :reader) && (Flipper.enabled?(:new_ledger_2026_06_30, record.event) || Flipper.enabled?(:new_ledger_2026_07_17, user)))
  end

end
