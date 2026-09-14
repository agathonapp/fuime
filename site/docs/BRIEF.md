# fuime site — build brief

Every worker on this site reads this file first. It is the contract. Nothing in
it is a suggestion.

## What fuime is

**A merchant of record for small businesses selling services and digital work
in the US.** A client buys from fuime; Stripe processes the payment; fuime pays
the venture what it earned after fees, refunds and disputes. Invoicing, books,
receipts, storefront, offers, recurring billing and a payment-links API sit on
top of that.

**fuime allows teenagers. It is not only for them.** Founder's instruction,
2026-09-14: *"our target is not only teens, we just simply allow teens."* A
seller aged 13 to 17 can run a venture with a parent or legal guardian as the
account holder and legal signer — and fuime is the only merchant of record that
will onboard them at all. That is a differentiator to state plainly in the
places it matters. It is **not** the frame of every page, and copy that assumes
the reader is a minor now excludes most of the audience.

This section used to open *"Invoicing and books for under-18 service
businesses."* That was true of the product and is no longer true of the market
it is sold to. `PADDLE_GAP_ANALYSIS.md` §6 posed the audience question and said
it belonged to the founder; this is the answer.

**fuime is not a bank, does not hold deposits, and offers no FDIC-insured
product.** That much is true today and always. Where a guardian is involved
they own the account and the young founder operates it. Copy that inverts that
ownership — "your kid's account, with you on it" — is a defect, not a wording
choice.

### ⚠️ "Position like Paddle" is not permission to claim what Paddle does

The founder wants fuime positioned as a peer of Paddle, and structurally it is
one: same mechanism, same liability transfer. **Its capabilities are not
comparable, and the gap is where this brief gets violated.** Verified in code,
2026-09-14: USD only; US only; English only; services and digital goods only;
**tax registrations in zero jurisdictions**; no multi-currency, no dunning, no
discounts or coupons, no buyer portal, no outbound webhooks, no SDKs, no API
sandbox. Physical goods, food and crafts are closed, and childcare, babysitting
and coaching children are deliberately excluded.

The honest peer claim is about structure, not features: *the same mechanism as
Paddle, for a different kind of seller.*

### Shipped vs. roadmap — do not blur these

This section exists because an earlier version of this brief described the
target architecture in the present tense, and the site was built from it. The
result was a public site claiming a KYC process and a fund flow the product did
not have. Then the reverse happened: the product went live (2026-08-20/21) and
the site kept saying "private beta, test mode" for weeks. Both are the same
defect. State on the page what is running, and only that; the banned phrases
are pinned in `spec/fuime_marketing_copy_spec.rb`.

**Shipped today (merchant-of-record, live):** fuime is the seller of record for
a venture's sales — a client pays fuime, Stripe processes the payment, and fuime
pays the venture what it has earned after fees, refunds and disputes. Ledger,
invoicing, receipts, storefront, offers. A human at fuime reviews every new
business before it can sell. The guardian flow is an emailed invitation plus
acceptance of the Guardian Agreement; there is **no identity verification of
any kind**, and the acceptance record (date, IP, agreement version) is all that
is kept. Nothing is paid out until a parent or legal guardian has accepted, and
payouts go only to a destination a parent or legal guardian sets up.

**Not shipped, and must not be described as shipped:** guardian identity
verification; the account-holder handover at 18; any per-venture Stripe account
owned by the guardian. The Connect architecture an earlier brief described is
not what runs, and pages may not describe it as the plan either — say what
runs. Never quote a review-time SLA; there is none.

### Pricing

These numbers must match `Event::Plan::Free` and `/billing`. There is **one
price and no tiers** (2026-09-14) — do not invent a second one.

**5% of collections, with a 50¢ minimum.** No monthly fee, and nothing at all
until a sale. Unlimited businesses. API keys **included, not unlocked** — but "included" is
not "unlimited": 10 live keys per venture is a safety cap you rotate within.
Founders 0% for the launch cohort, by invitation. Anything outside the standard
rate is a conversation with sales, not a tier.

**It is a FLOOR, not an additive fee, and the difference is not pedantry.**
`Event#fuime_fee_cents_on` computes `min(max(amount × 5%, 50¢), amount)`. On a
$400 sale that is **$20.00** — not $20.50. Writing it as "5% + 50¢" describes
Paddle's price, which is additive, and overstates fuime's own at every amount
above $10. Below $10 the floor binds and the effective rate is higher: a $5 sale
pays 50¢, which is 10%.

