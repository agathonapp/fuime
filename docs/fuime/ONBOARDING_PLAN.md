# Onboarding plan — get a teen into the product

**2026-09-11.** Plan of record for the founder-priority onboarding cut.
Implements TEEN_GROWTH_GAPS G2 (stop parking on "Waiting on Fuime") and the
field-cut / first-sale checklist / product-wizard work. Does **not** replace
G1 (waitlist invite, already shipped) or G5 (guardian reminders, already
shipped).

**Trust this for:** the teen path from marketing CTA → first draft offer.
**Do not trust this for:** payouts, Plaid, Connect, Stripe mode, parent
dashboard, or under-13.

---

## 0. Target flow

```
fuime.com primary CTA
    → /signup  (APP_ORIGIN/users/auth?signup=true)
    → email code
    → short profile (name + write-once 13+ + terms)
    → short business wizard (type → describe → country / parent email)
    → Submit
    → inside the venture, FounderProgress checklist
    → multi-screen "add something to sell"
    → publish (sale terms + vetting/eligibility)
    → share (copy / share / QR)
```

A teen can sell under merchant-of-record before a parent does anything.
Parents still gate **payouts**. Payouts are out of scope here.

---

## 1. Five moves

| # | Move | Why |
|---|---|---|
| 1 | Cut fields the system does not need | Signup asked phone / photo / preferred name. The wizard re-asked name, 13+, how-did-you-hear, political, previously-applied. None of those decide admission or selling. |
| 2 | Admit on submit | Approve + activate are HCB fiscal-sponsorship gates. Fuime's publish gate is vetting. `Fuime::FounderAdmission` stands the venture up; it does **not** vet. |
| 3 | FounderProgress on the teen home / venture | The six-stage checklist already existed on the admin cohort roster. Founders could not see it. |
| 4 | Marketing primary CTA → live signup | Waitlist stays. It is no longer the only door. |
| 5 | Multi-screen product creation | `/offers` listing stays. Creating a new offer is a wizard: what → price → storefront → review/terms → share. |

Moves 1–4 are Phase A. Move 5 is Phase B. One PR is fine if cohesive.

---

## 2. PR order (if split)

1. Field cuts + teen_led pre-answer + FounderAdmission + FounderProgress on home.
2. Marketing CTA.
3. Offer wizard.

Shipped together when the seams share specs (`family_signup_flow_spec`,
`fuime_full_business_flow_spec`, `offers_controller_spec`).

---

## 3. What must NOT move

- COPPA / age floor. Write-once 13+ checkbox stays. **No date of birth.**
- Guardian requirement. Under MoR it gates payouts, not selling. Under Connect
  `activation_blockers` still refuses a guardianless minor.
- Vetting-before-publish. Unvetted ventures cannot publish.
- MoR seller-of-record copy. Ninth Street Labs, LLC is the legal seller.
- Plaid, payout originator, Connect onboarding, `/payments/setup`,
  `ProvisionConnectAccountJob`, `STRIPE_MODE`, `FUIME_DEMO_SANDBOX`.
- A second auth system. Login codes stay.
- Price suggestions anywhere on the offer wizard (§8.3 D2).
- Ledger engine internals (CLAUDE.md Rule 3).
- Renaming `Event` / `HcbCode` (Rule 6).

---

## 4. Field cuts (the list)

**Signup (onboarding branch of `users/edit`):** keep full name, 13+ checkbox,
terms. Drop phone, photo, preferred name. Settings still has those for later.

**Application:**
- Do not re-ask full name or 13+ when already on the user.
- Do not ask "are you under 18?" after 13+. Pre-answer `teen_led` from
  `!user.known_adult?`.
- Drop required how-did-you-hear (`referrer`).
- Drop political activity and previously-applied (HCB leftovers).
- Keep: business type, name, description, country (sanctions), parent email
  when `needs_guardian?`.

---

## 5. Admission seam

`Event::Application#mark_submitted` still sends the guardian invite (and
does **not** swallow `InvalidInvite` — the founder sees it). Then:

1. `Fuime::CohortAdmission` if a live cohort is attached (approve + activate
   + vet, unchanged).
2. Else `Fuime::FounderAdmission` (approve + activate, **no vet**).

If activation is blocked (Connect + no guardian, free-plan slot, …) the
application stays submitted/approved and `next_step` names the blocker —
never "Waiting on Fuime to finish setting up your account".

---

## 6. FounderProgress (teen-facing)

Same six stages as the admin roster: `applied`, `venture_created`, `vetted`,
`can_sell`, `listed`, `sold`. `next_action` is rewritten for the founder
("Draft something to sell") rather than the organiser ("Approve them to
sell"). Guardian invite state is a separate row, not merged into the sell
funnel.

---

## 7. Follow-ups (do not block this PR)

- Parent one-email / parent dashboard.
- Guardian invite reminders are already G5.
- Waitlist "invite next N" is already G1; this PR only stops making the
  waitlist the primary door.
- Offer-level moderation (`PLATFORM_REVIEW.md`) before turning vetting off.
