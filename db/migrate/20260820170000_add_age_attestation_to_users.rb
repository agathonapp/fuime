# frozen_string_literal: true

# Fuime: stop asking children for their date of birth.
#
# ── The decision ─────────────────────────────────────────────────────────────
#
# Signup asked every user for a full month, day and year, `required: true`. The
# founder's call (2026-08-20) is to replace that with a checkbox, the way most
# consumer sites gate age. So this stores the attestation instead of the date.
#
# ── Why a state and not a boolean ────────────────────────────────────────────
#
# A single "I'm 13+" boolean cannot run this platform, and the reason is
# arithmetic rather than caution: the code asks three different age questions and
# a boolean has two states.
#
#   >= 13  User#minimum_age_requirement — the COPPA floor (L6)
#   >= 16  Fuime::OperatorEligibility — the FLSA operator floor, configurable
#          down to 13 and currently 13 in production
#   >= 18  User#known_adult? — who may be a GUARDIAN, which is the whole
#          parent-signs-for-the-teen structure (L2)
#
# With one boolean, `minor_or_unknown_age?` (deliberately fail-closed) reads true
# for everybody, so `known_adult?` is never true for anybody and no guardianship
# can ever activate — every user, including parents, is a minor waiting for a
# parent. So this column records WHICH claim was made:
#
#   minor_13_plus  "I am 13 or older"                     — the teen's box
#   adult_18_plus  "I am 18 or older, and their guardian" — the guardian's box
#
# One tick per person, no date, and the three thresholds still resolve.
#
# ── The security property, which is the load-bearing part ────────────────────
#
# **The box a user can tick from their own settings page can never make them an
# adult.** `minor_13_plus` is the only value the user-facing form can produce;
# `adult_18_plus` is set only by the guardian-acceptance flow, and
# `age_attestation` is deliberately NOT a permitted parameter on
# UsersController#update.
#
# That is the same property `User#birthday_is_write_once` was added for hours
# earlier in the security review (F-02): before it, a teen could PATCH their
# birthday to 1990 and switch off guardianship enforcement, the operator floor
# and the payout guardian gate in one request. Swapping a date for a checkbox
# must not reopen it, so the attestation is write-once too and the value that
# confers adulthood is unreachable from the form.
#
# ── What is NOT changed ──────────────────────────────────────────────────────
#
# `users.birthday` stays (CLAUDE.md Rule 2) and stays encrypted. Stripe requires
# a real date of birth for an Issuing cardholder and for a Connect individual, so
# the card form keeps its own prompt — that flow is the one place a date is
# genuinely needed, and it already only asks when the field is empty. Every
# ordinary user now goes through signup without being asked.
#
# ── The consent record ───────────────────────────────────────────────────────
#
# Timestamp, IP and user agent, mirroring `guardianships.agreement_*`. An
# unverified claim is still worth recording precisely: what was claimed, when, and
# from where is the difference between "we asked" and "we can show that we asked".
class AddAgeAttestationToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :age_attestation, :integer
    add_column :users, :age_attested_at, :datetime
    add_column :users, :age_attestation_ip, :string
    add_column :users, :age_attestation_user_agent, :string
  end
end
