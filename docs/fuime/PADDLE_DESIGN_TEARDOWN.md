# Paddle's design system — what it is, and what is worth taking

**Status: research. Written 2026-09-14. Extracted from paddle.com's served CSS, its `_next`
asset bundle, and the font binary's `name` table — not from memory or a third-party teardown.**

> Companion to `PADDLE_GAP_ANALYSIS.md`, which covers product and pricing. This file covers the
> marketing site and the seller dashboard.
>
> **The one caution that governs everything below: steal the system, not the identity.** Paddle's
> display face plus its yellow plus its two-clause headlines *are* Paddle's brand. Copying the
> tokens gives you their craft. Copying the identity gives you a site that reads as a knockoff,
> which costs exactly the credibility a payments company needs most.

---

## 1. The surprise: there is almost no technology here

Grepped the full 1MB homepage bundle. **No Lottie. No GSAP. No Framer Motion. No `<video>`. No
scroll-jacking.** Five keyframes on the entire homepage — a logo-garden slide, a marquee and its
reverse twin, a footer-nav flourish, a loader ripple, and an email-gate enter.

The site feels expensive entirely through type, warm neutrals, and restraint. This is good news:
almost all of it is reachable by a small team in CSS.

---

## 2. Design tokens (confirmed from served CSS)

### 2.1 Colour

```
--color-primary-yellow : #ffd400
--color-primary-black  : #0e1414
--color-primary-white  : #fcfcfc
```

Warm dark ramp — these are **brown-black, not grey**:
```
950 #1c1a15   900 #33312c   800 #3d3b35   700 #47453e   600 #534e42   50 #7e765d
```

Warm light ramp:
```
100 #f5f2ed   200/300 #ebe7df   600 #d6cbb6   900 #7e765d
```

Surfaces:
```
--color-surface-page          : #f9f8f7
--color-surface-light-brown   : #e8e6e2
--color-surface-lighter-brown : #e4e1d1
--color-border-brown          : #d9d3c9
```

Alpha bases, so every translucency stays in the warm family:
```
--black-rgb : 28, 26, 21     (#1c1a15)
--white-rgb : 251, 250, 249  (#fbfaf9)
```

**The single most transferable colour decision: there is no pure `#000` or `#fff` anywhere in the
layout system.** Against a warm ground, one saturated accent reads as a natural extreme rather than
a bolt-on brand colour.

Extended accents exist (blue/gold/green/purple/pink/red/teal ramps) but are reserved for data-viz
and illustration — they barely appear in layout.

### 2.2 Section theming — the highest-leverage idea on the site

```css
[data-surface=light] { --surface-background: var(--color-surface-page);     } /* #f9f8f7 */
[data-surface=dark]  { --surface-background: var(--color-neutral-dark-950); } /* #1c1a15 */
[data-surface=brown] { --surface-background: var(--color-neutral-light-200);} /* #ebe7df */
```

Each value also flips `--th-color-body` and `--th-color-body-subtle` between `--black-alpha-80` and
`--white-alpha-80`. Homepage usage: **brown ×5, dark ×4, light ×2.**

A whole page's visual rhythm from one HTML attribute per `<section>`. Highest leverage-per-line of
anything in this document.

### 2.3 Typography

Parsed from `/_next/static/media/serrif_condensed_regular-*.ttf`:

```
nameID 1  | Serrif Condensed
nameID 8  | Displaay Type Foundry s.r.o.
nameID 9  | Martin Vácha
nameID 11 | www.displaay.net
```

- **Display: Serrif Condensed** (Displaay, Prague). Commercial licence. Weights 400/500 only.
- **Body/UI: Inter**, with a metric-matched `Inter Fallback` to prevent layout shift.
- **Mono:** system stack, no webfont.

A **condensed** serif is the functional choice — it lets a 68px headline fit two or three words per
line without hyphenation, which is what their two-clause headline formula needs. *Any* condensed
display face gets this benefit; the specific licence is not the point.

Type scale — fluid, and note the asymmetry:

| Token | Desktop | Mobile | Δ |
|---|---|---|---|
| `5xl` | 68px | 45px | −34% |
| `4xl` | 56px | 30px | **−46%** |
| `3xl` | 40px | 28px | −30% |
| `2xl`–`xs` | — | — | **−6%** |

**Display sizes collapse hard on mobile; body sizes barely move.** Most teams do the reverse.

Line-height: `1` for display · `1.2` headings · `1.5` body. Tracking `-0.01em` dominant, `-0.02em`
at the largest sizes, `+0.03em` on uppercase eyebrows.

### 2.4 Radius, spacing, shadow

