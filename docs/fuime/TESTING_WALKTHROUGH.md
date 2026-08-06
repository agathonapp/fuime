# Testing walkthrough — every flow, by hand

How to exercise everything built as of 2026-08-06, as a human with a browser.
Companion to `docs/fuime/STRIPE_PASS.md` (which is the *automated* proof; this
is the clicking). Everything is Stripe **test mode** — no real money anywhere,
including production.

## Cheat sheet

| Thing | Value |
|---|---|
| Test card (pay anything) | `4242 4242 4242 4242`, any future date, any CVC |
| Test identity | DOB `01/01/1901`, SSN last-4 `0000`, EIN `000000000` |
| Test address | line 1 `address_full_match`, any city, CA, 94080 |
| Test bank | routing `110000000`, account `000123456789` |
| Local login codes | http://localhost:3000/letter_opener (or the rails runner below) |
| Local app | `docker compose up -d web` → http://localhost:3000 |

Login code from the database when letter_opener is awkward:

    docker compose run --rm -e RAILS_ENV=development -e DATABASE_URL=postgres://postgres:postgres@db:5432 \
      web bundle exec rails runner 'puts LoginCode.active.where(user: User.find_by(email: "EMAIL")).last&.pretty'

Make yourself an admin (needed to approve applications):

    ... web bundle exec rake "fuime:make_admin[you@example.com]"

## 1. The family funnel (D2C) — local

1. **Teen signs up.** Log out; sign in with a fresh email (e.g. `kid1@test.dev`).
   Code arrives in letter_opener.
2. **Profile.** Enter a name and a birthday that makes them 15.
   ✅ Expect: NO wall — you land in the product with a flash saying you'll
   invite a parent when the business is ready.
3. **Apply.** Start a business application. The form asks for a parent email
   (`parent1@test.dev`) — cosigner field.
   ✅ Expect on submit: the parent is invited AUTOMATICALLY (letter_opener has
   a guardianship invite addressed to them).
4. **Parent accepts.** Log out, sign in as `parent1@test.dev`, set name + adult
   DOB, open the invite link from the email, tick the agreement box, accept.
   ✅ Expect: guardianship active.
5. **Admin approves.** As your admin user, open the application, approve, then
   activate.
   ✅ Expect: venture exists; the teen is its manager.
   Counter-test: activate BEFORE step 4 completes → refused with "minor with
   no active guardian".
6. **Guardian connects payments.** As the parent, venture page →
   Set up payments. Stripe's embedded form (now themed to match the app) asks
   for the PARENT's identity — test values from the cheat sheet, accept ToS.
   ✅ Expect: status page flips to ready. Locally this needs
   `stripe listen --forward-to localhost:3000/fuime/webhooks/stripe/connect`
   for the mirror to sync automatically; without it, revisit the page to refresh.

## 2. Money in / books / money out — harness (no browser needed)

The venture `stripe-pass-full` is already fully onboarded. All tasks are
idempotent-ish and print what they did:

    SLUG=stripe-pass-full rake fuime:stripe_pass:status      # where things stand
    SLUG=stripe-pass-full rake fuime:stripe_pass:charge      # $25 in -> pending ledger line
    SLUG=stripe-pass-full rake fuime:stripe_pass:settle      # pending -> settled -> balance rises
    SLUG=stripe-pass-full rake fuime:stripe_pass:storefront  # prints a REAL checkout URL — pay it with 4242
    SLUG=stripe-pass-full rake fuime:stripe_pass:refund      # $5 back -> clamped reversal line
    SLUG=stripe-pass-full rake fuime:stripe_pass:payout      # teen asks, guardian approves, real payout
    SLUG=stripe-pass-full rake fuime:stripe_pass:payout_ledger  # the -$10 in the books
    SLUG=stripe-pass-full rake fuime:stripe_pass:subscribe   # $15/mo family checkout URL

(Prefix each with the usual `docker compose run --rm -e SLUG=stripe-pass-full
-e RAILS_ENV=development -e DATABASE_URL=... web bundle exec`.)

Then look at the venture's ledger page in the browser: every one of those
should be a line with a memo a fifteen-year-old could read.

## 3. Billing / paywall

1. `/my/billing` as the TEEN → sees the pitch and *the name of their parent*
   to ask; no upgrade button. POSTing anyway is refused (that's a spec, but
   feel free to try).
2. `/my/billing` as the PARENT → **Upgrade — $15/mo** → Stripe Checkout → pay
   with 4242.
   ✅ Expect: back on /my/billing with the welcome callout. Locally the ACTIVE
   flip needs `stripe listen --forward-to localhost:3000/fuime/webhooks/stripe`
   (platform endpoint, not /connect); in prod it's automatic.
3. **The slot.** Before upgrading: teen applies for a SECOND venture, admin
   approves, activate → ❌ refused: "the free plan includes one venture".
   After the parent upgrades → same activation succeeds, and every family
   venture's fee reads 4% instead of 7%.
4. **Manage billing** (as subscribed parent) → Stripe's portal: card, invoices,
   cancel. Cancel → fee resolution returns to 7%.

## 4. The school — local

Seeded by `rake "fuime:seed_school[Founders School,8]"` +
`rake "fuime:seed_school_cards[founders-school]"`:

| Who | Email | Should see |
|---|---|---|
| Business office | business-office@founders-school.test | everything |
| Guide | marisol-reyes@founders-school.test | every student, roster **Freeze** buttons + receipt badges |
| Student | naomi-okafor@founders-school.test | her venture only; "ask your guide" on payment pages; never an invite-your-parent prompt |

Click a Freeze on the roster: instant, no confirmation dialog, card shows
Frozen. (These are fabricated `ic_FAKE_` cards — freezing writes only to the
local database.)

## 5. Production (app.fuime.com — still test-mode money)

Same flows, three differences:
- Login codes arrive by REAL email (Resend). A fresh personal address is the
  truest signup test.
- Webhooks are live — no `stripe listen`, mirrors and subscriptions sync on
  their own. (First real delivery also confirms the endpoint repair.)
- The school flow: set the School plan on the Alpha org (console commands in
  PR #34), then walk `/[venture]/payments/setup` as a manager — the embedded
  form should ask for the SCHOOL's EIN, in Fuime's dark theme, with copy
  addressed to an administrator.

## What can't be clicked yet

Cards end-to-end (platform Issuing is sales-gated), disputes, and live-mode
anything. See STRIPE_PASS.md for the authoritative proven/unproven table.
