# frozen_string_literal: true

# == Schema Information
#
# Table name: events
#
#  id                                           :bigint           not null, primary key
#  aasm_state                                   :string           not null
#  activated_at                                 :datetime
#  address                                      :text
#  business_category                            :string
#  can_front_balance                            :boolean          default(FALSE), not null
#  country                                      :integer
#  deleted_at                                   :datetime
#  demo_mode                                    :boolean          default(FALSE), not null
#  description                                  :text
#  donation_page_enabled                        :boolean          default(TRUE)
#  donation_page_message                        :text
#  donation_reply_to_email                      :text
#  donation_thank_you_message                   :text
#  donation_tiers_enabled                       :boolean          default(FALSE), not null
#  fee_waiver_applied                           :boolean          default(FALSE), not null
#  fee_waiver_eligible                          :boolean          default(FALSE), not null
#  financially_frozen                           :boolean          default(FALSE), not null
#  hidden_at                                    :datetime
#  holiday_features                             :boolean          default(TRUE), not null
#  is_indexable                                 :boolean          default(TRUE)
#  is_public                                    :boolean          default(TRUE)
#  last_fee_processed_at                        :datetime
#  name                                         :text             not null
#  operator_vetted_at                           :datetime
#  operator_vetting_notes                       :text
#  operator_vetting_status                      :integer          default(0), not null
#  postal_code                                  :string
#  public_message                               :text
#  public_reimbursement_page_enabled            :boolean          default(FALSE), not null
#  public_reimbursement_page_message            :text
#  reimbursements_require_organizer_peer_review :boolean          default(FALSE), not null
#  risk_level                                   :integer
#  sale_terms_acknowledged_at                   :datetime
#  sale_terms_version                           :string
#  short_name                                   :string
#  show_recent_donors                           :boolean          default(FALSE), not null
#  show_top_donors                              :boolean          default(FALSE), not null
#  slug                                         :text
#  storefront_tagline                           :string
#  stripe_card_shipping_type                    :integer          default(0), not null
#  website                                      :string
#  created_at                                   :datetime         not null
#  updated_at                                   :datetime         not null
#  discord_channel_id                           :string
#  discord_guild_id                             :string
#  emburse_department_id                        :string
#  fuime_cohort_id                              :bigint
#  increase_account_id                          :string           not null
#  operator_vetted_by_id                        :bigint
#  parent_id                                    :bigint
#  point_of_contact_id                          :bigint
#  sale_terms_acknowledged_by_id                :bigint
#
# Indexes
#
#  index_events_on_discord_channel_id             (discord_channel_id) UNIQUE
#  index_events_on_discord_guild_id               (discord_guild_id) UNIQUE
#  index_events_on_fuime_cohort_id                (fuime_cohort_id)
#  index_events_on_operator_vetting_status        (operator_vetting_status)
#  index_events_on_parent_id                      (parent_id)
#  index_events_on_point_of_contact_id            (point_of_contact_id)
#  index_events_on_sale_terms_acknowledged_by_id  (sale_terms_acknowledged_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (fuime_cohort_id => fuime_cohorts.id)
#  fk_rails_...  (operator_vetted_by_id => users.id)
#  fk_rails_...  (point_of_contact_id => users.id)
#  fk_rails_...  (sale_terms_acknowledged_by_id => users.id)
#
class Event < ApplicationRecord
  MIN_WAITING_TIME_BETWEEN_FEES = 5.days

  include Hashid::Rails
  hashid_config salt: ""

  extend FriendlyId

  include PublicIdentifiable
  set_public_id_prefix :org

  include CountryEnumable
  has_country_enum

  include Commentable

  has_paper_trail
  acts_as_paranoid
  validates_as_paranoid

  validates_email_format_of :donation_reply_to_email, allow_nil: true, allow_blank: true
  normalizes :donation_reply_to_email, with: ->(donation_reply_to_email) { donation_reply_to_email.strip.downcase }
  validates :donation_thank_you_message, length: { maximum: 500 }
  validates :name, presence: true
  MAX_SHORT_NAME_LENGTH = 16
  validates :short_name, length: { maximum: MAX_SHORT_NAME_LENGTH }, allow_blank: true

  # Fuime: Business categories for teen ventures
  BUSINESS_CATEGORIES = %w[crafts services digital food other].freeze

  # Fuime: the version of the sale terms an operator acknowledged.
  #
  # Bumped when the SUBSTANCE changes — who the seller is, who bears refunds and
  # chargebacks, the refund window, or the "you set your own price" fact. Not for
  # rewording. A bump means every venture is asked again, so bumping it casually
  # interrupts fifty founders mid-event for nothing.
  #
  # Dated rather than numbered so the record says when, which is what anybody
  # reading it later actually wants to know.
  SALE_TERMS_VERSION = "2026-08-19"
  validates :business_category, inclusion: { in: BUSINESS_CATEGORIES }, allow_blank: true

  include AASM
  include PgSearch::Model
  pg_search_scope :search_name, against: [:name, :slug, :id], using: { tsearch: { prefix: true, dictionary: "simple" } }

  monetize :total_fees_v2_cents

  default_scope { order(id: :asc) }

  scope :active, -> {
    includes(canonical_event_mappings: :canonical_transaction)
      .where("canonical_transactions.created_at > ?", 1.year.ago)
      .references(:canonical_transaction)
  }

  scope :inactive, -> { where.not(id: Event.active.pluck(:id)) }

  scope :pending, -> { where(aasm_state: :pending) }
  scope :transparent, -> { where(is_public: true) }
  scope :not_transparent, -> { where(is_public: false) }
  scope :indexable, -> { where(is_public: true, is_indexable: true, demo_mode: false) }
  scope :omitted, -> { includes(:plan).where(plan: { type: Event::Plan.that(:omit_stats).collect(&:name) }) }
  scope :not_omitted, -> { includes(:plan).where.not(plan: { type: Event::Plan.that(:omit_stats).collect(&:name) }) }
  scope :hidden, -> { where.not(hidden_at: nil) }
  scope :not_hidden, -> { where(hidden_at: nil) }
  scope :funded, -> {
    includes(canonical_event_mappings: :canonical_transaction)
      .where("canonical_transactions.amount_cents > 0")
      .references(:canonical_transaction)
  }
  scope :not_funded, -> { where.not(id: funded) }
  scope :ysws, -> { includes(:event_tags).where(event_tags: { name: EventTag::Tags::YSWS }) }
  scope :hackathon, -> { includes(:event_tags).where(event_tags: { name: EventTag::Tags::HACKATHON }) }
  scope :organized_by_hack_clubbers, -> { includes(:event_tags).where(event_tags: { name: EventTag::Tags::ORGANIZED_BY_HACK_CLUBBERS }) }
  scope :not_organized_by_hack_clubbers, -> { includes(:event_tags).where.not(event_tags: { name: EventTag::Tags::ORGANIZED_BY_HACK_CLUBBERS }).or(includes(:event_tags).where(event_tags: { name: nil })) }
  scope :organized_by_teenagers, -> { includes(:event_tags).where(event_tags: { name: [EventTag::Tags::ORGANIZED_BY_TEENAGERS, EventTag::Tags::ORGANIZED_BY_HACK_CLUBBERS] }) }
  scope :not_organized_by_teenagers, -> { includes(:event_tags).where.not(event_tags: { name: [EventTag::Tags::ORGANIZED_BY_TEENAGERS, EventTag::Tags::ORGANIZED_BY_HACK_CLUBBERS] }).or(includes(:event_tags).where(event_tags: { name: nil })) }
  scope :robotics_team, -> { includes(:event_tags).where(event_tags: { name: EventTag::Tags::ROBOTICS_TEAM }) }
  scope :flag_enabled, ->(flag) {
    joins("INNER JOIN flipper_gates ON CONCAT('Event;', events.id) = flipper_gates.value")
      .where("flipper_gates.feature_key = ? AND flipper_gates.key = ?", flag, "actors")
  }

  # Following the convention of Module#ancestors https://apidock.com/ruby/Module/ancestors
  # this returns the id of self as well as all the ancestors,
  # in order from self->parent->grandparent->...
  # We guarantee this order using SEARCH BREADTH FIRST https://www.postgresql.org/docs/current/queries-with.html#QUERIES-WITH-SEARCH
  def ancestor_ids
    [id] + Event.connection.execute(<<-SQL).map { |row| row["id"] }
      WITH RECURSIVE parent_events AS (
        SELECT id, parent_id
        FROM events
        WHERE id = #{id}
        UNION ALL
        SELECT e.id, e.parent_id
        FROM events e
        INNER JOIN parent_events pe ON e.id = pe.parent_id
      ) SEARCH BREADTH FIRST BY id SET ordercol
      SELECT id FROM parent_events WHERE id != #{id} ORDER BY ordercol;
    SQL
  end

  def descendant_ids
    Event.connection.execute(<<-SQL).map { |row| row["id"] }
      WITH RECURSIVE child_events AS (
        SELECT id, parent_id
        FROM events
        WHERE parent_id = #{id}
        UNION ALL
        SELECT e.id, e.parent_id
        FROM events e
        INNER JOIN child_events ce ON e.parent_id = ce.id
      )
      SELECT id FROM child_events;
    SQL
  end

  # Following the convention of Module#ancestors https://apidock.com/ruby/Module/ancestors
  # this returns self as well as all the ancestors
  def ancestors
    # array_position preserves the order from ancestor_ids; sanitize_sql_array parameterizes the ids so it's statically safe and passes brakeman.
    fetched_ancestor_ids = ancestor_ids
    Event.where(id: fetched_ancestor_ids).reorder(Arel.sql(
                                                    Event.sanitize_sql_array(["array_position(ARRAY[?]::bigint[], events.id)", fetched_ancestor_ids])
                                                  ))
  end

  def descendants
    Event.where(id: descendant_ids)
  end

  # The direct sub-organizations `user` may see. #visible_descendant_ids walks
  # down from exactly this set, so it comes back empty whenever this does, which
  # is the cheap way to ask whether there is anything to show.
  def visible_subevents(user)
    return subevents if user&.auditor?

    organized_ids = user ? OrganizerPosition.reader_access.where(user:).pluck(:event_id) : []
    return subevents if organized_ids.any? && organized_ids.intersect?(ancestor_ids)

    subevents.where(is_public: true, hidden_at: nil).or(subevents.where(id: organized_ids))
  end

  # The descendants `user` is allowed to see, mirroring EventPolicy#show?
  # (`is_public || auditor_or_reader?`, where reader access is inherited from
  # any ancestor). Hidden events are treated as private, matching how every
  # other organization list treats `not_hidden`.
  #
  # Traversal stops at an event the user cannot see, so a transparent event
  # nested under a private one stays hidden too. Surfacing it would reveal that
  # the private organization exists.
  #
  # Like #descendant_ids, these ids skip the paranoid scope, so read them back
  # through ActiveRecord to drop any that are soft deleted.
  def visible_descendant_ids(user)
    return descendant_ids if user&.auditor?

    # Equivalent to OrganizerPosition.role_at_least?(user, self, :reader), reusing
    # the positions already fetched rather than querying for them again.
    organized_ids = user ? OrganizerPosition.reader_access.where(user:).pluck(:event_id) : []
    return descendant_ids if organized_ids.any? && organized_ids.intersect?(ancestor_ids)

    # Guard the empty case rather than let sanitize_sql_array render it, since it
    # turns [] into NULL and `e.id = ANY(ARRAY[NULL])` would make `unlocked` NULL.
    organized =
      if organized_ids.any?
        Event.sanitize_sql_array(["e.id = ANY(ARRAY[?]::bigint[])", organized_ids])
      else
        "FALSE"
      end
    transparent = "(e.is_public AND e.hidden_at IS NULL)"

    Event.connection.execute(<<-SQL).map { |row| row["id"] }
      WITH RECURSIVE child_events AS (
        SELECT e.id, e.parent_id, #{organized} AS unlocked
        FROM events e
        WHERE e.parent_id = #{id} AND (#{transparent} OR #{organized})
        UNION ALL
        SELECT e.id, e.parent_id, (ce.unlocked OR #{organized})
        FROM events e
        INNER JOIN child_events ce ON e.parent_id = ce.id
        WHERE #{transparent} OR #{organized} OR ce.unlocked
      )
      SELECT id FROM child_events;
    SQL
  end

  belongs_to :parent, class_name: "Event", optional: true
  has_many :subevents, class_name: "Event", foreign_key: "parent_id"

  MAX_PARENT_DEPTH = 50
  validate(:parent_id_is_acyclical)

  scope :event_ids_with_pending_fees, -> do
    query = <<~SQL
      ;select event_id, fee_balance from (
      select
      q1.event_id,
      COALESCE(q1.sum, 0) as total_fees,
      COALESCE(q2.sum, 0) as total_fee_payments,
      CEIL(COALESCE(q1.sum, 0)) + CEIL(COALESCE(q2.sum, 0)) as fee_balance

      from (
          select
          f.event_id,
          COALESCE(sum(f.amount_cents_as_decimal), 0) as sum
          from fees f
          inner join events e on e.id = f.event_id
          group by f.event_id
      ) as q1 left outer join (
          select
          cem.event_id,
          COALESCE(sum(ct.amount_cents), 0) as sum
          from canonical_event_mappings cem
          inner join fees f on cem.id = f.canonical_event_mapping_id
          inner join canonical_transactions ct on cem.canonical_transaction_id = ct.id
          inner join events e on e.id = cem.event_id
          and f.reason = 'HACK CLUB FEE'
          group by cem.event_id
      ) q2

      on q1.event_id = q2.event_id
      ) q3
      where fee_balance != 0
      order by fee_balance desc
    SQL

    ActiveRecord::Base.connection.execute(query)
  end

  scope :pending_fees_v2, -> do
    where("(last_fee_processed_at is null or last_fee_processed_at <= ?) and id in (?)", MIN_WAITING_TIME_BETWEEN_FEES.ago, self.event_ids_with_pending_fees.to_a.map { |a| a["event_id"] })
  end

  scope :demo_mode, -> { where(demo_mode: true) }
  scope :not_demo_mode, -> { where(demo_mode: false) }
  scope :filter_demo_mode, ->(demo_mode) { demo_mode.nil? ? all : where(demo_mode:) }
  scope :financially_frozen, -> { where(financially_frozen: true) }

  before_validation :enforce_transparency_eligibility

  BADGES = {
    # Qualifier must be a method on Event. If the method returns true, the badge
    # will be displayed for the event.
    omit_stats: {
      qualifier: :omit_stats?,
      emoji: "🏦",
      description: "Omitted from stats"
    },
    transparent: {
      qualifier: :is_public?,
      emoji: "📈",
      description: "Transparency mode enabled"
    },
    hidden: {
      qualifier: :hidden_at?,
      emoji: "🕵️‍♂️",
      description: "Hidden"
    },
    organized_by_hack_clubbers: {
      qualifier: :organized_by_hack_clubbers?,
      emoji: "🦕",
      description: "Organized by Hack Clubbers"
    },
    demo_mode: {
      qualifier: :demo_mode?,
      emoji: "🧪",
      description: "Demo Account"
    }
  }.freeze

  aasm do
    # All events should be approved prior to creation
    state :approved, initial: true # Full fiscal sponsorship
    state :rejected # Rejected from fiscal sponsorship

    # DEPRECATED
    state :unapproved # Old spend only events. Deprecated, should not be granted to any new events
    state :pending

    event :mark_pending do
      transitions from: [:awaiting_connect, :approved], to: :pending
    end

    event :mark_approved do
      transitions from: [:awaiting_connect, :pending, :unapproved], to: :approved
    end

    event :mark_rejected do
      transitions to: :rejected # from any state
    end
  end

  friendly_id :name, use: :slugged

  belongs_to :point_of_contact, class_name: "User", optional: true

  # we keep a papertrail of historic plans
  has_many :plans, class_name: "Event::Plan", inverse_of: :event
  has_one :plan, -> { where(aasm_state: :active) }, class_name: "Event::Plan", inverse_of: :event, required: true

  # Fuime: does an institution stand as the responsible adult for this org?
  #
  # Answered from self OR any ancestor, deliberately. A school programme is a
  # tree — the school is the main org and each student's venture is a sub org —
  # and the plan is set once at the top. Requiring the School plan on all several
  # hundred student sub orgs would be busywork that fails open the moment someone
  # forgets one, which for this predicate means asking a school for a parent
  # guardian who does not exist.
  #
  # Same direction of inheritance as CardGrant::InheritablePolicy: the
  # institution's answer flows down and nothing beneath it can contradict it.
  def institutionally_sponsored?
    return @institutionally_sponsored if defined?(@institutionally_sponsored)

    @institutionally_sponsored =
      Event.where(id: ancestor_ids)
           .includes(:plan)
           .any? { |event| event.plan&.institutionally_sponsored? }
  end

  has_one :config, class_name: "Event::Configuration"
  accepts_nested_attributes_for :config

  # Used for tracking slug history
  has_many :slugs, -> { order(id: :desc) }, class_name: "FriendlyId::Slug", as: :sluggable, dependent: :destroy

  has_many :organizer_position_invites, dependent: :destroy
  has_many :organizer_position_invite_links, class_name: "OrganizerPositionInvite::Link"
  has_many :organizer_position_invite_requests, through: :organizer_position_invite_links, source: :requests
  has_many :organizer_positions, dependent: :destroy

  def ancestor_organizer_positions
    OrganizerPosition.where(event_id: ancestor_ids)
  end

  def ancestor_users
    User.where(id: ancestor_organizer_positions.select(:user_id))
  end

  has_many :contracts, through: :organizer_position_invites
  has_many :organizer_position_deletion_requests, through: :organizer_positions, dependent: :destroy
  has_many :users, through: :organizer_positions
  has_many :signees, -> { where(organizer_positions: { is_signee: true }) }, through: :organizer_positions, source: :user
  has_many :managers, -> { where(organizer_positions: { role: :manager }) }, through: :organizer_positions, source: :user
  has_many :readers, -> { where(organizer_positions: { role: :reader }) }, through: :organizer_positions, source: :user
  has_many :g_suites
  has_many :g_suite_accounts, through: :g_suites

  has_many :event_follows, class_name: "Event::Follow", dependent: :destroy
  has_many :followers, through: :event_follows, source: :user

  has_many :fee_relationships
  has_many :transactions, through: :fee_relationships, source: :t_transaction

  has_many :affiliations, class_name: "Event::Affiliation", inverse_of: :affiliable, as: :affiliable

  has_many :stripe_cards
  has_many :stripe_authorizations, through: :stripe_cards
  has_many :stripe_card_personalization_designs, class_name: "StripeCard::PersonalizationDesign", inverse_of: :event

  has_many :emburse_cards
  has_many :emburse_card_requests
  has_many :emburse_transfers
  has_many :emburse_transactions

  has_many :ach_transfers
  has_many :payment_recipients
  has_many :payees
  has_many :payments, through: :payees
  has_many :payroll_positions, through: :payees, class_name: "Payroll::Position"
  has_many :payroll_invoices, through: :payroll_positions, source: :invoices, class_name: "Payroll::Invoice"

  has_many :disbursements
  has_many :incoming_disbursements, class_name: "Disbursement::Incoming"
  has_many :outgoing_disbursements, class_name: "Disbursement::Outgoing", foreign_key: :source_event_id
  has_many :donations
  has_many :donation_payouts, through: :donations, source: :payout
  has_many :recurring_donations
  has_one :donation_goal, dependent: :destroy, class_name: "Donation::Goal"
  has_many :donation_tiers, -> { order(sort_index: :asc) }, dependent: :destroy, class_name: "Donation::Tier"

  has_many :lob_addresses
  has_many :checks, through: :lob_addresses
  has_many :increase_checks

  has_many :paypal_transfers

  has_many :wires

  has_many :wise_transfers

  has_many :sponsors
  has_many :invoices, through: :sponsors
  has_many :payouts, through: :invoices

  has_many :reimbursement_reports, class_name: "Reimbursement::Report"

  has_many :employees
  has_many :employee_payments, through: :employees, source: :payments, class_name: "Employee::Payment"

  has_many :documents

  has_many :canonical_pending_event_mappings, -> { on_main_ledger }
  has_many :canonical_pending_transactions, through: :canonical_pending_event_mappings

  has_many :canonical_event_mappings, -> { on_main_ledger }
  has_many :canonical_transactions, through: :canonical_event_mappings

  has_many :announcements

  scope :engaged, -> {
    Event.where(id: Event.joins(:canonical_transactions)
        .where("canonical_transactions.date >= ?", 6.months.ago)
        .distinct)
  }

  scope :dormant, -> { where.not(id: Event.engaged) }

  has_many :fees
  has_many :bank_fees

  has_many :tags, -> { includes(:hcb_codes) }
  has_and_belongs_to_many :event_tags

  has_many :event_scoped_tags_events, class_name: "Event::ScopedTagsEvent", dependent: :destroy
  has_many :scoped_tags, through: :event_scoped_tags_events, source: :event_scoped_tag
  has_many :subevent_scoped_tags, class_name: "Event::ScopedTag", foreign_key: :parent_event_id, dependent: :destroy
  accepts_nested_attributes_for :event_scoped_tags_events

  has_one :ledger, -> { where(primary: true) }, inverse_of: :event
  after_create :create_ledger
  has_many :hcb_codes
  has_many :pinned_hcb_codes, -> { includes(hcb_code: [:canonical_transactions, :canonical_pending_transactions]) }, class_name: "HcbCode::Pin"

  has_many :check_deposits

  has_many :subledgers

  has_many :card_grants
  has_one :card_grant_setting
  accepts_nested_attributes_for :card_grant_setting, update_only: true

  has_one :increase_account_number

  has_one :column_account_number, class_name: "Column::AccountNumber"
  delegate :account_number, :routing_number, :bic_code, to: :column_account_number, allow_nil: true

  # Fuime: the guardian-owned Stripe account this venture is paid into. Absent
  # until a guardian completes payment setup, which is why every caller goes
  # through #accepts_payments? rather than assuming it exists.
  #
  # This is deliberately the venture's OWN account and nothing else. Code asking
  # "where does a payment for this venture go?" wants #payment_account, which
  # resolves through a school above it; code asking "does this venture own an
  # account?" wants this. Conflating the two is how a family venture would end up
  # taking payments into an unrelated parent org's account.
  has_one :stripe_connected_account, dependent: :destroy

  # Fuime: teens' requests to move money to the family's bank, and the guardian
  # decisions on them. Not `dependent: :destroy` — these are the record of who
  # authorised moving money, so they outlive the venture on purpose.
  has_many :payout_requests, dependent: :restrict_with_error

  # Fuime: the things this venture sells. See Fuime::Offer — an offer is what
  # turns the storefront from a tip jar into a store.
  #
  # `restrict_with_error` rather than `destroy`: an offer that was bought is
  # referenced by a ledger memo and a buyer's receipt, so cascading a delete
  # through it would leave payments nobody can explain. Offers archive; they do
  # not disappear.
  has_many :fuime_offers, class_name: "Fuime::Offer", dependent: :restrict_with_error

  # Fuime: where this venture's money goes under merchant-of-record. See
  # Fuime::PayoutMethod — a destination, not a merchant account.
  has_many :fuime_payout_methods, class_name: "Fuime::PayoutMethod", dependent: :restrict_with_error

  # Fuime: the cohort this venture was admitted under, if any. Denormalised from
  # the application at activation so the roster board can group and count
  # ventures directly — see CreateFuimeCohorts.
  belongs_to :fuime_cohort, class_name: "Fuime::Cohort", optional: true

  # Fuime: keys this venture has issued to its own software. See Fuime::ApiKey.
  #
  # `restrict_with_error` for the same reason as offers: a key is named by every
  # pay link it created, and those links are referenced by ledger memos and
  # buyers' receipts. Keys are revoked, not deleted.
  has_many :fuime_api_keys, class_name: "Fuime::ApiKey", dependent: :restrict_with_error

  # Fuime: top-ups this school made into its own Stripe balance. Restricted rather
  # than dependent-destroy for the same reason as payout_requests — these are the
  # record of real money movements a business office reconciles against, and they
  # outlive the Fuime org on purpose.
  has_many :school_fundings, dependent: :restrict_with_error

  # Fuime: money a school put into this venture ("$100 per A"). Restricted for the
  # same reason as payout_requests, plus one of its own: these rows are what a school
  # reconciles its 1099-MISC reporting against, and that obligation outlives the
  # student's venture.
  has_many :school_awards, dependent: :restrict_with_error

  # Awards this event handed OUT as the school. The inverse of the above, and a
  # separate association because the two mean opposite things on the same table.
  has_many :school_awards_granted, class_name: "SchoolAward",
                                   foreign_key: :school_event_id,
                                   dependent: :restrict_with_error

  # Fuime: people who can hold a business card on this venture's own Stripe account
  # (the guardian as Accountholder, the teen as Authorized User). Cards hang off the
  # cardholder, matching Stripe's own shape.
  has_many :venture_cardholders, dependent: :destroy
  has_many :venture_cards, through: :venture_cardholders

  has_one :application

  has_many :grants

  has_one_attached :donation_header_image
  validates :donation_header_image, content_type: [:png, :jpeg]
  validates :donation_header_image, size: { less_than_or_equal_to: 10.megabytes }, if: -> { attachment_changes["donation_header_image"].present? }

  has_one_attached :background_image
  validates :background_image, content_type: [:png, :jpeg, :gif]
  validates :background_image, size: { less_than_or_equal_to: 10.megabytes }, if: -> { attachment_changes["background_image"].present? }

  has_one_attached :logo
  validates :logo, content_type: [:png, :jpeg]
  validates :logo, size: { less_than_or_equal_to: 10.megabytes }, if: -> { attachment_changes["logo"].present? }

  has_one_attached :stripe_card_logo
  validates :stripe_card_logo, content_type: [:png, :jpeg]
  validates :stripe_card_logo, size: { less_than_or_equal_to: 10.megabytes }, if: -> { attachment_changes["stripe_card_logo"].present? }

  include HasMetrics

  include HasTasks

  validate :point_of_contact_is_admin

  include ::UserService::CanOpenDemoMode
  attr_accessor :demo_mode_limit_email

  validate :demo_mode_limit, if: proc{ |e| e.demo_mode_limit_email }
  validate :contract_signed, unless: -> { demo_mode? || financially_frozen? }

  validates :name, presence: true
  before_validation { self.name = name.gsub(/\s/, " ").strip unless name.nil? }

  validates :slug, presence: true, format: { without: /\s/ }
  validates :slug, format: { without: /\A\d+\z/ }
  validates_uniqueness_of_without_deleted :slug

  after_save :update_slug_history

  validates :website, format: URI::DEFAULT_PARSER.make_regexp(%w[http https]), if: -> { website.present? }

  validates :postal_code, zipcode: { country_code_attribute: :country, message: "is not valid" }, allow_blank: true

  validates :discord_guild_id, :discord_channel_id, uniqueness: { message: "is already linked to another organization. Please contact support@fuime.com if this is unexpected." }, allow_nil: true

  before_create { self.increase_account_id ||= "account_phqksuhybmwhepzeyjcb" }

  after_create :apply_plan_default_values

  before_update if: -> { demo_mode_changed?(to: false) } do
    self.activated_at = Time.now
  end

  before_validation do
    build_plan(type: fallback_plan_class) if plan.nil?
  end

  after_update if: -> { can_front_balance_changed? } do
    refresh_ledgers!
  end

  # Explanation: https://github.com/norman/friendly_id/blob/0500b488c5f0066951c92726ee8c3dcef9f98813/lib/friendly_id/reserved.rb#L13-L28
  after_validation :move_friendly_id_error_to_slug

  after_update :generate_stripe_card_designs, if: -> { attachment_changes["stripe_card_logo"].present? && stripe_card_logo.attached? && !Rails.env.test? }

  after_update_commit if: :is_public_previously_changed? do
    version = self.versions.where_object_changes(is_public:).last
    whodunnit = version&.whodunnit.present? ? User.find(version.whodunnit) : User.system_user

    if is_public
      EventMailer.with(event: self, whodunnit:).transparency_mode_enabled.deliver_later
    else
      EventMailer.with(event: self, whodunnit:).transparency_mode_disabled.deliver_later
    end
  end

  # We can't do this through a normal dependent: :destroy since ActiveRecord does not support deleting records through indirect has_many associations
  # https://github.com/rails/rails/commit/05bcb8cecc8573f28ad080839233b4bb9ace07be
  after_destroy_commit do
    organizer_positions.with_deleted.each do |position|
      position.organizer_position_deletion_requests.destroy_all
    end
  end

  comma do
    id
    created_at
    name
    revenue_fee
    country
    # Built from this deployment's own host. Upstream hardcoded
    # hcb.hackclub.com, so a Fuime CSV export handed the user links into Hack
    # Club's app, where their organization does not exist.
    slug "URL" do |slug| Rails.application.routes.url_helpers.root_url.chomp("/") + "/#{slug}" end
    is_public "Transparent"
    users "Active teenagers" do |users| users.active_teenager.distinct.count end
  end

  CUSTOM_SORT = Arel.sql(
    "CASE WHEN id = 183 THEN '1'"\
    "WHEN id = 999 THEN '2'     "\
    "WHEN id = 689 THEN '3'     "\
    "WHEN id = 636 THEN '4'     "\
    "WHEN id = 506 THEN '5'     "\
    "WHEN id = 4318 THEN '6'    "\
    "ELSE 'z' || name END ASC   "
  )

  enum :stripe_card_shipping_type, {
    standard: 0,
    express: 1,
    priority: 2,
  }

  enum :risk_level, {
    zero: 0,
    slight: 1,
    moderate: 2,
    high: 3,
  }, suffix: :risk_level

  # Fuime: has a human approved this venture to sell under Fuime's umbrella?
  #
  # Distinct from :risk_level, which upstream uses to grade an organization for
  # monitoring. This decides permission rather than attention, and it is
  # revocable: under merchant-of-record Fuime is the legal seller, so an operator
  # who starts selling something they never applied with has to be stoppable
  # today, without pretending their approved application was wrong in March.
  #
  # Read through Fuime::OperatorEligibility rather than directly — approval is
  # one of four conditions and the other three are not on this record.
  # See docs/fuime/MOR_MIGRATION_PLAN.md §8.
  enum :operator_vetting_status, {
    unvetted: 0,
    approved: 1,
    rejected: 2,
    suspended: 3,
  }, prefix: :operator_vetting

  belongs_to :operator_vetted_by, class_name: "User", optional: true

  include PublicActivity::Model
  tracked owner: proc{ |controller, record| controller&.current_user }, event_id: proc { |controller, record| record.id }, only: [:create]

  def admin_formatted_name
    "#{name} (#{id})"
  end

  def admin_dropdown_description
    "#{name} - #{id}#{" (DEMO)" if demo_mode?}"

    # Causing n+1 queries on admin pages with an event dropdown

    # badges = BADGES.map { |_, badge| send(badge[:qualifier]) ? badge[:emoji] : nil }.compact
    # desc += " [#{badges.join(' ')}]" if badges.any?

    # desc
  end

  def disbursement_dropdown_description
    "#{name} (#{ApplicationController.helpers.render_money balance_available})"
  end

  # displayed on /negative_events
  def self.negatives
    select { |event| event.balance_v2_cents < 0 }
  end

  def emburse_department_path
    "https://app.emburse.com/budgets/#{emburse_department_id}"
  end

  def emburse_budget_limit
    # We want to count positive Emburse TXs that are either pending OR complete,
    # because pending TXs will silently switch to complete and the admin will not
    # be notified to update the Emburse budget for this event later when that happens.
    # See also PR #317.
    self.emburse_transactions.undeclined.where(emburse_card_uuid: nil).sum(:amount)
  end

  def emburse_balance
    completed_t = self.emburse_transactions.completed.sum(:amount)
    # We're including only pending charges on emburse_cards so organizers have a conservative estimate of their balance
    pending_t = self.emburse_transactions.pending.where("amount < 0").sum(:amount)
    completed_t + pending_t
  end

  def refresh_ledgers!
    ledger.refresh_all!
    Ledger.where(card_grant: self.card_grants).find_each do |ledger|
      ledger.refresh_all!
    end
  end

  # Fuime: the Stripe account a payment to THIS venture actually lands in.
  #
  # For a family venture that is its own account and nothing else — the guardian
  # owns it, and no parent org can lend one.
  #
  # For a venture inside a school programme it is the school's account, resolved
  # up the tree. `Event::Plan::School` already states this outright ("the school
  # owns the account and the money"), but nothing implemented it: every call site
  # read `stripe_connected_account`, which is per-event with a UNIQUE index and no
  # fallback, so a student sub org under a fully onboarded school could take
  # exactly $0. The storefront rendered a working payment form and the checkout
  # endpoint then refused it.
  #
  # ── Why inheritance is gated on institutional sponsorship ────────────────
  #
  # Upstream HCB has sub-organizations too, and they are ordinary orgs that happen
  # to sit under a parent. If this walked the tree unconditionally, an HCB-shaped
  # parent/child pair would silently start routing the child's money into the
  # parent's Stripe account. Gating on #institutionally_sponsored? means the only
  # trees that share an account are the ones whose plan says the institution owns
  # the money, and it is the same inheritance direction as that predicate and
  # CardGrant::InheritablePolicy.
  def payment_account
    return @payment_account if defined?(@payment_account)

    @payment_account =
      stripe_connected_account ||
      (institutionally_sponsored? ? nearest_ancestor_payment_account : nil)
  end

  # Is the account this venture is paid into someone else's — i.e. shared with
  # sibling ventures under the same school?
  #
  # Load-bearing for money OUT, not just for bookkeeping. On a shared account
  # Stripe's balance is the whole school's, so anything that reads a balance to
  # decide what a single student may withdraw has to cap against that student's
  # own ledger instead. Fuime::PayoutService is where that happens.
  def shares_payment_account?
    payment_account.present? && stripe_connected_account.blank?
  end

  # Fuime: can this venture take a card payment right now?
  #
  # The single question the storefront, the checkout endpoint and the venture
  # dashboard all ask. Answered locally (no network call) from the mirrored
  # Stripe state, and false when no guardian has set payments up — which is the
  # correct answer for every venture until one has.
  #
  # ── Why the connected account is not required under merchant-of-record ──────
  #
  # This method used to demand `payment_account&.ready_for_payments?`
  # unconditionally, and under MoR that made every venture permanently unable to
  # sell. Not "harder to sell" — impossible. Under MoR the buyer is buying from
  # Fuime LLC, so the charge is created on FUIME's own Stripe account with no
  # `stripe_account:` at all (see Fuime::PaymentLinkService#create_mor_checkout_session).
  # There is no per-venture merchant account, and PR #68 correctly removed the
  # screen a guardian would have used to open one. So `payment_account` is nil
  # for every MoR venture, forever, and the guard above returned false forever.
  #
  # The consequence was silent and total: Fuime::Offer#only_a_selling_venture_may_publish
  # refused to publish any offer, Fuime::CheckoutsController refused every
  # checkout, the storefront and payment page rendered "not accepting payments",
  # and Fuime::DirectoryController filtered the venture out — while the service
  # layer underneath would happily have created the session. Verified against
  # Stripe test mode: a venture with zero selling blockers got a real Checkout
  # Session from the service and `false` from this method.
  #
  # What still gates an MoR sale is `selling_blockers` — vetting, the services-only
  # scope, the operator age floor and the guardian requirement. Those are the
  # controls that bound what Fuime is liable for as seller of record, and they are
  # unchanged. This only stops asking a venture for a merchant account that the
  # model it is running under does not issue.
  # Fuime: has this venture's operator been told, and said so?
  #
  # Only meaningful under merchant-of-record — under Connect the guardian owns the
  # account, signed Stripe's own terms, and carries the chargeback, so there is no
  # Fuime-as-seller relationship to acknowledge.
  #
  # Compares the recorded version, so a substantive change to the terms re-asks
  # rather than silently relying on somebody's agreement to a different document.
  def sale_terms_acknowledged?
    return true unless Fuime::Features.merchant_of_record?

    sale_terms_acknowledged_at.present? && sale_terms_version == SALE_TERMS_VERSION
  end

  def accepts_payments?
    unless Fuime::Features.merchant_of_record? || payment_account&.ready_for_payments?
      return false
    end

    selling_blockers.empty?
  end

  # Fuime: why this venture may not sell right now, if it may not.
  #
  # Always includes vetting — a human approving each operator is the compensating
  # control for letting minors sell at all, and it applies whether the guardian is
  # the merchant (Connect) or Fuime is (merchant-of-record). The launch-scope
  # checks on top of it bind only under MoR. Fuime::OperatorEligibility#blockers
  # explains the split; this method deliberately does not repeat it, so there is
  # one place that decides.
  #
  # ── Handle these carefully ──────────────────────────────────────────────────
  #
  # The strings name people and state their ages ("Jane Doe is 15"). They are for
  # the operator, their guardian and Fuime staff. They must never reach the
  # public storefront, which is why #accepts_payments? reduces them to a boolean
  # rather than the storefront rendering the list: an unauthenticated stranger
  # asking to pay a business is not entitled to the birthday of a child who runs
  # it.
  #
  # Not memoised. Eligibility depends on who holds a position, which changes
  # without this record being saved, and a stale "yes" here is a payment Fuime
  # was not entitled to take.
  def selling_blockers
    Fuime::OperatorEligibility.new(event: self).blockers
  end

  # Fuime: why money cannot leave this venture yet, under merchant-of-record.
  #
  # ── Why this lives here rather than in the payout run ───────────────────────
  #
  # Two places need the same answer and they are not the same code path.
  # Fuime::PayableAssessment asks it when generating a batch, where no controller
  # or policy is consulted at all; the payouts PAGE asks it to tell an operator
  # what to do next. Before this method the page did not ask at all — it gated on
  # `payment_account`, the Connect account, which under MoR is nil forever. So a
  # venture that simply had no payout destination yet was told "a parent or
  # guardian needs to set up this venture's payment account", pointing at a Stripe
  # onboarding screen that MoR has retired. Correct sentence, wrong model.
  #
  # Empty under Connect, where the money is already in the family's own Stripe
  # account and none of this is Fuime's business.
  #
  # ── Order is deliberate ─────────────────────────────────────────────────────
  #
  # Destination first, because it is the one the operator can fix themselves. A
  # screen that leads with "you need a parent" — which they may not be able to
  # produce today — reads as a wall, and the thing they could have done in two
  # minutes is underneath it.
  #
  # These name people ("Jane Doe"). Fine on the payouts page, which is the
  # operator's and their guardian's own, and on a batch a Fuime admin reads.
  # They must never reach a public page, exactly like #selling_blockers.
  def payout_setup_blockers
    return [] unless Fuime::Features.merchant_of_record?

    blockers = []
    blockers << "No payout destination set up yet." if fuime_payout_methods.usable.none?

    # Per operator rather than via #has_overseeing_guardian?, which is satisfied
    # by ONE guardian even when a second co-founder has none. Money is about to
    # be sent on behalf of every one of them.
    unless institutionally_sponsored?
      unguarded = users.select { |u| u.minor_or_unknown_age? && !u.has_active_guardian? }

      if unguarded.any?
        blockers << "Needs a parent or guardian on the account before money can be sent " \
                    "(#{unguarded.map(&:name).join(', ')})."
      end
    end

    blockers
  end

  # Fuime: record a human's decision about whether this operator may sell.
  #
  # The status alone is not the record. Under merchant-of-record Fuime is the
  # legal seller and manual review is the control that makes that survivable, so
  # what has to be reconstructable later is *who decided, when, and why* — not
  # merely the current value. paper_trail records that the column changed; it
  # cannot tell a reviewer's judgement apart from a background job's.
  #
  # Notes are kept on re-decision rather than overwritten, because the reason a
  # venture was approved in September is the context for suspending it in
  # November, and it is exactly what the automated risk model this replaces will
  # need as training data.
  def record_vetting_decision!(status:, by:, notes: nil)
    stamped = [
      notes.presence && "#{Time.current.to_fs(:long)} — #{by&.name}: #{notes.strip}",
      operator_vetting_notes.presence
    ].compact.join("\n\n")

    update!(
      operator_vetting_status: status,
      operator_vetted_at: Time.current,
      operator_vetted_by: by,
      operator_vetting_notes: stamped.presence
    )
  end

  # Fuime: the adults legally responsible for this venture.
  #
  # There was no query for this, and the absence produced a real bug: the public
  # storefront derived its "Guardian on account" badge from
  # `point_of_contact.has_active_guardian?`, but `point_of_contact` is set to the
  # *activating admin* (see Event::Application#activate_event!), so the badge was
  # reporting whether a Fuime staff member has a parent.
  #
  # Defined as: active guardians of the minors who hold a position on this
  # venture. Returns a relation because a venture can legitimately have more than
  # one — two teen co-founders with different parents, or one teen with two
  # guardians — and picking `.first` is how you end up asserting something about
  # the wrong family.
  def overseeing_guardians
    User.where(
      id: Guardianship
            .active
            .joins("INNER JOIN organizer_positions ON organizer_positions.user_id = guardianships.minor_id")
            .where(organizer_positions: { event_id: id, deleted_at: nil })
            .select(:guardian_id)
    )
  end

  # Fuime: does a responsible adult exist for this venture at all?
  #
  # This, not `point_of_contact.has_active_guardian?`, is what the storefront
  # badge means to ask. An adult-run venture correctly answers false — there is
  # no guardian because none is required.
  def has_overseeing_guardian?
    overseeing_guardians.exists?
  end

  # Fuime: fronting is credit extension, so it follows the sponsor-banking flag.
  #
  # Upstream, "fronting" means the platform lets an org spend against money that
  # has arrived but has not settled — HCB advances the funds from its own
  # reserves and collects when settlement lands. That is a lending decision, and
  # HCB can make it because it is a 501(c)(3) that legally owns the money in the
  # first place.
  #
  # Fuime has no reserves. Under the merchant-of-record model the figure being
  # fronted against is a PAYABLE — what Fuime owes an operator for sales Stripe
  # has not released yet — so fronting would mean advancing cash to a minor's
  # business against Fuime's own unpaid invoice, recoverable only by netting
  # against future sales that may never happen. Stripe settlement is T+2 with
  # refund and chargeback risk for 120 days after that.
  #
  # The column stays (CLAUDE.md Rule 2) and the migration only changes its
  # default, because existing rows carry `true` from upstream's default and a
  # data migration flipping them would be indistinguishable from a bug in the
  # audit log. This override is what makes the column inert: the answer is false
  # while custody is off, whatever the row says.
  #
  # `Fuime::VentureLedger#post!` already hardcodes `fronted: false` when writing
  # lines — this closes the other half, where a `true` row would make the READ
  # side count fronted money that was never posted as fronted.
  #
  # See docs/fuime/MOR_MIGRATION_PLAN.md §1 C2.
  def can_front_balance?
    return false unless ::Fuime::Features.sponsor_banking?

    super
  end

  def total_raised
    balance = settled_incoming_balance_cents
    if can_front_balance?
      balance += fronted_incoming_balance_v2_cents
    end
    balance
  end

  def total_spent_cents
    (settled_outgoing_balance_cents + pending_outgoing_balance_v2_cents) * -1
  end

  def balance_v2_cents(start_date: nil, end_date: nil)
    sum = settled_balance_cents(start_date:, end_date:)
    sum += pending_outgoing_balance_v2_cents(start_date:, end_date:)
    sum += fronted_incoming_balance_v2_cents(start_date:, end_date:) if can_front_balance?
    sum
  end

  # This calculates v2 cents of settled (Canonical Transactions)
  # @return [Integer] Balance in cents (v2 transaction engine)
  def settled_balance_cents(start_date: nil, end_date: nil)
    settled_incoming_balance_cents(start_date:, end_date:) + settled_outgoing_balance_cents(start_date:, end_date:)
  end

  # v2 cents (v2 transaction engine)
  def settled_incoming_balance_cents(start_date: nil, end_date: nil)
    ct = canonical_transactions.where("amount_cents > 0")

    ct = ct.where("date >= ?", start_date) if start_date
    ct = ct.where("date <= ?", end_date) if end_date

    ct.sum(:amount_cents)
  end

  # v2 cents (v2 transaction engine)
  def settled_outgoing_balance_cents(start_date: nil, end_date: nil)
    ct = canonical_transactions.where("amount_cents < 0")

    ct = ct.where("date >= ?", start_date) if start_date
    ct = ct.where("date <= ?", end_date) if end_date

    ct.sum(:amount_cents)
  end

  def fronted_incoming_balance_v2_cents(start_date: nil, end_date: nil)
    pts = canonical_pending_transactions.incoming.fronted.not_declined

    pts = pts.where("date >= ?", start_date) if start_date
    pts = pts.where("date <= ?", end_date) if end_date

    sum_fronted_amount(pts)
  end

  def pending_balance_v2_cents(start_date: nil, end_date: nil)
    pending_incoming_balance_v2_cents(start_date:, end_date:) + pending_outgoing_balance_v2_cents(start_date:, end_date:)
  end

  def pending_incoming_balance_v2_cents(start_date: nil, end_date: nil)
    cpt = canonical_pending_transactions.incoming.unsettled.not_fronted

    cpt = cpt.where("date >= ?", start_date) if start_date
    cpt = cpt.where("date <= ?", end_date) if end_date

    cpt.sum(:amount_cents)
  end

  def pending_outgoing_balance_v2_cents(start_date: nil, end_date: nil)
    cpt = canonical_pending_transactions.outgoing.unsettled

    cpt = cpt.where("date >= ?", start_date) if start_date
    cpt = cpt.where("date <= ?", end_date) if end_date

    cpt.sum(:amount_cents)
  end

  def balance_available_v2_cents
    @balance_available_v2_cents ||= begin
      fee_balance = can_front_balance? ? fronted_fee_balance_v2_cents : fee_balance_v2_cents
      if fee_balance.positive?
        balance_v2_cents - fee_balance
      else # `fee_balance` is negative, indicating a fee credit
        balance_v2_cents
      end
    end
  end

  alias balance balance_v2_cents

  # used for events with a pending ledger, this is the amount of money available
  # that isn't being transferred out by upcoming/floating transactions such as
  # pending fees or checks awaiting deposit -tmb@hackclub
  alias balance_available balance_available_v2_cents
  alias available_balance balance_available


  # `fee_balance_v2_cents`, but it includes fees on fronted (unsettled) transactions to prevent overspending before fees are charged
  def fronted_fee_balance_v2_cents
    feed_fronted_pts = canonical_pending_transactions
                       .incoming
                       .fronted
                       .not_waived
                       .not_declined

    feed_fronted_balance = sum_fronted_amount(feed_fronted_pts)

    (fees.sum(:amount_cents_as_decimal) - total_fee_payments_v2_cents + (feed_fronted_balance * BigDecimal(revenue_fee))).ceil
  end

  # This intentionally does not include fees on fronted transactions to make sure they aren't actually charged
  def fee_balance_v2_cents
    @fee_balance_v2_cents ||= total_fees_v2_cents - total_fee_payments_v2_cents
  end

  alias fee_balance fee_balance_v2_cents

  def used_emburse?
    emburse_cards.any?
  end

  def hidden?
    hidden_at.present?
  end

  def filter_data
    {
      exists: true,
      transparent: is_public?,
      omitted: omit_stats?,
      hidden: hidden?
    }
  end

  def ready_for_fee?
    last_fee_processed_at.nil? || last_fee_processed_at <= MIN_WAITING_TIME_BETWEEN_FEES.ago
  end

  def total_fees_v2_cents
    @total_fees_v2_cents ||= fees.sum(:amount_cents_as_decimal).ceil
  end

  def increase_account_number_id
    (increase_account_number || create_increase_account_number).increase_account_number_id
  end

  def organized_by_hack_clubbers?
    event_tags.where(name: EventTag::Tags::ORGANIZED_BY_HACK_CLUBBERS).exists?
  end

  def organized_by_teenagers?
    event_tags.where(name: [EventTag::Tags::ORGANIZED_BY_TEENAGERS, EventTag::Tags::ORGANIZED_BY_HACK_CLUBBERS]).exists?
  end

  def robotics_team?
    event_tags.where(name: EventTag::Tags::ROBOTICS_TEAM).exists?
  end

  def hackathon?
    event_tags.where(name: EventTag::Tags::HACKATHON).exists?
  end

  # Fuime: the tree-resolved answers each cost a recursive CTE, so they are
  # memoized — and `reload` does NOT clear plain instance variables, only attributes
  # and association caches. Without clearing them here, changing an event's plan and
  # then re-asking on the same in-memory object returns the answer from before the
  # change, which is exactly what the admin plan-change flow does.
  #
  # Found by spec/models/event_institutional_sponsorship_spec.rb the moment
  # #revenue_fee started resolving through #billing_plan: that made
  # #institutionally_sponsored? run during event setup rather than only from a
  # policy, so the memo was already warm by the time the School plan was installed.
  #
  # `remove_instance_variable` rather than assigning nil, because all three memos
  # guard on `defined?` — nil would read as a cached "no" forever.
  MEMOIZED_TREE_ANSWERS = %i[
    @institutionally_sponsored
    @billing_plan
    @payment_account
  ].freeze

  def reload(**args)
    @total_fee_payments_v2_cents = nil

    MEMOIZED_TREE_ANSWERS.each do |ivar|
      remove_instance_variable(ivar) if instance_variable_defined?(ivar)
    end

    super(**args)
  end

  def total_fee_payments_v2_cents
    @total_fee_payments_v2_cents ||=
      begin
        paid = canonical_transactions.includes(:fee).where(fee: { reason: "HACK CLUB FEE" }).sum(:amount_cents)
        in_transit = canonical_pending_transactions.bank_fee.unsettled.sum(:amount_cents)

        (paid + in_transit) * -1
      end
  end

  def color
    options = [
      "#ec3750",
      "#ff8c37",
      "#f1c40f",
      "#33d6a6",
      "#5bc0de",
      "#338eda",
      "#a633d6",
    ]

    options[hashid.codepoints.first % options.size]
  end

  def service_level
    return 1 if robotics_team?
    return 1 if organized_by_hack_clubbers?
    return 1 if organized_by_teenagers?
    return 1 if plan.is_a?(Event::Plan::HackClubAffiliate)
    return 1 if canonical_transactions.revenue.where("date >= ?", 1.year.ago).sum(:amount_cents) >= 50_000_00
    return 1 if balance_available_v2_cents > 50_000_00

    2
  end

  def engaged?
    canonical_transactions.where("date >= ?", 6.months.ago).any?
  end

  def dormant?
    !engaged?
  end

  # Fuime: the plan that sets this venture's COMMERCIAL terms, which is not always
  # its own.
  #
  # Inside a school programme the institution's plan governs. `Event::Plan::School`
  # is FeeWaived for a stated reason — a school already pays per student per year,
  # so taking a cut of each student's revenue charges one customer twice for one
  # product — but the fee was read from `plan&.revenue_fee` with no inheritance,
  # while `EventService::Create` defaults every new sub org to `Standard`. So a
  # student venture created under a 0% school was charged 4%: precisely the
  # double-charge the School plan exists to prevent.
  #
  # Fixed here rather than at sub-org creation on purpose. Creation-time defaulting
  # would leave every already-seeded student venture wrong and would silently
  # depend on nobody ever editing a plan afterwards; resolving at read time means
  # the institution's terms cannot be contradicted from below, which is the same
  # rule #institutionally_sponsored? and CardGrant::InheritablePolicy already
  # enforce for responsibility and for spending.
  #
  # Only institutional trees inherit. An ordinary HCB-shaped sub-organization keeps
  # reading its own plan, so no upstream billing behaviour changes.
  def billing_plan
    return @billing_plan if defined?(@billing_plan)

    # #ancestors needs an id to walk from, and `revenue_fee` is reachable during
    # validation on a new record where #institutionally_sponsored? would raise.
    return @billing_plan = plan unless persisted?

    @billing_plan =
      if institutionally_sponsored?
        ancestors.includes(:plan).find { |event| event.plan&.institutionally_sponsored? }&.plan || plan
      elsif family_pro?
        # The guardian's family subscription covers every venture they sign
        # for. An unsaved Pro instance is deliberate: Pro-ness is a property of
        # the FAMILY resolved at read time (like institutional sponsorship
        # above), not a plan row to swap on webhooks and sweep on lapse.
        Event::Plan::Pro.new(event: self)
      else
        plan
      end
  end

  # Does a guardian overseeing this venture hold an active family subscription?
  def family_pro?
    return @family_pro if defined?(@family_pro)

    @family_pro = overseeing_guardians.any?(&:fuime_pro?)
  end

  def revenue_fee
    configured = billing_plan&.revenue_fee
    return configured if configured.present?

    Rails.error.unexpected("#{id} is missing a plan!")

    Event::Plan::FALLBACK_REVENUE_FEE
  end

  # Fuime: what Fuime charges on a sale of this size — the ONE definition.
  #
  # `revenue_fee` is a percentage; this is the money. They are separate because a
  # percentage alone cannot express the floor, and the floor is what keeps a small
  # sale from costing Fuime more than it earns.
  #
  # ── Why there is a floor at all ─────────────────────────────────────────────
  #
  # Under merchant-of-record Fuime is the seller, so Stripe charges FUIME its
  # 2.9% + 30¢ rather than the family. The 30¢ is fixed, so Fuime's margin is
  # `(rate − 2.9%) × amount − 30¢` and every rate has a sale size below which it
  # is negative — $14.29 at 5%, and $300.00 at Pro's 3% (see
  # docs/fuime/MOR_MIGRATION_PLAN.md §8.6). Teen businesses sell stickers and
  # small commissions, so without a floor the most active operators would be the
  # most expensive to serve.
  #
  # A minimum is how Gumroad, Etsy and Paddle solve the same problem, and it
  # recovers exactly what causes it: Stripe's fixed component.
  #
  # ── Why it applies only under merchant-of-record ────────────────────────────
  #
  # Under Connect, Stripe's fee is deducted from the FAMILY's connected account
  # and costs Fuime nothing — so a floor there would not be recovering a cost,
  # it would be a surcharge on the smallest sellers on top of a Stripe fee they
  # are already paying themselves. On a $5 sale that is 50¢ from Fuime plus ~45¢
  # from Stripe: 19% of the sale. The floor exists to recover a real cost, so it
  # applies exactly where the cost is real.
  def fuime_fee_cents_on(amount_cents)
    amount_cents = amount_cents.to_i
    return 0 if amount_cents <= 0

    percentage_fee = (amount_cents * revenue_fee).round

    # A fee-waived or Founders venture pays nothing, and the floor must not
    # quietly reintroduce a charge for them. Zero means zero.
    return 0 if revenue_fee.to_f <= 0

    return percentage_fee unless Fuime::Features.merchant_of_record?

    # Never more than the sale itself: on a $0.30 sale the floor would otherwise
    # exceed the payment and hand the operator a negative payable.
    [[percentage_fee, Event::Plan::MINIMUM_FEE_CENTS].max, amount_cents].min
  end

  def generate_stripe_card_designs
    raise ArgumentError.new("This method requires a stripe_card_logo to be attached.") unless stripe_card_logo.attached?

    ActiveRecord::Base.transaction do
      stripe_card_personalization_designs.update(stale: true)
      stripe_card_logo.blob.open do |tempfile|
        converted = ImageProcessing::MiniMagick.source(tempfile.path).convert!("png")
        ::StripeCardService::PersonalizationDesign::Create.new(file: StringIO.new(converted.read), color: :black, event: self).run
        converted.rewind
        ::StripeCardService::PersonalizationDesign::Create.new(file: StringIO.new(converted.read), color: :white, event: self).run
      end
    end
  rescue Stripe::InvalidRequestError => e
    stripe_card_logo.delete
    raise Errors::InvalidStripeCardLogoError, e.message
  end

  def default_stripe_card_personalization_design
    stripe_card_personalization_designs.where("stripe_name like ?", "#{name} Black Card%").order(created_at: :desc).first
  end

  def config
    super || create_config
  end

  def donation_page_available?
    donation_page_enabled && plan.donations_enabled? && !financially_frozen?
  end

  def public_reimbursement_page_available?
    public_reimbursement_page_enabled && plan.reimbursements_enabled? && !financially_frozen?
  end

  def short_name(length: MAX_SHORT_NAME_LENGTH)
    return name if length >= name.length

    self[:short_name] || name[0...length]
  end

  monetize :minimum_wire_amount_cents

  def minimum_wire_amount_cents
    return 100 if canonical_transactions.where("amount_cents > 0").where("date >= ?", 1.year.ago).sum(:amount_cents) > 50_000_00
    return 100 if plan.exempt_from_wire_minimum?
    return 100 if Flipper.enabled?(:exempt_from_wire_minimum, self)

    return 500_00
  end

  def omit_stats?
    plan.omit_stats
  end

  validate do
    if id && id == parent_id
      errors.add(:parent, "can't be self-referential.")
    end
  end

  def eligible_for_transparency?
    !plan.is_a?(Event::Plan::SalaryAccount)
  end

  def forced_transparency?
    # `plan` is built by a later `before_validation` callback, so it can still
    # be nil the first time this runs on a new record.
    return false unless plan&.forces_transparency?

    parent&.is_public? || false
  end

  def eligible_for_indexing?
    eligible_for_transparency? && !risk_level.in?(%w[moderate high])
  end

  def active_teenagers
    users.active_teenager.count
  end

  def subevents_enabled?
    config.subevent_plan.present?
  end

  def organizer_contact_emails(only_managers: false, &block)
    included_users = only_managers ? managers : users
    included_users = block.call(included_users) if block

    emails = included_users.map(&:email_address_with_name)
    emails << config.contact_email if config.contact_email.present?

    emails
  end

  def merchants
    settled_merchants = canonical_transactions.map do |ct|
      rst = ct.raw_stripe_transaction
      stripe_transaction_merchant(rst) if rst.present?
    end.select(&:present?)

    pending_merchants = canonical_pending_transactions.map do |cpt|
      rpst = cpt.raw_pending_stripe_transaction
      stripe_transaction_merchant(rpst) if rpst.present?
    end.select(&:present?)

    settled_merchants.concat(pending_merchants)
  end

  def point_of_contact_history
    @point_of_contact_history ||= versions
                                  .filter_map { |v| v.changeset["point_of_contact_id"].presence }
                                  .filter_map { |(old_id, _new_id)| User.find_by(id: old_id) }
  end

  def has_discord_guild?
    discord_guild_id.present?
  end

  def valid_scoped_tags
    scoped_tags.where(parent_event_id: parent_id)
  end

  def to_combobox_display
    name
  end

  # FUIME-DISABLED: this returned a Hack Club onboarder's scheduling link from Airtable.
  # Fuime has no onboarding-call scheduling, so there is no link to offer.
  def onboarding_scheduling_link
    nil
  end

  def contracts_pending_on_hcb
    contracts.sent.select { |c| c.parties.not_hcb.all?(&:signed?) }
  end

  private

  # Nearest ancestor that actually owns a Stripe account, or nil.
  #
  # Nearest rather than root, so a school network can put the account on one
  # campus and have only that campus's students paid into it. `ancestors` is
  # ordered self-first then nearest-first, so `drop(1)` is the strict ancestor
  # chain in the order to try.
  def nearest_ancestor_payment_account
    ancestors.drop(1).each do |ancestor|
      account = ancestor.stripe_connected_account
      return account if account.present?
    end

    nil
  end

  def point_of_contact_is_admin
    return unless point_of_contact_changed?
    return unless point_of_contact
    return if point_of_contact&.admin_override_pretend?

    errors.add(:point_of_contact, "must be an admin")
  end

  def update_slug_history
    if slug_previously_changed?
      slugs.create(slug:)
    end
  end

  def demo_mode_limit
    return if can_open_demo_mode? demo_mode_limit_email

    errors.add(:demo_mode, "limit reached for user")
  end

  def contract_signed
    return if contracts.signed.any? || contracts.none? || !plan.contract_required? || Rails.env.development?

    errors.add(:base, "Missing a contract signee, non-demo mode organizations must have a contract signee.")
  end

  def sum_fronted_amount(pts)
    pt_sum_by_hcb_code = pts.group(:hcb_code).sum(:amount_cents)
    hcb_codes = pt_sum_by_hcb_code.keys

    ct_sum_by_hcb_code = canonical_transactions.where(hcb_code: hcb_codes)
                                               .group(:hcb_code)
                                               .sum(:amount_cents)

    pt_sum_by_hcb_code.reduce 0 do |sum, (hcb_code, pt_sum)|
      sum + [pt_sum - (ct_sum_by_hcb_code[hcb_code] || 0), 0].max
    end
  end

  def move_friendly_id_error_to_slug
    errors.add :slug, *errors.delete(:friendly_id) if errors[:friendly_id].present?
  end

  def enforce_transparency_eligibility
    unless eligible_for_transparency?
      self.is_public = false
      self.is_indexable = false
    end

    if forced_transparency?
      self.is_public = true
    end

    unless eligible_for_indexing?
      self.is_indexable = false
    end
  end

  def apply_plan_default_values
    return if plan&.default_values.blank?

    update!(plan.default_values)
  end

  def stripe_transaction_merchant(transaction)
    merchant_data = transaction.stripe_transaction["merchant_data"]
    yp_merchant = YellowPages::Merchant.lookup(network_id: merchant_data["network_id"])
    { id: merchant_data["network_id"], name: yp_merchant.name || merchant_data["name"].titleize }
  end

  def parent_id_is_acyclical
    return unless parent_id.present? && parent_id_changed?

    current_event = self
    visited_event_ids = Set.new

    visited_event_ids << id if id.present?

    outcome = 1.upto(MAX_PARENT_DEPTH) do
      if current_event.parent
        if visited_event_ids.add?(current_event.parent_id)
          current_event = current_event.parent
          next
        else
          errors.add(:parent, "is cyclical")
          break :halted
        end
      else
        break :halted
      end
    end

    if outcome != :halted
      errors.add(:parent, "max depth exceeded")
    end
  end

  def fallback_plan_class
    if parent
      if parent.config&.subevent_plan.present?
        return parent.config.subevent_plan.constantize
      end

      if parent.plan
        return parent.plan.class
      end
    end

    # Fuime: new root ventures start on the Free plan (7%, no monthly) — the
    # zero-friction end of the pricing ladder. Standard (4%) remains for
    # ventures that already have it. Sub-orgs still inherit their parent's
    # plan class above, which is what keeps a school's children on School.
    Event::Plan::Free
  end

end