```
--radii-brand : .625rem (10px)   ← 96 usages, the button/CTA radius
--radii-s .5rem  --radii-m .75rem  --radii-l 1rem
--corner-s .4rem --corner-m .5rem  --corner-l 1rem
```

10px is off-grid on purpose — not 8, not 12. Nested cards use `calc(var(--corner-l) + 6px)`, which
is the correct nested-radius formula. Pills (`100px`/`999px`) are reserved for tags and chips.

Two spacing scales, deliberately separate: component (`.25rem` → `5rem`) and section
(`1.5rem`/`2.5rem`/`4rem`/`8rem` at ≥1024px). Component spacing tops out where section spacing
begins.

Shadows are mostly **hairline rings, not blurs**:
```css
box-shadow: inset 0 0 0 1px var(--white-alpha-10);
box-shadow: 0 32px 32px 0 #00000052, inset 0 0 0 2px var(--white-alpha-10);  /* hero UI shot only */
```
Only the hero product shot gets a real drop shadow, paired with a 2px inner light ring so a dark app
window doesn't dissolve into a dark section.

**There is not a single decorative colour gradient or glow.** The only textures are a 1px grid
overlay (`linear-gradient(#ffffff4d 1px, #0000 0)` plus its 90° twin), a marquee edge-fade mask, a
vignette, and a dot pattern. That grid is the "engineering blueprint" cue, done in two lines of CSS
instead of an illustration budget.

### 2.5 Motion

One easing token: `cubic-bezier(.246, .75, .187, 1)` — fast-out, long-settle. Durations cluster at
`.16s / .2s / .24s / .32s` and **nothing interactive exceeds .32s**. `prefers-reduced-motion`
referenced 4×.

### 2.6 The yellow CTA band

Fully tokenised (`--banner-bg`, `--banner-text`, `--banner-cta-bg`, `--banner-grid-line`, …).
5rem padding desktop / 1.5rem mobile, 1.5rem radius — a rounded inset band, **not** a full-bleed
stripe. Black text, black button, the 1px grid overlaid.

**The brand's loudest colour appears exactly once per page, at the moment of the ask.** Scarcity is
what makes it work. Do not put your accent in the nav *and* the hero *and* the footer.

---

## 3. Information architecture

### 3.1 The footer is a sitemap

Link counts: **Products 10 · Solutions 8 · Resources 7 · Support 5 · Company 5 · Compare 12+1.**
Compare is the second-largest column; Company — the column most sites over-invest in — is the
smallest. That ratio is the positioning thesis in one glance.

### 3.2 Compare pages use two URL patterns for two buyer mindsets

| Pattern | Brands | Intent |
|---|---|---|
| `/compare/<brand>` | stripe, chargebee, fastspring, lemon-squeezy, solidgate, gumroad | "paddle vs stripe" — evaluating |
| `/compare/<brand>-alternative` | adyen, cleverbridge, razorpay, recurly, zuora | "zuora alternative" — already leaving |

Each competitor is assigned to whichever query actually has volume for that brand. People *escape*
Zuora and Recurly; people *compare* Stripe.

**Investment is tiered, not templated.** `/compare/stripe` is six sections with a 10-row capability
table ending in a bolded "Effective total" row, three proof cards and a migration testimonial.
`/compare/lemon-squeezy` has **no comparison table at all** — because Lemon Squeezy is priced
identically and Paddle cannot win that on price.

### 3.3 The `/compare` hub redraws the category boundary

Fifteen competitors sorted into **"Merchant of Record competitors"** (5) and **"Payment providers &
related services"** (10) — and the second bucket includes **TaxJar and Avalara**, which are tax
tools, not processors. The grouping argues that if you are shopping for a tax vendor you are solving
the wrong problem. That is positioning work no individual page can do.

### 3.4 Product pages vs Solutions pages

| | Product (`/billing`, `/billing/checkout`) | Solutions (`/solutions/startups`) |
|---|---|---|
| H1 | Category keyword — "SaaS Recurring Billing software" | Audience + outcome — "Billing Infrastructure for Startups" |
| Subhead job | Claim the category | Name the fear — *"Your team builds. Paddle handles what breaks at scale."* |
| Links | Sideways to siblings, down to country pages | **Down into product pages** |
| SEO extras | FAQ schema + country link farm | None |

**Solutions is a funnel layer above Products, not a parallel one.** Same component kit, different
ordering and framing — no new design work per page.

Every product page runs the same three-section spine: **Increase conversions · Reduce cost &
complexity · Reduce risk.** That is a CFO's framing, written once and reskinned per product.

---

## 4. Copy

### 4.1 Headline patterns

