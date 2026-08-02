/* fx/split.js — the signature.
 *
 * One hairline-ruled rule divided into three proportional segments —
 * YOU, FUIME, STRIPE — with the figures under it. The product's argument
 * rendered as its actual shape: the largest segment, by an enormous margin,
 * belongs to the person doing the work.
 *
 * Three mount modes, one object:
 *   'full'   — beneath the calculator, 10px, labelled underneath
 *   'dock'   — 2px under the nav on every page, unlabelled, aria-hidden
 *   'inline' — one flat rule inside the invoice sheet, above the total row
 *
 * It subscribes to the `fuime:fee` CustomEvent published by fx/ledger-bus.js
 * and to nothing else. It never reads a fee out of the DOM, never observes
 * site.js, never runs a MutationObserver, and never registers a per-frame
 * callback — it is event-driven and CSS-transitioned, so its steady-state cost
 * is zero.
 *
 * Every change to a figure on this object is caused by a hand. The one
 * viewport-triggered moment is the entrance, and what it animates is the
 * frame, not the number.
 */

import { getStage } from 'cwe/stage'

const STYLE_KEY = 'split'
const ORDER = ['you', 'fuime', 'stripe']

const DEFAULTS = {
  mode: 'full', // 'full' | 'dock' | 'inline'
  height: null, // px override; null → --split-h / --split-h-dock
  labels: null, // null → true for 'full', false otherwise
  drawOnEnter: null, // null → true for 'full', false otherwise
  drawMs: 240,
  tickMs: 40,
  resizeMs: 180,
  eventName: 'fuime:fee',
  threshold: 0.35,
  ground: 'auto', // 'light' | 'dark' | 'auto'
  bus: null, // the initLedgerBus handle, if the bus booted first
  roll: null, // { write(el, text) → boolean } from fx/roll.js, if present
  motion: null, // the bus's live motion object, if handed to us
  keys: { you: 'YOU', fuime: 'FUIME', stripe: 'STRIPE' },
  figureFor: ['you'], // which labels carry a currency figure
  staticPct: { you: 90, fuime: 7, stripe: 3 },
  staticFigure: '',
}

/* ── CSS ─────────────────────────────────────────────────────────────────
   Built entirely from :root tokens. The FINAL state — drawn, divided,
   labelled — is the default. The entrance state is opt-in and is only ever
   applied by JS after the observer is bound, so a throw, a print stylesheet,
   a text-mode reader or JS switched off all produce the full static design. */

