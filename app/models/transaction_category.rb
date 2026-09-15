# frozen_string_literal: true

# == Schema Information
#
# Table name: transaction_categories
#
#  id         :bigint           not null, primary key
#  slug       :citext           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_transaction_categories_on_slug  (slug) UNIQUE
#
class TransactionCategory < ApplicationRecord
  has_many(:transaction_category_mappings, inverse_of: :category)
  has_many(
    :canonical_transactions,
    through: :transaction_category_mappings,
    source: :categorizable,
    source_type: "CanonicalTransaction"
  )
  has_many(
    :canonical_pending_transactions,
    through: :transaction_category_mappings,
    source: :categorizable,
    source_type: "CanonicalPendingTransaction"
  )

  validates(
    :slug,
    presence: true,
    uniqueness: { case_sensitive: false },
    inclusion: { in: TransactionCategory::Definition::ALL.keys }
  )

  # FUIME: categories a venture operator may be shown.
  #
  # `hq_only` has been in db/data/transaction_categories.json since upstream and
  # `Definition#hq_only?` has always existed, but until 2026-09-15 nothing read
  # it — so every category list offered the whole set. On a venture's own ledger
  # filter that meant a teen founder and their guardian were offered Fuime's
  # internal bookkeeping categories ("Fuime revenue" — the platform's own take —
  # plus "Stripe service fees" and "Stripe fee reimbursements"), none of which
  # describe anything a venture can spend money on.
  #
  # A scope rather than a view-level `reject` because two filter menus
  # (events/filters and ledgers/filters) render the same list and had already
  # drifted apart once; the next surface that needs it should not have to
  # rediscover the flag.
  scope :operator_visible, -> {
    hq_only_slugs = TransactionCategory::Definition::ALL.values.select(&:hq_only?).map(&:slug)

    hq_only_slugs.any? ? where.not(slug: hq_only_slugs) : all
  }

  delegate :label, to: :definition

  def definition
    TransactionCategory::Definition::ALL.fetch(slug)
  end

end
