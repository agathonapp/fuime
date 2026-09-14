# Authoring a fuime page

## Who this is for (read before anything else)

**fuime is a general-purpose merchant of record for small businesses. It allows
teenagers; it is not only for them.** The founder's instruction, 2026-09-14:
*"our target is not only teens, we just simply allow teens."*

So the default reader of any page is anyone in the US selling services or
digital work who wants to get paid properly. Write age-neutral second person —
"you run a business" — and never frame a page around not being 18.

Guardianship is a **differentiator**, not the premise: fuime is the only
merchant of record that will onboard a seller aged 13 to 17 at all, with a
parent or guardian as the legal account holder. State that where it is
genuinely relevant. Do not make it the frame of every page.

⚠️ **"Position like Paddle" is not permission to claim what Paddle can do.**
This is the exact failure BRIEF.md exists to prevent, and a general-audience
framing makes it far more tempting. fuime is USD only, US only, services and
digital goods only, with **tax registrations in zero jurisdictions**, no
multi-currency, no dunning, and no buyer self-service. Every one of those is a
sentence you must not write your way around.

---

Read `BRIEF.md` first — it is the contract and this does not replace it. This
file is the working kit: what is true, what is forbidden, and what to compose.

## Mechanics

1. Copy `chrome/template.html` to your page's path. Fill `{{TITLE}}`,
   `{{DESCRIPTION}}`, `{{SLUG}}`, `{{OG_TITLE}}`.
2. Write **only** between the two `PAGE BODY` markers. Do not touch the nav or
   the footer — `tools/sync-chrome.mjs` owns them and will overwrite your copy.
3. Compose classes that already exist in `style.css`. **A hex literal outside
   `:root` is a build failure. No inline `<style>`, no CDN script, no emoji, no
   icon font, no stock image.**
4. Icons are hand-built inline SVG, `viewBox="0 0 22 22"`, `class="icon"`,
   stroke `currentColor`, no fill.
5. No `<img>` unless the file already exists in `img/`. A page with no
   photograph is fine and normal — most of these pages are argument, not
   atmosphere. Do NOT invent image paths; a 404'd `<picture>` is worse than none.

## What is true (you may assert these; nothing else)

Verified against the app on 2026-09-14. If it is not on this list, do not write it.

**Selling.** A venture publishes named offers at a set price ($1–$10,000). Each
gets a payment page at `/pay/<venture>/<offer>` and a public storefront at
`/b/<venture>`. A link survives renaming the offer. Checkout is Stripe-hosted.
A buyer can also be asked for a free-chosen amount. Sales are USD only.
Categories are limited to services and digital goods.

**Recurring.** An offer can bill monthly or yearly. Renewals post to the ledger
by themselves. **A buyer cannot cancel it themselves — they email
support@fuime.com.** If you write about subscriptions you must say that.

**The ledger.** Every sale becomes a real ledger line. Receipt upload, emailing
a receipt in, pairing receipts to transactions, and threaded comments all work
on it. fuime's fee posts as its own visible negative line naming the rate that
was actually charged. A refund posts a reversal AND rebates fuime's fee in
proportion. Partial refunds book the increment, not the running total.

**Tax.** `Fuime::TaxTrackerService` estimates net income for the year against
the IRS $400 self-employment threshold, applying the 92.35% Schedule SE
multiplier — so the real trigger is **$433.14 of net profit**. A guardian can
download a tax packet. It is an ESTIMATOR for the teen's income tax. It does
not touch checkout, does not calculate sales tax, and does not file anything.

**Guardianship.** A guardian accepts a versioned agreement; the signature IP,
user-agent, timestamp and document version are recorded. They get read access
to the ledger and payouts, can revoke at any time, and are the legal payee. A
teen cannot approve their own payout — enforced twice. Under-13 is refused at
signup, and the age floor is hard-clamped at 13.

**Payouts.** Runs are generated weekly and approved by a human before anything
moves, then marked paid against a real bank reference. Policy: a 7-day hold, a
10% rolling reserve over 90 days, a $2,500 per-run cap, a $10 floor. Every
skipped operator gets a stated reason. The operator-facing number is what fuime
**owes** — never a balance, never a withdraw button.

**API.** Three endpoints under `/api/fuime/v1`: `GET /me`, and list/create/
delete on payment links. Keys are `fuime_sk_`-prefixed, encrypted at rest,
shown once, 10 live keys per venture, 250 live links per key, 120 requests a
minute. **No route or body anywhere carries a venture id**, so a leaked key can
only ever touch one business. A key can ask for money; it cannot move money,
read the ledger, or see personal data. Included for everyone, not unlocked.

**Schools.** A school can hold a pooled account, fund a treasury, and make
awards, settling per student. A school stands in loco parentis, so no
per-student guardian is required.

**Pricing.** `min(max(5% × amount, 50¢), amount)`. A FLOOR, not an additive
fee — on a $400 sale the fee is $20.00, not $20.50. No monthly fee. Nothing
until a sale. Unlimited businesses and API keys included. Anything outside the
standard rate is a conversation with sales. Stripe's ~2.9% + 30¢ is paid by
fuime out of its own 5% and is **never** added to what the founder pays.
Founders cohort is 0%, by invitation. Fees bill the guardian, never the minor.

## What you may NOT write. Any one of these is a defect.

