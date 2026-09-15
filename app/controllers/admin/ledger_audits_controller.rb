# frozen_string_literal: true

module Admin
  # FUIME: this index is usually empty, and that is expected rather than broken.
  # The weekly sampler (Admin::LedgerAudit::GenerateJob) only draws from
  # CanonicalPendingTransaction.joins(:raw_pending_stripe_transaction) with a
  # negative amount — i.e. Stripe ISSUING card authorisations. Fuime's ledger
  # lines are RawPendingDonationTransaction (merchant-of-record Checkout), and
  # card issuing is off outside Stripe test mode, so the job creates an audit
  # with zero tasks each Monday and the `where.not(tasks: {id: nil})` filter
  # below correctly hides it.
  #
  # The live half of this feature is the "Flagged Transactions" queue
  # (Admin::LedgerAudits::TasksController), which an admin fills by hand from any
  # Fuime code's detail page. That works under MoR today, which is why these
  # routes stay.
  class LedgerAuditsController < AdminController
    def index
      @page = params[:page] || 1
      @per = params[:per] || 20

      @ledger_audits = Admin::LedgerAudit.all.order(created_at: :desc).includes(:admin_ledger_audit_tasks).where.not(admin_ledger_audit_tasks: { id: nil }).page(@page).per(@per)
    end

    def show
      @ledger_audit = Admin::LedgerAudit.find(params[:id])
      next_task = @ledger_audit.tasks.pending.first
      redirect_to admin_ledger_audits_task_path(next_task) and return if next_task.present?
    end

  end
end
