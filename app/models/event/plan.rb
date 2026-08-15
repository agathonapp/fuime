# frozen_string_literal: true

# == Schema Information
#
# Table name: event_plans
#
#  id          :bigint           not null, primary key
#  aasm_state  :string           not null
#  inactive_at :datetime
#  type        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  event_id    :bigint           not null
#
# Indexes
#
#  index_event_plans_on_event_id  (event_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
class Event
  class Plan < ApplicationRecord
    # Fuime's platform fee on money in. Upstream HCB used 0.07, the headline rate
    # of its fiscal sponsorship agreement.
    #
    # ── Why this went from 4% to 5% (2026-08-14) ────────────────────────────
    #
    # Not a price rise for its own sake. Under merchant-of-record, Fuime is the
    # seller, so **Stripe's processing fee comes out of Fuime's own balance** —
    # where under Connect it was deducted from the family's connected account and
    # never touched Fuime at all. The same headline number therefore means two
    # completely different things before and after the flip.
    #
    # At 2.9% + 30¢, Fuime's margin on a sale is `(rate − 2.9%) × amount − 30¢`,
    # so each rate has a break-even below which Fuime LOSES money on the sale:
    #
    #     4%  →  1.1% × amount = 30¢  →  break-even ≈ $27.27
    #     5%  →  2.1% × amount = 30¢  →  break-even ≈ $14.29
    #
    # Teen businesses sell small things. At 4% every sale under about $27 costs
    # Fuime money, which is most of them — so 4% is not a cheaper product, it is a
    # product that stops working. 5% is the brief's number and it roughly halves
    # the break-even; it still loses on sub-$15 sales, which is a real limit worth
    # knowing rather than discovering.
    #
    # This is the STANDARD/default rate. The other tiers are deliberately not
    # collapsed into it — see docs/fuime/MOR_MIGRATION_PLAN.md §8.3 D1 for the
    # open question about whether the ladder survives the brief's "5% flat, one
    # number teens understand".
    FALLBACK_REVENUE_FEE = 0.05

    # The minimum Fuime charges on a sale, in cents.
    #
    # Stripe's fee has a fixed 30¢ component that a percentage cannot cover on a
    # small sale, so without this the operators who sell most often — stickers,
    # small commissions, digital downloads — are the ones Fuime loses most money
    # on. 50¢ recovers the 30¢ with room for the percentage part.
    #
    # Applied by Event#fuime_fee_cents_on, and ONLY under merchant-of-record,
    # where Stripe's fee is Fuime's own cost. See that method for why.
    #
    # Env-tunable like the other two dials: it is a price.
    MINIMUM_FEE_CENTS = ENV.fetch("FUIME_MINIMUM_FEE_CENTS", "50").to_i

    has_paper_trail

    belongs_to :event

    include AASM
    aasm timestamps: true do
      state :active, initial: true
      state :inactive

      event :mark_inactive do
        transitions from: :active, to: :inactive
        after do |new_type|
          event.reload
          event.create_plan!(type: new_type)
          unless event.plan.writeable?
            event.update(financially_frozen: true)
            event.stripe_cards.active.each do |card|
              card.freeze!(frozen_by: User.system_user)
            end
          end
          if event.plan.hidden?
            event.update(hidden_at: Time.now)
          end
        end
      end
    end

    def standard?
      type == Event::Plan::Standard.name
    end

    def default_values
      {}
    end

    # The DocuSeal template a plan's signing flow serves.
    #
    # Upstream HCB hardcoded per-plan template IDs living in Hack Club's
    # DocuSeal account — 487784 for Standard, and five others. Those are Hack
    # Club's real fiscal sponsorship agreements: binding documents about
    # 501(c)(3) sponsorship, IP assignment to EIN 81-2908499, and nonprofit
    # asset transfer. None of it describes Fuime, and Fuime cannot edit them.
    #
    # Serving one to a Fuime user would ask a teen (or their guardian) to sign
    # another organization's legal agreement, so every plan now reads a single
    # Fuime-controlled template from the environment instead. Unset by default:
    # `contract_available?` is then false and callers must skip the signing
    # step rather than fall back to an upstream template.
    #
    # To enable: create the agreement in Fuime's own DocuSeal account, set
    # FUIME_DOCUSEAL_TEMPLATE_ID to its id, and set the DOCUSEAL credential.
    # See docs/fuime/DOCUSEAL_SETUP.md.
    def contract_docuseal_template_id
      ENV["FUIME_DOCUSEAL_TEMPLATE_ID"].presence
    end

    # Whether a signable agreement is actually configured. Guard the signing
    # step on this, never on the template id being merely non-nil.
    def contract_available?
      contract_docuseal_template_id.present?
    end

    # Fuime: the software subscription in cents/month, on top of revenue_fee.
    #
    # The two dials of the pricing model are deliberately separate: revenue_fee
    # is Fuime's cut of money a venture COLLECTS (taken as a Connect
    # application fee on each charge), and monthly_fee_cents is the
    # subscription for the software itself (billed to the responsible adult's
    # card via Stripe Billing — see Fuime::SubscriptionService). Stripe's own
    # processing (~2.9% + 30¢) is neither: on payments_only profiles the
    # venture pays it, itemised as its own ledger line.
    def monthly_fee_cents
      0
    end

    # Fuime: is the responsible adult an institution rather than a parent?
    #
    # Fuime's default assumption is that a minor operating a venture is backed by
    # a guardian who is the legal party — that is what LEGAL_RESEARCH L2 requires
    # and what the guardianships table records. A school is the exception: it
    # stands in loco parentis, its families have already signed enrolment
    # contracts, and there is no per-student guardian for Fuime to find.
    #
    # Three things key off this, and each of them is a wall for a school today:
    #
    #   * EventPolicy#setup_payments? authorises only a guardian or a Fuime admin,
    #     so a business-office manager cannot connect Stripe at all.
    #   * PaymentSetupsController#acting_guardian raises unless it finds exactly
    #     one overseeing guardian; for a school it finds zero.
    #   * EventPolicy#member? gates on permitted_to_operate_business?, so a
    #     14-year-old with no guardianship row cannot act on their own venture.
    #
    # Returning true here does NOT weaken the guardian requirement for anyone
    # else — it says the institution has already discharged it.
    def institutionally_sponsored?
      false
    end

    # Organizations on plans that force transparency can't opt out of it while
    # their parent organization is transparent.
    def forces_transparency?
      false
    end

    def was_backfilled?
      created_at < Date.new(2024, 8, 24)
    end

    def revenue_fee_label
      ActionController::Base.helpers.number_to_percentage(revenue_fee * 100, precision: 1)
    end

    def self.available_features
      # this must contain every HCB feature that we want enable / disable with plans.
      %w[cards invoices donations account_number check_deposits transfers promotions google_workspace documentation reimbursements card_grants unrestricted_disbursements front_disbursements]
    end

    self.available_features.each do |feature|
      define_method("#{feature}_enabled?") do
        feature.in?(features)
      end
    end

    def self.available_plans
      Event::Plan.descendants
    end

    def self.available_plans_by_popularity
      available_plans.sort_by { |p| plan_popularities[p].presence || 0 }.reverse!
    end

    # Whether an admin may newly assign this plan.
    #
    # Upstream HCB offered every subclass in every picker. For Fuime that means
    # offering Hack Club's grant programs (Argosy, the SC Google Grant, the
    # 2024 hackathon fee waiver), Hack Club's own internal org plans, and HCB's
    # fiscal-sponsorship fee ladder (7 / 5 / 3.5 / 2.9 / 10%) — none of which
    # Fuime administers or can honor.
    #
    # Those classes stay loadable rather than being deleted (CLAUDE.md Rule 2)
    # so existing `event_plans` rows never point at a missing constant and so
    # upstream ledger fixes still merge cleanly. They are simply no longer
    # offered. Override to false to retire a plan; subclasses inherit it.
    def self.selectable?
      true
    end

    # The plans Fuime actually offers.
    def self.selectable_plans
      available_plans.select(&:selectable?)
    end

    # Plans inherited from HCB that we keep for existing rows only.
    def self.legacy_plans
      available_plans.reject(&:selectable?)
    end

    def self.selectable_plans_by_popularity
      available_plans_by_popularity.select(&:selectable?)
    end

    # [label, class name] pairs for a plan <select>.
    #
    # `current` is the type an organization is already on. Passing it keeps a
    # retired plan in the options so that submitting the form for an unrelated
    # setting can't silently migrate the org onto a different plan.
    def self.select_options(current = nil)
      plans = selectable_plans
      current_plan = available_plans.find { |p| p.name == current.to_s }
      plans += [current_plan] if current_plan && !plans.include?(current_plan)
      plans.map { |p| [p.new.label, p.name] }
    end

    def self.plan_popularities
      Event::Plan.joins(:event).group(:type).select(:type, "count(*)").to_h { |p| [p.class, p.count] }
    end

    def self.that(method)
      self.available_plans.select { |plan| plan.new.try(method) }
    end

    validate do
      if Event::Plan.where(event_id:, aasm_state: :active).excluding(self).any?
        errors.add(:base, "An event can only have one active plan at a time.")
      end
    end

    validate do
      unless type.in?(Event::Plan.descendants.map(&:name))
        errors.add(:type, "is invalid")
      end
    end

  end

end