That difference is also the best honest thing fuime can say against a
competitor publishing the same headline number, and the site threw it away for
weeks by copying the shape of the number instead of the arithmetic.

**The 50¢ must still be quoted with the 5%** — "5%" alone describes a price
fuime does not charge (L8). Quote it as "5%, minimum 50¢", never as "5% + 50¢".

**Card processing is NOT charged on top.** fuime is the merchant of record, so
Stripe bills Ninth Street Labs, LLC — not the seller — and its ~2.9% + 30¢ comes
out of fuime's 5%. What the seller is owed is the sale minus the fuime fee, full
stop. Fees bill the **guardian** where there is one, never the minor: a minor's
payment authorisation is voidable at the minor's option, the guardian's is not.

#### The arithmetic lives in three places and they must agree

`site/site.js` (the no-modules fallback), `site/fx/ledger-bus.js` (what the fx
layer subscribes to), and `Event#fuime_fee_cents_on` in the app. On 2026-09-14
all three disagreed: both site files still ran the retired rate with no floor
**and subtracted Stripe's fee from the seller**, so the live calculator — the
one artifact on the site whose whole point is that the pricing is not a claim —
understated what a founder takes home by $19.90 on a $400 job, under a label
reading "5% + 50¢". The guard specs passed throughout, because they check that
the strings appear, not that the numbers are right. Change one, change all
three, and check the rendered figure.

## Four readers

1. **The seller.** Doing the work already and getting paid badly for it — late,
   in cash, through an app that puts their business in with their rent. Decides
   to _want_ it. The default reader of every page unless stated otherwise.
2. **The buyer's cardholder.** Has just found `Fuime* <venture>` on a
   statement and is deciding whether to call their bank. Owns
   `/why-has-fuime-charged-me`, and that page is written for them and nobody
   else. A chargeback is fuime's liability, so this reader is expensive.
3. **The parent.** Where the seller is 13 to 17, has to accept the Guardian
   Agreement and become the legal signer before anything is paid out. Decides
   whether it _happens_. Owns `/parents`.
4. **The teacher or programme lead.** Bringing a class or a closed cohort. Owns
   `/for/schools`, and is the only reader the email capture form still exists
   for.

Different jobs, different pages. Do not write one page at two of them.

## Feel

**Institutional, cinematic, unpatronising.** Nothing may read as a kids' app —
no bright primaries, no rounded-everything, no mascots, no exclamation marks.
That rule predates the audience change and survives it intact: it was written so
a teenager would not be condescended to, and it is now also what lets the same
pages be read by a thirty-year-old freelancer without a second design.

## The system (law)

The design language is Mercury.com's, adopted deliberately: alternating
dark→cream band rhythm, full-bleed cinematic hero with type high and subject
low, 4px as the dominant radius with pills reserved for buttons, and display
weight **480** — not 400, not 500. That weight is the detail that makes it look
bespoke instead of Figma-default.

One divergence: the accent is `#C2401F`, not an indigo.

All tokens live in `style.css` under `:root`. **A hex literal outside `:root`
is a build failure.** Use the variables:

```
--ink #272735   --ink-muted #535461   --ink-faint #C3C3CC
--on-dark #EDEDF3   --on-dark-mu   --on-dark-faint
--cream #F4F1EC   --paper #FFFFFF   --night #141420   --night-2 #1D1D2B
--accent #C2401F  --accent-tint     --hair
--t-hero --t-h2 --t-h3 --t-h4 --t-lead --t-body --t-small
--s1…--s10   --r --r-card --r-pill --r-media   --ease --dur   --wrap --gut
```

### Class vocabulary — already written in `style.css`. Compose these. Do not invent new CSS.

