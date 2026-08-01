# FUIME — 48-Hour Hackathon Product Spec
### The pivot: HCB fork → teen business banking platform

> Read alongside CLAUDE.md. Where the two conflict, THIS file wins for the hackathon —
> we're optimizing for a working demo in 48 hours, not production safety.
> Rules that still hold no matter what: test-mode Stripe only, never edit the ledger
> engine internals (`CanonicalTransaction`, `HcbCode`), no global find/replace of
> "hcb"/"event" in code — user-facing strings only.

---

## 1. The one-liner (memorize it)

**Fuime is the legal and financial home for teen-run businesses.** Teens under 18 can't
open business bank accounts or sign contracts — Fuime gives them a real business account,
a parent as the legal signer, clean books, and tax paperwork. At 18, they graduate into
their own LLC with years of financial history. Forked from HCB, the open-source platform
that has done this for teen *nonprofits* since 2018.

**What judges must feel in 3 minutes:** "This is a real product solving a real legal
problem, and it already works because it's built on infrastructure that moves millions."

---

## 2. The pivot at a glance

| HCB (upstream) | Fuime (48h) |
|---|---|
| Organization = "Event" (nonprofit project) | "Business" (user-facing string change only) |
| Backed by Hack Club 501(c)(3) | Backed by ONE Fuime platform Stripe account (test mode) — ledger allocates per business, HCB's native model |
| Organizers (teens, no age logic) | Teen owner + REQUIRED parent guardian |
| Donations as money-in | Payment links + invoices from customers |
| Transparency page = accountability | Transparency page = public storefront/portfolio |
| No tax concept | Tax Tracker vs. IRS $400 self-employment threshold |
| No lifecycle end | Graduation at 18 (LLC export) |

## 3. Feature set

### MUST — demo dies without these

**M1. Fuime identity.** New name/logo/colors everywhere a user looks: layout, login,
landing, emails, page titles, transparency pages. Kill all Hack Club logos and copy.
Keep "forked from HCB by Hack Club (AGPL)" in the footer — at a hackathon,
"built on proven open source" is a flex, not a confession.

**M2. Guardianship.** New `guardianships` table + `date_of_birth` on signup.
Rules: under-18 business owner requires an active guardian link; under-13 signup blocked.
Flow for demo: teen signs up → DOB gate → "invite your parent" screen → parent accepts
(magic link) → business unlocks. Parent gets read-only access to the business +
a "Guardian" badge. Simplify anything except the DOB gate and the invite moment —
that moment IS the product thesis on screen.

**M3. Business creation.** HCB's org creation flow, restrung: name, what do you sell
(category chips: crafts/services/digital/food/other), and "your parent will be the
account signer" explainer. Rename all user-facing "event/organization" → "business."

