# frozen_string_literal: true

# Fuime: the public directory of teen-run businesses.
#
# The demand side. A payment processor is cloneable in a weekend; a place buyers
# actually go is not, which is why the brief calls this the moat rather than a
# feature.
#
# ── The constraint that shapes every decision here ──────────────────────────
#
# This is a LISTING, never a DISPATCH. Operators publish; buyers browse and
# contact them. Fuime never assigns a buyer to an operator, never sets or
# suggests a price, and never ranks anyone by quality.
#
# That is not squeamishness, it is the risk the brief itself names: its own
# mitigation for the worker-classification question is "operators control their
# own pricing, clients and hours — we never route work to them or set rates."
# A directory that matches, ranks or scores is doing exactly that, and ranking by
# a quality metric Fuime enforces is the evidence an examiner looks for.
# See docs/fuime/MOR_MIGRATION_PLAN.md §8.3 D2.
#
# The exposure is smaller under Stripe Connect, where the guardian is the
# merchant and operators are not Fuime's vendors at all — but the rules cost
# nothing to keep and the model is meant to survive the move to
# merchant-of-record, so they are written down and tested rather than remembered.
#
# Concretely, and enforced by spec/controllers/fuime/directory_controller_spec.rb:
#
#   * ordering is neutral (newest first, or alphabetical) — never a quality score
#   * no ratings, no reviews, no completion or response-rate metrics
#   * no "featured", "top", "recommended" or "best match"
#   * no prices set or suggested by Fuime
#
# ── What may be listed ──────────────────────────────────────────────────────
#
# Only ventures that are already publicly visible AND can actually be paid. A
# directory entry that leads to a dead payment form is worse than no entry, and
# #accepts_payments? now folds in vetting — so an unreviewed or suspended venture
# drops out of the directory automatically, without a second rule to keep in sync.
module Fuime
  class DirectoryController < ApplicationController
    skip_before_action :signed_in_user
    skip_after_action :verify_authorized

    # A page of a directory is not a place to be clever about N+1s: keep it small
    # enough that the per-row #accepts_payments? check below stays cheap.
    PER_PAGE = 24

    ORDERINGS = {
      "newest" => "Newest first",
      "name"   => "A–Z",
    }.freeze

    def index
      @category = params[:category].presence
      @category = nil unless Event::BUSINESS_CATEGORIES.include?(@category)

      @ordering = ORDERINGS.key?(params[:order]) ? params[:order] : "newest"

      scope = Event.not_hidden
                   .where(is_public: true, is_indexable: true, demo_mode: false)
                   .operator_vetting_approved
                   .includes(:stripe_connected_account, :plan)
      scope = scope.where(business_category: @category) if @category

      # Ordering is applied in SQL and is deliberately boring. `unscope(:order)`
      # because Event's default_scope orders by id, which would otherwise win and
      # silently make every ordering option identical.
      scope = scope.unscope(:order)
      scope = @ordering == "name" ? scope.order(Arel.sql("LOWER(events.name) ASC")) : scope.order(created_at: :desc)

      # #accepts_payments? cannot be expressed in SQL — a school venture inherits
      # its payment account from an ancestor (Event#payment_account), so the join
      # would miss exactly the students a school programme exists to serve.
      # Filtering in Ruby over one page is the honest trade; PER_PAGE keeps it bounded.
      #
      # The paginated RELATION is kept separately because `select` returns an Array
      # and Kaminari's `paginate` helper needs the relation to know about pages.
      # The consequence, stated so nobody reads it as a bug: a page can show fewer
      # than PER_PAGE entries when some of its ventures cannot currently be paid.
      # Correct — a directory entry leading to a dead payment form is worse than a
      # short page — and it beats the alternative of loading every venture to fill
      # a page exactly.
      @page = scope.page(params[:page]).per(PER_PAGE)
      @ventures = @page.select(&:accepts_payments?)

      @categories = Event::BUSINESS_CATEGORIES
    end

  end
end