| Class                                                                                                                        | What it does                                         |
| ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `.wrap`                                                                                                                      | centred max-width container with gutters             |
| `.band` `.band--night` `.band--cream` `.band--paper`                                                                         | full-width section + its ground                      |
| `.eyebrow`                                                                                                                   | uppercase 14px label above a heading                 |
| `.h2` `.h3` `.h4` `.lead` `.muted` `.small`                                                                                  | type roles                                           |
| `.nav` `.nav--over` `.nav--solid` `.nav__in` `.nav__links` `.nav__link` `.nav__burger` `.mark`                               | the shared nav                                       |
| `.btn` + `.btn--accent` `.btn--ink` `.btn--light` `.btn--ghost`                                                              | buttons                                              |
| `.tlink` `.arrow`                                                                                                            | inline text link with an arrow that slides on hover  |
| `.hero` `.hero--short` `.hero__media` `.hero__in` `.hero__body` `.hero__cta` `.hero__note` `.hero__disclaimer` `.disclaimer` | hero                                                 |
| `.capture` `.capture__row` `.capture__msg` `.capture__done`                                                                  | the email form                                       |
| `.grid` `.grid--2` `.grid--3` `.grid--4` `.split` `.stack-lg`                                                                | layout                                               |
| `.card` `.icon`                                                                                                              | cards                                                |
| `.step` `.step__n`                                                                                                           | numbered steps                                       |
| `.price` `.price__fig`                                                                                                       | price figures (`<sub>` inside for "/mo")             |
| `.invoice` `.invoice__head` `.invoice__body` `.invoice__row` `.invoice__row--total` `.invoice__foot` `.tag`                  | the invoice artifact                                 |
| `.faq` (wraps `<details>`/`<summary>` + `.faq__a`)                                                                           | FAQ                                                  |
| `.foot` `.foot__top` `.foot__nav` `.foot__col` `.foot__bot`                                                                  | footer                                               |
| `.rise`                                                                                                                      | scroll-reveal; add to sections, `site.js` handles it |

If a layout genuinely needs something that isn't here, add it to `style.css`
built from tokens — never inline styles, never a hex literal.

## Shared chrome — stamped, not copied

The nav and footer live **once**, in `chrome/nav.html` and `chrome/foot.html`,
and `tools/sync-chrome.mjs` writes them into every page:

```
node tools/sync-chrome.mjs          # apply
node tools/sync-chrome.mjs --check  # exit 1 if any page is out of date
```

This used to say "copy the markup between pages verbatim", which was a workable
instruction for three pages and is not one for twenty-two: the footer is now a
five-column sitemap, so every added link would be twenty-two edits. The three
shipped pages had **already** drifted — `index.html` carried a `.foot__status`
row the other two did not.

It is a dev tool, not a build step. The pages in git still contain the full
markup and still ship exactly as they are; nothing at runtime depends on it
having been run. **Do not hand-edit a nav or footer in a page — it will be
overwritten.** Edit `chrome/`, then run the tool.

`aria-current="page"` is per-page and is re-applied by the tool from its own
`CURRENT` map.

Nav links: `How it works` → `/#how` · `What it costs` → `/pricing` ·
`Compare` → `/compare` · `Parents` → `/parents` · `Log in` → `/login` · then a
`.btn.btn--accent` "Start your business" → `/get-started`, the app's sign-up
door. Never `/start`: it answered a cacheable 308 to the dive for weeks and
browsers may still hold it.

Footer columns — **Product** · **The money** · **Who it's for** · **Compare** ·
**Company**. Compare is deliberately a whole column: it is the positioning
thesis, and Company is deliberately the smallest.

- A `.foot__legal` paragraph above the bottom line, **verbatim on every page**:
  `fuime is a financial technology company, not a bank. fuime does not hold
  deposits and does not offer FDIC-insured products. Payments are processed by
  Stripe. Ninth Street Labs, LLC, doing business as Fuime, is the seller of
  record on purchases. Guardians are the legal payee on operator payouts and
  must approve the destination before the first payout; young founders run the
  venture day to day.`
  The substring `financial technology company, not a bank` is asserted
  **case-sensitively**, so it can never start a sentence.
- Bottom line: `fuime · your client buys from us, and we pay you` and
  `Live. Every new business is reviewed by hand before it can sell.` The first
  was `invoicing for people who aren't 18 yet` until the audience change; it
  explains merchant-of-record in eight words, which is the job of a tagline on
  a site whose whole trust problem is that the buyer's statement says fuime.
- A `.beta` chip above the headline in every hero saying the product is live and
  that Stripe processes payments. **It must not say "beta"** — the claim is
  banned and the chip said "Private beta" for weeks after the product went live.
- `/start-scroll` has no footer bar, so its standing disclosure goes in a bare
  `.foot` / `.disclaimer` block — never inside the glass panel, which is clipped
  on a phone.

**Every href must resolve.** No `#`, no dead anchors, no 404s. This is now
tested: `test/server.test.mjs` fetches every href in `chrome/foot.html` and
fails on anything that does not answer 200.

## The sitemap

