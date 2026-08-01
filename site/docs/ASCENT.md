# ASCENT — the fuime build plan

Synthesised from three directions and three judge panels. **The spine is INSTRUMENT.**
It won two of three panels and the tally (242 / 236 / 179), and it won on the only thing
that matters twice over: it is the only direction that adds facts a hostile parent can
check, and it is the only direction whose fallback would actually get built.

**Its costume is cut.** All three panels independently hit the same target — uppercase mono
micro-type, a fixed edge rail, plate numbering, corner registration marks, HUD readouts.
Panel 1 called it the most saturated aesthetic on Awwwards. Panel 2 called it the exact
register a suspicious parent associates with crypto. That is not a taste note, it is two
independent kill shots on one component, so the component goes.

What replaces it is DOCUMENT's paper register, and this is not a blend — it is the fix for
INSTRUMENT's named defect using the runner-up's named strength. Panel 2's fatal on DOCUMENT
was "it reframes everything and adds nothing I can check." INSTRUMENT is exactly the missing
substance. Panel 2's fatal on INSTRUMENT was the terminal costume. DOCUMENT's ledger register
is exactly the cure. The two losing complaints cancel, and the word that resolves them is
**ledger**: a ledger is an instrument that computes and a document that a 45-year-old already
trusts, and it is literally what this product makes.

WORLD contributes three things and nothing else: the negative-space pricing band, the
`border-radius` arch draw (resolution-independent where both other directions reached for a
hand-authored SVG path that breaks on resize), and the observation that `/parents` has no
portrait hero. Its spine — a stitched photographic dusk plate — is cut, because its own author
conceded it would probably be abandoned for the procedural fallback, and a signature that dies
with its own fallback is not a signature.

Read `docs/BRIEF.md` first. It outranks this file everywhere they touch.

---

## Thesis

fuime's site is a working ledger: the price is a live line you can drag, every claim on it is a
figure you can check, and it is set as paper — creased, ruled, tabular — because paper is the
one instrument a parent already trusts.

---

## The Signature

**THE SPLIT.** One rule across the page, divided into three segments, showing exactly who gets
what out of your money — and you can drag it.

The thing itself: a hairline-ruled horizontal rule, 10px tall, running the full width of the
wrap directly beneath the calculator. Three segments, proportional, labelled underneath in the
site's own type with tabular figures:

```
├──────────────────────────────────────────────────┼───────┼────┤
  YOU  $360.10  90.0%                       FUIME  7.0%   STRIPE  3.0%
```

It resizes live under your thumb. A parent reads the fee structure proportionally in under a
second without reading a word, and sees that the largest segment by an enormous margin is their
kid's.

**Why it is fuime's and no one else's.** Three reasons, and the third is the one that makes it a
signature rather than a widget.

1. It is the product's actual argument rendered as its actual shape. fuime's whole pitch is
   "7% of what you collect, and Stripe's cut is separate and we show it." The split _is_ that
   sentence, drawn.
2. Nobody else can run it. A bank can't draw this bar because the bar would show their cut is
   most of it. A crypto app can't draw it because the honest version is embarrassing. It is
   only a flattering object if your fee is genuinely small, which makes it unforgeable.
3. **It is the same form at three scales, and that is the system.** Full-width in the console
   band as the artifact. 2px docked under the nav on all three pages, carrying the live number
   at every scroll position. And one line inside the invoice sheet itself, where the arithmetic
   is stated in words. The existing site already has one motif that works at three scales — the
   arch (loader glyph, portrait window, portal). Now it has two, and they divide the labour
   cleanly: **the arch is the door, the split is the money.**

**It fixes the flaw the panels named.** Panel 1's complaint about INSTRUMENT was that its
signature only exists once a judge decides to drag something. The split is on screen, visibly
proportional, from first paint — docked at 2px under the nav before you have scrolled anywhere,
full-width and already divided when the console band arrives. Dragging only makes it _move_.
And it takes a screenshot: when the console band first enters view the rule draws left to right
over 240ms and _then_ the three ticks drop in at their computed positions 40ms apart. Structure
arrives before data — INSTRUMENT's matrix boot order, applied to the one object that earns it.

**Cost to build.** `fx/split.js` is roughly 130 lines and injects roughly 60 lines of CSS. No
dependencies, no assets, no WebGL, no font. It subscribes to one `CustomEvent` published by
`fx/ledger-bus.js` and never touches the DOM it does not own. The nav-docked instance is the
same module with a different mount target. Half a day, and it is the half-day with the highest
return in this document.

---

## Opening Five Seconds

First visit only — `sessionStorage 'fuime.booted'` already gates this and stays. Hard cap drops
from 3200ms to 1200ms. Any input — scroll, tap, keypress — aborts straight to the landed state.

**t = 0ms.** `#141420` edge to edge, painted from the inline first-paint CSS already in
`index.html`. No white frame, ever, on any page, at any width — this is the only unrecoverable
failure in the budget and it is already solved on `/`; it gets ported to `/pricing` and
`/parents`, which currently flash. The arch outline sits centred at one hairline, unfilled. The
hero LQIP is already behind it. Nothing moves. No spinner, no percentage, no counter.

**t = 200ms.** The arch is filling bottom-up against the real three-step manifest in
`site.js` — untouched, it is the most honest thing on the site. To its right, **the receipt**:
three ruled lines appearing as their resource actually resolves, right-aligned figures, one
hairline rule above the last, set exactly like the invoice eleven screens below.

```
Typeface                              OK
Frame                             244 KB
Document                              OK
```

The figure is `PerformanceResourceTiming.encodedBodySize`, same-origin only. Where a resource is
cross-origin or served from cache the number is genuinely unavailable, so the row reads `OK` —
a receipt line with no figure is still a receipt line, and printing a fabricated kilobyte count
on a page about honesty would be the single funniest way to fail this brief.

**t = 800ms.** The handoff, and it is the money moment. The filled arch does one continuous FLIP
to the nav mark's measured bounding rect — 620ms on `--ease`, travelling up-left, scaling down,
landing where the logo lives. Nothing fades out. The loader _becomes_ the chrome. Behind it the
hero photograph is **already painted at full size, unmasked and untransformed** — what animates
is a night-coloured, arch-shaped scrim above it that shrinks away. This inversion is
non-negotiable: the hero is the LCP element and Chrome measures LCP at the end of a masked
reveal, so animating the image itself would spend 600ms of AC10 on a flourish. Identical to the
eye. Zero measured cost.

At the same moment the receipt collapses rightward and becomes the nav's live figure, and the
2px split docks beneath the nav bar, already divided.

**t = 2s.** The headline has struck — a `mask-image` wipe from the baseline upward and left to
right, 320ms, 90ms between the two lines, on a **fully opaque element**. Ink is laid down, never
faded in, so the text never touches `opacity` and cannot leave a blank page or regress LCP. Lead,
capture form and the price line have landed as blocks 90ms apart. The hero still has crossfaded
into `hero-live-web.mp4` (120KB, already encoded, poster is frame 1, verified pixel match, so
there is no pop) and the valley lights are breathing.

Under the CTA, above a hairline, static since 1.1s:
**7% of what you collect. No monthly fee until you're earning.**

**t = 5s.** The clip is still running its single pass. When it ends at ~6.9s it freezes on its
last frame and does not loop — a photograph that happened to be breathing and then settled reads
as film; a loop reads as a WordPress video header. From then on the only things on the page that
change are the split's figures when a hand moves them, and the nav's ground opacity as you
scroll. **The confidence to stop moving is the institutional signal**, and almost nobody copies
it from award sites.

Zero inputs demanded. Zero rituals performed. The price was on screen at 1.1 seconds.

---

## Stage Map

### index.html

| Section               | What it is now                                                                              | What it becomes                                                                                                                                                                                                                             | What moves                                                                                                                       | Trigger                                                      | Module                                                 |
| --------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------ |
| Loader (`#boot`, :96) | Arch fills against a real manifest, exits on opacity + `scale(1.12)`                        | Same engine, plus **the receipt** — three ruled lines with real byte figures. Exit is a FLIP onto the nav mark                                                                                                                              | Arch fill; receipt rows; 620ms FLIP; arch-shaped scrim shrinking off the hero                                                    | Real network progress, capped 1200ms, abortable by any input | `handoff.js`                                           |
| Nav (:110)            | Fixed 72px, binary `.nav--over` → `.nav--solid` flip                                        | Continuous ramp. Carries the landed mark, the live fee figure, and the 2px split                                                                                                                                                            | Ground alpha + bottom hairline 0→1 across hero height; drawer 40ms per-link stagger                                              | `stage.scroll` vs hero height                                | `split.js`, orchestrator CSS                           |
| Hero (:139)           | 100svh plate, `<picture>` + wired `<video loop>`, pointer glow, ±18px drift                 | Same composition — it is the best asset on the site. Adds the struck headline, the price line, still→video handoff, `loop` removed                                                                                                          | Headline strike; block arrivals 90ms apart; one video pass then freeze; ≤6px pointer depth                                       | Load, then pointer                                           | `strike.js`, `live.js`                                 |
| Strip (:236)          | 11 trades, 42s linear marquee, `aria-hidden` on the only row                                | The tape. Speed couples to scroll velocity, floor 0.35×, 900ms decay to base. Carries a `WORKED EXAMPLES` label                                                                                                                             | Marquee rate                                                                                                                     | Reader's own scroll velocity                                 | `tape.js`                                              |
| Calculator (:255)     | Two columns, live arithmetic, `textContent` swap, **no mobile override — clipped at 390px** | **THE CONSOLE.** Full-width collapse on mobile. Digit rolls, causal restrike, the $250 tick, and **THE SPLIT**                                                                                                                              | Rule draws then ticks drop (240ms + 40ms); per-digit roll 180ms/12ms; 4-row restrike 40ms apart; segment widths; ≤4px sheet tilt | **A hand moved.** Never a viewport                           | `split.js`, `threshold.js`, `roll.js`, `ledger-bus.js` |
| The problem (:350)    | Four `.card` boxes, identical 14px fade                                                     | **The crossed-out list.** Four ledger rows on night: hairline draws, icon strokes itself in, then a rule is struck through the method label                                                                                                 | Rule draw 240ms → icon `stroke-dashoffset` 320ms → strike-through 240ms, 60ms after                                              | IntersectionObserver, one shot                               | `rows.js`                                              |
| Seam (keys, ~:425)    | Full-bleed photograph doing nothing                                                         | A plate. Clip-inset reveal from its top crease, 1.06→1.00 scroll-coupled scale, caption below                                                                                                                                               | Clip + scale + ≤24px parallax                                                                                                    | `stage.scroll`, continuous, reversible                       | `plate.js`                                             |
| How it works (:439)   | Three steps, three identical fades, tiles rendering 351×600                                 | The tracked sequence. A hairline spine fills downward; step 2 does not begin until step 1 lands. `REQUIRES GUARDIAN` chip on step 02                                                                                                        | Spine ink height; per-step 4-beat: numeral 0 → rule 80 → tile 160 → copy 240ms                                                   | `stage.scroll` across the band, reversible                   | `steprail.js`                                          |
| Money (:561)          | Three `.card.price` boxes                                                                   | **The terms table.** Three ruled rows, label left, figure right in display 480 with tabular figures, set like a fee schedule on the back of a bank statement. **This is the still point — the one band where no ambient craft runs at all** | Rules draw in, 200ms, 60ms stagger. That is the entire budget                                                                    | IntersectionObserver, one shot, over before you look         | `rows.js`                                              |
| For parents (:613)    | Tall arch + four `.grid--2` cards, ~400px void bottom-right at 1440                         | Arch keeps its window; right column becomes four ruled entries running the arch's full height, killing the void                                                                                                                             | Arch `border-radius` draw; ≤6px window parallax                                                                                  | Scroll                                                       | `arch.js`, `plate.js`                                  |
| Join / portal (:703)  | Arch arrives fully formed and inert, 13px of drift                                          | The bookend. The arch **draws** — `border-radius` from `var(--r)` to `9999px 9999px var(--r) var(--r)`, scroll-coupled, complete before the band reaches viewport centre. `portal-live-web.mp4` plays once behind it, then holds            | Radius animation; one video pass                                                                                                 | `stage.scroll`                                               | `arch.js`, `live.js`                                   |
| Footer (:763)         | Static                                                                                      | One honest status row: `Status ······ Onboarding the first businesses`                                                                                                                                                                      | Nothing                                                                                                                          | —                                                            | orchestrator                                           |

