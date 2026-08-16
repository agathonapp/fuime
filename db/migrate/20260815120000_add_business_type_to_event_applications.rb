# frozen_string_literal: true

# Fuime: what kind of business this is, and where the founder is starting from.
#
# ── Why this is a step and not two more fields on `project_info` ────────────
#
# The existing application asks for a name and a free-text description, which is
# enough to review an application and not enough to do anything else with. Two
# concrete things fall out of asking the question properly:
#
#   * **`Event#business_category` is currently never set from an application.**
#     Nothing in `activate_event!` populates it, so every venture created through
#     the funnel starts with it blank — and under merchant-of-record
#     `Fuime::OperatorEligibility::ELIGIBLE_CATEGORIES` is `%w[services]`, which a
#     blank category does not satisfy. Ventures were being created pre-blocked and
#     the vetting queue was where anyone found out. Collecting it here fixes that.
#   * A 16-year-old who has decided to start a business and has no idea what to
#     sell is the largest drop-off in this funnel, and "describe your business" is
#     a wall to them. The three-way fork gives that person somewhere to go.
#
# ── The three starting points ───────────────────────────────────────────────
#
# Modelled on Whop's new-business fork, with its third card deliberately changed.
# Whop offers "clone a proven business"; Fuime offers "start from a template",
# because cloning requires holding real operators up as proven, and ranking
# operators is the thing MOR_MIGRATION_PLAN §8.3 D2 forbids — the directory
# already had to ship as a listing rather than a dispatch for exactly this
# reason. A Fuime-authored template names nobody and ranks nothing.
#
# ── What a template deliberately does NOT carry ─────────────────────────────
#
# Prices. The single most useful thing a starter template could offer a teenager
# is "charge about this much", and it is the one thing Fuime cannot say. D2's
# mitigation for worker misclassification is *"operators must control their own
# pricing, clients, and hours. We never route work to them or set rates"* — a
# suggested rate is a set rate with a softer verb. Templates carry structure and
# copy; the operator brings the number.
class AddBusinessTypeToEventApplications < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # have_business | have_idea | from_template. Nullable: every application that
    # already exists predates the question, and backfilling a guess would put a
    # claim in the record that nobody made.
    add_column :event_applications, :starting_point, :string

    # A key from Fuime::ServiceCatalog. Deliberately NOT a foreign key or an enum
    # in the database: the catalog is product copy that will be edited far more
    # often than the schema, and a migration per new service type would mean the
    # catalog is only as current as somebody's willingness to write one.
    add_column :event_applications, :service_type, :string

    # Which of Event::BUSINESS_CATEGORIES this resolves to. Stored rather than
    # derived from `service_type` at read time so that retiring or renaming a
    # service key later cannot silently re-categorise a venture that was already
    # reviewed and approved under the old one.
    add_column :event_applications, :business_category, :string

    add_check_constraint :event_applications,
                         "starting_point IS NULL OR starting_point IN ('have_business', 'have_idea', 'from_template')",
                         name: "event_applications_starting_point_known",
                         validate: false

    add_index :event_applications, :service_type,
              where: "service_type IS NOT NULL",
              algorithm: :concurrently
  end

end
