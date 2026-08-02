# fuime site — build brief

Every worker on this site reads this file first. It is the contract. Nothing in
it is a suggestion.

## What fuime is

Invoicing and books for under-18 service businesses. A 13–17-year-old who
already has paying clients — tutoring, lawn care, photo, video, web, DJ work —
sends a real invoice and gets paid into a Stripe account their guardian legally
owns and they operate day to day. A guardian completes one ID check at signup.
fuime charges 7% of money collected, $0/mo under $250 collected in the last 30
days, $15/mo over. Stripe's card processing is separate and goes to Stripe.

**fuime is not a bank and never holds the money.** Payments go client → the
guardian's Stripe account. Stripe holds the identity documents, not fuime. Any
copy implying otherwise is a defect, not a wording choice.

## Two readers

1. **The kid.** Already working, tired of being paid in a group chat. Decides
   to _want_ it.
2. **The parent.** Has to complete a government ID check before any of it
   works. Decides whether it _happens_.

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
- Bottom line: `fuime · invoicing for people who aren't 18 yet` and
  `fuime is not a bank. Payments settle into your own Stripe account.`

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
`pricing-foot`, `parents-foot`. Never change `api/waitlist.js` or
`test/waitlist.test.mjs` — they pass today and must keep passing untouched.

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
Send a real invoice, get paid into an account you run day to day, and know what
you owe at tax time. A parent co-signs once. After that it's yours.
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
Requires 18. That's the whole wall, and waiting it out costs you two years of clients.

How fuime works
Three steps. One of them needs a parent.
01 Sign up and name your business — Takes about a minute. You'll need a parent or
   guardian's email address, because of step two.
02 Your parent completes one ID check — Stripe lets a guardian own an account on
   behalf of someone 13 or older. They verify once and they're the legal owner.
   You're the operator: you send the invoices, you spend the money, you run the
   business.
03 Invoice clients and get paid — Send a link. Clients pay by card or bank
   transfer. The money settles into your account, and fuime keeps your books as
   it goes: income, expenses, net, and a warning when you cross the $400 the IRS
   cares about.

7% of what you collect. No monthly fee until you're earning.
A flat monthly fee on a kid making $80 a month is a tax on starting. So there
isn't one until the business is real.
Stripe's card processing is separate and goes to Stripe. We show it on every
invoice so the math is never a surprise.

7%   Charged on money you collect. If you don't get paid, there's no fee.
$0/mo   Under $250 collected in the last 30 days.
$15/mo  Over $250 collected in the last 30 days. Billed to the guardian.

For parents
You sign once. You keep the controls.
Your kid is going to keep taking money for work either way. This is the version
with a paper trail.

The account is yours — A Stripe account in your name, with them as operator.
  Your own Venmo and cards stay out of it.
You see everything — Every invoice and every payment, in a read-only view. You
  can shut it off.
Tax time is legible — Income, expenses, and net for the year, with the $400
  self-employment threshold flagged.
We never hold the money — Payments go from the client to your Stripe account.
  fuime takes its 7% and nothing else.

We're onboarding the first businesses now.
One email when it's your turn. Nothing else.
hi@fuime.com
```

### The worked example (invoice artifact)

```
Invoice 0014 · Maya R. · Photography · Due on receipt
Senior portraits · 3 hr session      $400.00
Card processing (Stripe)             −$11.90
fuime fee · 7%                       −$28.00
Lands in your account                $360.10
Paid Jun 14 · Visa ···· 4242
```

## Claims that must not appear

- fuime is a bank, holds funds, is FDIC-insured, or is a financial institution.
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
7. `/parents` states in plain language that the Stripe account is in the
   guardian's name, that **Stripe** holds the identity documents, and that
   fuime never holds the money — and carries an FAQ of at least six questions.
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
  api/waitlist.js DO NOT EDIT
  test/           DO NOT EDIT
  docs/BRIEF.md   this file
```

Every page loads `<link rel="stylesheet" href="/style.css">` and
`<script src="/site.js" defer></script>`. Nothing else. No CDN scripts, no
frameworks, no inline `<style>` blocks beyond the LQIP data URI if used.

Each page carries a real `<title>`, `<meta name="description">`, canonical
link, and Open Graph + Twitter card tags pointing at `/img/og.png`.
