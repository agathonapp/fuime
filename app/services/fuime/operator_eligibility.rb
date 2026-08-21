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
    # `digital` WAS the deliberate near-miss. Opened 2026-08-20 on the founder's
    # call, and the reasoning is worth keeping because the note above was written
    # as a "not yet" rather than a "no".
    #
    # Two of the three rationales for excluding physical goods never applied to
    # digital: no product liability on a file, and no shipping. What remained was
    # sales tax — roughly 30 states tax digital goods and SaaS, and under
    # merchant-of-record that nexus accrues against Fuime's single entity rather
    # than against fifty individual teenagers.
    #
    # What makes opening it recoverable rather than a one-way door: **the data
    # needed to compute that nexus is already being captured.**
    # Fuime::PaymentLinkService sets `billing_address_collection: "required"` on
    # every MoR checkout for exactly this reason — nexus is measured on history and
    # history cannot be backfilled. So what is missing is the registration and
    # reporting (§8.5 phase 8), which can be built later FROM stored data. Opening
    # the category now costs a reporting obligation to catch up on, not evidence
    # that is gone.
    #
    # Still excluded and for unchanged reasons: `crafts` and `food` (physical
    # goods, liability, licensing) and `other` (unknown by definition — this is an
    # allowlist so that unknown fails closed).
    #
    # ⚠️ Monthly subscriptions are a SEPARATE thing and are not enabled by this.
    # Fuime::Offer has no recurring concept and MoR checkout is `mode: "payment"`,
    # so an operator can sell one-time access to a digital product but cannot yet
    # bill for it monthly. See docs/fuime/MOR_RISK_ACCEPTANCE.md §5.
    ELIGIBLE_CATEGORIES = %w[services digital].freeze

    # 16 by default, from the Fair Labor Standards Act rather than from product
    # taste.
    #
    # FLSA leaves 16- and 17-year-olds unrestricted in hours for non-hazardous
    # occupations; below 16 the hour limits bite and the analysis changes shape.
    # That matters here and not on an ordinary marketplace because of §7 Q2: if
    # operators were ever recharacterised as Fuime's employees rather than its
    # vendors, the exposure is FLSA child-labour rather than tax. The bracket
    # keeps the worst case survivable while that question is open.
    #
    # ── Why this is configurable, and why only downward to 13 ───────────────
    #
    # 16–17 is the launch shape from the product brief (MOR_MIGRATION_PLAN §8.1),
    # and the brief itself widens to 14 in its own Phase 2. It is a business
    # decision about accepted risk on an open question — not a statute — so the
    # person accountable for that risk should be able to set it without a code
    # change, and `FUIME_MINIMUM_OPERATOR_AGE` is how.
    #
    # Deploy-time env rather than a Flipper toggle, for the reason in
    # Fuime::Features: lowering this widens who Fuime is legally exposed for, so
    # it should cost a deploy, a diff and a person — not a checkbox a support
    # admin can find.
    #
    # ⚠️ **13 is a hard floor and this method cannot go below it.** That one is
    # not a business decision: under-13 is COPPA (L6), `User` refuses under-13
    # signup outright, and the amended-COPPA programme that would be required
    # does not exist. A misconfigured or hostile value clamps up to 13 rather
    # than being honoured, and a value above the default is honoured as-is —
    # raising the floor is always safe.
    DEFAULT_MINIMUM_OPERATOR_AGE = 16
    ABSOLUTE_MINIMUM_OPERATOR_AGE = 13

    def self.minimum_operator_age
      configured = ENV["FUIME_MINIMUM_OPERATOR_AGE"].to_s.strip
      return DEFAULT_MINIMUM_OPERATOR_AGE if configured.empty?

      parsed = Integer(configured, exception: false)
      # An unparseable value is a misconfiguration, and the safe reading of a
      # misconfigured age floor is the default one — never "no floor".
      return DEFAULT_MINIMUM_OPERATOR_AGE if parsed.nil?

      [parsed, ABSOLUTE_MINIMUM_OPERATOR_AGE].max
    end

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
        *administrative_blockers,
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
    #
    # ── Why the guardian is NOT one of them, under MoR ──────────────────────
    #
    # A guardian used to be required here, before an operator could sell at all.
    # Under merchant-of-record that gate is in the wrong place, and moving it is
    # a deliberate product decision (2026-08-16) rather than a relaxation of L2.
    #
    # The reasoning is the one that already governs the payout destination
    # (CreateFuimePayoutMethods): ask for the adult at the moment the adult is
    # actually needed. Under MoR a teenager selling creates no merchant account,
    # no Stripe relationship, no bank account and no obligation they could be
    # held to — the buyer's counterparty is Fuime LLC, and what the operator has
    # is a claim on Fuime. Demanding a parent before a 16-year-old can find out
    # whether anybody will buy their thing is asking a family to do paperwork for
    # a business that has earned nothing, which is the single biggest drop-off in
    # the funnel and buys no protection during the period it blocks.
    #
    # The moment the adult genuinely matters is when money LEAVES: that is when
    # there is a payee, a tax consequence, and a debt that could run negative.
    # Fuime::PayableAssessment#compute_structural_skip_reason holds that gate now,
    # alongside the payout destination, and it is strictly harder to pass than
    # this one was — no guardian, no money out, no exceptions.
    #
    # ── What this costs, stated plainly ─────────────────────────────────────
    #
    # During the selling window there is no adult obligor behind the operator.
    # MOR_MIGRATION_PLAN §7 Q3 ("who owes a clawback?") is unresolved, so a
    # chargeback on an unguardianed operator's sale lands on Fuime with nobody to
    # countersign the debt. That exposure is bounded by the reserve and hold in
    # the payout policy, and by the fact that money cannot leave without the
    # guardian arriving first — but it is real, and it is the reason this belongs
    # in a comment rather than in a commit message.
    def umbrella_scope_blockers
      [category_blocker, *operator_blockers]
    end

    # Fuime: the three states where an ADMIN, or the venture's own setup, has
    # already said this venture is not trading — and which nothing was asking about.
    #
    # These bind in EVERY model, alongside vetting rather than inside
    # #umbrella_scope_blockers, because none of them is about the liability Fuime
    # inherits as seller. They are about whether this venture is supposed to be
    # taking money at all, which is the same question under Connect.
    #
    # ── Each one was reachable, and each failed differently ────────────────────
    #
    # `financially_frozen?` was the worst of the three, because it was already
    # checked on the way OUT: Fuime::PayableAssessment#compute_structural_skip_reason
    # skips a frozen venture from every payout run. So a frozen venture kept
    # selling, and every sale became money Fuime holds and has no path to release —
    # the one combination worse than blocking either direction.
    #
    # `hidden_at` is HCB's admin suppression, used for abuse and spam. Fuime's
    # public surfaces disagreed with each other about it: the payment page filters
    # `.not_hidden` and the directory filters `.not_hidden`, while the storefront and
    # the checkout both used a bare `Event.find_by!(slug:)`. So hiding a venture
    # removed it from the directory and left its Buy button working.
    #
    # `demo_mode?` is a venture with fake seeded data for demos and screenshots.
    # `Event#name` appends "(DEMO)" and the directory excludes it, but the checkout
    # would have taken a real card number against it.
    #
    # Answered here rather than in the two controllers so there is one place that
    # decides, which is the property this class was created for — and so the API
    # (`require_selling_venture!`), the storefront, the payment page and the
    # checkout cannot drift apart again.
    def administrative_blockers
      blockers = []
      blockers << "Payments are frozen on this venture." if @event.financially_frozen?
      blockers << "This venture has been hidden by Fuime and cannot accept payments." if @event.hidden?
      blockers << "This is a demo venture and cannot take real payments." if @event.demo_mode?
      blockers
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

      # Names what IS supported rather than only what is not: a founder reading
      # "not crafts" cannot tell whether they picked the wrong option or built the
      # wrong business.
      "Fuime supports service and digital businesses right now, not #{category}."
    end

    # One blocker per person, naming them.
    #
    # Named because the fix is per-person — "someone on this venture is too young"
    # sends the wrong teenager to ask — and because a two-founder venture can fail
    # for one person and pass for the other.
    #
    # The guardianship check that used to live here moved to the payout seam; see
    # #umbrella_scope_blockers for why, and what it costs.
    def operator_blockers
      minor_operators.filter_map do |user|
        # User#name already falls back through preferred_name, full_name and
        # finally the email handle, so it is never blank.
        age_blocker(user, user.name)
      end
    end

    def age_blocker(user, who)
      floor = self.class.minimum_operator_age
      age = user.age

      # ── No date of birth: read the checkbox ──────────────────────────────
      #
      # Signup stopped asking for a date of birth on 2026-08-20 and asks for a
      # confirmation instead (see AddAgeAttestationToUsers), so for most users
      # `age` is now nil and this is the ordinary path rather than an edge case.
      #
      # A "13 or older" tick clears a floor of 13 — which is the production value
      # of FUIME_MINIMUM_OPERATOR_AGE — and clears nothing higher, because it
      # genuinely does not distinguish a 14-year-old from a 17-year-old.
      #
      # So raising the floor back to 16 stops every checkbox-only operator from
      # selling, with a sentence that says why. That is the correct failure and it
      # is worth being explicit about: the alternative is guessing on behalf of a
      # control that exists to keep FLSA child-labour exposure out of the picture
      # (see MINIMUM_OPERATOR_AGE above), and a guess there is the one thing this
      # class was created to stop.
      if age.nil?
        return nil if user.attested_at_least?(floor)

        if user.age_attestation.present?
          return "#{who} has confirmed they're 13 or older, but Fuime operators " \
                 "must be at least #{floor} — we'd need their date of birth to tell."
        end

        return "#{who} hasn't confirmed their age yet."
      end

      # A stored date of birth still wins where one exists — a card or Connect
      # onboarding collects a real one, and it is the more specific fact.
      return nil if age >= floor

      "#{who} is #{age}. Fuime operators must be at least #{floor}."
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