### pricing.html

| Section               | What it is now                                                                  | What it becomes                                                                                                            | What moves      | Trigger | Module                                |
| --------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | --------------- | ------- | ------------------------------------- |
| Head                  | No `darkreader-lock`, no `theme-color`, no inline first-paint CSS, no loader    | Byte-identical shared chrome with `/`. Sets `fuime.booted` so a visitor landing here first never gets a mid-session loader | —               | —       | orchestrator                          |
| Nav                   | Plain                                                                           | Carries the docked split + live fee read from `sessionStorage`                                                             | Ground ramp     | Scroll  | `split.js`                            |
| Hero (`.hero--short`) | No mobile art direction, no CTA, contrast marginal                              | 4:5 portrait source at ≤900px; scrim extended for short heroes; a capture form ends it like every other hero               | Headline strike | Load    | `strike.js`                           |
| Calculator            | `class="calc split"`, slider max **5000**                                       | Identical console to `/`, range unified at 25–2000, full split + threshold                                                 | As `/`          | Hand    | `split.js`, `threshold.js`, `roll.js` |
| Fee table             | Cards                                                                           | The terms table, shared with `/`                                                                                           | Rules draw      | IO      | `rows.js`                             |
| Handover claim        | **Asserts the 18th-birthday handover as shipped fact — contradicts `/parents`** | Reconciled to `/parents`'s honest version. **Blocking trust defect, fixed before any craft work**                          | —               | —       | orchestrator                          |
| Footer                | Byte-identical to `/` — good                                                    | Unchanged plus the status row                                                                                              | —               | —       | orchestrator                          |

### parents.html

| Section            | What it is now                                                                                           | What it becomes                                                                                                                                                                                                            | What moves                            | Trigger | Module                           |
| ------------------ | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | ------- | -------------------------------- |
| Head               | Same three omissions as pricing                                                                          | Shared chrome, byte-identical                                                                                                                                                                                              | —                                     | —       | orchestrator                     |
| Hero               | Landscape-only sources (900×502); no portrait cut; `.hero__note` measures **3.90:1 at 390px — AC4 FAIL** | Native 4:5 kitchen-table frame at ≤900px, composed with dark sky where the type sits; scrim extended                                                                                                                       | Headline strike                       | Load    | `strike.js`                      |
| Arch               | Static image with rounded corners                                                                        | A window. `parents-live-web.mp4` (164KB, already on disk) plays once behind it, ≤6px parallax between contents and frame                                                                                                   | Radius draw; parallax; one video pass | Scroll  | `arch.js`, `live.js`, `plate.js` |
| Reassurance cards  | `<div class="grid">` with no modifier                                                                    | Ruled ledger entries, uniform rows                                                                                                                                                                                         | Rules draw                            | IO      | `rows.js`                        |
| Custodian          | Buried in a card                                                                                         | **Promoted to its own hairline-boxed row**, legible at 1440 without scrolling: `Custodian of identity documents ······ Stripe, Inc.` Naming who actually holds the documents is the strongest trust asset the product owns | Nothing                               | —       | orchestrator                     |
| `.archline` (:309) | **A class that does not exist in style.css**                                                             | Deleted                                                                                                                                                                                                                    | —                                     | —       | orchestrator                     |
| FAQ                | ≥6 questions — good                                                                                      | Unchanged. Answer visible first, reasoning one `<details>` away, never the reverse                                                                                                                                         | —                                     | —       | —                                |
| Footer             | Byte-identical — good                                                                                    | Plus status row                                                                                                                                                                                                            | —                                     | —       | orchestrator                     |

---

## Modules

All files live in `/Users/angus/dev/fuime-site-mercury/site/fx/`. `stage.js` and `scene.js` are
already vendored and byte-identical to the `webgl-scene-kit` skill — **do not re-copy, do not
edit, do not import `scene.js` anywhere.** No module imports three.js. This build ships zero
WebGL, which is why it fits inside AC10 with roughly 900KB to spare.

### House constraints — these apply to every module below, and the orchestrator hands this block to every build agent verbatim

1. **ES module.** `export function init<Name>(target, config) → handle` where `handle` has at
   minimum `{ destroy() }`. No default export. No side effects at import time.
2. **Injects its own CSS** from a template string into a single
   `<style data-fx="<name>">` appended to `<head>` on first init, guarded so a second init does
   not duplicate it. Every selector is namespaced `.fx-<name>__*` or scoped under a
   `[data-fx-<name>]` attribute the module sets itself.
3. **A hex literal inside an fx file is a build failure** (AC2). Read colours at init:
   `getComputedStyle(document.documentElement).getPropertyValue('--night').trim()`. Never a
   literal, never in a template string, never as a config default.
4. **Never edit `style.css`, `site.js`, `index.html`, `pricing.html` or `parents.html`.** If a
   module needs markup or a token, it goes on the integration list at the end of this section
   and the orchestrator makes the change. This is how parallel work avoids collisions.
5. **Opt in to motion, never out.** The injected CSS ships the element's **final** state as its
   default and the module removes it only after confirming `stage.reducedMotion === false` _and_
   successfully binding its trigger. A JS error, a print stylesheet, a text-mode reader or a
   non-scrolling renderer must all produce the full static design. This inverts the live
   `.rise { opacity: 0 }` trap that currently renders a blank page if anything throws.
6. **One rAF loop.** Get it from `import { getStage } from 'cwe/stage'` and subscribe with
   `stage.register(cb) → off`. Never call `requestAnimationFrame` yourself. Never read
   `window.scrollY` — read `stage.scroll`. Call every returned unsubscribe in `destroy()`.
7. **One scroll owner: native.** No Lenis, no smooth-scroll library, no scroll hijack, no
   pinning, no horizontal page sections. Nothing may call `stage.setScroll()`.
8. **Nothing may delay or obstruct the two conversion actions** — the waitlist email capture and
   reading what it costs. No overlay over a form, no motion on a numeric field, no
   `pointer-events` layer above the CTA.
9. **Nothing over 300ms in the UI layer.** Navigation ceremony (the loader FLIP) and photography
   (video crossfades, the arch draw) are exempt and are the only exemptions.
10. **Mobile is first-class**, not the desktop version with effects removed. Where a module
    behaves differently on a phone, that difference is specified below and is a design, not a
    fallback.

---

### `fx/ledger-bus.js`

**The shared dependency. Build this first; nothing else works without it.**

```js
export function initLedgerBus(config) → {
  state,        // current fee state, readable synchronously
  set(charge),  // programmatic set, same path as a drag
  motion,       // { reduced, coarse, saveData, tier }
  destroy()
}
```

**Skill composed:** `webgl-scene-kit` (`stage.js` only — zero-dependency rAF/pointer/scroll/
reduced-motion bus). Doctrine from `review-animations` for the quality tier.

**Config keys:** `stripePct` (0.029), `stripeFixed` (0.30), `fuimePct` (0.07),
`monthlyThreshold` (250), `monthlyFee` (15), `sliderSelector` (`.calc__range`),
`storageKey` (`'fuime.fee'`), `eventName` (`'fuime:fee'`).

**What it does.** Two jobs and no others.

_Job one — the fee is a pure function._ It recomputes the arithmetic itself from the slider
value rather than observing what `site.js` writes to the DOM:

```js
const stripe = charge * stripePct + stripeFixed
const fuime = charge * fuimePct
const lands = charge - stripe - fuime
const over = charge >= monthlyThreshold
```

Then it publishes on `document`:

```js
new CustomEvent('fuime:fee', { detail: { charge, stripe, fuime, lands, over } })
```

and mirrors `{charge, over}` into `sessionStorage` so `/pricing` and `/parents` open showing the
same reading. **Every other module subscribes to this event and never to the DOM, never to
`site.js`.** Zero MutationObservers, zero coupling, and the first time someone renames a class
nothing breaks. `site.js` keeps writing its own values in parallel and that is fine and
deliberate — it is the JS-fails floor.

_Job two — one motion gate._ Exposes `motion.reduced` (live, off the media query, updating on
change), `motion.coarse` (`(hover: none) and (pointer: coarse)`), `motion.saveData`
(`navigator.connection?.saveData`), and `motion.tier` (`'high' | 'low'`) from a rolling 60-frame
mean frame time: downgrade above 22ms, upgrade below 12ms, 180-frame cooldown. **Reduced-motion
and quality logic exists in exactly one file so there is exactly one thing to test.**

