# Umbrella merchant-of-record migration — plan of record

Status: **plan approved 2026-08-13; phases 1–2 landed (`837884068`). Phases 3+ resequenced
2026-08-14 — see §8, which supersedes §5.**
Written 2026-08-13 against `fuime/close-the-marketing-site` @ `a6002f4e6`.

> ## ⏪ Restore point — read this before undoing anything
>
> The complete working tree as it stood **immediately before the pivot began** is captured in
> the git tag **`pre-mor-pivot`** (`859fc5018`). It contains all 20 modified/untracked files of
> in-flight Stripe Connect work (embedded components, `provision_connect_account_job`,
> `EMBEDDED_CONNECT.md`, the new specs) that were uncommitted at the time.
>
> ```sh
> git show --stat pre-mor-pivot        # what's in it
> git diff pre-mor-pivot               # everything the pivot changed since
> git checkout pre-mor-pivot -- <path> # recover one file
> git checkout -b rescue pre-mor-pivot # recover the whole pre-pivot tree
> ```
>
> The tag is a real commit object, so it survives branch deletion and `gc`. Do not delete it
> until the pivot is merged and the Connect work is either landed or deliberately abandoned —
> §0.2 explains why it may need to come back.
>
> Baseline before any pivot code: **573 examples / 1 known failure**
> (`docs/fuime/known-failures.md`), plus the documented Apple-Silicon `wkhtmltopdf` set.

This is the file-by-file plan requested for the pivot from the current architecture to an
umbrella merchant-of-record (MoR) model where Fuime LLC is the legal seller, teen operators
are vendors, and Fuime pays them on a fixed cadence.

Read §0 first. Three things about the current codebase change the shape of the brief, and one
of them is not an engineering question at all.

---

## §0 — Read this first

### 0.1 The codebase is not in the state the brief assumes

The brief reads as though Fuime today is banking/deposit-shaped and needs to be de-custodied.
It is the opposite. As of PR #28 (2026-08-03) Fuime ships **Stripe Connect Standard with
guardian-owned connected accounts**: the guardian is the merchant of record, Stripe holds and
settles the funds, Fuime's cut arrives as a Connect `application_fee_amount`, and Fuime is
never in the flow of funds. That is stated in `CLAUDE.md` L1 and implemented across
~2,100 lines of `app/services/fuime/connect_*.rb`.