const CSS = `
[data-fx-split]{
  --fx-split-h: var(--split-h, 10px);
  --fx-split-r: 2px;
  --fx-split-move: 180ms;
  --fx-split-draw: 240ms;
  --fx-split-tick: 40ms;
  --fx-split-ease: var(--ease, cubic-bezier(0.2,0,0,1));
  display:block; width:100%; max-width:100%; color:inherit;
}
[data-fx-split="dock"]{ --fx-split-h: var(--split-h-dock, 2px); --fx-split-r: 0px }
[data-fx-split="inline"]{ --fx-split-h: 3px; --fx-split-r: 0px }

/* Matches the .split-mount:empty gradient the markup ships for the JS-off
   floor, so the hand-off from static rule to live rule is invisible. */
.fx-split__rule{
  position:relative; display:flex; width:100%; height:var(--fx-split-h);
  background: var(--paper);
  border-radius: var(--fx-split-r);
  box-shadow: inset 0 0 0 1px var(--hair);
  clip-path: inset(0 0 0 0 round var(--fx-split-r));
  transition: clip-path var(--fx-split-draw) var(--fx-split-ease);
}
[data-fx-split="dock"] .fx-split__rule,
[data-fx-split="inline"] .fx-split__rule{ background:transparent; box-shadow:none }

.fx-split__seg{
  position:relative; flex:0 0 auto; height:100%; min-width:0;
  transition: width var(--fx-split-move) var(--fx-split-ease);
}
.fx-split__seg::before{
  content:''; position:absolute; inset:0 0 0 1px;
  background: currentColor; opacity: var(--fx-split-fill, .2);
}
.fx-split__seg:first-child::before{ inset:0 }
/* The default proportions are the CSS's, not JS's, so a segment is never a
   zero-width sliver even in the window between building the markup and the
   first render, or if a render throws. JS overrides these inline. */
.fx-split__seg--you{ --fx-split-fill: .86; width:90% }
.fx-split__seg--fuime{ --fx-split-fill: .38; width:7% }
.fx-split__seg--stripe{ --fx-split-fill: .16; width:3% }
[data-fx-split="dock"] .fx-split__seg--you{ --fx-split-fill: .92 }
[data-fx-split="dock"] .fx-split__seg--fuime{ --fx-split-fill: .58 }
[data-fx-split="dock"] .fx-split__seg--stripe{ --fx-split-fill: .32 }

.fx-split__ticks{ position:relative; height: var(--s2, 8px) }
[data-fx-split="dock"] .fx-split__ticks,
[data-fx-split="inline"] .fx-split__ticks{ display:none }
.fx-split__tick{
  position:absolute; top:0; bottom:0; width:1px;
  background: var(--hair);
  opacity:1; transform:translateY(0);
  transition:
    left var(--fx-split-move) var(--fx-split-ease),
    opacity var(--fx-split-move) var(--fx-split-ease),
    transform var(--fx-split-move) var(--fx-split-ease);
}
[data-fx-split-ground="dark"] .fx-split__tick{ background: var(--on-dark-faint) }

.fx-split__labels{
  display:flex; flex-wrap:wrap; align-items:baseline; max-width:100%;
  margin-top: var(--s1, 4px);
  font-size: var(--t-small, .875rem);
  letter-spacing: var(--track-hud, .04em);
  font-variant-numeric: tabular-nums lining;
  line-height:1.3;
}
[data-fx-split="dock"] .fx-split__labels,
[data-fx-split="inline"] .fx-split__labels{ display:none }
.fx-split__label{
  display:flex; flex-wrap:wrap; align-items:baseline;
  gap: 0 var(--s2, 8px); min-width: max-content;
  padding-right: var(--s4, 16px);
  transition: width var(--fx-split-move) var(--fx-split-ease);
}
.fx-split__label--you{ flex:1 1 auto }
.fx-split__label--fuime,
.fx-split__label--stripe{ flex:0 0 auto }
.fx-split__label--stripe{ padding-right:0; justify-content:flex-end; text-align:right }
.fx-split__key{ opacity:.64 }
.fx-split__fig{ font-weight: var(--w-ui, 500) }
.fx-split__fig:empty{ display:none }
.fx-split__pct{ opacity:.64 }

/* Phone: each label wraps to two lines under its segment — key over figures —
   rather than shrinking below --t-small. Grid, not a wrapped flex row, because
   a wrapping flex row's max-content is the sum of its children and that pushes
   the third label onto its own line. */
@media (max-width: 720px){
  .fx-split__labels{ margin-top: var(--s2, 8px) }
  .fx-split__label{
    display:grid; grid-template-columns:auto auto;
    column-gap: var(--s2, 8px); row-gap:2px;
    justify-content:start; align-content:start;
    padding-right: var(--s3, 12px);
  }
  .fx-split__key{ grid-column: 1 / -1 }
  .fx-split__label--stripe{ justify-content:end }
}

/* The entrance. Applied only by JS, only on the 'full' instance, only once. */
[data-fx-split-enter="pre"] .fx-split__rule{ clip-path: inset(0 100% 0 0 round var(--fx-split-r)); transition:none }
[data-fx-split-enter="pre"] .fx-split__tick{ opacity:0; transform:translateY(-4px); transition:none }
[data-fx-split-enter="in"] .fx-split__tick{
  transition-delay: calc(var(--fx-split-draw) + var(--fx-split-i, 0) * var(--fx-split-tick));
}

@media (prefers-reduced-motion: reduce){
  [data-fx-split] .fx-split__rule,
  [data-fx-split] .fx-split__seg,
  [data-fx-split] .fx-split__tick,
  [data-fx-split] .fx-split__label{ transition: none }
}
`

/* ── helpers ─────────────────────────────────────────────────────────── */

