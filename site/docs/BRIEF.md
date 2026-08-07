# fuime site — build brief

Every worker on this site reads this file first. It is the contract. Nothing in
it is a suggestion.

## What fuime is

Invoicing and books for under-18 service businesses. A 13–17-year-old who
already has paying clients — tutoring, lawn care, photo, video, web, DJ work —
sends a real invoice and gets paid into a Stripe account their guardian legally
owns and they operate day to day.

**fuime is not a bank, does not hold deposits, and offers no FDIC-insured
product.** That much is true today and always. The guardian owns the account;
the young founder operates it. Copy that inverts that ownership — "your kid's
account, with you on it" — is a defect, not a wording choice.

### Shipped vs. roadmap — do not blur these

This section exists because an earlier version of this brief described the
target architecture in the present tense, and the site was built from it. The
result was a public site claiming a KYC process and a fund flow the product did
not have. State on the page which of these you are describing.

**Shipped today:** private beta in Stripe **test mode** — no real money moves.
Ledger, invoicing, receipts, storefront preview. The guardian flow is an emailed
invitation plus acceptance of the Guardian Agreement. There is **no identity
verification of any kind**, and funds (in test mode) land in fuime's own pooled
Stripe account, not the family's.

**Roadmap, and must be labelled as such:** each venture's account becomes a
guardian-owned Stripe connected account, so payments go client → the guardian's
own Stripe account and fuime never holds the money. Stripe performs the identity
check and holds the documents. Guardian identity verification ships with live
payments. Until it is built, the site may describe this as what *will* happen —
never as what does.

### Pricing

Starter $0 (no payments — books, storefront preview, education). Standard $0/mo
+ 7% of collections. Pro ~$15/mo + 4%. Founders 0% for the launch cohort.
Stripe's card processing (~2.9% + 30¢) is separate, goes to Stripe, and **must be
disclosed wherever a fee appears** — an all-in cost that only becomes visible
later is the FTC's hidden-fee fact pattern. Subscriptions bill the **guardian**,
never the minor: a minor's payment authorisation is voidable at the minor's
option, the guardian's is not.

## Two readers

1. **The kid.** Already working, tired of being paid in a group chat. Decides
   to _want_ it.
2. **The parent.** Has to accept the Guardian Agreement and become the legal
   signer before any of it works — and, once live payments ship, complete
   Stripe's identity check. Decides whether it _happens_.

The landing page converts the kid. `/parents` survives the parent's scrutiny.
Different jobs, different pages.

## Feel

**Institutional, cinematic, unpatronising.** Nothing may read as a kids' app —
no bright primaries, no rounded-everything, no mascots, no exclamation marks.
The whole argument is "this is the real thing, and you're allowed to use it."

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

## Shared chrome — byte-identical on all three pages

Copy the `<nav>` and `<footer>` markup between pages verbatim. Only the
`aria-current="page"` attribute changes.

Nav links: `How it works` → `/#how` · `What it costs` → `/pricing` ·
`Parents` → `/parents` · then a `.btn.btn--accent` "Get early access".
On `/pricing` and `/parents`, `How it works` still points at `/#how`.

Footer columns:

- **Product** — How it works `/#how` · Pricing `/pricing` · For parents `/parents`
- **Company** — Email `mailto:hi@fuime.com`
- A `.foot__legal` paragraph above the bottom line, **verbatim on every page**:
  `fuime is a financial technology company, not a bank. fuime does not hold
  deposits and does not offer FDIC-insured products. Payments are processed by
  Stripe. Venture accounts are opened and owned by a parent or legal guardian;
  young founders operate them with guardian oversight.`
- Bottom line: `fuime · invoicing for people who aren't 18 yet` and
  `Private beta in test mode — no real money moves yet.`
- A `.beta` chip above the headline in every hero, saying the product is in
  private beta in test mode and that payments are not live. `/` and
  `/start-scroll` have no footer bar, so the standing disclosure goes in a bare
  `.foot` / `.disclaimer` block below the dive — never inside the glass panel,
  which is clipped on a phone.

**Every href must resolve.** No `#`, no dead anchors, no 404s.

## The email form — exact markup, all three pages

`site.js` binds every `form.capture`. It needs this shape:

```html
<form class="capture" data-source="UNIQUE_SOURCE_ID" novalidate>
  <div class="capture__row">
    <input
      type="email"
      name="email"
      placeholder="you@school.edu"
      autocomplete="email"
      aria-label="Email address"
      required
    />
    <button type="submit" class="btn btn--accent">Get early access</button>
  </div>
  <p class="capture__msg" role="status" aria-live="polite"></p>
  <p class="capture__done">You're on the list. We'll email you once.</p>
</form>
```