Twenty-two pages. `/` is `index.html` — the landing page, which spent weeks
unreachable at `/home` behind `CLOSED` while `/` served the dive. The dive
(`start.html`, the only page loading the 22MB frame ladder) keeps its own
address at `/dive`.

| Pillar | Pages |
|---|---|
| **Spine** | `/` · `/pricing` · `/parents` · `/dive` |
| **Product** | `/payment-links` · `/subscriptions` · `/books` · `/taxes` · `/api` |
| **The money** | `/merchant-of-record` · `/why-has-fuime-charged-me` |
| **Who it's for** | `/for/tutoring` · `/for/photo-video` · `/for/lawn-care` · `/for/schools` |
| **Compare** | `/compare` · `/compare/venmo` · `/compare/paddle` · `/compare/waiting` |
| **Company** | `/roadmap` · `/faq` |

An audience page (`/for/*`) sits one layer **above** the product pages and links
**down** into them. Same component kit, different framing — it is a funnel
layer, not a parallel one, and it must not become a second description of the
product.

`/merchant-of-record` is the trust page and the most important one in the set.
`/why-has-fuime-charged-me` is chargeback deflection, not marketing: under MoR
the buyer's statement reads `Fuime* <venture>`, and a chargeback is fuime's
liability.

`/roadmap` is the only page that may describe unshipped work, and it must keep
the two halves visibly separate. No dates, no quarters, no "coming soon".

## Adding a page — the five lists

The site has no build step, so a new page is invisible to routing and to every
copy guard until it is added by hand in five places. **A page missing from
these may say "private beta", quote a retired rate, drop the not-a-bank
disclosure and ship no sign-up CTA, and every suite stays green.**

1. `site/server.js` → `PUBLIC_FILES`. The server is an **allowlist**. Without
   this, `/foo` answers 308 → 404: a redirect into a dead end that reads as a
   routing bug.
2. `spec/fuime_marketing_copy_spec.rb` → `public_pages`.
3. `spec/fuime_marketing_pricing_spec.rb` → `public_price_pages` **only if the
   page quotes a price** (membership forces `5%`, `50¢` and a sales route to be
   present), otherwise `marketing_files`.
4. `site/test/copy-guard.mjs` → `PUBLIC_PAGES` / `PRICE_PAGES`. This replicates
   the two rspec guards offline, because they need a Rails boot and a database
   and cannot run on a machine without the gem bundle.
5. `site/test/server.test.mjs` → `PAGES`.

Then `site/sitemap.xml` — and only if the page is actually served, because a
sitemap listing a redirect is worse than no sitemap. Every `<loc>` is fetched by
the test suite.

## The email form — schools, teachers and cohorts only

The app is open, so the primary action on every page is the `/get-started`
button, never this form. The form is kept (CLAUDE.md Rule 2) for a teacher
bringing a class or a programme bringing a closed cohort, labelled as exactly
that, and its copy may not imply a queue for founders ("early access", "your
turn", "onboarding the first businesses" are all banned — `server.test.mjs` and
`spec/fuime_marketing_copy_spec.rb` both check).

`site.js` binds every `form.capture`. It needs this shape:

```html
<form class="capture" data-source="UNIQUE_SOURCE_ID-cohort" novalidate>
  <div class="capture__row">
    <input
      type="email"
      name="email"
      placeholder="you@school.edu"
      autocomplete="email"
      aria-label="Email address"
      required
    />
    <button type="submit" class="btn btn--accent">Get in touch</button>
  </div>
  <p class="capture__msg" role="status" aria-live="polite"></p>
  <p class="capture__done">
    <svg class="capture__plane" …></svg>
    <span>Got it. We'll follow up by email.</span>
  </p>
</form>
```

`data-source` must be unique per form and must end in `-cohort` — that suffix
is what lets the admin roster tell a cohort enquiry from a legacy teen sign-up:
`start-cohort`, `start-scroll-cohort`, `home-cohort`, `pricing-cohort`,
`parents-cohort`.

`api/waitlist.js` and `test/waitlist.test.mjs` are **off limits to design and
copy work** — they are the capture path, and a page change has no business
touching them. They are not frozen against deliberate infrastructure changes:
they were rewritten in Aug 2026 when storage moved from Upstash REST to a
Render Key Value instance, because Render Key Value has no HTTP API. The rule
that actually matters is the one that survived that rewrite: **the tests must
pass, and the two-independent-sinks design must stay.** If the store is down or
misconfigured, the address must still reach a human by mail. That property is
why the storage swap was safe to make at all.