function injectCSS() {
  if (typeof document === 'undefined') return
  if (document.querySelector('style[data-fx="' + STYLE_KEY + '"]')) return
  const el = document.createElement('style')
  el.setAttribute('data-fx', STYLE_KEY)
  el.textContent = CSS
  document.head.appendChild(el)
}

function readToken(name, fallback) {
  try {
    const v = getComputedStyle(document.documentElement)
      .getPropertyValue(name)
      .trim()
    return v || fallback
  } catch (e) {
    return fallback
  }
}

function money(n) {
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    }).format(n)
  } catch (e) {
    return '$' + Number(n).toFixed(2)
  }
}

function num(v) {
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}

/* One channel of a computed colour function: a plain number, or a percentage
   of `full`. Returns null for anything it does not understand. */
function chan(tok, full) {
  const n = parseFloat(tok)
  if (!Number.isFinite(n)) return null
  return tok.indexOf('%') !== -1 ? (n / 100) * full : n
}

/* Ground detection: walk up for the first ancestor with an opaque background
   and measure its luminance. Every component is read out of the computed value
   at runtime — this file states no colour of its own, in any notation. Used
   only to choose which hairline token the ticks take. */
function resolveGround(el) {
  try {
    let node = el
    for (let i = 0; node && i < 12; i++) {
      const bg = String(getComputedStyle(node).backgroundColor || '')
      const m = /^([a-z]+)\(([^)]*)\)/i.exec(bg)
      if (m) {
        const wide = m[1].toLowerCase() === 'color'
        let parts = m[2].split(/[,\s/]+/).filter(Boolean)
        // `color(<space> r g b [/ a])` leads with a colour-space keyword and
        // carries 0–1 components; the r/g/b functions carry 0–255.
        if (wide) parts = parts.slice(1)
        const c = [
          chan(parts[0] || '', wide ? 1 : 255),
          chan(parts[1] || '', wide ? 1 : 255),
          chan(parts[2] || '', wide ? 1 : 255),
        ]
        if (c[0] !== null && c[1] !== null && c[2] !== null) {
          const a = parts.length > 3 ? chan(parts[3], 1) : 1
          if (a === null || a > 0.5) {
            const scale = wide ? 255 : 1
            const lum = (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) * scale
            return lum < 128 ? 'dark' : 'light'
          }
        }
      }
      node = node.parentElement
    }
  } catch (e) {}
  return 'light'
}

function inViewport(rect) {
  const h = window.innerHeight || document.documentElement.clientHeight || 0
  const w = window.innerWidth || document.documentElement.clientWidth || 0
  return rect.bottom > 0 && rect.top < h && rect.right > 0 && rect.left < w
}

/* ── the module ──────────────────────────────────────────────────────── */