`data-source` must be unique per form: `home-hero`, `home-foot`,
`pricing-foot`, `parents-foot`.

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
   send the invoices, you track the money, you run the business. (Roadmap, label
   it: Stripe permits a guardian to own an account on behalf of someone 13 or
   older, and Stripe's identity check ships with live payments.)
03 Invoice clients and get paid — Send a link. In the beta this runs in Stripe test
   mode, so nothing is really charged. fuime keeps your books as it goes: income,
   expenses, net, and a warning when you cross the $400 of net self-employment
   income at which the IRS expects a return.

Pricing on the page must match the Pricing section above, including Stripe's
separate processing fee. A flat monthly fee on a kid making $80 a month is a tax
on starting, which is why Standard has none — but never imply the 7% is the
all-in cost.
Stripe's card processing is separate and goes to Stripe. We show it on every
invoice so the math is never a surprise.

Starter   Free. Books, storefront and lessons, with no payment processing.
Standard  $0/mo + 7% of what you collect. No fee on an invoice nobody pays.
Pro       $15/mo + 4%. Cheaper than Standard above about $500 a month.
Founders  0% for the launch cohort, by invitation.
Stripe    2.9% + 30¢ a card payment, on top of every plan above, paid to Stripe.
Billed to the guardian who holds the account, never to the young founder — and
not billed at all during the beta, because no real money moves.

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
Where the money will sit — Roadmap, label it: at live launch, a Stripe account
  you own, with fuime holding no balance. Today it is test mode, so no real
  money moves.

We're onboarding the first businesses now.
One email when it's your turn. Nothing else.
hi@fuime.com
```

### The worked example (invoice artifact)

```
Invoice 0014 · Maya R. · Photography · Due on receipt
Senior portraits · 3 hr session      $400.00
Stripe processing · 2.9% + 30¢       −$11.90
fuime platform fee · 7% (Standard)   −$28.00
Left for the venture                 $360.10
Paid Jun 14 · Visa ···· 4242
```

Both fee lines are mandatory. A worked example that shows the platform fee and
hides Stripe's is the FTC-deception shape this brief exists to prevent, and
"lands in your account" is the ownership inversion it exists to prevent.
```

## Claims that must not appear

- fuime is a bank, holds funds, is FDIC-insured, or is a financial institution.
- Any present-tense claim that an identity or KYC check happens, that a document
  is uploaded or held by anyone, or that funds reach a family's own account.
  Those are roadmap, and the future tense plus a visible label is the only way
  they may appear.
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

## Acceptance criteria — all 13, verbatim

1. Three pages ship — `/`, `/pricing`, `/parents` — sharing one nav and one
   footer. Every nav link, footer link and in-page anchor resolves to a real
   target. Zero 404s, zero dead anchors.
2. Every colour, size, radius, and duration in the CSS comes from the token
   block. A grep for hex literals outside `:root` returns nothing.
3. The measured system matches: display type renders at weight **480**; the
   dominant border-radius is 4px; the page alternates `#141420` and `#F4F1EC`
   bands; accent `#C2401F` appears on primary buttons and the wordmark's `i`
   and nowhere else.
4. The hero is a fal-generated frame, cut at 21:9 (desktop) and 4:5 (mobile),
   subject in the bottom third. **Measured** contrast between the headline and
   the actual pixels behind it is ≥ 4.5:1 at 1440px and at 390px — sampled
   from the rendered screenshot, not asserted from the CSS.
5. Every raster image on the site is fal-generated; every icon is hand-built
   SVG. No stock, no placeholder greys, no emoji standing in for an icon.
6. The waitlist form works on all three pages: a valid email POSTs to
   `/api/waitlist` and reaches the success state; an invalid one shows the
   inline error without a request; a failed request shows the `hi@fuime.com`
   fallback. `test/waitlist.test.mjs` passes unmodified.
7. `/parents` states in plain language that the guardian is the account holder
   and the young founder the operator, that there is **no identity verification
   yet**, and that payments run in Stripe test mode today with the parent-owned
   no-custody account named as roadmap — and carries an FAQ of at least six
   questions.
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

## Files

```
site/
  index.html      landing
  pricing.html    /pricing
  parents.html    /parents
  style.css       the whole system — DO NOT duplicate any of it into a page
  site.js         nav, scroll-reveal, waitlist — DO NOT duplicate
  vercel.json     cleanUrls
  img/            fal-generated, pre-encoded AVIF + WebP
  api/waitlist.js the capture path — not design/copy territory (see above)
  test/           same
  package.json    one dependency: ioredis, for the waitlist store
  docs/BRIEF.md   this file
```

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
