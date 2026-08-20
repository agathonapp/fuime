# frozen_string_literal: true

module StaticPagesHelper
  extend ActionView::Helpers::NumberHelper

  # Fuime: one admin destination. The pin-to-top affordance that used to ride
  # along on every card was a workaround for a wall of ~30 undifferentiated
  # links; admin_tools.html.erb now separates the queues that have work
  # outstanding from the reference links, so there is nothing left to pin.
  def card_to(name, path, **options)
    badge = if options[:badge].present?
              badge_for(options[:badge], class: options[:subtle_badge].present? || options[:badge] == 0 ? "bg-muted h-fit" : "bg-accent h-fit")
            elsif options[:async_badge].present?
              turbo_frame_tag options[:async_badge], src: admin_task_size_path(task_name: options[:async_badge]) do
                badge_for "\u23F3", class: "bg-muted"
              end
            end

    content_tag(:li, id: options[:id] || "card-#{name.parameterize}", class: "list-none") do
      link_to path, class: "link-reset", method: options[:method] do
        content_tag(:div, class: "card card--hover flex items-center gap-2 py-3") do
          safe_join([
            content_tag(:strong, sanitize(name), class: "truncate"),
            content_tag(:span, "", class: "flex-grow"),
            badge,
            inline_icon("view-forward", size: 20, class: "muted fill-current shrink-0 -mr-1")
          ].compact)
        end
      end
    end
  end

  # Fuime: the admin console's index, as data.
  #
  # `admin_queues` is work outstanding — each entry badges a count, and the view
  # promotes the non-zero ones to a "Needs you" strip. `admin_directories` is
  # everything else: reference destinations grouped by what they are about,
  # collapsed behind a disclosure.
  #
  # These lived inline in admin_tools.html.erb as one flat list of ~30 equally
  # weighted cards. They are here so the template stays markup and the two
  # lists can be read, and reordered, without picking through ERB.
  def admin_queues
    [
      { name: "Operator vetting", path: operator_vetting_admin_index_path, badge: Event.not_hidden.operator_vetting_unvetted.count },
      { name: "Payout runs", path: payout_batches_admin_index_path, badge: Fuime::PayoutBatch.awaiting_approval.count },
      { name: "Applications", path: applications_admin_index_path, badge: Event::Application.under_review.count },
      { name: "Live cohorts", path: cohorts_admin_index_path, badge: Fuime::Cohort.live.count },
      { name: "OPDRs", path: organizer_position_deletion_requests_path, badge: OrganizerPositionDeletionRequest.under_review.count },
      { name: "Unmapped ledger", path: ledger_admin_index_path, badge: CanonicalTransaction.not_stripe_top_up.unmapped.count },
      { name: "Pending ledger", path: pending_ledger_admin_index_path, badge: CanonicalPendingTransaction.unsettled.count },
      { name: "Ledger audits", path: admin_ledger_audits_path, badge: Admin::LedgerAudit.pending.count },
      { name: "Bank fees", path: bank_fees_admin_index_path, badge: BankFee.in_transit_or_pending.count },
      { name: "Raw transactions", path: raw_transactions_admin_index_path, badge: RawCsvTransaction.unhashed.count },
    ]
  end

  def admin_directories
    {
      "Businesses & people" => [
        { name: "Businesses", path: events_admin_index_path, badge: Event.approved.where.not(id: fuime_system_event_ids).count, subtle: true },
        { name: "Users", path: users_admin_index_path },
        { name: "Waitlist", path: admin_waitlist_index_path, badge: Fuime::WaitlistRoster.cached_total, subtle: true },
        { name: "Contracts", path: contracts_admin_index_path, badge: Contract.count, subtle: true },
        { name: "Emails", path: emails_admin_index_path, badge: Ahoy::Message.count, subtle: true },
      ],
      "Money"               => [
        { name: "Invoices", path: invoices_admin_index_path },
        { name: "Cards", path: stripe_cards_admin_index_path },
        { name: "Fee revenues", path: fee_revenues_admin_index_path },
        { name: "Business balances", path: balances_admin_index_path },
        { name: "Negative businesses", path: negative_events_path },
        { name: "Bookkeeping", path: bookkeeping_path },
        { name: "Fuime codes", path: hcb_codes_admin_index_path },
      ],
      "System"              => [
        { name: "Blazer", path: blazer_path },
        { name: "Flipper", path: flipper_path },
        { name: "Common docs", path: common_documents_path },
        { name: "Search by user", path: admin_search_path },
      ],
    }
  end

  # The inherited Fuime system orgs (fee routing, grant funds, sweeps). They are
  # referenced by hardcoded id in the ledger and cannot be deleted, but they are
  # not real Fuime businesses, so they do not belong in the business count.
  def fuime_system_event_ids
    EventMappingEngine::EventIds.constants.map { |c| EventMappingEngine::EventIds.const_get(c) }
  end

  def flavor_text
    FlavorTextService.new(user: current_user).generate
  end


  def render_permissions(permissions, depth = 0)
    capture do
      permissions.each_with_index do |(k, v), i|

        # Nested title (for feature groups)
        if v.is_a?(Hash)
          concat(content_tag(:tr) do
            content_tag(:th, class: "h#{depth + 2} #{"pt3" unless i.zero?}", style: "padding-left: #{depth * 2}rem") do
              concat k

              if v[:_preface]
                concat content_tag(:span, v[:_preface], class: "muted regular pl2 h5")
              end
            end
          end)

          concat render_permissions(v, depth + 1)

        # Row for feature with permission icons
        elsif v.is_a?(Symbol)
          concat(content_tag(:tr) do
            concat content_tag(:th, k, class: "regular", style: "padding-left: #{depth * 2}rem")

            needed_role_num = OrganizerPosition.roles[v]

            OrganizerPosition.roles.each_value do |role_num|
              if role_num >= needed_role_num
                concat content_tag(:td, "✅")
              else
                concat content_tag(:td, "❌")
              end
            end
          end)
        end

      end
    end
  end
end
