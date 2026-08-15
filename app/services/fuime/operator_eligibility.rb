# frozen_string_literal: true

module Fuime
  # Fuime: may this venture sell under Fuime's umbrella today?
  #
  # ── Why this exists at all ──────────────────────────────────────────────────
  #
  # Under merchant-of-record, Fuime LLC is the legal seller of everything an
  # operator sells: Fuime's terms of sale, Fuime's name on the buyer's receipt,
  # Fuime carrying the refund, warranty and chargeback obligation. Fuime
  # therefore inherits its operators' liability, deliberately — that is the trade
  # the whole model makes, and the launch scope exists to keep the inherited
  # liability small enough to survive.
  #
  # docs/fuime/MOR_MIGRATION_PLAN.md §8.1 fixes that scope: services only,
  # operators 16–17, a human approving every operator. Before this class those
  # three constraints lived in a document. A constraint that only exists in a
  # document is not a constraint, and each of these has a specific failure it
  # prevents (below). So they live here, in one object, with one answer.
  #
  # ── Why one object rather than validations on Event ────────────────────────
  #
  # Two of these are not properties of the venture record. "Every minor operator
  # is 16 or older" is a property of the *people holding positions*, which
  # changes when a co-founder joins without the venture being saved — so an
  # ActiveModel validation would be checked at the wrong moment and pass forever
  # after. And eligibility is asked at request time ("can they take a payment
  # right now?"), not at write time.
  #
  # Modelled on Guardianship#activation_blockers: return the reasons, not a
  # boolean, because every caller either shows them to somebody or logs them, and
  # a bare false forces each caller to re-derive the why.
  class OperatorEligibility
    # The Phase 1 slice. Services only.
    #
    # Event::BUSINESS_CATEGORIES is `crafts services digital food other`. The
    # three that are missing here are missing for three different reasons:
    #
    #   crafts — physical goods. Under MoR the seller of record owes the buyer a
    #            conforming product, so Fuime would carry product liability on
    #            something a 16-year-old made in a garage, and physical sales
    #            accrue state sales-tax nexus against Fuime's single entity far
    #            faster than against any individual operator (§8.3 D3).
    #   food   — physical goods plus its own licensing regime (cottage food laws
    #            vary by state and several bar minors outright).
    #   other  — unknown by definition, and this list is an allowlist precisely
    #            so that "unknown" fails closed.
    #
    # `digital` is the deliberate near-miss and the obvious first widening: a
    # digital product carries no product liability and no shipping, so two of the
    # three rationales above do not apply. It is excluded anyway because ~30
    # states tax digital goods and the nexus tracking for that does not exist yet
    # (§8.5 phase 8). Widening to `digital` is a one-word change here once it
    # does — which is the reason this is a constant and not a scattered check.
    ELIGIBLE_CATEGORIES = %w[services].freeze

    # 16, from the Fair Labor Standards Act rather than from product taste.
    #
    # FLSA leaves 16- and 17-year-olds unrestricted in hours for non-hazardous
    # occupations; below 16 the hour limits bite and the analysis changes shape.
    # That matters here and not on an ordinary marketplace because of §7 Q2: if
    # operators were ever recharacterised as Fuime's employees rather than its
    # vendors, the exposure is FLSA child-labour rather than tax. The bracket
    # keeps the worst case survivable while that question is open.
    #
    # This is a floor on OPERATORS, and it is stricter than the platform's floor
    # on users, which stays at 13 per L6. A 14-year-old may hold an account; they
    # may not sell under the umbrella in Phase 1.
    MINIMUM_OPERATOR_AGE = 16

    def initialize(event:)
      @event = event
    end

    # Every reason this venture may not sell, in the order a human would fix
    # them. Empty means eligible.
    #
    # ── Two scopes, deliberately ────────────────────────────────────────────────
    #
    # **Vetting applies in every model.** "A human approved this operator" is not
    # a merchant-of-record control — it is the compensating control for letting
    # minors sell at all, and it is worth just as much under Connect, where the
    # guardian is the merchant, as under MoR, where Fuime is. It is also the thing
    # the brief calls the training data for the risk model that replaces it, and
    # that data only accrues if approvals actually happen from day one.
    #
    # **The launch-scope checks apply only under merchant-of-record.** Services
    # only, 16+, and a guardian per operator all exist to bound the liability
    # Fuime inherits *as seller of record*. Under Connect, Fuime is not the
    # seller: the guardian owns the account, Stripe settles to the family, and
    # product liability and the FLSA question land on the family rather than on
    # Fuime. Imposing Fuime's umbrella scope on a model where Fuime carries none
    # of that risk would block ventures for reasons that do not apply to them —
    # notably school ventures, where Event#institutionally_sponsored? already
    # stands in for a guardian.
    #
    # So the same object answers a narrower question when Fuime is not the seller.
    def blockers
      @blockers ||= [
        vetting_blocker,
        *(umbrella_scope_blockers if Fuime::Features.merchant_of_record?)
      ].compact
    end

    def eligible?
      blockers.empty?
    end

    # Raise rather than return false, for the call sites where continuing would
    # collect money Fuime is not entitled to collect. Same reasoning as
    # Fuime::Features.merchant_of_record!.
    def eligible!
      return true if eligible?

      raise Ineligible, "#{@event.name} cannot sell under Fuime: #{blockers.join('; ')}"
    end

    private

    # The checks that only bind while Fuime is the legal seller. See #blockers.
    def umbrella_scope_blockers
      [category_blocker, *operator_blockers]
    end

    def vetting_blocker
      return nil if @event.operator_vetting_approved?

      case @event.operator_vetting_status
      when "suspended" then "This venture is suspended and cannot accept payments."
      when "rejected"  then "This venture was not approved to sell on Fuime."
      else "This venture has not been approved by Fuime yet."
      end
    end

    def category_blocker
      category = @event.business_category.presence

      # Blank fails closed rather than passing. An unset category is the state
      # every venture created before this control existed is in, and treating
      # "not answered" as "allowed" would exempt exactly that population.
      return "Choose what this venture sells before accepting payments." if category.nil?
      return nil if ELIGIBLE_CATEGORIES.include?(category)

      "Fuime currently supports service businesses only, not #{category}."
    end

    # One blocker per person, naming them.
    #
    # Named because the fix is per-person — "someone on this venture needs a
    # guardian" sends the wrong teenager to ask their parent — and because a
    # two-founder venture can fail both checks for different people at once.
    def operator_blockers
      minor_operators.flat_map do |user|
        # User#name already falls back through preferred_name, full_name and
        # finally the email handle, so it is never blank.
        who = user.name

        [
          age_blocker(user, who),
          guardianship_blocker(user, who)
        ]
      end.compact
    end

    def age_blocker(user, who)
      age = user.age

      # Unknown age is not an eligible age. Consistent with
      # User#minor_or_unknown_age?, and load-bearing for the same reason: a
      # missing birthday must not be the way past a floor that exists to keep
      # FLSA hour limits out of the picture.
      return "#{who} has no date of birth on file." if age.nil?
      return nil if age >= MINIMUM_OPERATOR_AGE

      "#{who} is #{age}. Fuime operators must be at least #{MINIMUM_OPERATOR_AGE}."
    end

    def guardianship_blocker(user, who)
      return nil if user.has_active_guardian?

      "#{who} needs a parent or guardian on the account."
    end

    # Positions held by people who are minors, or whose age we do not know.
    #
    # Event#overseeing_guardians answers "does an adult exist for this venture",
    # which is a different and weaker question: it is satisfied by ONE guardian
    # even when a second teen co-founder has none. Eligibility has to be true of
    # every operator individually, so this walks the people rather than the
    # venture.
    #
    # Known adults are skipped entirely — an adult co-founder needs no guardian
    # and is subject to no age floor.
    def minor_operators
      @minor_operators ||= @event.users.select(&:minor_or_unknown_age?)
    end

    class Ineligible < StandardError; end

  end
end
