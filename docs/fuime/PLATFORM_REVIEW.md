# Is Fuime a full business platform? — an honest audit

**2026-08-16.** Written against `fuime/e2e-and-security`. The question asked was whether Fuime
is *in fact* a full business platform, so this answers it with the gaps named rather than the
wins listed.

## The short answer

**Yes for services, no for anything else, and one gap is load-bearing.**

A 16-year-old can now go from nothing to a paying business without leaving Fuime: apply, pick
what kind of business, get vetted, list what they sell at their own price, publish a storefront,
take a card payment, see the money explained, and be paid on a weekly run. That journey is
covered end to end by `spec/requests/fuime_full_business_flow_spec.rb` — one long example on
purpose, because a suite of green units and a broken journey is the failure this exists to
catch.

**What that spec does not prove is Stripe.** `PaymentLinkService` is stubbed at the boundary. It
asserts Fuime asks for the right charge, not that Stripe accepts it. The only thing ever run
against real Stripe is the direct-charge shape (2026-08-14, `EMBEDDED_CONNECT.md` §7); **every
webhook path is still documentation-derived.** A green suite is not a working payment.

## What exists, by what a founder would call it

| A business needs to… | State |
|---|---|
| Start and be approved | ✅ Application → business-type fork → vetting queue |
| Say what it sells, at its own price | ✅ `Fuime::Offer` |
| Have a page customers can buy from | ✅ Storefront with Buy buttons |
| Take a card payment | ⚠️ Built; the direct-charge shape is verified, the webhook is not |
| Know what it earned and what was deducted | ✅ `Fuime::PayablesLedger`, reconciling by construction |
| Get paid on a schedule | ✅ Weekly batches, reserve, caps, admin review |
| Keep receipts and books | ✅ Inherited from HCB, untouched |
| Know what it owes in tax | ✅ `Fuime::TaxTracker`, 1099 collection built |
| Spend from the business | ⚠️ Cards exist behind a default-off flag with no funding rail |
| Handle a refund or chargeback | ❌ Reversal posting exists; **clawback does not** |
| File its 1099s | ❌ Collection built, filing not |
| Sell physical goods or digital products | ❌ Services only, by design (§8.3 D3) |

## The gap that is load-bearing

**Disputes and clawback (§8.5 phase 7) is the only missing piece that can lose money.**

The reversal posting exists and debits the operator's ledger, and phase 6's rolling reserve
absorbs part of it. What does not exist is the case the reserve does not cover: an operator who
stops selling after a chargeback. There is no measurement of that residual, no admin visibility
into it, and no decision recorded about who owes it — §7 Q3 (does the guardian countersign as
obligor, or does Fuime absorb it?) is still with counsel.

Everything else on the ❌ list is either a deliberate scope decision (physical goods), a vendor
integration (~$3/form 1099 filing), or blocked on a rail decision (cards). This one is an
exposure with no owner.

## Security review — findings

Reviewed the surface added since 2026-08-15: the public checkout, the offers CRUD, the payout
batch admin, and the business-type step.

### 🔴 Fixed — ledger memo injection (this branch)

**A stranger could corrupt a teenager's earnings page.** The bracketed `[fuime_…]` suffix is how
`Fuime::PayablesLedger` classifies every ledger line, and two paths put human text into those
memos:

- `Fuime::Offer#payment_description` — the operator names their own offer.
- `Fuime::CheckoutsController#payment_description` — **an anonymous, unauthenticated buyer**
  types "what's this for?" on a public page.

An offer named `Mow [fuime_fee_x`, or a stranger typing it into a checkout, produces a sale
whose memo classifies as *Fuime's platform fee* — a $35 sale reported to a teenager as a $35 fee
they paid. `FeeEngine::Create` reads the same marker to decide whether Fuime's cut has already
been taken, which is the more serious half of the same primitive.

Fixed by `VentureLedger.sanitize_memo_text`: **refused** on the operator path (there is a person
to tell) and **stripped** on the buyer path (there is not, and a validation error on a checkout
is a lost sale for a child over a character they had no reason to avoid).
`spec/services/fuime/ledger_memo_injection_spec.rb` covers both, and demonstrates the corruption
on the real classifier rather than asserting about the sanitiser in the abstract.

**Bounded, and worth stating precisely:** the *money* was never at risk. `net_payable_cents` is
the ledger balance, not a memo classification, and `#other_adjustments_cents` is a residual by
construction — so the totals always reconciled even while the components lied. That design
choice is what kept this a display bug instead of a payout bug.

### ✅ Checked and correct

- **Price tampering.** A posted `amount` alongside an `offer_id` is ignored entirely; the price
  comes off the record. Without this a stranger buys a $35 lawn mow for $1 by editing a form
  field. Specced.
- **IDOR on offers.** Checkout scopes to *this venture's published* offers, so another venture's
  id, a draft, an archived offer and a stale link all refuse rather than falling back to a free
  amount. The operator CRUD scopes through `@event.fuime_offers`, so an operator cannot act on
  another venture's offer by id — the same hazard `decide_payout?` documents.
- **Authorization split.** `manage_offers?` is the operator; the guardian reads. Deliberately
  the inverse of payouts (§8.3 D2 — a third party setting the rate is a third party whether it
  is Fuime or a parent).
- **XSS.** All operator text renders through ERB's default escaping; no `raw` or `html_safe` on
  any offer field.
- **Storefront privacy.** `Event#selling_blockers` names operators and states their ages. The
  end-to-end spec asserts none of them, and no operator email, appears on the public page.
- **Payout run authorization.** Generate/approve/mark-paid/cancel are admin-only at the service
  layer, not just the controller.

### ⚠️ Noted, not fixed

- **Offer text is operator-authored and renders publicly**, and under merchant-of-record Fuime
  is the seller of record for whatever it describes. There is no moderation queue. Vetting is
  the compensating control today, and it reviews the *venture*, not each offer — a vetted
  operator can later publish an offer nobody read. Worth a decision before real volume.
- **`nav` hiding is cosmetic.** `fuime_module_hidden?` removes entry points; the real control is
  `DisabledModules` at the request layer. That is the correct division and is stated here so
  nobody mistakes the nav change for a security boundary.

## Identity and copy

- The L5 forbidden vocabulary (`bank`, `neobank`, `deposit`, `savings`, `FDIC`, …) is enforced
  by an existing spec sweeping mailers and helpers. Nothing added on this branch introduces one.
- `PayablesLedger#disclosure` still says "not a bank balance, not a deposit" and the end-to-end
  spec asserts it, so the framing survives a rewording of the page.
- The offers page and storefront say the price is the operator's, in their own words, and a spec
  greps the rendered HTML for a numeric placeholder and for "most people charge"-shaped copy.

## What I could not verify

**Smoothness.** No browser was driven. Everything above is asserted at the request and model
layer, which catches dead links, wrong prices and leaked data — and catches nothing about how
the thing feels. A real click-through on a seeded database is the next honest step, and it is
also where `stripe login` should finally be run (`EMBEDDED_CONNECT.md` §7), because a click-
through that stops at the payment button proves less than half the journey.