## Voice — copy is PORTED, not rewritten

The old site's copy is the source of truth for tone. Mercury supplies layout,
type and rhythm. fuime keeps its own voice: specific, direct, a little angry,
never corporate. **Any line that comes out more corporate than the line it
replaces is a regression.**

The bar to beat, from the old page:

> It's her account, her name, her transaction history. You ask her for your own
> money.

Banned: "empower", "seamless", "unlock", "journey", "revolutionise", "we're on
a mission", em-dash rhythm, "it's not X, it's Y", fake-profound closing lines,
exclamation marks, emoji.

### Lines that must survive verbatim or better

```
You're already working. Start billing.
Write a real invoice, keep books that hold up, and know what you owe at tax
time. A parent or guardian owns the account and signs once. You operate it: you
write the invoices, you chase the ones that go unpaid, you run the business.
Built for tutoring, lawn care, photo, video, web, and DJ work.

How you get paid today
Every option makes you look like a kid doing a favor.
The work is real and the client is real. The payment method is a group chat and
somebody's mom.

Venmo → mom
It's her account, her name, her transaction history. You ask her for your own money.

Cash
No record. Nothing to show a client who wants a receipt, or the IRS if you clear $400.

"I'll get you next week"
You have no invoice to point at, so following up feels like begging.

A business account
Requires 18 nearly everywhere, and waiting it out costs you two years of clients.
Say it as the practical wall it is, not as a legal absolute: a minor *can* sign,
but the contract is voidable at the minor's option, which is why banks and
processors won't rely on it.

How fuime works
Three steps. One of them needs a parent.
01 Sign up and name your business — Takes about a minute. You'll need a parent or
   guardian's email address, because of step two.
02 Your parent becomes the legal signer — They accept the Guardian Agreement, which
   makes them the account owner and responsible adult. You're the operator: you
   send the invoices, you track the money, you run the business. (Their
   acceptance is recorded, not identity-checked. You can set up while you wait;
   nothing is paid out until they have signed.)
03 Invoice clients and get paid — Once fuime has reviewed your business by hand,
   send a link. Your client pays through Stripe, with fuime as the seller of
   record. fuime keeps your books as it goes: income, expenses, net, and a
   warning when you cross the $400 of net self-employment income at which the
   IRS expects a return.

Pricing on the page must match the Pricing section above. A flat monthly fee on
a kid making $80 a month is a tax on starting, which is why there is none — but
never quote the 5% without the 50¢, and never imply there is a tier to upgrade to.

fuime     5% of what you collect, minimum 50¢. No monthly fee. Unlimited
          businesses and API keys included. No fee on an invoice nobody pays.
Scale     Custom pricing — a conversation, not a tier. support@fuime.com
Founders  0% for the launch cohort, by invitation.
Cards     ~2.9% + 30¢ a payment, paid by fuime out of its 5% — NOT charged to the
          founder on top, because fuime is the legal seller.
Where a guardian holds the account it is billed to them, never to the minor.

For parents
You sign once. You keep the controls.
Your kid is going to keep taking money for work either way. This is the version
with a paper trail.

The account is yours to own — You are the account holder, they are the operator.
  Your own Venmo and cards stay out of it.
You see everything — Every invoice and every payment, in a read-only view. You
  can revoke the guardianship and shut it off.
Tax time is legible — Income, expenses, and net for the year, with the $400
  self-employment threshold flagged.
Where the money goes — A client pays fuime, as the seller of record, and Stripe
  processes the payment. Nothing is paid out until you have signed, and payouts
  go only to a destination you set up.

Schools, teachers and cohorts
Bringing a class or a closed group?
Leave your address. We read every one and follow up by email.
hi@fuime.com
```

### The worked example (invoice artifact)

```
Invoice 0014 · Maya R. · Photography · Due on receipt
Senior portraits · 3 hr session      $400.00
fuime fee · 5%, minimum 50¢          −$20.00
Left for the venture                 $380.00
Paid Jun 14 · Visa ···· 4242
```

**One fee line, and Stripe is not one of them.** This previously said "both fee
lines are mandatory", written when processing was charged on top of the platform
fee. Under merchant-of-record it is not: Stripe bills fuime, so deducting it from
the seller's total in a worked example is itself the deception the rule was
written against. The page shipped for weeks with a `Stripe processing −$11.90`
row and a total of `$360.10`, which is $19.90 less than the seller is owed.

