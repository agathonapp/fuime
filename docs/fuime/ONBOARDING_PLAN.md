# Onboarding plan — the easiest way for a teen and a parent to get on Fuime

**2026-09-10.** Grounded in `main` at `c824a4de2` (G10 merged). Every claim below
was read from the code on that commit; file references are exact. No product
code changed to produce this document.

**Trust this for:** what the teen and the parent actually go through today, what
"the best and easiest onboarding" should look like for each, and the ordered
list of PRs that gets there.

**Do not trust this for:** live-money gates, counsel, or Stripe underwriting.
Those stay in `LAUNCH_SPEC.md` §0–§2 and `LEGAL_RESEARCH.md`. Nothing here
loosens a control — §3 lists what must not move.

**Status 2026-09-11: Phase A shipped** on branch `fuime/onboarding-a-copy-routing`
(UPSTREAM_DIVERGENCE.md "2026-09-11 — Onboarding Phase A"). The same day a parallel
session shipped PRs #98–#103 to `main`, which cover most of Phases B and C — §0.5
reconciles the two so this stays the one plan. Corrections the build forced on this
plan are marked *[corrected 2026-09-11]*. **Still open after the merge: B3, C1, D1,
E1–E3.**

**Production posture assumed throughout:** merchant-of-record
(`render.yaml`: `FEATURE_MERCHANT_OF_RECORD=true`, `FUIME_MINIMUM_OPERATOR_AGE=13`).
Under MoR a teen can sell before a parent has done anything; the parent gates
*payouts*. That single fact shapes both flows.

---

## 0. One-screen answer

| | Teen today | Teen target | Parent today | Parent target |
|---|---|---|---|---|
| Screens to "in the product" | 4 | 3 | 6 | **1** |
| Form fields before first screen of product | 5 (name, preferred, phone, 13+, photo) | 2 (name, 13+) | 5 — including **"I'm 13 or older"** | 1 (name, only if unknown) |
| Emails they must open | 1 (login code) | 1 | 2 (invite, then login code) | **1** (the invite signs them in) |
| Wizard pages to submit a business | 5 + review | 3 | — | — |
| Human gates before they can *enter* their venture | 2 (approve, activate) | **0** | — | — |
| Human gates before they can *publish* | 3 | 1 (vetting, with an email when done) | — | — |
| Progress visible after submit | dies at activation | checklist to first sale | none | dashboard that shows the money |
| Emails that were promised and never sent | 1 ("we'll email you when approved") | 0 | all of them ("important notifications") | 0 |

**The five moves:**

1. **Cut every field the system does not need.** Phone, photo, "how did you
   hear", a second name box, an "under 18?" radio after a 13+ checkbox.
2. **Let the teen into their venture the moment they submit.** Approve and
   activate are HCB's fiscal-sponsorship intake gates. Fuime's real gate is
   vetting, and an unvetted venture already cannot publish. Stop making
   founders stare at "Waiting on Fuime" when they could be writing their
   first offer.
3. **Put the checklist the admins already have in front of the teen.**
   `Fuime::FounderProgress` computes six stages and a `next_action`. It is
   rendered only on the admin cohort roster.
4. **Make the parent's whole job one email and one page.** The invite link
   signs them in (same pattern as the waitlist invite), the accept page
   collects the one missing fact, and they land on a page that shows them
   the money.
5. **Send the emails the copy already promises.** "We'll email you when
   yours is approved" and "you'll receive important notifications" are both
   in shipped copy and both have no mailer.

---

## 0.5 What landed on `main` the same day (PRs #98–#103) — reconciled

A parallel session shipped a founder-priority onboarding cut while Phase A was
being built, with its own shorter `ONBOARDING_PLAN.md` (five moves, PR order,
must-not-move list). That file's content is folded in here; the two plans agreed
on every move and differed only in scope. Mapping:

