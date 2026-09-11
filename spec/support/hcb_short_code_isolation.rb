# frozen_string_literal: true

# Fuime: give a factory/sweep memo an HCB-xxxxx that assign_ledger_item will
# actually accept.
#
# Putting a random token in the memo is not enough. CanonicalTransaction#short_code
# reads HCB-(\w{5}) from the memo; the grouping engine then looks up an HcbCode
# with that short_code and, if none exists, falls through to HCB-000-<id> and a
# freshly generated short_code. assign_ledger_item compares the two, reports
# unexpected, and create_ledger_item! UniqueViolation-collides with a leftover
# Ledger::Item (CI shard flake on connect_settlement_sweep_spec /
# payables_ledger_spec).
#
# Pre-create both rows so the memo token, the grouping HcbCode, and the ledger
# item are the same object. Spec-only; ledger engine untouched.
module HcbShortCodeIsolation
  def isolated_hcb_short_code
    8.times do
      hcb = HcbCode.create!(hcb_code: "HCB-000-iso#{SecureRandom.hex(8)}")
      token = hcb.short_code
      next if token.blank? || Ledger::Item.exists?(short_code: token)

      item = Ledger::Item.create!(
        memo: "iso #{token}",
        amount_cents: 0,
        datetime: Time.current,
        short_code: token
      )
      hcb.update!(ledger_item: item)
      return token
    end

    raise "could not isolate an HCB short_code"
  end
end