The banking surface the brief wants flagged — ACH origination, checks, wires, disbursements,
Emburse — is **already blocked at the request level** by
[app/controllers/concerns/fuime/disabled_modules.rb](app/controllers/concerns/fuime/disabled_modules.rb).
The "Fuime is not a bank, does not hold deposits, not FDIC-insured" disclosure the brief asks
for in item 8 **already exists** in [_footer.html.erb:39](app/views/application/_footer.html.erb#L39)
(standing, every page), [terms.html.erb:42](app/views/static_pages/terms.html.erb#L42),
[faq.html.erb:87](app/views/static_pages/faq.html.erb#L87), and a whole operator-facing copy
rulebook at [branding.html.erb:34](app/views/static_pages/branding.html.erb#L34).

So items 1 and 8 are mostly **already done**, and cost far less than budgeted.

The real cost is the reverse of what the brief expects: **this pivot invalidates the Connect
stack**, which is the most recently built and most carefully reasoned code in the repo.

### 0.2 The pivot moves money *into* Fuime's balance — the exact posture L1 forbids

`CLAUDE.md` L1 and `LEGAL_RESEARCH.md` §3 say the pooled model — customer money landing in
Fuime's own Stripe balance, paid out to ventures later — is unlicensed money transmission
(18 U.S.C. § 1960, criminal) and independently violates Stripe's ToS.

The MoR structure is a genuine, well-established escape from that, and I want to state the
distinction precisely rather than reflexively refuse:

> You are not a money transmitter when you receive your **own** revenue. If Fuime is the legal
> seller — Fuime's terms of sale, Fuime's name on the receipt, Fuime bearing the refund,
> warranty, and chargeback obligation to the buyer — then the customer is paying Fuime for a
> product Fuime sold, and the operator payment is Fuime paying its own vendor. No third-party
> funds are ever transmitted. This is how Paddle, FastSpring, Lemon Squeezy, and Whop operate.

That structure works. But it is load-bearing on **facts about the commercial relationship, not
on code**, and the facts cut against Fuime in one specific place:

- L1's analysis assumed Fuime was a *conduit*. MoR makes Fuime a *principal*. Different
  statute, different answer. Engineering cannot make that flip true — the terms of sale,
  buyer-facing receipts, and refund policy have to actually name Fuime.
- **`LEGAL_RESEARCH.md` §1 already flags the countervailing risk**, and MoR makes it worse:
  *"Danger zones: Fuime looking like the teens' employer (never set prices/schedule work)."*
  Under MoR, Fuime *is* the seller setting the terms of sale. The independent-contractor
  characterization of a 16-year-old operator gets materially harder to defend, and if it
  fails you are in FLSA child-labor territory rather than tax territory.
- A dispute clawback against an operator with no future payables is a **receivable from a
  minor**. Minors' contracts are voidable (L2, *Doe v. Epic Games*). The guardian must be the
  obligor on that debt or it is uncollectable by design.

**This is a counsel memo, not a sprint.** The specific questions are in §7. I can build the
whole thing under the stated assumption that counsel blesses the structure — say the word and
I will — but you should know that the code cannot resolve it, and that the current
architecture was built specifically to avoid needing it resolved.

### 0.3 HCB's contractor feature is the right substrate, and its payout rails are all dead

You were right to point at it. `Payee → LegalEntity → Payment → Payment::Attempt` is roughly
90% of brief items 3, 4, and 6 already built, including W-9 collection, TIN hashing, payout
methods, and a full AASM lifecycle with retries. Details in §4.

The catch: every payout rail it can reach —
[Payment::Attempt::PAYOUT_METHOD_TRANSFER_MAPPING](app/models/payment/attempt.rb#L28) →
`IncreaseCheck`, `AchTransfer`, `Wire`, `WiseTransfer` — runs on **Column and Increase**, which
Fuime has no relationship with and will not get
([ach_transfer.rb:207](app/models/ach_transfer.rb#L207) says so explicitly). All four are
blocked in `DisabledModules`. So the contractor feature is a complete payout *system* with no
working *rail*. A new Stripe-backed `LegalEntity::PayoutMethod` subclass is the critical new
build (§4.2).

---

## §1 — Where custody is baked in and hard to gate cleanly

This is the section you specifically asked for. Ranked by how much trouble each will cause.

### C1 — `Event#balance_*` is a subledger, and 111 view files read it ⚠️ hardest

[app/models/event.rb:814–916](app/models/event.rb#L814) defines fifteen balance methods, aliased
to `balance`, `available_balance`, `balance_available`. **111 files under `app/views` reference
"balance."**

The math is fine — under MoR, "sum of ledger lines mapped to this operator" is exactly the net
payable. The problem is that the *concept* is custody-shaped and the *name* is legally
load-bearing (brief item 3 is right about this).

Why it can't be cleanly flagged:
- You cannot gate `Event#balance` behind `FEATURE_SPONSOR_BANKING` — the payables view needs
  the same number. The flag has to gate **semantics and presentation**, not the method.
- Renaming it breaks upstream mergeability (CLAUDE.md Rule 6) across hundreds of call sites.

**Recommendation:** leave `balance_v2_cents` and the whole family untouched and internal. Add a
thin `Fuime::PayablesLedger` presenter that is the *only* thing views may call, exposing
`gross_sales_cents`, `fuime_fee_cents`, `net_payable_cents`, `next_payout_on`, `paid_to_date_cents`.
Then a spec asserts no operator-facing view calls `balance` directly. This gets the legal
distinction without a 111-file rename and without touching the ledger engine (Rule 3).

### C2 — `can_front_balance` is literal credit extension

[event.rb:12](app/models/event.rb#L12) — `can_front_balance` defaults to **TRUE**, and
[balance_v2_cents:817](app/models/event.rb#L817) adds `fronted_incoming_balance_v2_cents` when
set. "Fronting" means HCB advances spendable credit against money that has not settled, backed
by Hack Club's reserves.

`Fuime::VentureLedger#post!` hardcodes `fronted: false` and its comment explains why. But the
column default is still TRUE and any Event created outside that path inherits it. Under MoR,
fronting means **Fuime lending money to a minor's business against unsettled sales.**

**Recommendation:** flag-gate hard (`FEATURE_SPONSOR_BANKING` off ⇒ `can_front_balance?` returns
false regardless of column value), plus a migration changing the default to FALSE. Column
preserved.

### C3 — Stripe Issuing approves swipes against the subledger, funded by the platform

[stripe_card.rb:392](app/models/stripe_card.rb#L392) — `balance_available` reads
`event.balance_available_v2_cents`; the debit lands on Fuime's *platform* Issuing balance. The
long comment at [disabled_modules.rb:70](app/controllers/concerns/fuime/disabled_modules.rb#L70)
already documents that this is structurally broken under Connect.

Under MoR it is *less* broken — Fuime's own money, Fuime's own cards — but it becomes Fuime
extending revolving credit to a minor against an unpaid payable, with Celtic Bank's
Accountholder terms making Fuime liable for every swipe.

**Recommendation:** `FEATURE_SPONSOR_BANKING` gates all of `fuime/cards`, `stripe_cards`,
`stripe_cardholders`, `venture_card`, `venture_cardholder`, `Fuime::CardIssuingService`,
`Fuime::CardSpendPolicy`, `Fuime::ConnectCardRecorder`. This is the single cleanest flag
boundary in the whole plan — cards are already behind a default-off per-event flag, so it is a
tightening rather than a new mechanism.

### C4 — `PayoutService` caps against the live Stripe balance of a connected account

[payout_service.rb:52](app/services/fuime/payout_service.rb#L52) — `available_balance_cents`
calls Stripe for the *connected account's* available balance. Under MoR there is no connected
account, and the cap must become the payables ledger.

Note the well-designed precedent here: on a shared (school) account the service **already**
falls back to `[stripe_available, [@event.balance_v2_cents, 0].max].min` — capping a student
against their own subledger inside a pooled Stripe account. **That branch is the MoR model
already written.** See C7.

### C5 — Reversals debit the operator; under MoR the dispute debits Fuime

[connect_payment_recorder.rb:64](app/services/fuime/connect_payment_recorder.rb#L64) books
refunds and `charge.dispute.created` against the venture, which is correct when the venture's
own Stripe balance took the hit. Under MoR the money leaves *Fuime's* balance and the operator
may have no payable to net against.

This is brief item 5, and it is the one that needs new legal machinery, not just new code:
a negative payable is a debt owed by a minor. See §7 Q3.

### C6 — `RawPendingDonationTransaction` is the money-in entry point

`Fuime::VentureLedger` feeds the ledger through `RawPendingDonationTransaction` because it is
the narrowest legitimate entry point and Rule 3 forbids touching pipeline internals. This
survives the pivot **unchanged** — which is the single biggest thing going right in this plan.
Under MoR the three-line posting (gross, Fuime fee, Stripe processing fee) is *exactly* the
gross/fee/net breakdown brief item 3 asks for. No ledger work needed; it is presentation.

### C7 — The school/pooled path is already the MoR model 💡

`Event#shares_payment_account?` ([event.rb:756](app/models/event.rb#L756)),
`PayoutRequest::PERSONAL_TRANSFER`, `PayoutService#approve_personal_transfer!`, and
`#settle!` implement: one Stripe account holds everyone's money → each participant has a
subledger balance → an adult approves a payout → the money moves outside Stripe → someone
asserts it was paid and *then* the ledger debits.

Swap "school" for "Fuime LLC" and that is the umbrella MoR payout flow, already built, already
spec'd (`spec/services/fuime/pooled_simulator_guard_spec.rb`), with the ledger keys and
idempotency already reasoned through. **Reuse this, do not rebuild it.** It is the highest-
leverage discovery in this review and it cuts item 4 roughly in half.

---

## §2 — Flag design

Do **not** introduce a new flags module. Flipper is already wired
([config/initializers/flipper.rb](config/initializers/flipper.rb)) with an ActiveRecord + cache
adapter, a UI, and actor gates on `Event` and `User`.

But `FEATURE_SPONSOR_BANKING` must **not** be a Flipper flag. Flipper flags are togglable by an
admin from a web UI, and turning custody on without a partner bank is a criminal-exposure
event, not a beta rollout. Two tiers:

| Tier | Mechanism | Used for |
|---|---|---|
| **Structural** | `Fuime::Features` — a plain module reading ENV at boot, memoized, no runtime toggle | `FEATURE_SPONSOR_BANKING` (default false) |
| **Rollout** | Existing Flipper | payout cadence experiments, vetting UI, per-operator betas |

**New:** `app/lib/fuime/features.rb`

```ruby
module Fuime::Features
  def self.sponsor_banking? = ENV["FEATURE_SPONSOR_BANKING"] == "true"
end
```

Enforcement rides the existing layers rather than sprouting new ones:

1. **Request level** — extend `Fuime::DisabledModules` with a
   `SPONSOR_BANKING_CONTROLLER_PREFIXES` list, gated on the flag. This is already the
   enforcement layer and already handles the admin exemption.
2. **Model level** — `Event#can_front_balance?`, `StripeCard#balance_available` return
   safe values when off.
3. **Boot level** — extend
   [config/initializers/fuime_safety_check.rb](config/initializers/fuime_safety_check.rb) to
   **raise** if `FEATURE_SPONSOR_BANKING=true` without a configured partner-bank credential.
   Same policy as the existing live-Stripe-key check: ambiguous half-configured money states
   refuse to boot.
4. **Policy level** — `EventPolicy` methods already carry `FUIME-DISABLED` stubs; extend that
   convention.

---

## §3 — File-by-file inventory

Legend: **FLAG** = gated, code preserved · **CHANGE** = semantics change · **ADD** = new ·
**KEEP** = untouched, listed because you would expect otherwise. **Nothing is deleted.**

### 3.1 Feature flag system (item 1)

| File | Action | Note |
|---|---|---|
| `app/lib/fuime/features.rb` | **ADD** | ~20 lines |
| `app/controllers/concerns/fuime/disabled_modules.rb` | **CHANGE** | add flag-gated prefix list |
| `config/initializers/fuime_safety_check.rb` | **CHANGE** | new check #5, raises |
| `app/models/event.rb` (`can_front_balance?`) | **FLAG** | C2 |
| `app/models/stripe_card.rb` (`balance_available`) | **FLAG** | C3 |
| `db/migrate/*_default_can_front_balance_false.rb` | **ADD** | default only, column preserved |
| `spec/lib/fuime/features_spec.rb` | **ADD** | assert default-off |

### 3.2 Banking surface — FLAG, no deletion (item 1)

Already blocked by `DisabledModules`; moves under the flag so re-enabling is one config change:

`ach_transfer.rb` · `increase_check.rb` · `check.rb` · `check_deposit.rb` · `wire.rb` ·
`wise_transfer.rb` · `disbursement.rb` · `bank_account.rb` · `increase_account_number.rb` ·
`column/*` · `raw_column_transaction.rb` · `raw_increase_transaction.rb` ·
`raw_intrafi_transaction.rb` · plus their controllers, views, and `api/v4` twins.

**All KEEP as code.** Only the gate changes. Their specs stay green — the models are never
touched, only routing to them.

Cards (C3): `app/controllers/fuime/cards_controller.rb`, `app/views/fuime/cards/`,
`app/services/fuime/card_issuing_service.rb`, `card_spend_policy.rb`, `connect_card_recorder.rb`,
`venture_card.rb`, `venture_cardholder.rb`, `stripe_card*.rb` → **FLAG**.

### 3.3 Operator model (item 2)

The brief says "rename Event → Operator." **Do not.** CLAUDE.md Rule 6 forbids it and `Event`
has hundreds of references. Rename the *user-facing noun* only — which the repo has already
done once ("venture") and can do again cheaply.

| File | Action | Note |
|---|---|---|
| `db/migrate/*_add_operator_fields_to_events.rb` | **ADD** | `legal_name`, `dba`, `operator_age_bracket`, `guardian_consent_status`, `agreement_signed_at`, `vetting_status`, `payout_legal_entity_id`. `business_category` and `guardian consent` already exist |
| `app/models/event.rb` | **CHANGE** | validations, `vetting_status` enum, `PROHIBITED_CATEGORIES`. `BUSINESS_CATEGORIES` already at [event.rb:92](app/models/event.rb#L92) |
| `app/models/guardianship.rb` | **KEEP** | already does consent, versioned agreement, IP/UA, signature record. Item 6's guardian countersignature is **already built** |
| `config/locales/` or a `Fuime::Nouns` helper | **ADD** | one place that says "Operator", so the next rename is one file |

### 3.4 Payables ledger (item 3)

| File | Action | Note |
|---|---|---|
| `app/services/fuime/payables_ledger.rb` | **ADD** | presenter over `Event#balance_*`; the only thing operator views may call. ~150 lines |
| `app/services/fuime/venture_ledger.rb` | **KEEP** | 100% survives. Three-line gross/fee/fee posting is already the earnings breakdown |
| `app/views/fuime/payouts/index.html.erb` | **CHANGE** | becomes the earnings/payables page |
| `app/views/events/*` (balance widgets) | **CHANGE** | route through the presenter |
| `spec/services/fuime/payables_ledger_spec.rb` | **ADD** | incl. a spec asserting no operator view calls `balance` |

### 3.5 Payout scheduling (item 4)

| File | Action | Note |
|---|---|---|
| `app/models/payout_request.rb` | **CHANGE** | AASM + approval + destination + failure fields all reusable as-is. Add `payout_batch_id` |
| `app/models/fuime/payout_batch.rb` | **ADD** | batch generation + approval |
| `app/models/legal_entity/payout_method/bank_account.rb` | **ADD** | **critical** — the only working rail (§0.3). Plaid-verified, originator per §4.3 (Slash / Mercury / Stripe). Was drafted as `::StripeConnect`; see §4.3 for why the rail is now an open decision |
| `app/services/fuime/payout_service.rb` | **CHANGE** | swap the Stripe-balance cap for the payables cap. The `personal_transfer` branch is the template (C7) |
| `app/jobs/fuime/generate_payout_batch_job.rb` | **ADD** | weekly cadence |
| `app/models/payment.rb`, `payment/attempt.rb` | **KEEP** | retry/failure lifecycle reused wholesale |

### 3.6 Chargebacks and clawback (item 5)

| File | Action | Note |
|---|---|---|
| `app/models/fuime/dispute_event.rb` | **ADD** | attribution to operator |
| `app/services/fuime/connect_payment_recorder.rb` | **CHANGE** | dispute handling moves from operator-Stripe-balance to Fuime-balance + payable clawback (C5) |
| `app/services/fuime/clawback_service.rb` | **ADD** | net against future payables; **blocked on §7 Q3** |

### 3.7 Onboarding and agreements (item 6)

Largely already built. `Contractable` + `Contract` + DocuSeal + `Guardianship`'s versioned,
hash-pinned agreement machinery covers e-signature, countersignature, and consent records.

| File | Action | Note |
|---|---|---|
| `app/models/event/application.rb` | **CHANGE** | vetting checklist + prohibited-category screen |
| `app/models/concerns/contractable.rb` | **KEEP** | already generic |
| `app/models/event/plan.rb` (`contract_docuseal_template_id`) | **KEEP** | already env-driven and Fuime-owned |
| `app/views/guardianships/agreements/_2026_XX_v3.html.erb` | **ADD** | new version for the MoR relationship (additive; v1/v2 stay) |
| `app/models/tax/form.rb`, `w9.rb` | **KEEP** | W-9 for vendor operators, already built |

### 3.8 Sales tax groundwork (item 7)

Do not extend `Fuime::TaxTrackerService` — that computes the *operator's income tax* and
conflating it with Fuime's *sales tax* nexus would produce a wrong number in a legally
sensitive place.

| File | Action | Note |
|---|---|---|
| `db/migrate/*_add_buyer_jurisdiction_to_*.rb` | **ADD** | buyer state, postal, country |
| `app/services/fuime/payment_link_service.rb` | **CHANGE** | `billing_address_collection: "required"` — **currently not collected at all**, so nexus data starts accruing only from ship date |
| `app/services/fuime/connect_payment_recorder.rb` | **CHANGE** | persist `customer_details.address` |
| `app/services/fuime/nexus_report_service.rb` | **ADD** | volume + transaction count by state |
| `app/services/fuime/tax_tracker_service.rb` | **KEEP** | different tax, leave alone |

### 3.9 Copy audit (item 8)

Mostly done. Remaining, scoped:

| Target | Action | Note |
|---|---|---|
| `app/views/fuime/**` (9 dirs) | **CHANGE** | "balance" → "amount owed to you, paid on ___" |
| `app/views/application/_footer.html.erb` | **KEEP** | disclosure already correct and standing |
| `static_pages/{terms,faq,branding}.html.erb` | **CHANGE** | terms must now name Fuime as **seller of record** — this is the legally operative copy change, not a word swap |
| `app/views/events/**`, `admin/**` | **KEEP** | admin/internal; "balance" is accurate there |
| `spec/views/fuime/copy_spec.rb` | **ADD** | extend the existing forbidden-phrase spec pattern |

### 3.10 The Connect stack — the cost of the pivot ⚠️

Under MoR, guardians do not own Stripe accounts. These become dead:

| File | Lines | Fate |
|---|---|---|
| `connect_onboarding_service.rb` | 537 | **FLAG** — needed again if you ever restore operator-owned accounts |
| `connect_payment_recorder.rb` | 434 | **CHANGE** — dispute/refund logic reused, account resolution replaced |
| `requirement_collection_service.rb` | 287 | **FLAG** — guardian KYC only needed when the guardian is the merchant |
| `connect_funding_recorder.rb` | 208 | **FLAG** |
| `connect_payout_recorder.rb` | 200 | **CHANGE** — reusable for Fuime→operator transfers |
| `connect_settlement_sweep.rb` | 180 | **CHANGE** — sweeps Fuime's own balance now |
| `connect_webhook_handler.rb` | 165 | **CHANGE** |
| `payment_setups_controller.rb` + 3 views + 2 JS controllers | ~600 | **FLAG** |
| `payment_webhook_handler.rb` | 421 | **PROMOTE** — the "retired pooled simulator" becomes the primary money-in path |

**~1,200 lines go dark and ~1,400 get reworked.** That is the honest price, and it is why §0.2
matters: if counsel comes back unfavourable on MoR you will have retired working code to
return to a structure it was purpose-built for.

---

## §4 — What HCB's contractor feature buys you

You asked me to look. It is a better find than expected.

```
Payee (event, display_name, email, legal_entity)
  └── LegalEntity (tin_hash, entity_type, archived_at, banned_reason)
        ├── Tax::Form          → W-9 collection, DocuSeal-backed
        ├── PayoutMethod       → AchTransfer | Check | Wire | WiseTransfer
        └── Payment            → AASM: pending_legal_entity → under_review
                                       → sent → successful | rejected | canceled
              └── Payment::Attempt  → retry, failure capture, one live attempt
```

`LegalEntity#payable?` already means "has a completed tax form and a payout method," and
`refresh_pending_contractors_payments!` re-drives blocked payments when either lands. Payment
already includes `Receiptable` and `Commentable`. This is items 3, 4, and half of 6.

Two structural mismatches to plan around:

**4.1 Ownership is inverted.** `Payee belongs_to :event` — a payee is a *vendor of an org*.
Under MoR the operator is a vendor *of Fuime*. Either create a house `Event` representing
Fuime LLC (cheap, ugly, zero migration risk) or make `payee.event_id` nullable with a
`platform` scope (cleaner, touches an upstream table). **I recommend the house Event** for
Phase 1 — it keeps the upstream schema pristine and is trivially reversible.

**4.2 No working rail.** All four `PayoutMethod` subclasses run on Column/Increase/Wise. One new
subclass is the only genuinely new money-movement code in this plan — but **which** rail is now
an open product decision (see §4.3), not a foregone conclusion.

**4.3 Money-in and money-out decouple — which is the pivot's biggest structural win**
*(revised 2026-08-13 after the Slash / Mercury / Plaid question.)*

An earlier draft of §4.2 assumed "you still need Connect, just Express-for-payouts". That was
too narrow. Under merchant-of-record the two halves stop being one system:

| | Before (Connect Standard) | Under MoR |
|---|---|---|
| Money **in** | Direct charge on the guardian's connected account | **Plain Stripe charge on Fuime's own account. No Connect at all.** |
| Money **out** | Stripe payout to the guardian's bank | Fuime paying its own vendors — ordinary accounts payable, any rail |

**Why a business-banking rail (Slash, Mercury) becomes legitimate here, when it was not
before.** This is the load-bearing point and it is easy to get backwards. Under the pooled
model, money sitting in a Fuime-controlled account was *other people's money*, which is
money transmission (L1). Under MoR the same balance is **Fuime's own revenue from Fuime's own
sale**, so holding it is ordinary corporate treasury and paying it out is ordinary AP. The
structure, not the vendor, is what makes it lawful.

Roles, which are commonly conflated:

- **Slash / Mercury** — where Fuime's money sits, and the ACH origination rail.
- **Plaid (Auth)** — verifies the operator's account and routing numbers. **Plaid does not
  move money**; it always needs an originator behind it.

**What leaving Connect actually costs: 1099-NEC filing.** Paying operators ≥$600/yr as vendors
triggers 1099-NEC. Stripe Connect files these; **Slash and Mercury do not.** HCB already
handles the *collection* side — `Tax::Form` (DocuSeal-backed W-9) and `LegalEntity#tin_hash` —
so what is missing is filing, not gathering. Decide this deliberately rather than discovering
it in January. Connect also performs recipient KYC, which a bank rail leaves to Fuime.

**Diligence before building, in order:**

1. **Mercury's API and ToS.** The API is limited and they are conservative about accounts that
   resemble payments platforms. Confirm that programmatic ACH to hundreds of third parties —
   many of them minors' guardians — is permitted. Slash is more API-native and is likely the
   better fit if the answer is grudging.
2. **Who the recipient is.** A minor generally cannot open a bank account alone, so the
   destination is usually a guardian-owned account. True on every rail; Plaid verifies
   whoever's account it is.
3. **Batch-day limits.** ACH volume caps at a fintech bank bite on a weekly payout run.

**Implementation impact is small, because the abstraction already exists.**
`Payment::Attempt::PAYOUT_METHOD_TRANSFER_MAPPING` maps a `PayoutMethod` subclass to a transfer
model, and `AchTransfer` merely happens to call Column. So the work is **implementing one
class** — `LegalEntity::PayoutMethod::BankAccount`, Plaid-verified, backed by whichever
originator — not redesigning. Keeping it behind `PayoutMethod` is what makes the rail swappable
if Mercury says no.

---

## §5 — Sequencing

Each phase is one branch, one PR (Rule 5). Phases 1–2 are safe to start before the counsel
memo; phase 3 onward is not.

| # | Phase | Depends on |
|---|---|---|
| 1 | `Fuime::Features` + flag plumbing + safety check + card gating | nothing |
| 2 | Copy audit + payables presenter (`Event#balance` untouched) | 1 |
| 3 | Operator fields, vetting, prohibited categories, v3 agreement | counsel §7 Q1 |
| 4 | Money-in flips to Fuime's account; promote `PaymentWebhookHandler`; buyer jurisdiction capture | **counsel Q1 + Stripe Q4** |
| 5 | `PayoutMethod::StripeConnect`, batches, cadence | 4 |
| 6 | Disputes and clawback | counsel Q3 |
| 7 | Nexus report | 4 |

Prime Directive 1 applies throughout: baseline is **573 examples / 1 known failure**
(`docs/fuime/known-failures.md`), plus the documented Apple-Silicon `wkhtmltopdf` set.

---

## §6 — Things I am deliberately not doing without a word from you

- Renaming `Event` → `Operator` in code (Rule 6). User-facing noun only.
- Deleting anything (your constraint, and Rule 2).
- Touching `CanonicalTransaction` / `HcbCode` / the ingestion pipeline (Rule 3).
- Computing or remitting sales tax (your item 7 says groundwork only — agreed).
- Flipping `STRIPE_MODE` off test.

---

## §7 — Open questions, blocking and non-blocking

**Blocking (counsel):**

1. **Does the MoR structure hold?** Specifically: does Fuime LLC contracting as seller of
   record, with operators as vendors, take the collection leg outside 18 U.S.C. § 1960 and
   state MTL — and does it satisfy Stripe's ToS where the pooled model did not? L1 was written
   against the conduit model and does not answer this.
2. **Does umbrella MoR break the independent-contractor characterization?**
   `LEGAL_RESEARCH.md` §1 warns against Fuime looking like the operators' employer. As seller
   of record, Fuime sets terms of sale. If these are employees rather than vendors, FLSA child
   labor rules attach and the 16–17 model changes shape entirely. **This is the question I am
   least comfortable proceeding past.**
3. **Who owes a clawback?** A negative payable is a debt from a minor and voidable (L2). Does
   the guardian countersign as obligor on operator debts, or does Fuime absorb dispute losses?
   The answer determines whether §3.6 is a ledger feature or a collections feature.

**Blocking (Stripe):**

4. Can a single Stripe account be the merchant of record for goods sold by ~N third-party
   operators, with Fuime as principal? This is adjacent to the "payment facilitation and
   aggregation on behalf of third-party sellers" restriction and needs Stripe's own answer,
   not our reading.

**Non-blocking (yours):**

5. Payout cadence — weekly default confirmed? Minimum threshold? Hold period after sale
   (dispute window is 120 days; paying out same-week means unsecured clawback exposure).
6. Fee — does the 4% `revenue_fee` survive, or does MoR change the take-rate story?
7. House `Event` vs. nullable `payee.event_id` (§4.1) — I recommend house Event.
8. Under-16-with-consent: MoR removes Stripe's 13+ floor for *operators* (they no longer hold
   a Stripe account), but `User` still refuses under-13 signup at
   [user.rb:933](app/models/user.rb#L933) per L6. Confirm that stays.

---

## §8 — Revision 2026-08-14: the brief answers §7, and adds three things it did not price

A revised product brief ("Fuime is Whop for under-18s") arrived 2026-08-14. It is the same
structure this plan describes, with a launch shape attached: **services only, operators 16–17,
5% flat, weekly payouts, 25 operators / $25K GMV by November.** This section records what it
settles, what it changes, and what it missed. **It supersedes §5's sequencing.**

### 8.1 What the brief settles (the non-blocking half of §7)

| §7 | Question | Answer |
|---|---|---|
| Q5 | Payout cadence | **Weekly**, with an approval step. Hold period still unstated — see 8.4. |
| Q6 | Does the 4% fee survive? | **No — 5% flat, all-in.** This is not a number change. See 8.3 D1. |
| Q7 | House `Event` vs nullable `payee.event_id` | Brief is silent; recommendation stands — **house Event**. |
| Q8 | Does the under-13 refusal stay? | **Yes.** Phase 1 is 16–17; the brief widens to 14 only in its own Phase 2, still above L6's floor. |

Scope decisions the brief adds, all of which need enforcement rather than intent:
**services only** (no physical goods, so no sales-tax nexus and no product liability),
**16–17 only** (FLSA leaves non-hazardous occupations unrestricted at 16, which is the whole
reason for the bracket), and **manual approval on every operator and every payout**.

### 8.2 The blocking half of §7 is accepted risk, not resolved risk

The brief does not answer Q1, Q2 or Q4 — it *accepts* them and budgets $5–8K of counsel plus a
direct conversation with Stripe. That is a legitimate posture and this plan proceeds on it, but
the distinction matters: the questions are still open, and Q2 in particular now constrains
product decisions (8.3 D2).

**The engineering consequence: writing this code moves no money.** `STRIPE_MODE` is test
everywhere including production, and phases 3+ ship behind a new structural flag
(`FEATURE_MERCHANT_OF_RECORD`, 8.5) whose boot guard demands a counsel-memo reference the same
way `FEATURE_SPONSOR_BANKING` demands a named bank. The gate moves from "do not write it" to
"cannot switch it on" — mechanical rather than remembered, and it lets the build run in parallel
with the legal work instead of behind it.

### 8.3 Three deltas the brief did not price

**D1 — "5% flat, all-in" changes who pays Stripe, and the ledger currently says the operator does.**

This is the most consequential line in the brief and it reads as pricing. It is not.

Today an operator's payables page is debited three times: gross, −4% Fuime
([venture_ledger.rb](app/services/fuime/venture_ledger.rb)), and −(2.9% + 30¢) Stripe, surfaced
as [`PayablesLedger#processing_fee_cents`](app/services/fuime/payables_ledger.rb#L172).
On a $100 sale the operator nets **$92.80 — an effective take of 7.2%**, not 4%.

The brief's "5% flat, all-in… net to Fuime after processing: roughly 2%" means Stripe's fee is
**Fuime's cost of being the merchant**, not a pass-through. Under MoR that is also the only
coherent answer: Fuime is the merchant of record, so Stripe charges Fuime for Fuime's own sale,
and billing it onward to a vendor is a second, undisclosed markup on top of the advertised flat
rate.

So `processing_fee_cents` must stop being an operator deduction, and the operator-facing
breakdown goes from four rows to two: **gross − 5% = net payable.** The Stripe fee stays posted
(it is real, and reconciliation needs it) but moves to Fuime's side of the line. That is a
ledger-shape change, which is why the fee is its own phase below rather than a constant edit.

**D2 — the brief's Phase 2 directory contradicts the brief's own Q2 mitigation.**

The brief mitigates misclassification with: *"operators must control their own pricing, clients,
and hours. We never route work to them or set rates."* Its Phase 2 then builds *"operator
directory, reputation, completed-job history"* and calls the demand side the moat.

Those are in tension. A directory that **ranks, matches, or assigns** is routing work, and
reputation scoring that gates visibility functions as performance management — precisely the
evidence an FLSA or IRS examiner looks for. The moat is real and worth building; it has to be
built as a **listing, not a dispatch**:

- Operators publish; buyers browse and contact. Fuime never assigns a buyer to an operator.
- No Fuime-set or Fuime-suggested rates. Operators price themselves, always.
- No acceptance-rate, response-time or completion-rate metric that Fuime enforces or ranks on.
- Ordering is neutral (recency, alphabetical, operator-chosen category) — not a quality score.

Encoded as a spec in the shape of `spec/views/fuime/payables_copy_spec.rb`, which already proves
this repo can hold a legal distinction in place with a test rather than a comment.

**D3 — services-only needs a gate, and the category list does not have one.**

[`Event::BUSINESS_CATEGORIES`](app/models/event.rb#L92) is
`crafts services digital food other`. Two of those five are physical goods and one (`food`)
carries its own licensing regime. Phase 1 being services-only is currently a sentence in a
document rather than a validation — and the exposures it exists to remove, sales-tax nexus and
product liability, are the two the brief leans on hardest.

### 8.4 Still open after the brief

1. ~~**Hold period before payout.**~~ **Answered in phase 6 (2026-08-15), pending the founder's
   sign-off on the numbers.** The exposure is split rather than closed by one dial: a **7-day
   hold** catches fast failures and a **10% rolling reserve over a 90-day trailing window**
   carries the tail. A 120-day hold would close the gap and destroy the product — a teenager
   paid in October for a June job is not running a business. Rolling rather than
   withhold-and-release, because a release schedule creates money Fuime holds while somebody
   waits on a job to notice it, which is a stored balance with extra steps. All four dials are
   env-tunable (`Fuime::PayoutPolicy`) and **frozen onto each batch row**, so a run stays
   explainable after the configuration moves. Still interacts with §7 Q3 — the reserve is what
   a clawback nets against when an operator has stopped selling, which is the case the brief's
   answer does not cover.
2. **1099-NEC filing** (§4.3). Collection is built; filing is not, and leaving Connect means
   nobody files it. Decide before January, not in it.
3. ~~**Per-operator volume caps and reserve.**~~ **Built in phase 6.** The cap is $2,500 per
   operator per run and is a *concentration limit, not a refusal* — the remainder stays payable
   and rolls into the following week. What it buys is time: an operator whose volume suddenly
   looks nothing like the vetted business Fuime approved cannot empty the account before a human
   reads the run. There is also a $10 floor, below which a payable rolls forward rather than
   generating a line.

### 8.5 Revised sequencing — supersedes §5

> **✅ DECISION 2026-08-14: merchant of record is the destination. Build phases 3c–8.**
>
> A "Connect for now" reading was recorded earlier the same day and **reversed within the
> hour** — noted because the reversal is the useful part of the record, not an embarrassment
> to hide. The reasoning that settled it:
>
> **Connect cannot deliver the product's headline promise.** The brief's pitch is *"no
> parent's SSN, bank account, or tax identity is required."* Under Connect the guardian owns
> the Stripe account, so Stripe demands their SSN last-4, their address and their bank
> account, and the income lands under their tax identity (L3). That is precisely the status
> quo the brief describes as the problem. Only MoR moves the tax identity to the teen's own
> SSN via a 1099-NEC.
>
> **Two consequences that shape everything below:**
>
> 1. **Connect stays as the shipping path until MoR can go live.** It is what HEAD runs with
>    the flag off, it is the only thing that can carry real users while Fuime LLC does not
>    exist, and phase 9 (the directory) already runs under both. Nothing here deletes it —
>    `FEATURE_MERCHANT_OF_RECORD` is the switch, and MOR_MIGRATION_PLAN §0.2 plus the
>    `pre-mor-pivot` tag are the way back.
> 2. **"5% flat, all-in" becomes achievable, and only here.** Under Connect, Stripe deducts
>    its fee from the *family's* account and Fuime cannot absorb a cost it never touches.
>    Under MoR the charge is on Fuime's own account, so Stripe's fee is Fuime's cost and the
>    operator's payable is a clean `gross − 5%`. This is why D1 is a ledger-shape change
>    rather than a constant edit.
>
> **Still true, and unchanged by this decision:** MoR cannot be switched on until Fuime LLC
> exists, the operator agreements are papered, and the boot guard's `FUIME_MOR_COUNSEL_MEMO`
> can be answered truthfully. Building the code now is safe precisely because that gate is
> mechanical rather than remembered (§8.2).

Each phase is one branch, one PR (Rule 5). Everything ships behind `FEATURE_MERCHANT_OF_RECORD`
(default off, boot-guarded) so none of it can transact until the §8.2 gate opens.

| # | Phase | Delivers | Depends on |
|---|---|---|---|
| **3a** | MoR structural flag + boot guard | `FEATURE_MERCHANT_OF_RECORD`, counsel-memo boot check | nothing |
| **3b** | Operator model | age bracket, vetting status, prohibited categories, services-only gate (D3) | 3a |
| **3c** | Agreement v3 | MoR relationship, guardian as obligor on clawbacks | 3b, §7 Q3 |
| **4** | Money-in flips to Fuime | promote `PaymentWebhookHandler`, buyer jurisdiction capture | 3a; §7 Q1+Q4 to *enable* |
| **5** | Fee becomes 5% all-in | processing fee leaves the operator's side (D1) | 4 |
| **6** | Payout batches ✅ | weekly cadence, approval step, volume caps, reserve — **shipped 2026-08-15**, minus the originator (§4.3), which a human assertion stands in for | 5 |
| **7** | Disputes and clawback | attribution, netting against payables | 6, §7 Q3 |
| **8** | Nexus report | volume + count by state | 4 |
| **9** | Operator directory | listing-not-dispatch (D2) | 6 |

Baseline throughout (Prime Directive 1): **2896 examples, 8 known failures**
(`docs/fuime/known-failures.md`), Docker only.

---

## §8.6 — Pricing, and the Pro margin problem (2026-08-14)

The founder's ladder, implemented in `Event::Plan::{Free,Standard,Pro}` and pinned by
`spec/models/event/plan_pricing_spec.rb`:

| Plan | Monthly | Rate |
|---|---|---|
| Free | $0 | 7% |
| Standard | $15.00 | 5% |
| Pro (family) | $19.99 | 3% |

Both dials are env-tunable (`FUIME_STANDARD_MONTHLY_CENTS`, `FUIME_PRO_MONTHLY_CENTS`) and the
rate is read from the class everywhere — specs derive expectations from
`FALLBACK_REVENUE_FEE` rather than restating it, so a price change is a one-line decision and
not a wave of red tests.

### Why the rate changed meaning, not just value

Under Connect, `revenue_fee` was a **platform cut** and Stripe's 2.9% + 30¢ was deducted from
the *family's* connected account. Under merchant-of-record Fuime is the seller, so Stripe
charges **Fuime**. The rate stops being a cut and becomes a margin:

```
margin per sale = (rate − 2.9%) × amount − 30¢
break-even      = 30¢ ÷ (rate − 2.9%)
```

| Rate | Margin over Stripe | Break-even sale |
|---|---|---|
| 7% (Free) | 4.1% | **$7.32** |
| 5% (Standard) | 2.1% | **$14.29** |
| 3% (Pro) | 0.1% | **$300.00** |

### ⚠️ Pro at 3% loses money on essentially every teen-sized sale

0.1% over Stripe's own rate means a $100 sale nets Fuime **−20¢**. The $19.99 subscription is
the entire margin, and whether the tier works depends on volume in a way that inverts:

```
 20 sales × $100/mo  →  −$4.00 margin + $19.99  =  +$15.99  ✅
200 sales × $10/mo   →  −$58.00 margin + $19.99 =  −$38.01  ❌
```

The second row is the ordinary shape of a teen business — stickers, small commissions, digital
downloads — so this is a live exposure, and it gets *worse* the more successful a Pro operator
is at low ticket sizes. It is implemented as specified rather than quietly corrected, because
pricing is the founder's call; the code documents it at
[pro.rb](app/models/event/plan/pro.rb) and the spec asserts the loss zone so nobody
"fixes" the sign later without realising.

### The floor: implemented, and what it actually fixes

`Event#fuime_fee_cents_on` now charges `max(rate × amount, MINIMUM_FEE_CENTS)` with a **50¢**
default (`FUIME_MINIMUM_FEE_CENTS`), applied **only under merchant-of-record** — under Connect
Stripe bills the family, so a floor there would be a surcharge on the smallest sellers rather
than the recovery of a Fuime cost. It is the single definition both the checkout and the
webhook fallback use. A fee waiver stays a waiver, and the fee never exceeds the sale itself.

Margin per sale, in cents, before and after:

| Sale | Free 7% | Standard 5% | Pro 3% |
|---|---|---|---|
| $5 | −9.5 → **+5.5** | −19.5 → **+5.5** | −29.5 → **+5.5** |
| $10 | +11.0 | −9.0 | −29.0 → **−9.0** |
| $20 | +52.0 | +12.0 | **−28.0** |
| $100 | +380.0 | +180.0 | **−20.0** |
| $300 | +1200.0 | +600.0 | 0.0 |

**The floor fixes Free, mostly fixes Standard, and does not fix Pro.** A minimum only bites
while `rate × amount` is below it, so it rescues small sales — and Pro's problem is not small
sales. At 3% the margin over Stripe is 0.1 points at *every* size, so Pro loses from about $7
all the way to $300.

Solving `max(rate·A, F) ≥ 2.9%·A + 30` for all A gives `F ≥ 30 ÷ (1 − 2.9%/rate)`:

| Rate | Minimum fee that would make it never lose |
|---|---|
| 7% | 52¢ |
| 5% | 72¢ |
| **3%** | **$9.09** — not a real option |

### ⚠️ Still open: Pro needs a rate change, not a floor

Pinned by `spec/models/event/plan_pricing_spec.rb` ("the floor does not rescue Pro"), so this
cannot be quietly forgotten. Three real options:

1. **Raise Pro to ~4.5–5%.** At 4% the margin is 1.1 points and break-even falls to $27.27;
   at 4.5% it is $18.75. This is the only option that fixes the middle of the range, which is
   where teen sales actually sit.
2. **Position Pro for high-ticket operators** — tutoring, dev work, commissions over $300 —
   and say so in the plan copy so it is never sold to a sticker shop. The $19.99 covers a
   low-volume operator and inverts on a high-volume one.
3. **Raise the subscription** enough to cover expected volume. Fragile: the loss scales with
   the operator's success, so the sub would have to be priced for the worst case.

Note that a 3% Pro rate *below* a 5% Standard rate also inverts the usual logic: the tier that
pays Fuime most per month is the one Fuime loses most on per sale.

Also raise `FUIME_MINIMUM_FEE_CENTS` to **75¢** if Standard's $10–$14 band matters — that is
the only remaining negative window outside Pro.

§8.4's open-questions list gains this as item 4.

---

## §9 — Whop as the substrate: an evaluation, not a decision (2026-08-15)

Raised by the founder after finding Whop's neobank template, Whop for Platforms and Whop
Cards. Recorded here because it is the first proposal that could close **three** open blockers
at once, and because one part of the reasoning behind it is wrong in a way that would be
expensive to discover later.

### 9.1 What is actually true

Verified against Whop's own documentation rather than a chat summary:

| Claim | Verdict |
|---|---|
| Whop for Platforms enrolls connected accounts under a platform company | **True.** A `Company` object per tenant, taking direct charges, with platform-side splits and commissions via API. |
| Whop Cards issues cards against an existing balance, no underwriting | **True.** The platform builds no card infrastructure. |
| Whop is the merchant of record, incl. VAT and sales tax | **True**, and it is why §8.4 item 2 cuts *for* Whop — see 9.3. |
| **Fuime would not need its own bank partner** | **True.** The licensed chain is Whop → Rain → issuing bank. This is the strongest argument in the proposal. |
| Therefore Fuime can market itself as a neobank | **False.** See 9.2. |

### 9.2 The one that is wrong, and why it matters

"We do not need a bank partner" and "we may call ourselves a bank" are different claims, and
only the first follows from the Whop stack.

**L5 restricts the word, not the custody.** Cal. Fin. Code § 562, 205 ILCS 5/46 and FDIC Part
328 Subpart B govern who may *hold themselves out* as a bank. A fintech sitting three layers
above an issuing bank is not one. **DFPI v. Chime is precisely this case**: Chime had genuine
bank partners and was still ordered to stop calling itself a bank. Whop's own copy is
consistent with that reading — "business banking on the Whop API" is developer documentation,
not consumer-facing "we are your bank."

Adopting Whop would improve the rails. It would not move one word of L5's forbidden vocabulary
or remove the standing footer disclosure.

### 9.3 What adopting it would actually change

**It is a substrate swap, not an integration.** If Whop is the merchant of record, **Fuime is
not** — and phases 3–6 were built on Fuime being the seller. Re-examined, in order of cost:

- `Fuime::PayablesLedger` — still correct in shape (an operator has a receivable, not a
  balance), but the debtor changes and every copy string naming Fuime as payer is wrong.
- **The 5% all-in fee** (§8.3 D1). Its whole justification was that Stripe charges *Fuime* for
  *Fuime's* sale. Under Whop-as-MoR, Whop's take comes first and Fuime's margin is what is
  left. `Event::Plan`'s ladder needs re-deriving, and the Pro tier is already underwater
  (§8.6).
- **1099-NEC filing** (§8.4 item 2) — **this is the argument for Whop.** The obligation is open
  precisely because leaving Connect means nobody files. If Whop is MoR, Whop files them.
- `FEATURE_SPONSOR_BANKING`'s boot guard demands a named partner bank. Whop would answer it.
- Phases 7 (disputes) and 8 (nexus report) largely evaporate — both are obligations Fuime holds
  *because* Fuime is the seller.

### 9.4 The blocking unknown, and it is the familiar one

**Whop's floor is 13 with guardian supervision, and 13–17 are flagged as minor accounts with
restrictions** — structurally the same model Fuime built, and a better fit than Stripe's
arm's-length 13.

But every Whop program that *pays a person* has an adult floor: Content Rewards is 18+, the
Affiliate Program is 18+. So the question is the one Stripe has not answered either:

> **Q9.** Can a guardian be the verified principal (KYB/KYC) on a Whop connected account whose
> day-to-day operator is a 16-year-old, with the guardian as obligor on chargebacks — and is
> that permitted by the Seller Terms rather than merely technically possible?

Until that has an answer in writing, this is not a plan. It is a candidate, and it is the same
class of unknown as §7 Q1/Q2/Q4: an infrastructure answer does not resolve a licensing question.

### 9.5 Recommendation

**Do not swap yet, and do not stop building.** Ask Whop Q9 in the same conversation already
owed to Stripe — the two answers are directly comparable and one call decides the substrate.
Meanwhile the work that is substrate-independent (onboarding, guides, own-business analytics,
the vetting and payout-review queues) is safe to build under either, and phase 6's dials and
approval gate survive both.

The failure mode to avoid is the one L8 already names: **letting the story lead the code.** The
last time that happened it was fuime.com describing a Stripe Connect architecture that did not
exist. Adopting a substrate because it makes a better sentence is the same error with a larger
blast radius.