**CSS injected:** none. This module is logic only.

**Stage:** takes the singleton via `getStage()` and registers one callback purely to sample
frame time for the tier. Nothing else.

**Reduced motion:** it is the thing that reports reduced motion. It never animates. It fires the
same event on the same schedule regardless — the arithmetic was never the animation.

**Mobile:** identical. Binds `input` on the range, which covers touch drag natively.

**Failure mode:** if `.calc__range` is absent (on a page with no calculator) it hydrates from
`sessionStorage` and fires one event at init so the nav split still renders, then idles. If
`sessionStorage` is unavailable (private mode, some embedded webviews) it falls back to an
in-memory value and the cross-page continuity is silently lost — no throw, no console noise.
Every subscriber must therefore tolerate never receiving an event and render its static default.

---

### `fx/split.js`

**The signature. The single highest-value file in this build.**

```js
export function initSplit(target, config) → { refresh(), destroy() }
```

**Skills composed:** `stripe-level-ui` and `emil-design-eng` for the surface;
`make-interfaces-feel-better` #9 (tabular figures) and #11 (image/edge outlines pure black or
white at low alpha, never a tinted neutral).

**Config keys:** `mode` (`'full' | 'dock' | 'inline'`), `height` (10 for full, 2 for dock),
`labels` (true for full, false for dock), `drawOnEnter` (true for full), `drawMs` (240),
`tickMs` (40), `resizeMs` (180), `eventName` (`'fuime:fee'`).

**What it does.** Renders one hairline-ruled rule divided into three proportional segments —
YOU, FUIME, STRIPE — with the figures under it. Three mount modes, one object:

- `'full'` — beneath the calculator, 10px tall, full wrap width, labelled underneath:
  `YOU $360.10 90.0%` / `FUIME 7.0%` / `STRIPE 3.0%`. Segment order is always
  YOU-first-and-largest, left to right, because that is the fact.
- `'dock'` — 2px, pinned under the nav bar on all three pages, unlabelled, `aria-hidden`,
  carrying the same proportions. This is what puts the fee permanently on screen at every
  scroll position on every page, which makes "they're hiding the number" structurally
  impossible to think.
- `'inline'` — one flat rule inside the invoice sheet, above the total row.

**The entrance, which is the screenshot.** On the `'full'` instance only, when the console band
first intersects: the rule draws left to right over 240ms, **and only then** do the three ticks
drop in at their computed positions, 40ms apart. Structure arrives before data. One shot,
IntersectionObserver, then unobserve. This is the one place a viewport-triggered entrance is
doing real semantic work, because what it is animating is the _frame_, not the _number_.

**Every subsequent change is caused by a hand.** Segment widths transition on `width` over
180ms; figures are handed to `roll.js` if present and set with `textContent` if not. **No
number on this site ever moves because a viewport moved.**

**CSS injected.** Flex row of three segments with `width` in percent; 1px dividers built from
`--hair` on light grounds and `--on-dark-faint` on dark; segment fills at low-alpha ink,
never accent — accent is reserved for primary buttons and the wordmark's `i` (AC3). Labels at
`--t-small`, tracking `0.04em`, `font-variant-numeric: tabular-nums lining`. The rule sits on
`--paper` with a `--hair` outline and no shadow, because this site's boxes have edges, not
glows.

**Reads the Stage:** it does not, except through `ledger-bus`. No `stage.register` callback at
all — it is event-driven and CSS-transitioned. Zero per-frame cost.

**Reduced motion:** ships fully drawn and fully divided as the CSS default, at the value it
hydrates from `sessionStorage` or the slider's `value` attribute. Widths still change on drag —
that is a state change, not an animation — but instantly, with `transition: none`. The entrance
draw does not run. **This is arguably the better readout and it is the whole reduced-motion
argument in one object.**

**Mobile:** `'full'` spans gutter to gutter and the labels wrap to two lines under their
segments rather than shrinking below `--t-small`. `'dock'` stays at 2px directly under the nav —
this is the _only_ fixed chrome on a phone, it is 2px, it carries no text, and nothing else may
be pinned anywhere. No bottom bar, ever: nothing competes with the CTA or fights the iOS safe
area.

**Failure mode:** if no `fuime:fee` event ever arrives, it renders the static default from
`data-*` attributes on its own mount point (orchestrator supplies them) and never moves. If the
three percentages do not sum to 100 within 0.1 (rounding), it renders the two known segments and
gives the remainder to YOU rather than showing a gap — a gap in this bar reads as a hidden fee
and is the worst possible failure.

---

### `fx/threshold.js`

```js
export function initThreshold(target, config) → { destroy() }
```

**Skill composed:** `review-animations` #2 (frequency-appropriate motion — an element that
updates on every keystroke gets no animation).

**Config keys:** `threshold` (250), `rangeSelector` (`.calc__range`),
`readoutSelector` (`[data-out="monthly"]`), `label` (`'$250 / 30 days'`).

**What it does.** Two things.

1. Draws a tick on the slider track at the threshold's **true proportional position**
   `(250 − min) / (max − min)`, with a small label beneath it. It is a physical position on the
   instrument, not a footnote.
2. Executes the monthly readout's state change `$0/mo → $15/mo` with **zero easing** while every
   other number on the page interpolates.

**The law this encodes, and it is the only motion decision in this build that carries meaning
rather than style: thresholds do not interpolate, quantities do.** Dragging past the tick throws
the readout like a switch. That single detail teaches the entire pricing model in one drag, to
both readers, with no copy. It also means this module is the one place where "no animation" is
the _designed_ behaviour rather than the degraded one, which is why its reduced-motion path is
identical to its full path.

**CSS injected:** the tick (1px, `--ink-muted` on cream, `--on-dark-mu` on night), its label at
`--t-small`, and a `transition: none !important` on the readout scoped to its own attribute —
the only `!important` permitted in this build, and only because an inherited transition would
silently defeat the entire point of the module.

**Stage:** none. Subscribes to `fuime:fee`.

**Reduced motion:** identical. It had no animation to remove.

**Mobile:** the tick draws at the same true position on a 44px-tall track with a 28px thumb.
Thumb-dragging a threshold and feeling `$0` throw to `$15` under your finger is a better
interaction than with a mouse, and it is the one place the phone genuinely wins.

**Failure mode:** if the slider's `min`/`max` cannot be read as numbers, the tick is not drawn
at all rather than drawn in the wrong place — a tick at the wrong position is a lie about the
pricing model. The readout still throws.

---

### `fx/roll.js`

```js
export function initRoll(root, config) → { refresh(), destroy() }
```

**Skills composed:** `kinetic-type` (numeral path only — `mode: 'scramble'` is banned by name on
this site; numbers that decode from garbage on a page about someone's money actively teach
distrust). `make-interfaces-feel-better` #9.

**Config keys:** `selector` (`[data-out]`), `digitMs` (180), `stagger` (12),
`restrikeOrder` (`['charged','stripe','fuime','lands']`), `restrikeGap` (40).

**What it does.** Per-digit odometer roll on the calculator's figures: each changed digit
y-translates 180ms with a 12ms stagger across the number, `font-variant-numeric: tabular-nums
lining` enforced so nothing reflows. Then the invoice's four rows **re-strike in causal order** —
charge, then Stripe's cut, then fuime's 7%, then what lands — 40ms apart, so the arithmetic is
shown happening rather than swapped. That sequence is the site's whole pricing argument
delivered as motion instead of a claim.

**It fires on `input` and `pointer` events only. Never on IntersectionObserver.** Count-up-on-
scroll is banned by name: a number may move because a hand moved, never because a viewport
moved. Same animation, opposite signal, and the only difference is causality.

**CSS injected:** a digit column mask and `transform` per glyph, scoped under
`[data-fx-roll]`. Sets `font-variant-numeric` on its targets. No colour flash — the existing
accent tint on `data-live` is removed by the orchestrator under AC3.

**Stage:** none per-frame. Uses CSS transitions.

**Reduced motion:** **snaps.** The number changes instantly and is correct, tabular, no reflow.
The four rows update in the same frame. The argument is intact; the arithmetic was never the
animation.

**Mobile:** identical. The figures are the largest thing on a phone screen, so the roll reads
better there than on desktop.

**Failure mode:** if a target's text is not parseable as a formatted number it is set with
`textContent` and not rolled. If two `input` events land inside one roll, the in-flight roll is
cancelled and restarted from the current rendered value — interrupting always leaves a valid end
state, never a half-rolled digit.

---

### `fx/crease.js`

```js
export function initCrease(config) → { destroy() }
```

**Skills composed:** `make-interfaces-feel-better` (surfaces — hairlines and edges over shadows
and glass), `emil-design-eng`.

**Config keys:** `selector` (`.band`), `ridge` (1), `valley` (3), `curl` (40).

**What it does.** Renders every band boundary as a **fold** rather than a colour change: a 1px
lit ridge on the incoming panel, a 3px soft shadow valley beneath it, and a ~40px page-curl
gradient into the panel above. Achieved with injected CSS on sibling selectors
(`.band + .band::before` and friends) built entirely from existing tokens.

**Zero rAF. Zero JS after init. Roughly 2KB.** It is the cheapest reclassification available:
four seconds after landing, a reader registers that the boundaries are folds and the whole page
moves from _website_ to _object_. It works identically at 390px, in print, under reduced motion,
and with JavaScript disabled — the only signature-adjacent element in this document that is
continuously visible rather than confined to one sub-second window.

**CSS injected:** all of it. This module is a stylesheet with an init function.

**Stage:** does not read it.

**Reduced motion:** unchanged. It is static by construction.

**Mobile:** unchanged, and this is where it earns most — a phone is a portrait column and a
document is a portrait column, so scrolling a phone through this site reads as unfolding a strip
of paper one panel at a time.

**Failure mode:** if the band alternation is not night/cream as expected, the ridge and valley
read as a flat hairline, which is still correct and still better than a hard colour edge. It
cannot produce a visual defect, only a weaker version of itself.

---

### `fx/strike.js`

```js
export function initStrike(target, config) → { replay(), destroy() }
```

**Skill composed:** `kinetic-type` (reveal mode, `split: 'lines'`, built-in splitter, GSAP-free).

**Config keys:** `selector` (`h1, .h2`), `lineMs` (320), `lineGap` (90),
`velocityToSkew` (**0** — locked; velocity skew on a fintech headline is where premium tips into
unstable), `autoplay` (true), `threshold` (0.85).