- **Banking words** — bank, banking, neobank, checking, savings, deposits,
  insured, FDIC, "your money is safe / protected / guaranteed". The only legal
  use is inside the standing disclosure's own negations. Also: never "your
  balance", never "withdraw", never "spend from your fuime account".
- **Any identity or KYC claim.** There is **no identity verification of anyone**.
  Age is a self-attested checkbox. Vetting is a human reading an application.
  Never say a document is checked, uploaded, or held.
- **Payout timing or a rail.** No seller can attach a bank account today and
  there is no automated payout rail — a human sends it. Never "paid Friday",
  never "in your account in N days", never an SLA or a review-time promise.
- **Cards.** Card issuing is off in production. Do not mention a fuime card.
- **Sales tax, VAT, GST, "we handle tax", "tax compliance included", "we're
  liable for tax".** fuime is registered in zero jurisdictions and files nothing.
- **Anything international.** USD only, English only, US only.
- **"Your own Stripe account" / "the teen's account"** — backwards. Under
  merchant-of-record the buyer's counterparty is Ninth Street Labs, LLC. The
  venture has a claim on fuime. Accounts are "opened and owned by a parent or
  legal guardian"; the young founder **operates**.
- **A suggested price, typical rate, or "most founders charge ~$X".** The
  product deliberately has nowhere to store one — a suggested rate is a set
  rate with a softer verb, and that is how a misclassification examiner reads it.
- **"Sell anything."** Services and digital goods only. Childcare, babysitting
  and coaching children are deliberately excluded. So are physical goods, food
  and crafts.
- **Invented social proof.** No testimonials, no logos, no user counts, no
  press, no launch dates, no "trusted by". There are none.
- **Beta / queue language.** The product is live. Banned substrings, checked
  case-insensitively **over the whole file including HTML comments**:
  `payments are not live`, `no real money moves`, `test mode`, `early access`,
  `your turn`, `onboarding the first businesses`, `not something running today`.
- **`href="/start"`** — it answered a cacheable 308 for weeks. Use
  `/get-started`.
- Named partners beyond Stripe. **PayPal and Etsy are unconfirmed — never
  mention them**, including on a comparison page.

### Regex traps that will fail the build on innocent prose

- `/\b7%/` also matches **2.7%**, **0.7%**, **1.7%**. Stripe's rate is written
  `2.9% + 30¢` and that is safe; no other decimal ending in 7 is.
- `/drops? to/` matches inside **"backdrop to"**. Avoid both.
- `/one venture\b/i` catches ordinary prose — "start with one venture" fails.
  Write "a venture".
- `50¢` must be the literal cent sign. `&cent;`, `50c` and `$.50` all fail.
- The disclosure substring is **case-sensitive**: `financial technology company,
  not a bank` must appear exactly, lower-case f.
- `<meta>` content is plain ASCII on the existing pages — write `50c` there,
  not `50¢`.

## Required on every page

- `<a class="btn btn--accent" href="/get-started">Start your business</a>` —
  the anchor's only child must be exactly that text, no `<span>`.
- `<a class="nav__link" href="/login">Log in</a>` — comes with the chrome.
- The standing disclosure — comes with the footer.
- If the page carries a capture form, `data-source` must be unique and end
  `-cohort`, and every `capture__done` needs exactly one `capture__plane`.
  **Most of these pages should NOT carry a capture form** — the app is open and
  the primary action is `/get-started`. Only add one if the page genuinely
  addresses schools, teachers or cohorts.

## Composition

**Band rhythm.** The hero is night. The footer is night. So the first band
after the hero is cream, the last band before the footer is night, and no
ground repeats twice in a row. `--paper` is the rarest, saved for the one
section that should read as the brightest thing on the page — an FAQ, or a
comparison table. Use `.hero--short` on every page except the home page.

**Section shape.** Open with `.bhead` (eyebrow + `.h2`, optionally a `.lead`
beside it). Then ONE object: a `.grid--2/3` of `.card`, a `.rows` of
`.card--row`, a `.matrix` table, or a `.faq`. Then optionally one closing
`.tlink`. That is the whole budget for a band — never two objects.

**Counts.** Four cards is the house number; six when it is a catalogue of
negatives. An FAQ has at least six questions. A page has four to seven bands.

**Copy density.** Eyebrow 2–5 words, a category not a slogan. `.h2` one
sentence of 5–10 words ending in a full stop. `.lead` one or two sentences,
20–40 words, adding a fact the headline cannot carry. Card body 1–3 sentences,
20–45 words; cards get no sub-headings and no lists.

**Every page must carry one section that admits a limit** — what fuime is not,
or where it stops. That is house style, and on these pages it is also the only
honest way to write about a product this early.

## Voice

Second person throughout. "You", "your kid". Never "users", never "founders" as
a mass noun. Numbers stated, never rounded away. Name a consequence, not a
benefit — the bar to beat is *"It's her account, her name, her transaction
history. You ask her for your own money."*

Banned: empower, seamless, unlock, journey, revolutionise, "we're on a mission",
"it's not X, it's Y", em-dash rhythm, fake-profound closing lines, exclamation
marks, emoji. **Any line that comes out more corporate than the line it
replaces is a regression.**

## Before you finish

Run from `site/`:

```
node tools/sync-chrome.mjs        # stamps nav + footer
node test/copy-guard.mjs          # the rspec copy/pricing guards, offline
npm test                          # server + waitlist
```