**M4. Money in → ledger (single pooled account — HCB's own model).** ONE Fuime platform
Stripe account (test mode). Each business gets a Checkout payment link tagged with its
org id in metadata; the webhook maps the payment to that org through the EXISTING
ledger/allocation pipeline, exactly the way HCB allocates one bank account across
thousands of orgs. A test payment renders as a normal ledger line — with the 4% Fuime
platform fee shown as a ledger split (judges love a visible business model).
- Plan A: real webhook flow — Stripe CLI `listen` forwarding to localhost, metadata →
  org mapping, idempotent event handling.
- Plan B (if webhooks fight back — decide by Sat 2pm): Stripe CLI `trigger` + a rake
  task that injects the mapped transaction. Nobody watching a demo can tell.
- HARD RULE: this pooled model must never see a live key. In production it's the
  regulated merchant-of-record structure (Phase 2, lawyers + Stripe payfac conversation).
  Test mode only, forever, in this repo.

**M5. The ledger (already built — that's the point).** HCB's org home: running balance,
transaction list, transaction drawer with receipt upload. Touch only strings and colors.
This screen is where you say "this ledger design has processed millions of dollars."

**M6. Tax Tracker (NEW — the demo star).** A card on the business home + a `/taxes` page:
- Net income this year (computed from ledger: money in − money out)
- Progress bar toward the $400 IRS self-employment threshold
- Under $400: "You're under the filing threshold — we're watching it for you."
  Over: "You'll owe self-employment tax — here's your parent packet." + a
  **Download Year-End Packet** button (generated PDF/CSV: income, expenses, net, the
  one paragraph a parent hands their accountant).
This is ~a day of work for the most differentiated 30 seconds of the demo. No teen
fintech on earth shows a kid their tax threshold.

**M7. Storefront (transparency mode, reframed).** Public `/b/[slug]`: business name,
what they sell, "Official on Fuime · Parent-signed account ✓" badge, the payment link
button, and (toggle) the public ledger. Pitch line: "your business's public proof it's real."

### SHOULD — do these if MUSTs are done

**S1. Graduation page.** `/graduate`: timeline of the business's history, "Days until 18"
countdown, and a mock "Export to LLC" flow (static wizard, 3 steps, ends on "Fuime will
file your Articles of Organization"). Pure narrative gold, ~2–3 hours, mostly frontend.

**S2. Parent dashboard.** One page for the guardian: businesses they sign for, balances,
recent transactions, tax status. Even a simple read-only list sells "parents see everything."

**S3. Invoices.** HCB's invoice module already exists — restring it and show sending one.

**S4. Card mock.** A beautiful (fake) Fuime debit card design on a "Coming in Phase 1"
page. Do NOT wire Stripe Issuing. 1 hour, makes the roadmap tangible.

### WON'T — hide these, don't build or fix them

Real money · live keys · KYC · card issuing · ACH/checks/wires · donations · grants ·
G Suite · reimbursements (hide nav) · mobile · email deliverability (use letter_opener
or console links for magic links) · admin console polish (it exists; leave it).
Hide via nav removal + route disable. Delete nothing.

## 4. UI spec

**Brand: we ARE the HCB design system.** This is a platform revamp, not a redesign.
Keep HCB's entire UI as-is: layout, components, typography, spacing, cards, buttons,
badges, the ledger's visual language — all of it. It's a mature design system that's
been refined against real teen users for years; it is the single biggest thing we
forked FOR. Rules:
- **New pages must look like HCB built them.** /taxes, /graduate, guardian pages, the
  parent dashboard: compose them ONLY from existing HCB partials, helpers, components,
  and CSS classes. Before building any new page, find the most similar existing HCB
  page and copy its structure. If a new page needs a component HCB doesn't have, you're
  designing too much — simplify until it doesn't.
- **No new CSS frameworks, no new fonts, no new spacing scales.** Match whatever the
  neighboring view uses.
- **Identity changes only:** the Fuime wordmark/logo replaces HCB's, and (optional,
  ~30 min, decide Sat AM) swap the primary accent CSS variable from HCB red to Fuime
  blue `#2242FF` — one variable, whole app follows. Everything else stays. If keeping
  red feels too much like wearing your employer's jersey, this one variable is the
  entire differentiation budget.
- **Official ✓** stays as the signature *copy* moment (payment received → "Official ✓",
  parent accepts → "Official ✓") — implemented with HCB's existing success/badge
  components, not new ones.

**Page-by-page (K = keep HCB, R = restring/restyle, N = new):**
- Landing page — N (simple: one-liner, problem stats, screenshot, CTA). 2h max, do it last.
- Signup/login — R: add DOB step; teen path forks to guardian invite. Magic-link UX stays.
- Guardian invite/accept — N: two small pages. The accept page shows what they're
  signing for in plain English + big "I'm the adult on this account" button → Official ✓.
- Business home (org page) — R: balance header, ledger, + NEW Tax Tracker card,
  + "Share your storefront" card.
- Transaction drawer — K (receipts, comments). Maybe recolor.
- /taxes — N (M6 spec above).
- Storefront /b/[slug] — R of transparency page + verified badge + pay button.
- /graduate — N (S1).
- Parent dashboard — N (S2).
- Everything else HCB has — leave it, hide nav links to nonprofit modules.

## 5. Data model changes (all additive)

```ruby
create_table :guardianships do |t|
  t.references :guardian, foreign_key: { to_table: :users }
  t.references :minor,    foreign_key: { to_table: :users }
  t.integer :status, default: 0   # pending / active / revoked
  t.datetime :agreement_signed_at
  t.timestamps
  t.index [:guardian_id, :minor_id], unique: true
end

add_column :users,  :date_of_birth, :date
add_column :events, :business_category, :string
add_column :events, :storefront_tagline, :string
```
Tax numbers are computed live from the ledger — no new money tables. Never store a balance.

## 6. The 3-minute demo script (build toward exactly this)

1. **Cold open (20s):** "Meet Maya, 16. She makes $700/month selling prints. Stripe,
   Etsy, Shopify — all require 18+. Her money runs through her mom's Venmo." 
2. **Signup (30s):** Maya signs up → DOB gate → "Fuime needs your parent's signature"
   → mom's magic link → mom accepts → **Official ✓**. (Two browser windows, pre-staged.)
3. **The business (40s):** Maya's business page: real ledger, running balance, receipts.
   "This ledger isn't a prototype — it's HCB's engine, which has moved millions for
   teen nonprofits. We forked it and pointed it at commerce."
4. **Money in (40s):** Open storefront → customer pays via payment link (test card
   4242…) → ledger line appears → 4% Fuime fee visible. "That's our revenue model, live."
5. **The kicker (40s):** Tax Tracker crosses $400 → "Maya just legally became a
   taxpayer and Fuime is the only one who noticed." Download the parent packet.
6. **Close (10s):** Graduation page countdown. "At 18, Maya exports to her own LLC
   with 2 years of books. Fuime: where teen businesses become official."

Pre-seed Maya's account Saturday night. NEVER live-create data you can pre-stage.

## 7. Two-person / two-day plan

**Person A (backend/infra) · Person B (UI/brand).** Sync at every checkpoint (~4h apart).

**Sat AM** — A: boot app + seed data + rspec baseline; start guardianship migration/models.
B: identity swap only (Fuime wordmark in layout, favicon, accent-variable decision),
kill Hack Club logos/copy, restring nav + org pages to "business" language. With no
brand kit to build, B starts guardian invite/accept screens Saturday afternoon —
composed from existing HCB page patterns.
**Sat 2pm checkpoint** — webhook spike verdict: Plan A (real webhook flow) or Plan B
(CLI trigger + rake injection). Decide, don't debate.
**Sat PM** — A: money-in path end-to-end (whichever plan) + guardianship rules done.
B: signup/DOB/guardian-invite screens; business-creation restring.
**Sat night** — merge everything to main; seed "Maya" demo account; both run the demo
path once; list breakages.
**Sun AM** — A: Tax Tracker computation + /taxes + packet download; fix Sat breakages.
B: storefront page + Tax Tracker card UI + Official ✓ states.
**Sun 1pm checkpoint** — MUSTs done? If yes → S1 graduation page (B) + S2 parent
dashboard (A). If no → cut SHOULDs, harden the demo path only.
**Sun PM** — landing page (B), demo rehearsal ×3 with a timer, record a backup screen
recording of the full flow (projector wifi is where demos go to die), pre-stage both
browser windows, write the 6-line pitch on a card.

**Standing rule:** anything broken at a checkpoint that isn't on the demo path gets
hidden, not fixed.

## 8. Definition of done (the only checklist that matters)

- [ ] Teen signup with DOB gate → parent invite → parent accept works twice in a row
- [ ] Test payment → ledger line with fee shown, twice in a row
- [ ] Tax tracker crosses $400 live off Maya's seeded ledger
- [ ] Packet downloads
- [ ] Storefront loads logged-out on a phone
- [ ] Zero Hack Club logos visible anywhere on the demo path
- [ ] Every NEW page (taxes, guardian, storefront, graduate) is visually
      indistinguishable from a native HCB page — same components, same rhythm
- [ ] Backup screen recording exists
- [ ] Both of you can give the demo alone