The concern behind the old rule stands — **an example that hides the processor
is not honest** — and is met by the `.split-mount` bar directly beneath the
invoice, which cuts the sale three ways and labels Stripe's slice with its
amount: on $400, `YOU $380.00 · FUIME $8.10 · STRIPE $11.90`. That is where
Stripe's cost belongs, because it comes out of fuime's cut and not the seller's.

"lands in your account" remains the ownership inversion this brief exists to
prevent.

## Claims that must not appear

- fuime is a bank, holds funds, is FDIC-insured, or is a financial institution.
- Any present-tense claim that an identity or KYC check happens or that a
  document is uploaded or held by anyone. None exists.
- Any claim that fuime is in beta or test mode, that payments are not live, or
  that no real money moves; any queue language ("early access", "your turn",
  "onboarding the first businesses"); any description of a guardian-owned
  Stripe account or a fund flow that bypasses fuime. The live model is
  merchant-of-record — a client pays fuime, Stripe processes it, fuime pays the
  venture out — and `spec/fuime_marketing_copy_spec.rb` pins the banned phrases.
- A review-time promise ("usually within a day"). Vetting is human and has no
  SLA.
- The words bank, banking, checking, savings, deposits, neobank, insured, FDIC,
  or any form of "your money is safe / protected / guaranteed" — except inside
  the standing disclosure's own negations.
- A fee quoted without Stripe's 2.9% + 30¢ named alongside it.
- "The teen's account", or any phrasing where the young founder owns rather than
  operates.
- Any named partner beyond Stripe. **PayPal and Etsy are unconfirmed — never
  mention them.**
- Specific launch dates, user counts, testimonials, logos, or press mentions.
  There are none. Inventing social proof is a defect.

## Images

Every raster on the site is fal-generated and already encoded into `img/`.
Every icon is hand-built inline SVG using `.icon` (22px, 1.4 stroke,
`currentColor` via the class). **No emoji, no icon fonts, no stock, no
placeholder greys.** Use `<picture>` with AVIF then WebP:

```html
<picture>
  <source
    type="image/avif"
    srcset="/img/NAME-SMALL.avif 700w, /img/NAME-LARGE.avif 1600w"
    sizes="..."
  />
  <source
    type="image/webp"
    srcset="/img/NAME-SMALL.webp 700w, /img/NAME-LARGE.webp 1600w"
    sizes="..."
  />
  <img
    src="/img/NAME-LARGE.webp"
    alt="..."
    width="W"
    height="H"
    loading="lazy"
    decoding="async"
  />
</picture>
```

The hero image is eager (`fetchpriority="high"`, no `loading="lazy"`);
everything below the fold is lazy. Every `<img>` carries real `width`/`height`
so nothing shifts on load.

## Acceptance criteria — all 15, verbatim

1. Twenty-two pages ship (see **The sitemap**), sharing one nav and one footer
   stamped by `tools/sync-chrome.mjs`. Every nav link, footer link and in-page
   anchor resolves to a real target. Zero 404s, zero dead anchors. Every page
   appears in all five lists in **Adding a page**.
2. Every colour, size, radius, and duration in the CSS comes from the token
   block. A grep for hex literals outside `:root` returns nothing.
3. The measured system matches: display type renders at weight **480**; the
   dominant border-radius is 4px; the page alternates `#141420` and `#F4F1EC`
   bands; accent `#C2401F` appears on primary buttons and the wordmark's `i`
   and nowhere else.
4. Where a hero carries a photograph it is a fal-generated frame, cut at 21:9
   (desktop) and 4:5 (mobile), subject in the bottom third. **Measured**
   contrast between the headline and the actual pixels behind it is ≥ 4.5:1 at
   1440px and at 390px — sampled from the rendered screenshot, not asserted
   from the CSS. A page with no photograph is fine and normal; most of the
   pages added in 2026-09 are argument, not atmosphere.
5. Every raster image on the site is fal-generated; every icon is hand-built
   SVG. No stock, no placeholder greys, no emoji standing in for an icon.
   **No page references an image file that does not exist** — a 404'd
   `<picture>` is worse than no picture.
6. The waitlist form works wherever it appears: a valid email POSTs to
   `/api/waitlist` and reaches the success state; an invalid one shows the
   inline error without a request; a failed request shows the mail fallback.
   `test/waitlist.test.mjs` passes unmodified. It appears only on pages
   addressing schools, teachers and cohorts — the app is open, and the primary
   action everywhere else is `/get-started`.
