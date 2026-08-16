# frozen_string_literal: true

# Fuime: the four dials that decide what a weekly payout run actually pays.
#
# All four are env-tunable for the same reason the pricing dials are (see
# `Event::Plan`): they are commercial decisions that will move as loss experience
# accumulates, and a founder should be able to move them without a deploy that
# touches arithmetic. They are read ONCE, at batch generation, and copied onto the
# `Fuime::PayoutBatch` row — see that migration's header for why a batch that
# floats with the env is a batch nobody can explain afterwards.
#
# ── The exposure these exist to bound ───────────────────────────────────────
#
# Under merchant-of-record Fuime is the seller. A customer who disputes a sale
# disputes it against FUIME, and Stripe debits Fuime's account, not the operator's
# (MOR_MIGRATION_PLAN §1 C5). The dispute window is 120 days. Weekly payouts mean
# Fuime has typically paid the operator ~113 days before the last moment the
# customer can take the money back, and the clawback answer — net it against
# future payables — is empty for an operator who has stopped selling.
#
# A 120-day hold would close the gap and destroy the product: a teenager who
# mowed a lawn in June would be paid in October, which is not a business, it is a
# savings account nobody consented to. So the exposure is split:
#
#   * a SHORT HOLD catches the fast failures — the card that was stolen, the
#     customer who charges back within the week;
#   * a ROLLING RESERVE carries the long tail, sized against trailing volume so
#     it scales with the risk it is covering rather than with a fixed guess.
#
# ── Why a rolling reserve and not per-payout withholding ────────────────────
#
# The obvious design withholds a slice of each payout and releases it 90 days
# later. It needs a release date per line, a job to action it, and — the part that
# bites — a class of money that is owed to somebody, held by Fuime, and waiting on
# a scheduled task to notice. That is a stored balance with extra steps, and the
# whole point of Fuime::PayablesLedger is not building one of those.
#
# A rolling reserve is a TARGET, recomputed every run as a percentage of trailing
# volume. Nothing is earmarked and nothing needs releasing: as old sales age out
# of the window the target falls on its own, and the operator's next payout is
# correspondingly larger. An operator who stops selling sees the reserve unwind to
# zero over one window with no intervention, which is the behaviour a per-line
# scheme has to be carefully built to imitate.
#
# ── What the defaults do to a real operator ─────────────────────────────────
#
# A steady operator earning $100/week, at the defaults (7-day hold, 10% of a
# 90-day trailing window):
#
#   Reserve target at steady state = 10% × 13 weeks × $100 = $130.
#
#   Weeks 1–13   paid $90/week, the withheld $10 building the reserve.
#   Week 14 on   paid $100/week. The target has stopped growing (the window
#                rolls), so every dollar earned is a dollar paid.
#   If they stop  the window empties over 90 days and the $130 pays out with it.
#
# So the reserve costs an operator about 1.3 weeks of earnings, once, held for as
# long as they trade. Against it: 10% of trailing volume covers a dispute rate of
# 10%, where a vetted services business running through manual approval should see
# well under 1%. That is roughly twenty times cover, which is deliberately
# generous while Fuime has no loss history at all to size it against.
#
# **These numbers are the founder's call, not an engineering constant.** They are
# implemented as specified and the arithmetic is pinned by
# `spec/lib/fuime/payout_policy_spec.rb` so a change is a change to one env var
# and not a wave of red tests. MOR_MIGRATION_PLAN §8.4 item 1 records the hold
# period as an open question; this is a defensible answer to it, not a settled one.
module Fuime
  class PayoutPolicy
    # How long money must have been settled before a batch may consider it.
    #
    # Seven days rather than Stripe's own T+2: two days catches nothing a
    # chargeback would have surfaced, and seven means a sale made on any day of a
    # week is payable in the following week's run rather than the same one — which
    # is also the sentence that is easiest to tell an operator truthfully.
    DEFAULT_HOLD_DAYS = 7

    # 10%, in basis points. Basis points rather than a float so the arithmetic is
    # integer end to end and a reserve can never be off by a rounding cent.
    DEFAULT_RESERVE_BASIS_POINTS = 1_000

    # The trailing window the reserve is sized against. Shorter than the 120-day
    # dispute window on purpose: the reserve is not trying to cover every open
    # dispute simultaneously, it is trying to cover the realistic rate over the
    # period most disputes actually land in.
    DEFAULT_RESERVE_WINDOW_DAYS = 90

    # The most one operator can be paid in one run — $2,500.
    #
    # A concentration limit, not a refusal: the remainder stays payable and rolls
    # into the following week. What it buys is time. An operator whose volume
    # suddenly looks nothing like the vetted business Fuime approved cannot empty
    # the account before a human sees the batch, and the batch is where a human
    # looks (MOR_MIGRATION_PLAN §8.4 item 3).
    DEFAULT_MAXIMUM_CENTS = 250_000

    # Below $10 the payable rolls forward instead of generating a line.
    #
    # A transfer costs money and a batch costs attention, and neither is worth
    # spending on $1.40. Deliberately low anyway — this is an audience for whom
    # $12 is a real payout, so the floor is set where the cost argument actually
    # bites rather than where it is administratively convenient.
    DEFAULT_MINIMUM_CENTS = 1_000

    attr_reader :hold_days, :reserve_basis_points, :reserve_window_days,
                :maximum_cents, :minimum_cents

    # The policy as configured right now. Call this at generation and nowhere else.
    def self.current
      new(
        hold_days: env_int("FUIME_PAYOUT_HOLD_DAYS", DEFAULT_HOLD_DAYS),
        reserve_basis_points: env_int("FUIME_PAYOUT_RESERVE_BASIS_POINTS", DEFAULT_RESERVE_BASIS_POINTS),
        reserve_window_days: env_int("FUIME_PAYOUT_RESERVE_WINDOW_DAYS", DEFAULT_RESERVE_WINDOW_DAYS),
        maximum_cents: env_int("FUIME_PAYOUT_MAXIMUM_CENTS", DEFAULT_MAXIMUM_CENTS),
        minimum_cents: env_int("FUIME_PAYOUT_MINIMUM_CENTS", DEFAULT_MINIMUM_CENTS)
      )
    end

    # The policy a batch was generated under, read back off the row.
    #
    # The reason this class is not a bag of constants: every consumer downstream of
    # generation must read the batch's frozen copy, and giving them a PayoutPolicy
    # means they cannot accidentally reach for the live env instead.
    def self.from(batch)
      new(
        hold_days: batch.hold_days,
        reserve_basis_points: batch.reserve_basis_points,
        reserve_window_days: batch.reserve_window_days,
        maximum_cents: batch.maximum_cents,
        minimum_cents: batch.minimum_cents
      )
    end

    # Negative dials are nonsense rather than a configuration choice, and a
    # negative hold or reserve would silently invert the control it exists to be —
    # a "reserve" of -10% pays out more than is owed. Clamped rather than raised on
    # because this is read at boot-adjacent times and a typo'd env var should not
    # take the app down; the clamp is visible in the batch's frozen copy.
    def self.env_int(name, default)
      raw = ENV[name]
      return default if raw.blank?

      [raw.to_i, 0].max
    end
    private_class_method :env_int

    def initialize(hold_days:, reserve_basis_points:, reserve_window_days:,
                   maximum_cents:, minimum_cents:)
      @hold_days = hold_days
      @reserve_basis_points = reserve_basis_points
      @reserve_window_days = reserve_window_days
      @maximum_cents = maximum_cents
      @minimum_cents = minimum_cents
    end

    # The last date whose settled money a run ending `period_end` may pay out.
    def eligibility_cutoff(period_end)
      period_end.to_date - hold_days
    end

    # The first date whose sales count toward the reserve target.
    def reserve_window_start(period_end)
      period_end.to_date - reserve_window_days
    end

    # The reserve to hold against `gross_cents` of trailing volume.
    #
    # Rounds DOWN, so rounding always resolves in the operator's favour. A cent
    # either way is immaterial to the exposure and "Fuime rounded its own reserve
    # up" is not a sentence worth having to defend.
    def reserve_target_cents(gross_cents)
      return 0 if gross_cents.to_i <= 0

      gross_cents.to_i * reserve_basis_points / 10_000
    end

    def attributes_for_batch
      {
        hold_days:,
        reserve_basis_points:,
        reserve_window_days:,
        maximum_cents:,
        minimum_cents:
      }
    end

    def reserve_percentage
      reserve_basis_points / 100.0
    end

  end
end