| Landed on `main` | This plan's item | Status |
|---|---|---|
| Signup asks name + write-once 13+ + terms only; application stops re-asking name/13+, pre-answers `teen_led` from `!known_adult?`, drops required `referrer`, political and previously-applied | A2, C2 | **Shipped** (#102). Phase A adds the copy on top: "What should we call you?", the 13+ helper, "Let's go", the MoR/Connect terms clause, and drops the settings-branch phone `required`. |
| Admit on submit: `Fuime::FounderAdmission` approves + activates, never vets; cohort code still auto-vets; `next_step` names a blocker instead of "Waiting on Fuime" | C3 | **Shipped** (#102). §6 decision 1 is answered: yes. |
| `Fuime::FounderProgress` on the teen home and venture page, with a separate guardian status line and invite link | B1 | **Shipped** (#102). |
| Marketing primary CTA → `/signup` on index / parents / pricing | A1 | **Half shipped** (#102): those three pages are `CLOSED`; the live front door `start.html` still had no link into the app and every page kept the "early access / your turn" queue copy. Phase A finishes it: `/get-started`, CTA on `start.html` + `start-scroll.html`, queue copy removed, waitlist relabelled for cohorts, L8 sweep pinned by `spec/fuime_marketing_copy_spec.rb`. |
| Offer creation as a wizard: what → price → storefront → review (sale terms) → share, with copy / share / QR (`fuime/offers/_share_link`) | B2, D2 | **Shipped** (#102). |
| Site and legal copy for MoR: Ninth Street Labs, LLC named as seller of record, guardian as legal payee and clawback obligor; guardian agreement `2026-09-11-v3` | A1, A6 | **Shipped** (#99). The entity naming is kept and carried into Phase A's site copy. v3 still says "software platform, not a bank" and its §2/§4 say consent gates "create or run" and revocation ends operation — false under MoR — so Phase A's agreement text is **v4** (`2026-09-11-v4`); v3 stays resolvable for anyone who signed it. |
| Draft while unvetted, publish still reviewed; nav honesty; Playground Mode; demo sandbox | — | **Shipped** (#98, #101, #103). Outside this plan. |

Their must-not-move list (13+ checkbox, no DOB, guardian gates payouts under MoR,
vetting before publish, MoR seller-of-record copy, no second auth system, no
price suggestions in the offer wizard, ledger internals, no `Event`/`HcbCode`
rename) is a subset of §3 here plus one new item worth keeping: **no price
suggestions anywhere on the offer wizard.**

---

## 1. What a teen goes through today

Verified against `main`, with the friction named where it bites.

| # | Where | What they see | Friction |
|---|---|---|---|
| 1 | fuime.com — the real front door is `site/start.html` (server.js `CLOSED` sends `/home`, `/index`, `/pricing`, `/parents` to `/`, which serves the "dive"); `index.html:1128-1149` is dark *[corrected 2026-09-11]* | Primary CTA "Get early access" → **waitlist form**. No link into the app at all | The app is open. Nothing on the site says so. Every warm visitor is parked in Redis. Reopening the three closed pages is the founder's call (§6). |
| 2 | `/users/auth` (`app/views/logins/new.html.erb:2`) | Title **"Sign in to Fuime"**, bare email box | Sign-up is a `?signup=true` param nothing on the site sets. No explanation of what Fuime is or what happens next. |
| 3 | Code page (`logins/email.html.erb`) | "Enter login code" | Fine. This is the one email a teen must open. |
| 4 | Profile form (`app/views/users/edit.html.erb:30-117`) | "Create your account" — full name, preferred name, **mobile phone (required)**, "I'm 13 or older", profile picture | Phone is `required="required"` in HTML and required by `logins#complete` (`logins_controller.rb:180`), and used nowhere downstream (`Event::Application#user_ready_to_submit?` dropped it). Photo is noise at signup. |
| 5 | Home (`static_pages/index.html.erb:167-176`) | "Ready to start your first business?" → **New business** | Fine as a first screen. Becomes a dead end the moment an application exists: no progress, no guardian state, no next action. |
| 6 | `/applications/new` (`event/applications/_begin.html.erb:58-73`) | **"Are you under 18?"** radio | The user just confirmed 13+. For anyone not `known_adult?` the answer is derivable; ask only "I'm 18 or older" as an opt-out. |
| 7 | business_type (10%) | Category cards + service picker | Good page. Keep. |
| 8 | project_info (25%) | Name, description, website, political?, previously applied | Political / previously-applied are HCB nonprofit intake. |
| 9 | personal_info (50%) | Full name **again**, 13+ **again** if unanswered, country (required), **"how did you hear" (required)**, accessibility, parent email | Two duplicates and one analytics field standing between a 14-year-old and selling. |
| 10 | review (75%) → submit | Confetti, then `#show`: Submit ✓ → **Await review** → Start selling | Then silence. `Event::Application#next_step` says "Waiting on Fuime to finish setting up your account" until an admin clicks approve **and** activate. |
| 11 | Activation email (`event/application_mailer/activated.html.erb`) | "Invite other members of your team", "Review your business details" | Neither is "list something to sell". Vetting is not mentioned; the venture still cannot publish. |
| 12 | Venture → What you sell (`fuime/offers/index.html.erb`) | Sale-terms acknowledgement card, add form, Publish | Acknowledgement is right (MoR, `c13edb6ef`) and enforced at publish (`offers_controller.rb:96`). Its placement as a wall above the form reads as paperwork. |
| 13 | Published offer | Pay link in a **readonly input with `onclick="this.select()"`** | No copy button, no share sheet, no QR — with `clipboard_controller.js`, `qr_code_controller.js` and `rqrcode` already in the repo. |
| 14 | `_selling_blockers.html.erb:26-28` | "Fuime reviews every new business before it can sell. **We'll email you when yours is approved.**" | No such mailer exists. `Event#record_vetting_decision!` sends nothing. |

Guardian state is invisible to the teen everywhere except a user-menu item
(`application/_user_menu.html.erb:30-35`). If the auto-invite from the
application fails (`Event::Application` `mark_submitted`, `:211-212` swallows
`InvalidInvite`), the teen is never told.

Two things the traces got right that are **not** bugs and should stay:

- The 13+ checkbox instead of a date of birth is a decision
  (`AddAgeAttestationToUsers`, 2026-08-20; `TEEN_GROWTH_GAPS.md` G7). Do not
  re-add DOB to fix onboarding.
- The `teen_led` question exists because the profile form deliberately
  cannot make anyone an adult (`User` attestation is write-once; `adult_18_plus`
  only via guardian accept). The fix is to *pre-answer* it, not remove it.

---

## 2. What a parent goes through today

There is **no parent-first entry.** `GuardianshipPolicy#new?` refuses known
adults; `GuardianshipsController#create` hardcodes `minor: current_user`;
`site/parents.html` has one CTA and it is the waitlist. Every parent arrives
by one email, triggered either by the teen's application submit
(`Event::Application#mark_submitted` → `Fuime::GuardianInviteService`) or by
the teen filling `/guardian/new`.

| # | Where | What they see | Friction |
|---|---|---|---|
| 1 | Invite email (`guardianship_mailer/invite.html.erb`) | "{Teen} invited you to be their parent or guardian on Fuime… legal signer and responsible adult… Review guardian invitation" | Vague on *why now*. The one line that moves a parent — **"they can sell but they cannot get paid"** — appears only in the day-3 / day-6 reminders (`invite_reminder.html.erb:20-23`), never in the first email. |
| 2 | `/guardian/:token` signed out | Redirect to login: "Please sign in to accept this guardian invitation." | The token was mailed to their inbox. That *is* inbox control. Now they have to prove it a second time. |
| 3 | Login code email | Second email, six digits | Round trip #2. |
| 4 | Profile form (same `users/edit.html.erb`) | Full name, preferred name, **phone (required)**, **"I'm 13 or older"**, profile picture | A parent is asked to confirm they are 13. The spec comments on it (`spec/requests/family_signup_flow_spec.rb:86-98`). The return path does survive this page via a hidden field (`edit.html.erb:101`) — the earlier read of this as a lost redirect was wrong — **but** a parent with a half-finished session who reopens the email link is bounced to `/settings` with no way back (`guardianships_controller.rb:5` skips `redirect_to_onboarding` only for `new`/`create`). |
| 5 | Accept page (`guardianships/show.html.erb`) | "You've been invited", five bullets, agreement in a scroll box, checkbox, **"Agree & activate their account"** | The page itself is good. The button is false under MoR (accepting unblocks payouts, not activation). `hide_footer` (`guardianships_controller.rb:7`) strips the not-a-bank disclosure from the one page a new adult reads before signing — the layout's own comment says this reader is who it exists for. |
| 6 | After accept | `redirect_to root_path`, flash "You are now {Teen}'s guardian on Fuime!" | Dropped on a dashboard built for teens. No "here is what you can see", no link to `/guardian`, no mention of payout approval. |
| 7 | `/guardian` (`guardianships/index.html.erb`) | Per ward: status, per venture: **Ledger, Transactions**, settled balance | Every guardian *action* page is missing from the venture nav: Payouts, Payout account, Taxes are gated on `organizer_signed_in?` (`events_helper.rb:154, 178, 252`), which a guardian never is by design. Policy says yes; nav says no. |
| 8 | Later | Nothing | Zero guardian-addressed mailers after accept. The agreement they signed (§3), the invite, and the accept page all promise "important notifications." |
| 9 | Expired link | "Invalid or expired invitation link." → root | No resend affordance. Recovery lives on `/guardian` (signed-in) or the admin page. |
| 10 | Wrong account | "This invitation was sent to {email}, but you are logged in as {other}." → root | No sign-out link. |
| 11 | `/billing` before accepting | Refused — `known_adult?` is only ever set by `#accept` | Correct ordering, never explained. |

Latent, one env var away: with `FUIME_DOCUSEAL_TEMPLATE_ID` set, the parent gets
a **second** same-day email from `Contract::PartyMailer#notify_cosigner` asking
them to sign a *different* document on DocuSeal, with reminders at
3/7/14/30/45/60 days. Neither signature satisfies the other's gate.

---

## 3. What "best and easiest" means here — and what does not move

**Principles**

1. **Sell first, paperwork when there is money.** MoR already allows it. Every
   screen and email should say it plainly: *you can start now; your parent
   signs before you get paid.*
2. **One email per person per action, ever.** The login code is the teen's
   one. The invite is the parent's one. Nothing else needs an inbox trip.
3. **Never ask a question the system already knows.** Name once. Age once.
   Under-18 derived from the attestation. Phone never.
4. **Every wait has a face, an ETA, and an email at the end.** If Fuime is the
   one who has to act, the screen says so, says how long, and the mailer fires
   when it is done.
5. **The parent gets a pitch, a page, and a tap.** Then a dashboard that shows
   the money and a message every time money moves.
6. **Friction has to earn its place** (see `fuime-design-judgment`): before any
   safer-but-worse choice, name the concrete attack it stops.

**What does not change** (the controls the traces confirmed and this plan keeps
bit-for-bit):

- 13+ attestation, write-once, honor-system without DOB (`User#attest_minor_13_plus!`).
- `adult_18_plus` reachable **only** through `GuardianshipsController#accept`.
- Versioned agreement, IP/UA/version recorded, append-only partials
  (`Guardianship::CURRENT_AGREEMENT_VERSION`).
- Guardian as a parallel association, never an `OrganizerPosition` (§3 of the
  agreement: the minor cannot turn it off).
- Operator vetting as a human gate before publish (`Fuime::OperatorEligibility`).
  `PLATFORM_REVIEW.md`: do not remove until offer-level moderation exists.
- Guardian gate at the payout seam (`Event#payout_setup_blockers`,
  `EventPolicy#decide_payout?`, `PayoutRequest#approver_must_be_the_responsible_adult`).
- L4: no ID imagery, ever. L5 vocabulary. L6: under-13 refusal stays. L7:
  transactional-only mail to minors, nothing 12–6 a.m.
- Lapsed family plan never freezes payouts or the ledger.

---

## 4. The target flows

### 4.1 Teen — "sell something before dinner"

**Screen 1 — fuime.com.** Primary CTA **Start your business** →
`app.fuime.com/users/auth?signup=true`. Secondary: "Parents: what you'll be
asked to sign" → `/parents`. Waitlist stays only as a form for schools and
closed cohorts, labelled as such.

**Screen 2 — `/users/auth?signup=true`.**
> **Start your business on Fuime**
> Free to start. About two minutes. Under 18? You can set up now and sell as
> soon as Fuime approves your business — a parent or guardian signs off before
> you get paid.
>
> *[corrected 2026-09-11: "start selling now" was false — human vetting comes
> before any sale.]*
> [email] **Continue**
> Already have an account? Sign in

**Screen 3 — code.** Unchanged.

**Screen 4 — profile.**
> **What should we call you?**
> Full name · Preferred name (optional)
> ☐ I'm 13 or older — *Fuime is for founders 13 and up. Under 18, a parent or
> guardian joins your account later.*
> By continuing you agree to the Terms and Privacy Policy. [Let's go]

No phone. No photo. Both stay in Settings.

**Screen 5 — home, with a checklist.** Rendered from `Fuime::FounderProgress`
(`applied → venture_created → vetted → can_sell → listed → sold`) plus a
guardian side-track:

> **Your first sale**
> ✓ Create your account
> ○ Tell us about your business — *3 minutes* → Start
> ○ Fuime approves your business — *we check every new business by hand;
>   usually within a day. We'll email you.*
> ○ List something to sell
> ○ Share your link
> ○ First sale 🎉
>
> **Parent or guardian** — Not needed to start. Needed before you get paid.
> · Not invited yet → *Invite* · Invited {date}, waiting → *Resend · Copy a link
> to text them · Change email* · Accepted ✓

The same card sits at the top of the venture page until `sold`.

**Screens 6–8 — the application, three pages.**

1. **Your business** — category cards (existing), name, one-line description
   with per-category placeholder, "Have an event code?" collapsed.
2. **About you** — name (prefilled), country (US first), and for anyone not
   `known_adult?`: *"You told us you're 13 or older. If you're actually 18+,
   say so here"* as a single opt-out link that sets `teen_led = false`.
   Parent or guardian email with: *"We'll email them when you submit. You can
   start selling before they reply; you can't be paid until they sign."*
   "How did you hear" and accessibility notes: optional, collapsed.
3. **Review & submit.**

Political, previously-applied, and website move behind the adult-led branch or
become optional. Disable in the form; do not delete the columns (Rule 2).

**Screen 9 — submit → straight into the venture.** When
`activation_blockers.empty?` (true for a first MoR venture in an eligible
category), approve and activate on submit — the same calls
`Fuime::CohortAdmission` already makes, minus `vet!`. The teen lands on their
venture page with the checklist at stage 3 and a banner:

> **You're in.** Fuime is reviewing {Venture} — you can set everything up now
> and publish the moment we approve, usually within a day. We'll email you.

Vetting stays human. An unvetted venture can draft offers and cannot publish
(`Event#accepts_payments?`), which is exactly the wait we want them to have.

**Email — vetting approved** (new). Subject: *"{Venture} is approved — publish
your first offer."* One button to `/{slug}/offers`.

**Email — activated** (rewritten). Next steps become: *Add what you sell*,
*Share your storefront*, and *Your parent hasn't signed yet — resend* when
pending. Team invites move to the bottom.

**Screen 10 — offers.** Sale-terms acknowledgement appears **at first publish**
as the checkbox under the Publish button, once, not as a card above the form.
Server check unchanged. After publish:

> **Your link** `app.fuime.com/pay/{slug}/{offer}` **[Copy] [Share] [QR]**
> Paste it in a bio, a group chat, a flyer.

`clipboard_controller.js` and `qr_code_controller.js` already exist. `Share`
uses `navigator.share` where present.

**Venture home** gets one card: *Share your storefront* — `/b/{slug}` with the
same three buttons (G15).

### 4.2 Parent — "a pitch, a page, a tap"

**The email** (rewritten; this is the pitch).

> Subject: **{Teen} started a business — they need a parent to sign off**
>
> Hi — {Teen} just set up **{Venture}** on Fuime, a financial platform for
> young founders. Because they're under 18, a parent or guardian has to be the
> responsible adult on the account, and {Teen} named you.
>
> **What you're agreeing to** *(one page, about two minutes)*
> • You're the legal signer for {Venture}. {Teen} runs it day to day.
> • You can see every sale and every dollar, always. {Teen} can't turn that off.
> • Nothing is paid out until you've accepted and set up where the money goes.
>
> {Teen} can keep going without waiting on you. **They can't be paid until you sign.**
>
> *[corrected 2026-09-11: "until you approve it" and "can already take orders"
> were false — payouts run as a weekly admin-approved batch the guardian does
> not approve line by line, and selling waits on vetting, which has not happened
> when this email fires on application submit.]*
>
> **[Review and sign]**
>
> We won't ask for a Social Security number, an ID, or a payment. When there's
> money to send, we'll ask where it should go.
>
> Not expecting this? Ignore it — nothing happens unless you accept.

Reminders (day 3 / day 6) keep their subjects and reuse this body.

**The link signs them in.** The email URL carries a signed token
(`User#signed_id(purpose: :guardian_invite, expires_in: 7.days)`) alongside the
guardianship token. `GuardianshipsController#show` verifies it and finishes the
session exactly as `WaitlistInvitesController#show` does — `Login` +
`ProcessLoginService#process_signed_email_link`, 2FA preserved. Inbox control
is the same proof a login code offers; this removes one email and two screens
and weakens nothing.

*The teen's copyable link is the plain `/guardian/:token` URL, which still
requires signing in as the invited address.* The signed sign-in token lives
only in the email, so a teen who copies the link to text a parent cannot use it
to sign as the parent. `Guardianship#self_signed_signals` stays as the
detector.

**The page.** One screen, no detour through the profile form.

> **{Teen} needs a parent to sign off on {Venture}**
> • You'll be the legal signer and responsible adult; {Teen} runs it.
> • You see every transaction, always.
> • Nothing is paid out until you've accepted and set up where the money goes.
>   *[corrected 2026-09-11: was "You approve every payout" — see above.]*
>
> Your full name *(shown only when blank)*
> [Guardian agreement — scroll box, versioned, unchanged]
> ☐ I'm {Teen}'s parent or legal guardian, I'm 18 or older, and I agree to
>   the guardian agreement above.
> **[I agree]**
> We record the date, your IP address and the agreement version. This is not
> an identity check.
> *(footer disclosure visible)*

`#accept` saves `full_name` if provided, then does what it does today.
`redirect_to_onboarding` is skipped for `show`/`accept`, which also closes the
half-session bounce.

**The landing.** `/guardian` with a first-visit state:

> **You're {Teen}'s guardian ✓**
> **{Venture}** — settled $0.00 — Ledger · Transactions · Payouts
> **What happens next.** When {Teen} makes a sale, we'll email you. When they
> ask to be paid, you approve it here. Nothing moves without you.
> [Set up where payouts go] *(MoR + Plaid collectable; optional now)*
> Family plan: only when a second venture needs it — one line, not a wall.

**The nav.** Payouts, Payout account and Taxes appear for a guardian on their
ward's venture. `events_helper.rb` gates move from `organizer_signed_in?` to
the policy method that already returns true for guardians.

**The emails after.** Four transactional mailers to the guardian, all deep-linked:
venture live (with the payout-setup link — G6), first sale ("{Teen} made their
first sale — set up where payouts go"), payout requested ("Approve ${amount}"),
payout paid. The accept page and the agreement already promise these.

**Recovery.** Expired link → *"This link expired. Send me a new one"* (re-mints
via `resend_invite!`, emails the same address, no sign-in required — it only
reaches their own inbox). Wrong account → *"Sign out and open the link again"*
button. `/billing` before accept → *"You can upgrade after you've accepted a
guardian invitation — that's what confirms you're the adult on the account."*

---

## 5. The work, in PR order

**Status after the 2026-09-11 merge:** Phase A shipped on this branch; B1, B2, C2,
C3 and D2 shipped on `main` (§0.5). **Open: B3, C1, D1, E1–E3.** C1 is now the
single biggest remaining win — the parent still needs a login-code email.

One phase = one branch = one PR (Rule 5). Sizes are shape, not days. Each row
names the friction it removes from §1/§2.

### Phase A — stop losing the people who show up *(copy and routing; S each)*

| # | Change | Files | Kills |
|---|---|---|---|
| A1 | Site primary CTA → `/get-started` (307 → app `?signup=true`; `/start` had a cached 308 history) on `start.html`, `start-scroll.html`, index, parents, pricing; L8 sweep of all five pages (test-mode / no-real-money / Connect-plan copy → MoR facts, pinned by `spec/fuime_marketing_copy_spec.rb`); waitlist relabelled for schools/cohorts with `*-cohort` sources; signup page copy *[as shipped 2026-09-11]* | `site/server.js`, `site/start.html`, `site/start-scroll.html`, `site/index.html`, `site/parents.html`, `site/pricing.html`, `app/views/logins/new.html.erb` | §1 #1, #2 |
| A2 | Profile form: drop phone requirement and photo from the onboarding branch; `logins#complete` and `WaitlistInvitesController#after_waitlist_login_path` check name only | `app/views/users/edit.html.erb`, `app/controllers/logins_controller.rb:180`, `app/controllers/waitlist_invites_controller.rb` | §1 #4, §2 #4 |
| A3 | Invite email rewrite (the "can't be paid until you sign" line in the first email); `/guardian/new` copy true under MoR; accept button "I agree"; remove `hide_footer` on `show` | `app/views/guardianship_mailer/invite.*`, `guardianships/new.html.erb`, `guardianships/show.html.erb`, `guardianships_controller.rb:7` | §2 #1, #5 |
| A4 | Vetting-approved mailer; activation email rewrite | new `Fuime::VettingMailer`, `Event#record_vetting_decision!`, `event/application_mailer/activated.html.erb` | §1 #11, #14 |
| A5 | Expired-link resend, wrong-account sign-out, billing-before-accept copy | `guardianships_controller.rb` (`set_guardianship`, `show`), `fuime/billing/show.html.erb` | §2 #9, #10, #11 |
| A6 | Agreement v3: §5 says "software platform, not a bank"; L5 prescribes "financial technology company, not a bank". New partial + `CURRENT_AGREEMENT_VERSION` bump; v1/v2 stay for past signers | new `guardianships/agreements/_<date>_v3.html.erb`, `app/models/guardianship.rb:40-51` | L5 on the one document a parent signs |

Spec updates: `guardianship_mailer_spec`, `guardianships_render_spec`,
`onboarding_terms_spec`, `family_signup_flow_spec` (assert no phone needed),
`fuime/status_disclosure_spec` (add `/guardian/:token`).

### Phase B — make the flow visible *(M)*

| # | Change | Files | Kills |
|---|---|---|---|
| B1 | Founder checklist on home and venture page from `FounderProgress`, with guardian side-track (not invited / pending / accepted; resend, copy link, change email); surfaces a failed auto-invite as "not invited yet" | `app/services/fuime/founder_progress.rb`, new `fuime/_founder_checklist.html.erb`, `static_pages/index.html.erb`, `events/show.html.erb` | §1 #5, #10, guardian invisibility, silent invite failure |
| B2 | Pay link copy/share/QR; storefront share card on venture home | `fuime/offers/index.html.erb`, `events/show.html.erb`, existing `clipboard_controller.js`, `qr_code_controller.js` | §1 #13 |
| B3 | Guardian nav (policy-gated, not organizer-gated); `/guardian` first-visit landing; accept redirects there | `app/helpers/events_helper.rb`, `guardianships/index.html.erb`, `guardianships_controller.rb#accept` | §2 #6, #7 |

### Phase C — remove a round trip *(M; C3 needs a decision, §6)*

| # | Change | Files | Kills |
|---|---|---|---|
| C1 | Signed sign-in token in the invite email; `show` completes the session like the waitlist invite; name field on accept page; skip `redirect_to_onboarding` for `show`/`accept` | `guardianship_mailer.rb`, `guardianships_controller.rb`, `guardianships/show.html.erb`, reuse of `ProcessLoginService#process_signed_email_link` | §2 #2, #3, #4 |
| C2 | Wizard to three pages; pre-answered `teen_led`; referrer optional; adult-only fields behind the adult branch; event code on page 1 | `event/applications_controller.rb`, `event/applications/*.html.erb`, `Event::Application#required_submission_fields` | §1 #6, #8, #9 |
| C3 | Approve + activate on submit when `activation_blockers.empty?` under MoR; vetting stays human; banner copy | `Event::Application#mark_submitted`, reuse `Fuime::CohortAdmission` internals | §1 #10 |

### Phase D — keep the parent in the loop *(M)*

| # | Change | Files | Kills |
|---|---|---|---|
| D1 | Guardian mailers: venture live, first sale, payout requested, payout paid | new `Fuime::GuardianMailer`, hooks in `activate_event!`, `Fuime::PaymentWebhookHandler` (post-ledger, not in the ledger), `PayoutRequest` transitions | §2 #8, G6 |
| D2 | Sale-terms acknowledgement moves to first publish | `fuime/offers/index.html.erb`, `_operator_sale_terms.html.erb` | §1 #12 |

### Phase E — later, or needs a decision

| # | Change | Note |
|---|---|---|
| E1 | Parent-first entry: parent signs up, names the teen, accepts the agreement up front; guardianship waits on the teen (`awaiting_minor` status) | Model change. Worth it once `/parents` has traffic. Until then A1 gives `/parents` an honest CTA: *"Have your teen start; you'll get one email."* |
| E2 | DocuSeal cosigner notify suppressed when a guardianship invite covers the same adult | Latent; only bites if `FUIME_DOCUSEAL_TEMPLATE_ID` is set |
| E3 | `/admin/funnel` — stage counts and median time between stages from timestamps | Server-side only; no third-party analytics on minors (L7) |

Every phase ends with `bundle exec rspec`, a line per change in
`UPSTREAM_DIVERGENCE.md`, and the handoff note in `SETUP_NOTES.md`.

---

## 6. Decisions only Rushil can make

1. **C3 — auto-activate on submit.** Recommended yes for MoR + eligible
   category + `activation_blockers.empty?`. Cost: junk `Event` rows from
   abandoned applicants (invisible: Discover lists published offers only, and
   an unvetted storefront says nothing). Benefit: the single largest wait in
   the funnel disappears. Adult-led and non-eligible categories keep the admin
   approve step.
2. **A2 — phone optional at signup.** SMS login exists in upstream code but
   Twilio is stubbed under Rule 4. Recommended yes.
3. **C2 — "how did you hear" optional.** It is the only analytics question in
   the funnel. Recommended optional, kept on the form.
4. **The approval ETA sentence.** "Usually within a day" is only honest if the
   vetting queue is worked daily. Pick the number that is true.
5. **E1 — parent-first entry.** Build, or defer until `/parents` converts.
6. **Reopen the closed site pages?** `site/server.js` `CLOSED` still sends `/pricing`
   and `/parents` to the dive. Their copy is now true; whether to reopen them and
   restore them to the sitemap is a marketing call. *[added 2026-09-11]*
7. **Terms of Service.** `app/views/static_pages/terms.html.erb` still carries the
   beta banner "no real money moves through Fuime", §3's beta bullet and §10's
   "can no longer operate a business". Real money has moved since 2026-08-21.
   This is G19 (counsel-drafted terms); agreement v3 links to the Terms only for
   refunds and disputes so as not to vouch for the rest. *[added 2026-09-11]*
8. **"Nothing is billed during the private beta."** `site/pricing.html` (meta, plans
   lead), `site/parents.html` (FAQ + JSON-LD) and "price list at launch" on
   `index.html` arrived with #99, while `/billing` offers the $19.99 family plan on
   live Stripe. Either the site is right and billing should be paused, or the copy
   should go. Not changed here; it is a pricing promise only the founder can make.
   *[added 2026-09-11, surfaced during the merge]*

---

## 7. Do not do

- Re-collect date of birth "to fix the honor system." Decided 2026-08-20; G7.
- Add identity verification to the accept page. That is `LAUNCH_SPEC` §4.2 with
  a vendor, and L4 governs how — not an onboarding PR.
- Remove or auto-pass operator vetting. Under MoR Fuime is the seller of record.
- Make guardian acceptance block *selling* again. MoR moved it to payouts for a
  reason (`operator_eligibility.rb:173-206`).
- Put the signed sign-in token anywhere the teen can see it.
- Notify minors of anything but their own transactional events; nothing 12–6 a.m.
- Add third-party analytics, pixels, or session replay to any page a minor uses.
- Any Connect-path work. Production is MoR.
- Rename `Event`, touch `HcbCode`, or delete the disabled HCB fields (Rules 2, 6).

---

## 8. How we will know

Every stage already has a timestamp: `User.created_at`,
`Event::Application.submitted_at` / activation, `Event.operator_vetting_*`,
`Fuime::Offer` publish, first `CanonicalTransaction`, `Guardianship.created_at`
/ `agreement_signed_at`, payout method verified, first payout. E3 turns them
into one admin page. Until then, the cohort roster is the funnel.

Targets, measured on the next cohort after Phase C ships:

| Metric | Now (from code) | Target |
|---|---|---|
| Teen: land → application submitted | ~10 screens, 1 email, ≥ 12 fields | ≤ 7 screens, 1 email, ≤ 8 fields, under 5 minutes |
| Teen: submitted → inside venture | 2 admin clicks, unbounded | 0 clicks, instant |
| Teen: vetted → link shared | manual select-and-copy | one tap; ≥ 80% of vetted ventures share within a day |
| Parent: email opened → signed | 2 emails, 6 screens | 1 email, 1 page, under 2 minutes; ≥ 70% within 48 h |
| Parent: signed → knows what to do next | flash on a teen dashboard | landing page; first payout approved without a support email |

---

## 9. Docs this corrects

- `LAUNCH_SPEC.md` §6 still says the teen "enters a date of birth" and is
  "parked until a guardian is invited", and that the guardian "verifies their
  identity." All three are false on `main`.
- `TEEN_GROWTH_GAPS.md` §1.2 / §4 / G1 / G5: waitlist admit, day-3/6 reminders
  and the stale queue have shipped (`043b62ba9`, `363aad218`). Its "vetting
  approved does not ping the teen" is still true and is A4 here.
- The "important notifications" promise in the agreement (`§3`), the invite
  email and the accept page has no implementation; D1 is what makes it true.
- `CLAUDE.md` CURRENT POSITION still describes Connect as production. Not
  touched here; update it the next time that file is edited.
