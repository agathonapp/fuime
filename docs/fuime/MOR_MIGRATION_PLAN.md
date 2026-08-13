# Umbrella merchant-of-record migration — plan, not yet approved

Status: **plan approved 2026-08-13; Phase 1 in progress on `fuime/mor-pivot-phase1`.**
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