export function initSplit(target, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})
  cfg.keys = Object.assign({}, DEFAULTS.keys, (config && config.keys) || {})
  cfg.staticPct = Object.assign(
    {},
    DEFAULTS.staticPct,
    (config && config.staticPct) || {}
  )
  cfg.figureFor = Array.isArray(cfg.figureFor)
    ? cfg.figureFor
    : DEFAULTS.figureFor

  const inert = {
    refresh: function () {},
    destroy: function () {},
    mode: cfg.mode,
    state: null,
  }

  if (typeof document === 'undefined') return inert

  const root =
    typeof target === 'string'
      ? document.querySelector(target)
      : target && target.nodeType === 1
        ? target
        : document.querySelector('[data-fx-split]')

  // No mount point is not an error. The page is correct without us.
  if (!root) return inert

  // The markup declares the mode; config only overrides it.
  const mode =
    (config && config.mode) ||
    root.getAttribute('data-fx-split') ||
    root.getAttribute('data-split-mode') ||
    DEFAULTS.mode
  const wantLabels = cfg.labels === null ? mode === 'full' : !!cfg.labels
  const wantEnter =
    (cfg.drawOnEnter === null ? mode === 'full' : !!cfg.drawOnEnter) &&
    mode === 'full'

  injectCSS()

  const rmq =
    typeof matchMedia === 'function'
      ? matchMedia('(prefers-reduced-motion: reduce)')
      : null

  /* This module registers no per-frame callback, so it must not be the thing
     that boots the shared rAF loop — `getStage()` starts it on first call.
     The bus's motion object is the authority, the media query answers the same
     question locally, and the Stage is only consulted if neither exists. */
  let stage = null
  function reduced() {
    if (cfg.motion && typeof cfg.motion.reduced === 'boolean')
      return cfg.motion.reduced
    if (rmq) return !!rmq.matches
    if (!stage) stage = getStage()
    return !!(stage && stage.reducedMotion)
  }

  /* ── static default, from the mount's own data-* ───────────────────── */

  /* The mount ships `data-you` / `data-fuime` / `data-stripe` and, with JS off,
     paints itself from `.split-mount:empty`. We adopt the same numbers so the
     hand-off from the static rule to the live one is not a jump. */
  const d = root.dataset || {}
  const staticPct = {
    you: null,
    fuime: num(d.fuime !== undefined ? d.fuime : d.splitFuime),
    stripe: num(d.stripe !== undefined ? d.stripe : d.splitStripe),
  }
  if (staticPct.fuime === null) staticPct.fuime = cfg.staticPct.fuime
  if (staticPct.stripe === null) staticPct.stripe = cfg.staticPct.stripe
  // The remainder is always YOU. A gap in this bar reads as a hidden fee.
  staticPct.you = 100 - staticPct.fuime - staticPct.stripe

  let staticFigure =
    cfg.staticFigure || d.lands || d.splitLands || d.figure || ''
  if (staticFigure && num(staticFigure) !== null)
    staticFigure = money(num(staticFigure))

  /* ── markup: adopt if the orchestrator shipped it, otherwise build ─── */

  let created = false
  let rule = root.querySelector('[data-fx-split-rule]')
  // Everything is keyed by segment name, never by DOM order: the orchestrator
  // may ship partial markup (two ticks, no label for STRIPE) and an index into
  // a dense array would then point at the wrong segment's boundary.
  const segs = {}
  const tickEls = {}
  const labelEls = {}
  const pctEls = {}
  const figEls = {}
  let ticksBox = null
  let labelsBox = null

  function build() {
    created = true
    const frag = document.createDocumentFragment()

    rule = document.createElement('div')
    rule.className = 'fx-split__rule'
    rule.setAttribute('data-fx-split-rule', '')
    rule.setAttribute('aria-hidden', 'true')
    ORDER.forEach(function (k) {
      const s = document.createElement('span')
      s.className = 'fx-split__seg fx-split__seg--' + k
      s.setAttribute('data-fx-split-seg', k)
      rule.appendChild(s)
    })
    frag.appendChild(rule)

    ticksBox = document.createElement('div')
    ticksBox.className = 'fx-split__ticks'
    ticksBox.setAttribute('aria-hidden', 'true')
    ORDER.forEach(function (k, i) {
      const t = document.createElement('span')
      t.className = 'fx-split__tick'
      t.setAttribute('data-fx-split-tick', k)
      t.style.setProperty('--fx-split-i', String(i))
      ticksBox.appendChild(t)
    })
    frag.appendChild(ticksBox)

    if (wantLabels) {
      labelsBox = document.createElement('div')
      labelsBox.className = 'fx-split__labels'
      ORDER.forEach(function (k) {
        const l = document.createElement('div')
        l.className = 'fx-split__label fx-split__label--' + k
        l.setAttribute('data-fx-split-label', k)

        const key = document.createElement('span')
        key.className = 'fx-split__key'
        key.textContent = cfg.keys[k]
        l.appendChild(key)

        if (cfg.figureFor.indexOf(k) !== -1) {
          const f = document.createElement('span')
          f.className = 'fx-split__fig'
          f.setAttribute('data-fx-split-fig', k)
          l.appendChild(f)
        }

        const p = document.createElement('span')
        p.className = 'fx-split__pct'
        p.setAttribute('data-fx-split-pct', k)
        l.appendChild(p)

        labelsBox.appendChild(l)
      })
      frag.appendChild(labelsBox)
    }

    root.appendChild(frag)
  }

  if (!rule) build()

  function collect() {
    rule = root.querySelector('[data-fx-split-rule]')
    ticksBox = root.querySelector('.fx-split__ticks')
    labelsBox = root.querySelector('.fx-split__labels')
    ORDER.forEach(function (k, i) {
      segs[k] = root.querySelector('[data-fx-split-seg="' + k + '"]')
      labelEls[k] = root.querySelector('[data-fx-split-label="' + k + '"]')
      pctEls[k] = root.querySelector('[data-fx-split-pct="' + k + '"]')
      figEls[k] = root.querySelector('[data-fx-split-fig="' + k + '"]')
      const t = root.querySelector('[data-fx-split-tick="' + k + '"]')
      tickEls[k] = t || null
      if (t) t.style.setProperty('--fx-split-i', String(i))
    })
    // Hand-written markup may ship one unkeyed figure slot. It belongs to the
    // first key that is meant to carry a figure.
    const first = cfg.figureFor[0]
    if (first && !figEls[first]) {
      const loose = root.querySelector('[data-fx-split-fig=""]')
      if (loose) figEls[first] = loose
    }
  }
  collect()

  if (!rule) return inert

  // Anything the markup already declared is the markup's, and destroy() must
  // hand the mount back exactly as it found it — including the attributes we
  // did not write.
  const ownsModeAttr = !root.hasAttribute('data-fx-split')
  const ownsGroundAttr = !root.hasAttribute('data-fx-split-ground')
  const ownsAriaHidden = mode !== 'full' && !root.hasAttribute('aria-hidden')
  const OWN_PROPS = [
    '--fx-split-move',
    '--fx-split-draw',
    '--fx-split-tick',
    '--fx-split-ease',
    '--fx-split-h',
  ]
  root.setAttribute('data-fx-split', mode)
  root.setAttribute(
    'data-fx-split-ground',
    cfg.ground === 'auto' ? resolveGround(root) : cfg.ground
  )
  root.style.setProperty('--fx-split-move', cfg.resizeMs + 'ms')
  root.style.setProperty('--fx-split-draw', cfg.drawMs + 'ms')
  root.style.setProperty('--fx-split-tick', cfg.tickMs + 'ms')
  root.style.setProperty(
    '--fx-split-ease',
    readToken('--ease', 'cubic-bezier(0.2,0,0,1)')
  )
  if (cfg.height !== null && num(cfg.height) !== null)
    root.style.setProperty('--fx-split-h', num(cfg.height) + 'px')
  if (mode !== 'full') root.setAttribute('aria-hidden', 'true')

  /* ── the arithmetic is the bus's. We only take proportions from it. ── */

  let state = {
    you: staticPct.you,
    fuime: staticPct.fuime,
    stripe: staticPct.stripe,
    figure: staticFigure,
    figures: { you: staticFigure, fuime: '', stripe: '' },
    recovered: false,
  }

  function proportions(detail) {
    const charge = num(detail && detail.charge)
    if (charge === null || charge <= 0) return null

    let stripe = ((num(detail.stripe) || 0) / charge) * 100
    let fuime = ((num(detail.fuime) || 0) / charge) * 100
    if (!Number.isFinite(stripe) || stripe < 0) stripe = 0
    if (!Number.isFinite(fuime) || fuime < 0) fuime = 0
    stripe = Math.min(stripe, 100)
    fuime = Math.min(fuime, 100 - stripe)

    // YOU is always the remainder. If the reported `lands` disagrees with the
    // remainder by more than 0.1 of a point, we render the two segments we
    // know and hand the rest to YOU rather than leaving a gap — a gap in this
    // bar reads as a hidden fee, which is the worst failure available.
    const you = 100 - fuime - stripe
    const lands = num(detail.lands)
    const landsPct = lands === null ? null : (lands / charge) * 100
    // Only a `lands` that actually arrived can disagree with us. A missing one
    // is not a disagreement, and must not raise the flag.
    const recovered = landsPct !== null && Math.abs(landsPct - you) > 0.1

    // The figures are amounts, not proportions, and each label carries its own.
    const amounts = {
      you: lands,
      fuime: num(detail.fuime),
      stripe: num(detail.stripe),
    }
    const figures = {}
    ORDER.forEach(function (k) {
      figures[k] =
        amounts[k] === null
          ? (state.figures && state.figures[k]) || ''
          : money(amounts[k])
    })

    return {
      you: you,
      fuime: fuime,
      stripe: stripe,
      figure: figures.you,
      figures: figures,
      recovered: recovered,
    }
  }

  function pct1(n) {
    return Math.round(n * 10) / 10
  }

  function writeFigure(el, text) {
    if (!el || !text) return
    const roll = cfg.roll
    if (roll && typeof roll.write === 'function') {
      try {
        if (roll.write(el, text) === true) return
      } catch (e) {}
    }
    if (el.textContent !== text) el.textContent = text
  }

  function render(next) {
    state = next

    // Displayed percentages are rounded to one place and YOU absorbs the
    // rounding, so the three printed figures always sum to exactly 100.0.
    const fD = pct1(state.fuime)
    const sD = pct1(state.stripe)
    const yD = pct1(100 - fD - sD)
    const shown = { you: yD, fuime: fD, stripe: sD }

    const widths = {
      you: state.you,
      fuime: state.fuime,
      stripe: state.stripe,
    }
    const figures = state.figures || {}
    let left = 0
    ORDER.forEach(function (k) {
      const w = Math.max(0, widths[k])
      if (segs[k]) {
        segs[k].style.width = w.toFixed(3) + '%'
        // Not `data-fx-split-pct`: that attribute names a label element, and
        // two meanings on one attribute name is a query waiting to go wrong.
        segs[k].setAttribute('data-fx-split-share', String(shown[k]))
      }
      if (tickEls[k]) tickEls[k].style.left = left.toFixed(3) + '%'
      if (labelEls[k] && k !== 'you')
        labelEls[k].style.width = w.toFixed(3) + '%'
      if (pctEls[k]) {
        const txt = shown[k].toFixed(1) + '%'
        if (pctEls[k].textContent !== txt) pctEls[k].textContent = txt
      }
      if (figEls[k]) writeFigure(figEls[k], figures[k])
      left += w
    })

    if (state.recovered) root.setAttribute('data-fx-split-recovered', 'true')
    else root.removeAttribute('data-fx-split-recovered')
  }

  // Hydrate synchronously from the bus handle when the orchestrator hands it
  // to us; otherwise the mount's own data-* defaults stand until an event
  // arrives, and if one never arrives they stand forever. Either way the bar
  // is drawn and divided at first paint.
  if (cfg.bus && cfg.bus.state) {
    const p = proportions(cfg.bus.state)
    if (p) state = p
  }
  render(state)

  /* ── the only input: a hand on the slider ──────────────────────────── */

  function onFee(e) {
    const p = proportions(e && e.detail)
    if (!p) return
    render(p)
  }
  document.addEventListener(cfg.eventName, onFee)

  /* ── the entrance. Structure arrives before data. Once, then never. ── */

  let io = null
  let enterTimer = 0
  let safety = 0
  let safetyTries = 0
  let entered = false
  let began = false

  function finishEnter() {
    entered = true
    if (io) {
      io.disconnect()
      io = null
    }
    if (enterTimer) clearTimeout(enterTimer)
    if (safety) clearTimeout(safety)
    enterTimer = 0
    safety = 0
    root.removeAttribute('data-fx-split-enter')
  }

  /* Idempotent on purpose. `entered` alone does not guard this: it is not set
     until the entrance finishes, so a second call in between — an observer
     record queued before the disconnect, a stray manual call — would re-arm
     the finish timer and orphan the first one. It runs once. */
  function beginEnter() {
    if (entered || began) return
    began = true
    if (io) {
      io.disconnect()
      io = null
    }
    if (safety) clearTimeout(safety)
    safety = 0
    if (enterTimer) clearTimeout(enterTimer)
    enterTimer = 0
    // Force the pre-state to be computed so the transition actually runs.
    void rule.getBoundingClientRect().width
    root.setAttribute('data-fx-split-enter', 'in')
    // Long enough to cover the whole choreography: the draw, the last tick's
    // stagger, and that tick's own transition — which runs at --fx-split-move,
    // i.e. resizeMs. Clearing the attribute early would snap the ticks.
    enterTimer = setTimeout(
      finishEnter,
      cfg.drawMs + (ORDER.length - 1) * cfg.tickMs + cfg.resizeMs + 200
    )
  }

  /* If the observer never reports — the mount is inside a collapsed ancestor,
     say — clear the entrance state rather than leave a rule undrawn. We only
     give up once the rule is demonstrably on screen and still not entered. */
  function armSafety() {
    safety = setTimeout(function () {
      if (entered) return
      safetyTries++
      if (inViewport(rule.getBoundingClientRect()) || safetyTries >= 6) {
        finishEnter()
        return
      }
      armSafety()
    }, 4000)
  }

  function onReducedChange(e) {
    // Not a motion policy — the bus owns that. This only aborts an entrance
    // that is already in flight so a mid-session OS change cannot leave the
    // rule clipped.
    if (e.matches) finishEnter()
  }
  if (rmq && rmq.addEventListener)
    rmq.addEventListener('change', onReducedChange)

  const rect0 = rule.getBoundingClientRect()
  const laidOut = rect0.width > 0 || rect0.height > 0

  /* Constraint 5, structurally: the un-drawn state is applied ONLY after the
     trigger that undoes it is confirmed bound. Bind first, hide second. If any
     of this throws, the attribute was never set and the rule is simply already
     drawn — which is the design, not a fallback. */
  if (
    wantEnter &&
    laidOut &&
    !reduced() &&
    typeof IntersectionObserver === 'function'
  ) {
    let armed = false
    if (inViewport(rect0)) {
      // Already on screen: run it on the next task so the pre-state paints.
      try {
        enterTimer = setTimeout(beginEnter, 0)
        armed = true
      } catch (e) {
        armed = false
      }
    } else {
      try {
        io = new IntersectionObserver(
          function (entries) {
            for (let i = 0; i < entries.length; i++) {
              if (entries[i].isIntersecting) {
                beginEnter()
                return
              }
            }
          },
          { threshold: cfg.threshold }
        )
        io.observe(root)
        armSafety()
        armed = true
      } catch (e) {
        if (io) io.disconnect()
        io = null
        if (safety) clearTimeout(safety)
        safety = 0
        armed = false
      }
    }
    if (armed) root.setAttribute('data-fx-split-enter', 'pre')
    else entered = true
  } else {
    entered = true
  }

  /* ── handle ────────────────────────────────────────────────────────── */

  return {
    mode: mode,
    get state() {
      return state
    },
    refresh: function () {
      collect()
      render(state)
    },
    destroy: function () {
      document.removeEventListener(cfg.eventName, onFee)
      if (rmq && rmq.removeEventListener)
        rmq.removeEventListener('change', onReducedChange)
      if (io) io.disconnect()
      io = null
      if (enterTimer) clearTimeout(enterTimer)
      if (safety) clearTimeout(safety)
      enterTimer = 0
      safety = 0
      root.removeAttribute('data-fx-split-enter')
      root.removeAttribute('data-fx-split-recovered')
      if (created) {
        // Emptying the mount hands the rule back to `.split-mount:empty`,
        // which is the JS-off floor. It is never left blank.
        if (rule && rule.parentNode === root) root.removeChild(rule)
        if (ticksBox && ticksBox.parentNode === root) root.removeChild(ticksBox)
        if (labelsBox && labelsBox.parentNode === root)
          root.removeChild(labelsBox)
      }
      // Everything we wrote onto the mount itself comes off whether we built
      // the markup or adopted it; everything the markup already had stays.
      if (ownsModeAttr) root.removeAttribute('data-fx-split')
      if (ownsGroundAttr) root.removeAttribute('data-fx-split-ground')
      if (ownsAriaHidden) root.removeAttribute('aria-hidden')
      for (let i = 0; i < OWN_PROPS.length; i++)
        root.style.removeProperty(OWN_PROPS[i])
      if (!root.getAttribute('style')) root.removeAttribute('style')
    },
  }
}