**What it does.** The type move, and it is a wipe, not a fade. A `mask-image` gradient travels
from the baseline upward and left to right across each line, 320ms, 90ms between lines, **on a
fully opaque element**. Ink is laid down; ink does not fade in.

Two consequences that are the reason this technique was chosen over every alternative: the
element never touches `opacity`, so it cannot regress LCP and cannot leave a blank page; and the
headline is _partially revealed_ for 320ms rather than _invisible_ for 320ms, so the value
proposition is never withheld. Per-letter, per-word, scramble, decrypt and typewriter treatments
are all banned — the headline is the argument and delaying its legibility to look clever trades
the only sentence that matters for a trick.

**CSS injected:** the mask gradient and its transition, scoped under `[data-fx-strike]`. The
**final, fully-visible state is the CSS default**; the module applies the masked start state
only after confirming motion is available and its observer is bound.

**Stage:** reads `stage.reducedMotion` at init. No per-frame callback.

**Reduced motion:** the headline is simply present, fully legible, at first paint. Nothing to
remove because nothing was ever added.

**Mobile:** identical, and the h1 must land in two lines at 390px — verified by screenshot, not
asserted.

**Failure mode:** if the line splitter cannot resolve line boxes (a font swap mid-measure is the
realistic cause), it treats the whole heading as one line and wipes it in 320ms. It never leaves
text hidden: a `finally` block clears the mask unconditionally after `lineMs + lineGap × lines +
200ms` regardless of what happened.

---

### `fx/rows.js`

```js
export function initRows(target, config) → { destroy() }
```

**Skills composed:** `make-interfaces-feel-better`, `emil-design-eng` (clip and stroke reveals),
`review-animations` as the gate.

**Config keys:** `mode` (`'strike' | 'plain'`), `ruleMs` (240), `iconMs` (320),
`strikeMs` (240), `strikeDelay` (60), `stagger` (60).

**What it does.** Draws the hairline rules on the converted card sets, left to right, and in
`'strike'` mode adds the two extra beats:

1. The row's rule draws left → right, 240ms.
2. The row's inline SVG `.icon` strokes itself in via `stroke-dashoffset`, 320ms. The paths
   already exist in the markup, so this costs nothing.
3. 60ms later, a rule is **struck through the method label** — Venmo → mom, Cash, "I'll get you
   next week", A business account — left to right, 240ms.

Four ways of getting paid, crossed off a list, in front of you. This is the most memorable band
below the fold and **the motion is the copy, executed** — not decoration around it. It is the
one place scroll-triggered entrance animation earns its keep, because a line drawing wants to be
drawn and a rejected option wants to be crossed out.

`'plain'` mode is the same rule-draw with no icon and no strike, used on the money band
(200ms/60ms and nothing else — a price table that performs is a price table that is selling you
something) and the parents ledger.

**CSS injected:** `stroke-dasharray`/`stroke-dashoffset` on `.icon` paths and a `scaleX`
transform-origin-left rule, all scoped under `[data-fx-rows]`. **Final state — rules present,
icons drawn, labels struck — is the CSS default.**

**Stage:** one IntersectionObserver, one shot, then unobserve. No per-frame callback.

**Reduced motion:** everything renders in its final state at first paint. The rules are there,
the icons are drawn, **and the four methods are struck through** — the argument lands with no
motion at all.

**Mobile:** identical. The rows stack naturally; the strike-through is more legible at 390px
than at 1440px because the labels are shorter relative to the measure.

**Failure mode:** if the SVG paths have no measurable length (`getTotalLength()` returns 0 on a
`<use>` reference in some engines), the icon step is skipped and the rule and strike still run.
The module must not throw on a card set that has no icon at all.

---

### `fx/handoff.js`

```js
export function initHandoff(config) → { destroy() }
```

**Skills composed:** `cinematic-loader` (doctrine only — the engine is already built and better
than the skill's: first-paint CSS inline in `<head>` above every script, `svh` never `vh` in the
loader placeholder, hard cap, dismissible). `emil-design-eng` (blur to mask an imperfect
transition).

**Config keys:** `markSelector` (`.mark__glyph`), `flipMs` (620),
`easing` (`var(--ease)`), `receipt` (true), `blurMask` (6).

**What it does.** Three things, in order.

1. **The receipt.** Beside the filling arch, three ruled lines with right-aligned figures,
   appearing as each manifest step actually resolves. The figure is
   `PerformanceResourceTiming.encodedBodySize` for **same-origin resources only**. Cross-origin
   resources without `Timing-Allow-Origin` (the Fontshare faces) and cache hits genuinely report
   0, so those rows read `OK` rather than a fabricated number. Never print `0 KB`.
2. **The FLIP.** At loader completion, the filled arch travels to `.mark__glyph`'s measured
   `getBoundingClientRect()` and scales to fit, 620ms. Nothing fades. The loader becomes the
   chrome. Simultaneously the receipt collapses rightward toward the nav.
3. **The LCP-safe reveal.** The hero `<img>` is already painted, full size, unmasked,
   untransformed — it is never animated. What animates is a **night-coloured, arch-shaped scrim
   above it** that shrinks away, with a 6px blur on the departing layer resolving to 0 in the
   first 180ms to mask the seam.