**Two clauses, verb-first, separated by a period — gain then removed cost:**
> "Sell globally. Grow without the complexity."
> "Reach every market. Capture every opportunity."
> "Built for growth. Proven at scale."
> "Your team builds. Paddle handles what breaks at scale."

The period does real work: it turns one sentence into a claim plus a separate promise, and lets a
condensed display face set two short lines instead of one long wrap.

**Negation-of-category:** "Not just another payments platform" · "Move beyond stitching together
Stripe products" · "Ditch the spreadsheets"

**Prohibition-as-permission:** "Don't let billing, tax and subscription management hold you back."

### 4.2 The pain vocabulary

The formula is **[abstract obligation] + [visceral pain noun]**. "Compliance" and "tax" name the
thing; "headache", "admin", "the hard parts" name the feeling. "Headache" is the workhorse — it
beats "burden" and "complexity" in frequency because it is the most physical word available that is
still boardroom-safe.

> "**Take the headache out of** growing your software business" — *the universal final-CTA H2*
> "**Eliminate sales tax headaches** with full, automatic global tax compliance"
> "**We handle the hard parts for you**"

### 4.3 The pricing reframe

Paddle's rate is *higher* than Stripe's, so they change the denominator: publish one all-in number,
then reconstruct the competitor's from itemised add-ons (base 2.9% + tax 0.5% + churn recovery +
subscription billing + international + chargebacks…), ending in a row labelled **"Effective total
(subscription business)"** — Paddle "5% + 50¢" vs Stripe "More than 7.1% + 30¢".

They concede the sticker price and win the sum. Note for honesty's sake: their 7.1% loads unpriced
headcount into a percentage, and a sophisticated reader will catch it.

### 4.4 Three moves on the trust problem

1. **Reframe custody as liability transfer.** They explain the reseller mechanism in plain language
   — *"there are actually two transactions taking place during the sale"* — converting "a third
   party holds my money" into "a third party owns the risk." Structure is the reassurance.
2. **Own the worst artifact.** `/about/why-has-paddle-charged-me` is written for the *buyer* who
   sees an unfamiliar name on a card statement, and it is linked **from the final CTA of product
   pages**. Putting your most awkward question in your highest-intent slot kills the objection a
   prospective seller cares about most.
3. **Third-party proof, never self-assertion.** SOC 2 linked to audit docs, G2 badges,
   `security.paddle.com`, `status.paddle.com`.

Plus: **numbers are always specific and odd.** "$106,000+ recovered in 72 days." "87% MRR growth in
nine months." "$130 million in sales taxes remitted last year" — that last one is the clever one,
because it proves the boring regulated thing actually happens.

### 4.5 Competitor tone

Reframe, never disparage. They call Stripe Managed Payments "a positive step" before arguing Paddle
is purpose-built. Headings say "Thousands have **outgrown** Stripe" — not *escaped*. And the
highest-friction objection gets a testimonial aimed straight at it: *"The migration from Stripe was
way easier than I thought it would be."*

---

## 5. The seller dashboard

Recovered at full fidelity from homepage card assets and `developer.paddle.com` SVGs.

- **Hard inverted split:** near-black rail (`#0d0f0f`→`#181e1d`) against white/`#f3f5f5` content.
  Not a light sidebar with a border. The chrome is dark; the data is light. Two rail states —
  expanded and collapsed icon-only.
- **A balance card sits at the top of the rail, above navigation.** Micro-label "Balance", large
  value "US$ 120,567". **Money before navigation.** For a financial product this is the single most
  copyable decision on the page.
- **Page header = square app icon + title + plain-language subtitle** — "Billing overview" /
  *"Your business at a glance."* The cheapest onboarding you will ever ship.
- **Filters as dismissible chips, not a form:** `⌕ Filter | 📅 Aug 8, 2023–Aug 14, 2024 ✕ | +`.
  Every applied filter is a visible object you can remove individually.
- **KPI row is one bordered container split by vertical hairlines**, not three cards. Grey label
  ~14px, near-black value ~32px, delta as arrow + % in green ↗ / red ↙.
- **Charts:** single area chart, solid accent line with gradient fill, **dotted grey line for the
  comparison period**, exactly three gridlines, no legend, no chart junk. Period comparison as
  dotted-vs-solid means one accent hue does all the work.
- **Data tables carry in-cell bar charts** — a proportional light-tint bar filled behind the label
  cell, so the row is label and chart simultaneously at zero extra height.
- **Status pills:** fully rounded, uppercase, bold, white on saturated fill (green ≈`#0f7b5f`, red
  ≈`#d82a46`, blue ≈`#6aa8f5`). In list views: **status first, amount second** — the actual scan
  order.