7. `/parents` states in plain language that the guardian is the account holder
   and the young founder the operator, that there is **no identity verification
   yet**, that fuime is the seller of record and Stripe processes the payment,
   and that nothing is paid out until the guardian has signed — and carries an
   FAQ of at least six questions.
8. At 390px, 768px and 1440px: no horizontal scroll, no clipped or overlapping
   text, nav collapses cleanly, hero type stays clear of the subject. Verified
   by **screenshot at each width**, looked at — not by an assertion that only
   proves the CSS parsed.
9. `prefers-reduced-motion: reduce` disables every transform and opacity
   animation, including the scroll-reveal. Verified by rendering with the media
   feature forced.
10. Total transferred weight of `/` is under 1.2MB with images served as AVIF
    with WebP fallback, and LCP under 2.5s measured in a real headless load,
    not estimated.
11. All prose passes `no-ai-slop` against its `eval.md`.
12. Verified on the deployed URL, not the dev server.
13. Every line of copy carried over from the old site is at least as specific
    and as direct as the line it replaces. New copy matches that voice. Judged
    line-by-line against the old `index.html`, and the whole set passes
    `no-ai-slop`.
14. **Every figure on the site matches the arithmetic in the code.** The fee is
    `min(max(amount × 5%, 50¢), amount)` and Stripe's cost is never deducted
    from the seller. Check the rendered number, not the label beside it: the
    guards assert that "5%" and "50¢" appear, not that the total is right, and
    a wrong total passed every suite for weeks.
15. **No page claims a capability the code does not have.** In particular: no
    identity or KYC check, no payout timing or rail, no cards, no sales tax, no
    multi-currency, nothing outside the US, no buyer self-service, no
    testimonials, user counts, launch dates or SLAs. `docs/AUTHORING.md` carries
    the verified list of what is true.

## Files

```
site/
  index.html          /          the landing page and the front door
  start.html          /dive      the cinematic dive; the only page loading the
                                 frame ladder in dive/ and dive-m/
  start-scroll.html              a dive variant; public but unlinked
  pricing.html        /pricing
  parents.html        /parents
  payment-links.html  subscriptions.html  books.html  taxes.html  api.html
  merchant-of-record.html        why-has-fuime-charged-me.html
  roadmap.html        faq.html   compare.html
  for/                tutoring · photo-video · lawn-care · schools
  compare/            venmo · paddle · waiting

  chrome/         nav.html · foot.html · template.html — the shared chrome and
                  the starting point for a new page. NOT served.
  tools/          sync-chrome.mjs — stamps chrome/ into every page
  style.css       the whole system — DO NOT duplicate any of it into a page
  site.js         nav, scroll-reveal, waitlist, the fallback fee calculator
  fx/             the effect modules; ledger-bus.js owns the fee arithmetic
  server.js       static server, redirects, and the PUBLIC_FILES allowlist
  img/ vid/       fal-generated, pre-encoded AVIF + WebP
  dive/ dive-m/   the frame ladder, ~22MB, used only by start.html
  api/waitlist.js the capture path — not design/copy territory (see above)
  test/           server.test.mjs · waitlist.test.mjs · copy-guard.mjs
  docs/           BRIEF.md (this file) · AUTHORING.md · ASCENT.md
```

`docs/` was in `PUBLIC_DIRS` until 2026-09-14, which published this file at
`https://fuime.com/docs/BRIEF.md` — the internal contract, including the list of
claims the site may not make. Nothing linked it; it was reachable because the
directory sat next to the pages. Do not put it back.

The site is no longer strictly dependency-free: the waitlist store moved from an
HTTP API to the Redis protocol, so the service runs `npm ci --omit=dev` at
build. There is still no bundler and no build output — the pages ship as-is.
`ioredis` is imported dynamically and failing soft, so a deploy that somehow
skips the install degrades the waitlist to mail-only rather than 500-ing every
page on the site.

Every page loads `<link rel="stylesheet" href="/style.css">` and
`<script src="/site.js" defer></script>`. Nothing else. No CDN scripts, no
frameworks, no inline `<style>` blocks beyond the LQIP data URI if used.

Each page carries a real `<title>`, `<meta name="description">`, canonical
link, and Open Graph + Twitter card tags pointing at `/img/og.png`.