**It does not edit `site.js`.** `site.js` already adds `boot-out` to `<html>` and
`data-done="true"` to `#boot` at completion; a MutationObserver on `#boot`'s attributes is the
hook, and it needs zero source change. (The CAP 3200→1200 change and the any-input dismiss _are_
`site.js` edits and are on the orchestrator's list.)

**CSS injected:** the receipt rows, the scrim, and the FLIP transform, scoped under
`[data-fx-handoff]`.

**Stage:** reads `stage.reducedMotion` and `stage.viewport`. No per-frame callback — the FLIP is
a CSS transition.

**Reduced motion:** the arch renders already full, the receipt renders complete with its real
figures, and the loader cross-dissolves in 120ms with no travel. **The visitor still watches an
honest manifest and still gets the receipt** — they lose the camera move, not the idea.

**Mobile:** identical. It is one transform on one element and it costs nothing. It is also the
best 620ms on the site and there is no reason a phone should not have it.

**Failure mode, and this is the one to plan for.** The FLIP runs inside a stacking context that
also holds a fixed nav, and `style.css` already carries a comment warning that a transform on
`body > *` breaks the nav's containing block. **Tiered fallback, decided in advance:**
if the FLIP jitters or the nav detaches, downgrade to opacity plus `scale(1.02 → 1.00)` on the
hero media only, receipt still collapsing into the nav. Loses the best 500ms, keeps the thesis,
and is still a better handoff than the cut that ships today. If `.mark__glyph` cannot be
measured (0×0 because the nav has not laid out yet), skip the FLIP entirely and cross-dissolve.
**The animation is allowed to not happen. A white flash and a black hole are not.**

---

### `fx/live.js`

```js
export function initLive(target, config) → { destroy() }
```

**Skill composed:** `webgl-asset-pipeline` (video rule: resolve on `canplaythrough`, ship a
separate mobile cut, `preload="none"` for anything below the fold, budget-first).

**Config keys:** `plays` (1), `crossfadeMs` (250), `blur` (6), `holdLastFrame` (true),
`rootMargin` (`'200px'`).

**What it does.** Owns every still→video handoff on the site. The `<video>` elements are already
in the markup with webm+mp4 sources and `preload="none"`. This module:

- removes the `loop` attribute's behaviour (the orchestrator removes the attribute itself),
  plays exactly once, and **freezes on the last frame**;
- mounts on IntersectionObserver with a 200px root margin, so the 409KB portal video is not
  fetched at t=0 for a band eleven screens down — that is exactly how a comfortable byte budget
  becomes a failed criterion;
- gates the swap on `canplaythrough`, never on `loadedmetadata`;
- crossfades over 250ms with a 6px blur on the outgoing layer to mask sub-pixel drift. The
  posters are frame 1 and pixel-match the shipped stills, so there is no pop even with the blur
  removed;
- **never scrubs a `<video>`.** Keyframe seeking stutters and iOS throttles seeks. Every clip
  here is a crossfade, not a scrub.

Assets already encoded and on disk: `hero-live-web.mp4/webm` (120KB),
`portal-live-web.mp4` (409KB), `parents-live-web.mp4/webm` (164KB),
`reader-live-web`, `stone-live-web`, `terminal-live-web`.

**CSS injected:** the stacked still/video layers and the crossfade, scoped under
`[data-fx-live]`.

**Stage:** reads `stage.reducedMotion` and `ledgerBus.motion.saveData`.

**Reduced motion — or `save-data`, or `motion.tier === 'low'`:** **the video is never
requested.** The still is the hero. Poster and `src` being the same frame means there is nothing
to notice, and it saves 120KB on the page that has the tightest budget.

**Mobile:** serves the 4:5 portrait cut where one exists. A phone gets a native vertical
cinematic frame, not `object-fit: cover` throwing away the subject.

**Failure mode:** if `canplaythrough` never fires (throttled connection, codec refusal), the
still stays and nothing is lost. A `play()` promise rejection is caught and ignored — autoplay
refusal is normal, not exceptional. The video is `muted playsinline aria-hidden="true"
tabindex="-1"` in the markup already; **autoplaying sound is banned outright and there is no
audio anywhere in this build.**

---

### `fx/arch.js`

```js
export function initArch(target, config) → { destroy() }
```

**Skill composed:** `emil-design-eng` (`@starting-style`, clip-path and radius reveals).

**Config keys:** `from` (`'var(--r)'`), `to` (`'9999px 9999px var(--r) var(--r)'`),
`completeAt` (0.5 — normalized band progress at which the draw must be finished).

**What it does.** The arch **draws** as you arrive at it, by animating `border-radius` from
`var(--r)` to `9999px 9999px var(--r) var(--r)`, scroll-coupled, completing before the band
reaches viewport centre so it is never mid-animation when you read the form inside it.

**Why `border-radius` and not a stroked SVG path**, which is what two of the three directions
proposed: the browser clamps a 9999px radius to half the box width, so this is
**resolution-independent and survives resize with no JS**. A hand-authored SVG path needs its
`d` regenerated on every resize, and the existing `#arch` symbol in the markup is the filled logo
letterform, not the portal silhouette — a stroked version of it would be a different shape
entirely. This is WORLD's one genuinely superior technique and it is ~25 lines.

Applies to the join band's portal and the `/parents` arch.

**CSS injected:** a custom property the transition reads, scoped under `[data-fx-arch]`.
**The fully-drawn arch is the CSS default.**

**Stage:** one `stage.register` callback reading `stage.scroll` and mapping the band's travel to
a 0–1 progress. Unsubscribes in `destroy()`.

**Reduced motion:** the arch is rendered complete at first paint. It is the site's signature
form and it should be present, not withheld.

**Mobile:** identical — it is one animated property on one element, it costs nothing, and the
arch is the brand.

**Failure mode:** if the band's offsets cannot be measured, the arch renders complete and the
callback never registers. On a browser that cannot transition `border-radius` smoothly, the
result is a step change at the band boundary, which is ugly for one frame and correct
thereafter.

---

### `fx/plate.js`

```js
export function initPlate(target, config) → { destroy() }
```

**Skill composed:** `depth-parallax` **doctrine only — the engine is rejected.** It needs three.js
and an offline depth model, there is no local torch environment on this machine, and a soft
grass-against-sky horizon cut into two CSS planes produces visible cardboard-cutout disocclusion
the moment you displace it. CSS transforms deliver the readable part of the effect at ~3KB.

**Config keys:** `clipFrom` (0.88), `scaleFrom` (1.06), `parallax` (24), `pointerDepth` (6),
`caption` (null), `gyro` (3).

**What it does.** Turns full-bleed photographs from wallpaper into material. A clip-path inset
reveal opening from the plate's top crease, a 1.06→1.00 scale coupled to the plate's own scroll
travel, a ≤24px counter-drift, and an optional caption below the frame set in the site's own
type at `--t-small` with `0.04em` tracking and no uppercase mono.

Applies to the seam (keys), the three `How it works` tiles, the `/parents` arch and the hero.
On the hero only, a ≤6px pointer depth and ≤3° gyro displacement.

**Explicitly not applied to the hero `<img>` as an entrance.** The hero is the LCP element; its
reveal belongs to `handoff.js`'s departing scrim. This module only adds the continuous
pointer/gyro depth there.

**CSS injected:** the clip, the transform, and the caption, scoped under `[data-fx-plate]`.
**The final, fully-revealed composition is the CSS default.**

**Stage:** one shared `stage.register` callback for all plate instances, reading `stage.scroll`
and `stage.pointer`. One callback total, not one per plate.

**Reduced motion:** final composition, no transform, no clip, caption present. A composed,
graded, captioned photograph — which is what it was always going to be at rest.

**Mobile:** no pointer effects. ≤3° gyro on the hero plate only, requested silently on the first
`touchstart` anywhere on the page (capture phase, self-removing) — **never a prompt, never an
instruction, never a "tilt your phone" affordance.** Denied or unavailable, the same displacement
is driven by scroll and nobody can tell. Gyro decays to zero after 4s of no device motion so it
never sits burning battery in a pocket.

**Failure mode:** if `DeviceOrientationEvent.requestPermission` throws or is denied, fall through
to scroll-driven displacement silently. If a plate's image has not reported `naturalWidth` at
init, defer that instance to the `load` event rather than measuring zero.

---

### `fx/steprail.js`

```js
export function initStepRail(target, config) → { destroy() }
```

**Config keys:** `stepSelector` (`.step`), `beats` (`[0, 80, 160, 240]`),
`extraHoldOnStep` (2), `extraHoldMs` (40).

**What it does.** A 1px vertical rail down the left of the three `How it works` steps, whose ink
fills downward driven by scroll position, with a node at each step. Step 2's beats do not begin
until step 1's copy has landed. Per step, four beats: numeral (0ms) → rule extends (80ms) → tile
clip-reveals (160ms) → copy (240ms).

Step 02 — the one that needs a parent — holds 40ms longer than the others, because it is the
step that decides the deal, and naming the friction where it happens is worth more than
discovering it later. (The `REQUIRES GUARDIAN` chip itself is markup and belongs to the
orchestrator.)

Fully reversible: scroll back up and the ink retreats. This is the one place on the site where
scrolling is rewarded with visible progress.

**CSS injected:** the rail, its nodes, and the per-beat transitions, scoped under
`[data-fx-steprail]`. **The filled rail and landed steps are the CSS default.**

**Stage:** one `stage.register` callback reading `stage.scroll`.

**Reduced motion:** rail rendered full, all three steps in their final state, nodes present.

**Mobile:** the rail moves to 12px from the left edge with the step numbers hanging in the
gutter beside it. A phone is already a single column with a margin, so this is more native there
than on desktop.

**Failure mode:** if fewer than two `.step` elements are found, it does not mount. If the band's
scroll travel is shorter than the viewport (a very tall phone), the rail fills over whatever
travel exists rather than never completing.

---

### `fx/tape.js`

```js
export function initTape(target, config) → { destroy() }
```

**Skill composed:** `smooth-scroll-stage` **velocity doctrine only — Lenis is rejected**, because
it takes ownership of the scrollbar and adds latency to the one control the reader owns, and a
parent scrolling fast on a phone who feels the page lag behind their thumb has been handed a
reason to doubt.

**Config keys:** `baseMs` (42000), `floor` (0.35), `ceiling` (2.2), `decayMs` (900).

**What it does.** Couples the existing marquee's rate to `stage.scroll.velocity` with a 0.35×
floor and a 900ms ease back to base — it never stops, but it moves _with_ you, so it reads as
connected to the reader rather than to a timer. Pauses on hover and when off-screen.

Also fixes a live accessibility bug: `site.js` currently sets `aria-hidden="true"` on the only
`.strip__row` after duplicating it, hiding the entire trade list from screen readers. **This
module moves `aria-hidden` onto the runtime clone and unhides the source.**

**The one causality exception in this build, disclosed.** Recon D permits ambient motion only in
the photographic and environmental layer. A marquee is not that layer. It is taken anyway
because its base rate is unchanged from what ships today, it accelerates only under the reader's
own scroll, and a labelled tape of job types is closer to environment than to UI. **If review
disagrees it degrades to a static wrapped list, which is already the reduced-motion state, so
the fallback is built and tested by construction.**

**CSS injected:** an `animation-duration` custom property, scoped under `[data-fx-tape]`.

**Stage:** one `stage.register` callback reading `stage.scroll.velocity`.

**Reduced motion:** the marquee stops and the 11 trades become a **static wrapped list, all
entries visible at once**. Better for reading than the moving version.

**Mobile:** touch gain is roughly 2× wheel gain, because thumb travel is shorter than a wheel.

**Failure mode:** if `.strip__row` is absent it does not mount. If velocity readings are NaN
(some engines on the first frame), clamp to base rather than propagating NaN into
`animation-duration`, which would freeze the marquee mid-run.

---

### `fx/field.js`

```js
export function initField(root, config) → { recalc(), destroy() }
```

**Skills composed:** `magnetic-cursor` with **three mandated overrides**;
`make-interfaces-feel-better` #12 (press feedback) and #16 (44×44 hit areas);
`review-animations` as the ship gate.

**Config keys:** `magnetSelector` (`[data-magnetic]`), `magnetStrength` (**≤0.3**),
`magnetRadius` (80), `maxPull` (**5px, hard cap**), `hideNativeCursor` (**false**),
`blend` (**false**), `hoverScale` (**≤1.3**), `pressScale` (0.97), `pressMs` (120).

**The three overrides are not preferences, they are conversion bugs if reversed.**
`hideNativeCursor: false` because the waitlist email input needs its I-beam and a custom cursor
over a text field with no I-beam affordance is a direct hit on conversion action #1.
`blend: false` because a difference-blend ring inverting across the cream/night band boundary
will look broken on `#f4f1ec`. `maxPull: 5` because beyond that the target physically moves away
from a 45-year-old's cursor, which is a literal, measurable conversion loss.

**What it does.** The conversion surface, which currently gets less interaction design than the
arrows:

- `:focus-visible` rings on both capture forms. `.capture input` currently sets `outline: none`
  **with no replacement**, which is a WCAG failure as well as a craft gap.
- `scale(0.97)` press feedback, 120ms, on the CTAs.
- 44×44 minimum hit areas on the mobile form.
- ≤5px magnetic pull on the primary CTA and the waitlist submit only. Nothing else on this site
  is magnetic.
- ≤300ms error and success choreography on the capture form.

Magnet bounds are measured at init, so `recalc()` must be called after any layout shift — the
orchestrator wires it to the console re-render and to the mobile drawer.

**CSS injected:** focus rings built from `--accent`, press transform, hit-area padding, scoped
under `[data-fx-field]`.

**Stage:** one `stage.register` callback for the magnet, reading `stage.pointer`.

**Reduced motion:** focus rings and colour transitions stay at ≤120ms; the press scale and the
magnet are dropped. Focus indication is accessibility, not decoration, and is never removed.

**Mobile:** the magnet does not mount (no pointer). Hit areas and focus rings do. Press feedback
stays — it is the tactile confirmation a thumb needs.

**Failure mode:** if `recalc()` is never called after a layout change, the magnet pulls toward a
stale rect. Bounded at 5px, the worst case is a 5px error nobody perceives — which is the reason
for the cap as much as the conversion argument.

---

### `fx/grain.js`

```js
export function initGrain(config) → { destroy() }
```

**Skill composed:** `cinematic-grade` **grain path only.** Bloom, chromatic aberration, DOF and
vignette are banned by name: chromatic aberration on a fee table reads as a rendering bug, and
the full skill would cost three.js plus `postprocessing@6.39.2` to add noise that a 2KB CSS
overlay delivers.

**Config keys:** `opacity` (0.03, range 0.02–0.04), `bands` (`.band--night`), `tile` (256).

**What it does.** A 256² tiling noise data-URI at **exact 1:1 device pixels**
(`background-size: 256px 256px`, no scaling) over the night bands. Kills banding on `#141420`
and makes a dark ground read as printed stock rather than a `<div>`.

**Static. Never animated. Never disabled at any quality tier.** Animated grain is a music video;
static grain is invisible as an effect and enormous as a quality signal, and it is load-bearing
for the look. The existing `.grain` div in the hero markup is its first mount point.

**CSS injected:** all of it. No rAF, no JS after init, ~2KB.

**Stage:** does not read it.

**Reduced motion:** unchanged. Grain is not motion.

**Mobile:** unchanged, and it matters more there — banding is more visible on OLED.

**Failure mode:** none available. It is a background image on a `pointer-events: none` overlay.
If the data-URI fails to decode, the band is flat, which is what ships today.

---

### Integration points — orchestrator only

No module may touch these files. Every item below is made once, by the orchestrator, in
`style.css`, `site.js`, `index.html`, `pricing.html`, `parents.html` or a new `vercel.json`.
**Items 1–9 are blocking and land before any craft work starts.**

**Blocking correctness**

1. **`.calc` mobile collapse.** `style.css:1038` sets two columns with **no responsive override
   anywhere in the file**. Measured at 390px it computes to `138.75px 163.25px` and the invoice
   is clipped mid-number. Add `@media (max-width: 900px) { .calc { grid-template-columns: 1fr } }`.
   The best object on the site is currently unreadable on the primary reader's device.
2. **`body { overflow-x: hidden }` (`style.css:101`) hides the evidence** — every "no horizontal
   scroll" assertion passes green while content is genuinely cut off. Verification of AC8 is by
   screenshot, looked at, at all three widths.
3. **`.tile { height: auto }`.** `aspect-ratio: 4/3` is set but the `height="600"` HTML attribute
   wins; tiles render 351×600 portrait crops of an 800×605 source.
4. **Reconcile the handover contradiction.** `pricing.html` asserts the 18th-birthday account
   handover as shipped fact; `parents.html` states it has not shipped. Two pages of one site
   contradicting each other on the single thing a parent cares most about is an instant no.
   `parents.html`'s honest version wins.
5. **Shared chrome, byte-identical.** Port `<meta name="darkreader-lock">`,
   `<meta name="theme-color" content="#141420">` and the inline first-paint
   `html { background: #141420 }` to `pricing.html` and `parents.html`. Both currently flash
   white and both will be inverted to mud by Dark Reader.
6. **`sessionStorage 'fuime.booted'` set on all three pages**, so a visitor whose first URL is
   `/pricing` does not get the full loader mid-session on their second page.
7. **`.rise-i` reset inside the reduced-motion block.** `style.css:1365` resets `.rise` but not
   `.rise-i`, which survives today only because `site.js` adds a class. One JS error currently
   renders a blank page.
8. **`vercel.json` with `cleanUrls: true`.** It is in the brief's file manifest and is absent
   from the repo; every nav and footer link uses extensionless paths.
9. **Delete `.archline`** (`parents.html:309`) — a class with zero declarations in `style.css`.

**AC3 — accent discipline, currently failed in both directions**

10. Add `color: var(--accent)` to `.mark i`. The wordmark's `i` is currently not accented at all.
11. Remove accent from `.icon`, `.step__n`, `.tlink`, `.tag`, the calc slider, `.num[data-live]`,
    `.strip__item::after`, `.boot__lit` and `.mark__glyph`. Accent appears on primary buttons and
    the wordmark's `i` **and nowhere else**.

**Tokens added to `:root`** (built from existing values, no new hexes)

12. `--split-h: 10px; --split-h-dock: 2px; --track-hud: 0.04em;`
    `--cwe-z-bg: 0; --cwe-z-content: 10; --cwe-z-fx: 20; --cwe-z-transition: 100;`
13. **Tabular figures.** Set `font-variant-numeric: tabular-nums lining` on `.num`, `.price__fig`,
    the invoice column and the split labels. **Measure it:** render `$25.00` and `$1,888.88` in
    the same slot and compare rendered widths. If General Sans lacks a `tnum` feature and the
    widths differ, add `--font-mono: ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace`
    and apply it to figures only. **A `--font-mono` uppercase micro-label anywhere on this site
    is out of scope and is the costume two judges killed — figures only, or not at all.**

**site.js edits (only these four)**

14. Loader `CAP` 3200 → **1200**.
15. Any input — `scroll`, `keydown`, `pointerdown`, `touchstart` — aborts the loader immediately
    to the landed state.
16. `aria-hidden="true"` moves from the source `.strip__row` onto the runtime clone.
17. The accent flash on `data-live` is removed (superseded by `roll.js` and AC3).

**Markup changes**

18. Remove `loop` from both hero `<video>` elements (`index.html:175`, `parents.html:164`).
19. Hero `<source media>` breakpoint 720px → **900px** to match the layout breakpoint. At 768px
    the desktop `hero-1600.avif` (2.33:1) is currently cropped into a ~900px-tall hero and the
    subject is lost.
20. `scroll-margin-top: 88px` on `#how`, plus `scroll-behavior: smooth` already present and a
    72px fixed nav.
21. **The comparison matrix** on `/` — the four `.card`s in the problem band become ruled rows
    (`.card--row`, a new variant in `style.css` built from tokens), each carrying its
    brief-locked copy verbatim. On `/parents`, one hairline-ruled table comparing Venmo→mom /
    cash / "next week" / a business account / fuime against **Record · Receipt · Whose name ·
    Needs 18**, in its own `overflow-x: auto` container with a sticky first column on mobile.
    Answer visible first, reasoning one `<details>` away, never the reverse.
22. **The terms table** — three `.card.price` boxes on `/` and `/pricing` become three ruled rows,
    label left, figure right in display 480, tabular.
23. **`REQUIRES GUARDIAN` chip** on step 02 of How it works.
24. **Custodian row** on `/parents`: `Custodian of identity documents ······ Stripe, Inc.`, its
    own hairline-boxed row, legible at 1440 without scrolling.
25. **`WORKED EXAMPLE` label** on the invoice artifact and on the strip. The brief bans invented
    social proof; a labelled worked example is arithmetic, and saying so is a trust deposit.
    This also closes the honesty gap on `Paid Jun 14 · Visa ···· 4242`, which without a label
    reads as a real customer record.
26. **Footer status row:** `Status ······ Onboarding the first businesses` — brief-sanctioned
    copy, already in the voice.
27. Slider range unified at **25–2000** on both pages (`pricing.html` currently says 5000).
28. Mount points for `split.js` (`'full'` under the calculator on `/` and `/pricing`, `'dock'`
    under the nav on all three), each carrying `data-*` static defaults so it renders correctly
    with JS off.
29. `<picture>` sources for the new 4:5 portrait heroes on `/pricing` and `/parents` once the
    assets land; extend `.hero--short`'s scrim to 88% as the ≤720px rule already does, which is
    the structural cause of the measured contrast failures.
30. Fix `parents.html`'s arch `height="1250"` → `1241` to match the actual asset.

**Boot**

31. Import map in `<head>`, above every script:
    `{"imports": {"cwe/stage": "/fx/stage.js"}}` — engines import the bare specifier; fix paths
    in the map, never in the file.
32. One `<script type="module">` wiring the boot order in §Build Order. Every module is wrapped
    in its own `try/catch` so one failure cannot take down the rest.

---

## Assets

House rules applied to every prompt: positive framing only, blank unmarked surfaces, screens are
_a clean even panel of soft warm light with no detail on it_, 50mm, shallow depth of field,
muted film colour, deep shadow, warm practical light. No brand marks, no legible text, no logos.

Model: `fal-ai/flux/dev` for stills, `fal-ai/kling-video/v1.6/standard/image-to-video` for clips.

| id                           | still/clip | literal prompt                                                                                                                                                                                                                                                                                                                                                                                                    | model          | est cost  |
| ---------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | --------- |
| `parents-m` ×6               | still 4:5  | Vertical four by five frame. A kitchen table at night, a set of car keys, a closed laptop and a half-full mug on bare wood, one warm pendant light above and to the left, deep shadow filling the room behind, the upper half an empty dark wall with room for type, fifty millimetre lens, shallow depth of field, muted film colour, warm practical light, blank unmarked surfaces                              | flux/dev       | $0.36     |
| `pricing-m` ×6               | still 4:5  | Vertical four by five frame. A small card reader and a folded sheet of blank unmarked paper on a wooden table at night, the reader showing a clean even panel of soft warm light with no detail on it, one warm lamp low and to the right, deep shadow filling the upper half with room for type, fifty millimetre lens, shallow depth of field, muted film colour, warm practical light, blank unmarked surfaces | flux/dev       | $0.36     |
| `plate-fold` ×3              | still 3:2  | Extreme macro of a thumb pressing a crease into a sheet of heavy cream paper, blank unmarked surface, ink black shadow in the valley of the fold, a warm rim of light along the ridge, fifty millimetre lens, shallow depth of field, muted film colour, deep shadow, warm practical light                                                                                                                        | flux/dev       | $0.18     |
| `parents-m-live` ×2          | clip       | Steam rises slowly from the mug, the pendant light is steady, the room behind stays dark and still, the camera holds completely still                                                                                                                                                                                                                                                                             | kling v1.6 i2v | $0.50     |
| `pricing-m-live` ×2          | clip       | The warm light on the reader breathes almost imperceptibly, nothing else moves, the camera holds completely still                                                                                                                                                                                                                                                                                                 | kling v1.6 i2v | $0.50     |
| `fold-live` ×2               | clip       | The thumb completes the crease and lifts slowly out of frame, the paper settling, the camera holds completely still                                                                                                                                                                                                                                                                                               | kling v1.6 i2v | $0.50     |
| **Committed**                |            |                                                                                                                                                                                                                                                                                                                                                                                                                   |                | **$2.40** |
| AC4 contrast re-roll reserve | stills     | re-runs of `parents-m` / `pricing-m` with a darker type zone until measured contrast clears 4.5:1 at 390px                                                                                                                                                                                                                                                                                                        | flux/dev       | $6.00     |
| **Ceiling**                  |            |                                                                                                                                                                                                                                                                                                                                                                                                                   |                | **$8.40** |

Balance $56.65. Ceiling $8.40. **Well under the $25 limit, and the underspend is the decision,
not an oversight.**

The binding constraint on this site is AC10 — 1.2MB transferred on `/` — not the fal balance.
More footage is more bytes and more chances for a seam, and one panel explicitly flagged a
35-round-trip asset plan as a burden in a session that also has to fix nine correctness defects.
The reserve sits where regeneration is actually likely: AC4 requires **measured** ≥4.5:1 contrast
sampled from the rendered screenshot, `/parents`'s note currently measures **3.90 at 390px**, and
the root cause is compositional — the scrim gives up at 68% while short-hero type sits below it.
That needs frames with genuinely dark sky where the type lands, and it may take three tries.

**Already on disk, reused as-is, zero spend:** `hero-live-web.mp4/webm` (120KB),
`portal-live-web.mp4` (409KB), `parents-live-web.mp4/webm` (164KB), `reader-live-web`,
`stone-live-web`, `terminal-live-web`, `hero-m-700/1000` (700×869 — already a native 4:5 mobile
hero for `/`), `keys-1600`, `arch-dusk`, `parents-arch`, all three `tile-*` sets.

**`og.png` is regenerated at $0** by screenshotting the console at the exact frame the slider
crosses $250, with the split mid-resize. The share card is the product doing its job. Generating
a photograph for it would be the less honest option.

**Encoding:** `heif-enc` / `magick` — **`avifenc` is not installed on this machine.** AVIF then
WebP per the brief's `<picture>` pattern, real `width`/`height` on every `<img>`.

---

## Mobile

The primary reader is fifteen and on a phone, and under today's build they get the worst version
of the site: a static JPEG (the pointer glow is `pointer: fine` only), a calculator clipped at
138px, and the desktop hero crop at 768px. That inversion is fixed by giving the phone the
version that is genuinely better, not the desktop version with things switched off.

**The console is where mobile wins.** Full width, single column, invoice below the slider at
full gutter width. The charge figure is the largest thing on the screen. The slider is a 44px
track with a 28px thumb and the `$250` tick drawn at its true position. **Thumb-dragging a
threshold and feeling `$0/mo` throw to `$15/mo` under your own finger is a better interaction
than it is with a mouse** — the one place the phone beats the desktop outright, and it lands on
the object the whole plan is built around.

**The split spans gutter to gutter**, labels wrapping to two lines under their segments rather
than shrinking below `--t-small`.

**Native portrait footage, not crops.** `/` already has a 4:5 hero at 700×869. `/pricing` and
`/parents` get theirs from the asset table. The `<source media>` cut moves 720px → 900px to match
the layout breakpoint.

**The crease is more native on a phone than on a desktop.** A phone is a portrait column; a
document is a portrait column. Scrolling through this site reads as unfolding a strip of paper,
one panel at a time.

**Tilt.** ≤3° gyro on the hero plate only, permission requested silently on the first touch
anywhere on the page, capture phase, self-removing. Never a prompt, never an instruction, never
a "tilt your phone" affordance. Denied or unavailable falls through to scroll-driven
displacement and nobody can tell. Decays to zero after 4s of no device motion.

**The comparison table stays a table.** It does not become four cards. Horizontally scrollable
inside its own `overflow-x: auto` container with a sticky first column — density is not a
desktop privilege, and every price-comparison app on a phone ships exactly this. **The page body
never scrolls sideways.**

**No fixed edge chrome.** The 2px docked split under the nav is the only pinned element on a
phone. No bottom bar, no rail, nothing competing with the CTA, nothing fighting the iOS safe
area or the URL bar.

**Scroll is native.** iOS momentum untouched. No smooth-scroll library, no hijack, no pinning,
no horizontal sections. A parent scrolling fast on a phone must never feel the page lag behind
their thumb.

**Weight.** Today `/` is 100KB at 390px. Add the hero video (120KB, and not requested at all
under `save-data` or reduced motion) and ~30KB of modules, and mobile lands near 250KB against
a 1.2MB ceiling. The portal video is `preload="none"` and gated on intersection.

---

## Reduced Motion

The flag gives you a second, complete design: **a dense, still, hairline-ruled, fully-live
document.** Not the site with the fun switched off.

| Element               | Full                                       | Reduced                                                                                                             |
| --------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| Loader                | Arch fills, receipt lands, 620ms FLIP      | Arch renders already full, **receipt renders complete with its real byte figures**, 120ms cross-dissolve, no travel |
| Hero image            | Departing arch scrim                       | Present, unmasked, at first paint. Identical pixels                                                                 |
| Hero video            | One pass, then freeze                      | **Never requested — saves 120KB**                                                                                   |
| Headline              | 320ms baseline mask wipe                   | Present, fully legible                                                                                              |
| Split                 | Rule draws, ticks drop, widths transition  | **Drawn and divided at first paint.** Widths still change on drag, instantly                                        |
| Threshold             | Un-eased flip                              | **Identical.** It had no animation to remove                                                                        |
| Figures               | Per-digit roll 180ms                       | **Snap.** Instant, correct, tabular, no reflow                                                                      |
| Invoice rows          | 4-beat causal restrike                     | All four update in the same frame                                                                                   |
| Crease                | (static already)                           | Unchanged                                                                                                           |
| Grain                 | (static already)                           | Unchanged                                                                                                           |
| Rejected-methods band | Rule draws → icon strokes → strike-through | **All present and struck through at first paint.** The argument lands with zero motion                              |
| Terms table           | Rules draw 200ms                           | Complete                                                                                                            |
| Plates                | Clip reveal + parallax                     | Final composition, captions present                                                                                 |
| Step rail             | Ink fills on scroll                        | Rendered full, all three steps landed                                                                               |
| Arch                  | `border-radius` draws                      | Rendered complete                                                                                                   |
| Tape                  | Velocity-coupled                           | **Static wrapped list, all 11 entries visible.** Better for reading                                                 |
| Focus rings           | ≤120ms                                     | Unchanged. Focus indication is never removed                                                                        |
| `.rise` / `.rise-i`   | 14px / 420ms                               | Final state, **including `.rise-i`**, reset in CSS not JS                                                           |

**Why it is still good.** Everything that carries this design's value is composition, not motion:
the creases, the ruled rows, the strike-throughs, the split fully divided, the terms table, the
tabular figures, the grain, the captions, the magazine scale. Paper's default state is still.
Several substitutions are genuinely better — a snapping readout is a better instrument than a
rolling one, and a static wrapped list of eleven trades is easier to read than a moving one.

And the structural guarantee that makes AC9 hold rather than being asserted: **every module ships
its final state as the CSS default and removes it only after confirming motion is available.**
Today `.rise { opacity: 0 }` plus one JS error equals a blank page — that is literally how the
audit's screenshots came back empty. Under this rule a JS failure, a print stylesheet, a
text-mode reader, a blocked module and a non-scrolling renderer all produce the full static
design.

---

## Acceptance

Every item is checkable by a screenshot, a measurement or a command. None is checkable by
opinion. The brief's 13 criteria still bind; these are additive and more specific.

**Correctness**

1. At 390px, `getComputedStyle(document.querySelector('.calc')).gridTemplateColumns` returns a
   single track, and a screenshot shows every invoice figure complete with no clipped glyph.
2. `document.querySelector('.tile').getBoundingClientRect()` returns a ratio within 0.02 of 1.333
   at all three widths.
3. `grep -n 'archline' parents.html` returns nothing.
4. `grep -riE '#[0-9a-f]{3,8}' style.css | grep -v ':root' -A0` returns nothing, and the same
   grep across `fx/*.js` returns nothing.
5. `grep -c 'darkreader-lock' index.html pricing.html parents.html` returns 1, 1, 1. Same for
   `theme-color`.
6. `vercel.json` exists and contains `"cleanUrls": true`; `/pricing` and `/parents` resolve on
   the deployed URL with no extension and no redirect chain.
7. Every claim about the 18th-birthday handover is identical in `pricing.html` and
   `parents.html`, verified by diffing the two paragraphs.
8. Both pages' sliders report `min="25" max="2000"`.

**The signature**

9. With JavaScript disabled, the split renders at its static default proportions on all three
   pages — screenshot at 1440px and 390px.
10. Dragging the slider from 200 to 300 changes the split's three segment widths and the docked
    2px instance under the nav within one frame, verified by screenshot at both values.
11. Navigating `/` → `/pricing` preserves the docked split's proportions, verified by reading
    `sessionStorage.getItem('fuime.fee')` on the second page.
12. The three segment percentages sum to 100.0 ± 0.1 at charge values 25, 250, 400 and 2000.
13. `getComputedStyle` on the monthly readout reports `transition-duration: 0s`, and the value
    changes between slider 249 and 251 with no intermediate frame captured in a 60fps recording.

**Performance floors**

14. Total transferred weight of `/` under **1.2MB**, measured by a headless load with cache
    disabled. Report the number.
15. **LCP under 2.5s** on a headless load, and the LCP element is the hero `<img>` — not a
    scrim, not a video, not text. Report both.
16. **CLS under 0.05** across a full scroll of `/` at 390px and 1440px.
17. **INP / first visible response to a slider drag under 100ms**, and the roll completes within
    400ms.
18. `document.querySelectorAll('script[src*="/fx/"]').length` matches the module count, and
    total `fx/*.js` transferred is under **40KB**.
19. Exactly **one** `requestAnimationFrame` loop is live — instrument `stage.js` and assert no
    other module calls it. `grep -c 'requestAnimationFrame' fx/*.js` returns 0 for every file
    except `stage.js`.
20. Nothing calls `stage.setScroll()`: `grep -c 'setScroll' fx/*.js` returns 0.

**Conversion actions unobstructed**

21. **Time-to-legible-headline under 1.5s** on a 4× CPU throttle and a Fast 3G profile, measured
    from a Performance trace. If it exceeds 1.5s, `handoff.js` self-downgrades to a 200ms
    cross-dissolve — this is a coded fallback, not a note.
22. The price line — _7% of what you collect. No monthly fee until you're earning._ — is inside
    the first viewport at 390px and 1440px, verified by screenshot, with no interaction.
23. Both capture forms accept a valid email and reach the success state on all three pages;
    an invalid email shows the inline error with **zero** network requests; a failed request
    shows the `hi@fuime.com` fallback. `test/waitlist.test.mjs` passes **unmodified**.
24. At every point in the loader and the handoff, the capture input remains focusable and no
    element with `pointer-events` other than `none` covers it. Tab from the top and confirm.
25. Every focusable element has a visible `:focus-visible` indicator at ≥3:1 against its
    background. Sampled from the screenshot, not from the CSS.

**The trust rule (recon D's gate — all five must pass, per effect)**

26. **Zero-input legibility:** on a cold throttled load with no interaction and no scroll, the
    headline, the subhead and a visible path to what it costs are readable by **t = 1.5s**.
27. **Causality:** no figure on any page changes as a result of an IntersectionObserver.
    `grep -n 'IntersectionObserver' fx/roll.js fx/split.js fx/threshold.js` shows it used only
    for `split.js`'s one-shot _frame_ draw, never for a value.
28. **Non-blocking:** run
    `document.querySelectorAll('script[type=module]').forEach(s=>s.remove())`, reload with fx
    blocked, and screenshot at 390 / 768 / 1440. **Every screenshot must be at least as good as
    today's baseline.** Any module whose removal makes a screenshot worse is load-bearing and
    is cut or downgraded. Repeat with `prefers-reduced-motion: reduce` forced.
29. **Latency and completion:** no UI-layer animation exceeds **300ms** (the loader FLIP at
    620ms, the video crossfades and the arch draw are the only exemptions, and each is
    interruptible with a valid end state). Audited by reading every duration in `fx/*.js`.
30. **The parent test, made decidable:** every shipped effect is describable as a property of the
    material, not as a thing the website does. _"The line shows who gets what."_ _"The numbers
    move when you drag them."_ _"The dark is grainy like paper."_ All pass. Anything that reads
    as _"the website makes you…"_ does not ship.

**Trust facts present**

31. `/parents` names Stripe as custodian of identity documents in its own hairline-boxed row,
    visible at 1440px without scrolling — screenshot.
32. The invoice artifact and the strip both carry a worked-example label, so no fabricated
    figure can be read as a customer record.
33. AC4 re-measured: contrast between headline/note text and the actual rendered pixels behind
    it is **≥4.5:1 at 390px and 1440px on all three pages**, sampled from the screenshot at the
    5th percentile _and_ the worst pixel under the text bounding box.
34. AC3 re-measured: `#C2401F` appears in the rendered page on primary buttons and the
    wordmark's `i` and nowhere else. Enumerate every element whose computed colour or background
    resolves to the accent.
35. All prose passes `no-ai-slop` against its `eval.md`, and every ported line is at least as
    specific as the line it replaces, judged line-by-line.
36. Verified on the **deployed URL**, not the dev server.

---

## Build Order

**Phase 0 — blocking correctness. Serial, orchestrator only, nothing else starts until it is
done.** Integration items 1–11 plus 14–20 and 27, 30. This is the whole reason the plan works:
after Phase 0, deleting every fx module leaves a site that is _better than today's baseline_, so
no module is ever load-bearing for legibility. Roughly half a day. **Files touched:
`style.css`, `site.js`, all three HTML files, new `vercel.json` — all orchestrator-serialised.**

**Phase 1 — the bus. Serial. One worker. Blocks everything in Phase 2.**
`fx/ledger-bus.js`. Nothing else can be built against a moving target.

**Phase 2 — parallel, one worker per file, no shared files.** Every module below imports only
`cwe/stage` and `fuime:fee`, injects its own CSS, and touches nothing another worker touches.

- **2a — the signature (highest priority, staff it first):** `fx/split.js`, `fx/threshold.js`,
  `fx/roll.js`
- **2b — the register:** `fx/crease.js`, `fx/strike.js`, `fx/rows.js`, `fx/grain.js`
- **2c — the finish:** `fx/handoff.js`, `fx/live.js`, `fx/arch.js`, `fx/field.js`
- **2d — the depth:** `fx/plate.js`, `fx/steprail.js`, `fx/tape.js`

**Phase 3 — assets. Fully parallel with Phase 2, different worker, no code overlap.**
Generate the six stills, curate, encode with `heif-enc`/`magick`, then the three i2v clips.
Hands finished files to the orchestrator, who wires the `<picture>` sources (integration item 29).
**`img/` and the three HTML files are orchestrator-serialised.**

**Phase 4 — wiring. Serial, orchestrator only.** Integration items 12–13, 21–26, 28, 31–32.
The markup conversions (comparison matrix, terms table, chip, custodian row, worked-example
labels, status row, split mount points) and the boot script in this exact order — it is not
stylistic, four of these are true dependencies:

```
getStage()                          singleton; nothing runs before it
  ↓
initLedgerBus()                     publishes fuime:fee; everything below subscribes
  ↓
crease · grain                      CSS-only, no layout dependency, safe at any time
  ↓
handoff                             must bind its MutationObserver before site.js lifts #boot
  ↓
live · plate · steprail · tape      read stage.scroll
  ↓
strike · rows · arch                one-shot entrances
  ↓
split · threshold · roll            the console; subscribe to the bus
  ↓
field                               LAST — its magnet bounds are measured at init,
                                    so any earlier layout shift invalidates them
```

**Phase 5 — verification. Serial.** All 36 acceptance items, in order, on the deployed URL.
Run the delete-all-fx screenshot test (item 28) at three widths **and look at the images** — a
green assertion has hidden a broken page on this project three times, and `overflow-x: hidden`
is still masking clipping from every automated check. Then `review-animations` as the ship gate
(it is `disable-model-invocation: true`, so invoke it deliberately) and `no-ai-slop` on every
line of new prose.

**Files more than one worker would touch — all serialised through the orchestrator, no
exceptions:**

- `style.css` — Phase 0 and Phase 4 only. **No module writes to it, ever.**
- `site.js` — Phase 0 only, four edits, listed above.
- `index.html` / `pricing.html` / `parents.html` — Phase 0, Phase 4, and the Phase 3 asset
  hand-off. Never by a module worker.
- `img/` — Phase 3 worker writes, orchestrator wires.
- `fx/stage.js` / `fx/scene.js` — **read-only. Vendored, byte-identical to the skill. Nobody
  edits these.**
- `api/waitlist.js` / `test/` — **DO NOT EDIT.** They pass today and must keep passing untouched.

**If the schedule collapses, this is what ships and it is still a committed direction:**
Phase 0 + `ledger-bus` + `split` + `threshold` + `roll` + `crease`. That is one day of work, it
contains the entire thesis — the price is a live line you can drag, set on paper — and it is
already better than what is on disk. **The test of whether a direction is real is whether it
survives being reduced to its single best object. This one does.**

---

## Cut List

**From INSTRUMENT (the spine), cut anyway:**

- **The fixed edge rail.** Two panels called it costume, its own author cut it on mobile, and a
  parent who has never seen a Bloomberg terminal reads a pinned HUD as a game. Its one real job
  — keeping the fee on screen at every scroll position — is done better by the 2px docked split,
  which is the signature rather than chrome around it.
- **Uppercase mono micro-labels, plate numbering, corner registration marks, the `PLATE 04`
  slugs, `50MM · f/1.8 · DUSK`.** The single most saturated aesthetic on Awwwards, and the exact
  register a suspicious parent associates with the category they most fear. `--font-mono` is
  permitted on **figures only**, and only if General Sans measurably lacks tabular numerals.
- **Fabricated kilobyte figures in the loader receipt.** `transferSize` is 0 for cross-origin and
  cached resources; the row reads `OK`. Printing a made-up number on a page about honesty is the
  funniest possible way to fail this brief.
- **Dollar figures on the tape.** A figure adjacent to a job type reads as a testimonial no
  matter what label sits above it. The tape carries job types only. Costs the band ~30% of its
  interest and zero of its integrity.
- **The nav HUD as two mono fields.** Replaced by the docked split, which says the same thing
  proportionally and does not look like a trading terminal.

**From DOCUMENT (the register), cut:**

- **The PAID stamp on the invoice.** `Paid Jun 14 · Visa ···· 4242` arriving with a stamp makes a
  fabricated artifact look like a real customer record. The copy stays (it is brief-locked); the
  stamp animation goes, and the worked-example label lands beside it.
- **The arch-shaped clip-path reveal of the hero image.** Chrome measures LCP at the end of a
  masked reveal; that is ~600ms of a measured acceptance criterion spent on a flourish. Replaced
  by a departing arch-shaped scrim over an image that painted unmasked. Same visual, zero cost.
  DOCUMENT cut this itself and it was the sharpest instinct in the three documents.
- **23 stills and 12 i2v attempts.** Thirty-five fal round-trips in a session that also has to
  fix nine correctness defects. Six stills and three clips, and a reserve where regeneration is
  actually likely.
- **Cream bands that lift/tilt as you scroll.** Motion in the UI-and-numbers layer, landing on
  the object that has to look like a ledger. DOCUMENT cut this itself, unprompted, and was right.

**From WORLD (179 points, one-third of the graft):**

- **`world-continuum.js` and the stitched photographic dusk plate.** Its own author called it
  high-probability failure; a fixed background slice fights iOS Safari's URL-bar resize and
  repaints per scroll frame on a phone. A signature that dies with its own fallback is not a
  signature.
- **`depth-plate.js` and Depth Anything V2.** No local torch environment on this machine, and a
  soft grass-against-sky horizon cut into two CSS planes produces cardboard-cutout disocclusion
  at 6px of displacement. The existing ±18px pointer drift already delivers the readable part at
  zero cost.
- **The 520ms full-screen arch scale-through as the entry.** Structurally the closest thing in
  the three directions to the door the brief bans, and it stands between the reader and the
  headline. The FLIP-to-nav-mark does the same emotional job in the same time while _building_
  the chrome instead of covering the page.

**Refused by name across all three, so they cannot quietly regrow:**

- **Entry gates of any kind** — gesture gates, hold-to-enter, click-to-begin, audio unlock. A
  parent arriving from their kid's text message reads a ritual before the value prop as a mask.
- **Scroll hijacking, virtual scroll, pinned chapters, horizontal sections.** They break Cmd+F,
  deep links, the back button and screen readers, on a page whose job includes "let me read what
  it costs."
- **Lenis and every smooth-scroll library.** Latency on the one control the reader owns.
- **Custom cursor sprites.** Pointer precision on the two targets that matter; dead weight on
  touch; reads as a game.
- **Count-up-on-scroll stat counters.** Reads as a deck, and a number that moves because a
  viewport moved is the exact inversion of this plan's causality rule.
- **`kinetic-type` `mode: 'scramble'`, per-letter headline assembly, decrypt, typewriter.** The
  headline is the value proposition.
- **`webgl-text-fx`, `cinematic-grade`'s bloom/CA/DOF, `glass-transmission`, `fluid-cursor`,
  `image-trail`, `ribbon-trails`, `flowmap-trail`, `gooey-filters`, `ascii-halftone-pass`,
  `infinite-grid`, `webgl-image-hover`, `shader-transitions`, `scroll-morph-sequence`,
  `webgl-narrative-stages`, `page-transition-router`, and every particle/fluid/raymarch skill.**
  All spectacle, all three.js, all megabytes, and not one of them makes a parent more likely to
  co-sign. **This build ships zero WebGL and imports three.js nowhere.**
- **Glassmorphism, neon glow, gradient-mesh blobs, drop shadows in place of hairlines.** Reads
  2021 startup, not institution, and fights the Mercury system the brief locks.
- **Autoplaying sound, anywhere, ever.**
- **Anything requiring a "Skip intro" affordance.** Needing the skip is the admission that the
  thing is a tax.