- **Per-product accent hue, neutral shared chrome.** Billing is cyan, Metrics is teal-green. You
  know which product you are in from the chart colour, not a reskinned shell.
- **Brand warmth stops at the login wall.** The marketing site is warm and serif; the app is cool,
  neutral, Inter throughout, no yellow, no serif. Data gets neutral ground.

### 5.1 Two screenshot techniques worth copying

**Marketing:** oversize the app window, **crop it off the right edge** so ~60% shows (implies more
product than fits), rounded 16–20px corners, `0 32px 32px #00000052` + `inset 0 0 0 2px
rgba(255,255,255,.1)`. Float a second smaller artifact in front at a different scale. No 3D tilt, no
device frames. **And show one KPI trending down in red** — mixed results read as a real account;
all-green reads as a render.

**Docs:** draw screenshots as **redacted SVG wireframes** — real structure, real *teaching* element
(the status pill, the amount), everything else replaced by grey lorem bars. 15–46KB, crisp at any
zoom, and they never go stale when an unrelated column changes. For a small team this is *less*
maintenance than screenshots, not more.

---

## 6. Prioritised for Fuime

### 6.1 Marketing site

**P0**
1. **One `data-surface` attribute, three values.** Build page rhythm by alternating it per section.
2. **Warm the neutrals; delete pure black and white.** Set `--black-rgb`/`--white-rgb` so alphas stay
   in family. One afternoon; the whole site stops looking like a template.
3. **One accent, once per page, at the ask.**
4. **The two-clause period headline.** Write four, pick one.
5. **A CTA pair everywhere** — self-serve primary + human secondary. Never one, never three.
6. **Ship `/why-has-fuime-charged-me` and link it from the final CTA.** *This is the highest-value
   item in this document for Fuime specifically.* Fuime has Paddle's problem worse: **"Ninth Street
   Labs, LLC" appears on a buyer's statement for a purchase from a teenager's storefront.** That page
   is chargeback deflection, not marketing — and chargebacks are Fuime's liability under MoR
   (`MOR_RISK_ACCEPTANCE.md` §4).
7. **Reconstruct the competitor's total from add-ons**, ending in a bolded "Effective total" row.
   Fuime's version writes itself: a flat 7% with no fixed fee **beats 5% + 50¢ on every order under
   $25** — see `PADDLE_GAP_ANALYSIS.md` §6.

**P1**
8. Comparison pages, tiered — full build for the real threat, light pages for the rest.
9. Split compare URLs by intent (`/compare/x` vs `/compare/x-alternative`).
10. Separate Product pages from Solutions pages; make Solutions link down into Products.
11. Adopt the three-section spine on every product page.
12. Specific, odd numbers only in every proof card.

**P2** — the 1px grid gradient as the only texture · one easing token and a .16/.2/.24/.32s ladder ·
one off-grid signature radius · clamp display type hard on mobile and body type barely · a
metric-matched font fallback.

Fuime already has a marketing layout and a `/for/*` prefix (`config/routes.rb:1048-1052`,
`app/views/marketing/`) built so audience pages slot in — the IA work has somewhere to land.

### 6.2 In-app dashboard

**P0**
1. **Put the money above the navigation.** Fuime's equivalent of the balance card is the payable —
   *"Fuime owes you $84.20, paid Friday 15 August."* That phrasing is already mandated by
   `Fuime::PayablesLedger`, which exists specifically to keep operator-facing copy off the word
   "balance." The compliance constraint and the design move agree here.
2. **Invert the chrome** — dark rail, light content.
3. **Filters as dismissible chips.**
4. **KPI row as one container with hairline dividers.**
5. **Page header = icon + title + plain-language subtitle.**

**P1**
6. Period comparison as a dotted line, not a second colour.
7. In-cell bar charts in data tables.
8. Status pills; status first, amount second in list views.
9. Info `(i)` beside every non-obvious form label — for a product explaining fees, holds and taxes to
   teenagers and their parents, this is where the explanation belongs.

**P2** — redacted SVG wireframes for docs · oversized cropped hero shots with a floating second
artifact · one red KPI in the marketing screenshot.

---

## 7. Sources

paddle.com served CSS and `_next` bundle · the Serrif Condensed binary's `name` table ·
paddle.com (home, /pricing, /billing, /billing/checkout, /billing/reporting, /solutions/startups,
/compare, /compare/stripe, /compare/lemon-squeezy) · developer.paddle.com ·
paddle.com/blog/why-we-refreshed-the-paddle-brand · Displaay Type Foundry.

One published third-party teardown attributes the display face to Dinamo — **that is wrong**; the
font binary says Displaay.
