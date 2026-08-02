/* fx/steprail.js — the tracked sequence.
 *
 * Three steps, one of them needs a parent. A hairline spine runs down the left
 * of them and its ink fills downward as you scroll, with a node at each step.
 * A node lit is a step landed, and a step lands in four beats in causal order:
 * the numeral, then the rule under it, then the tile, then the copy. Step two
 * does not start until step one's copy is on the page, so the sequence reads as
 * a sequence and not as three things arriving at once.
 *
 * Step 02 holds `extraHoldMs` longer before step 03 begins. It is the step that
 * decides the deal — a parent has to do something — and the page is better off
 * naming that friction where it happens than letting someone discover it at
 * signup.
 *
 * Fully reversible: scroll back up and the ink retreats, the nodes go hollow
 * and the steps return to their pre-state. This is the one place on the site
 * where scrolling is rewarded with visible progress, which only works if the
 * progress is real — so it is read off `stage.scroll`, not off a one-shot
 * observer that can only ever fire forwards.
 *
 * FINAL STATE IS THE CSS DEFAULT. The filled rail, the lit nodes, the landed
 * steps: that is what this file's stylesheet says with no attributes set. The
 * pre-state exists only under [data-fx-steprail-state='armed'], which is
 * written after this module has confirmed reduced motion is off AND that its
 * frame callback is bound. A JS error, a print stylesheet, a text-mode reader
 * or a renderer that never scrolls all produce the complete three steps.
 *
 * One `stage.register` callback reading `stage.scroll`. No requestAnimationFrame
 * of its own, no scroll listener, no window.scrollY.
 */

import { getStage } from 'cwe/stage'

const NAME = 'steprail'
const ATTR = 'data-fx-steprail'
const STATE = 'data-fx-steprail-state'
const STEP = 'data-fx-steprail-step'
const BEAT = 'data-fx-steprail-beat'
const LANE = 'data-fx-steprail-lane'
const AXIS = 'data-fx-steprail-axis'
const BOOT = 'data-fx-steprail-boot'
// Set on a step once its whole sequence has finished playing, so the
// transitions this module needed can be taken back off the shared elements.
const DONE = 'data-fx-steprail-done'

const DEFAULTS = {
  stepSelector: '.step',
  beats: [0, 80, 160, 240],

  // 1-BASED step number, matching the `02` printed on the page.
  extraHoldOnStep: 2,
  extraHoldMs: 40,

  numeralSelector: '.step__n',
  // Anything sitting on the numeral's line — the REQUIRES GUARDIAN chip —
  // arrives on the numeral's beat. A chip left hanging over hidden copy is a
  // label with nothing to label.
  metaSelector: '.step__meta',
  tileSelector: '.tile',
  copySelector: 'h2, h3, h4, p, ul, ol',

  // Per-beat transition durations. Nothing here may exceed 300ms.
  numeralMs: 220,
  ruleMs: 260,
  tileMs: 300,
  copyMs: 260,
  nodeMs: 220,

  // Where the fill starts and finishes, as a fraction of viewport height.
  // Ink begins when the rail's top is 85% down the screen and completes when
  // its bottom passes 55%.
  enter: 0.85,
  exit: 0.55,
  // The least travel, as a fraction of viewport height, that is worth hiding
  // copy behind. Under it the rail is filled and the steps are landed.
  minTravel: 0.35,

  // Desktop: the rail sits this far to the left of the step column.
  // Phone: it sits this far in from the left edge of the *screen*, with the
  // numerals hanging in the lane between it and the copy.
  railGap: 24,
  railInset: 12,
  laneGap: 13,
  lanePad: 12,
  mobileMax: 720,
}

// Below this the ink would be chasing sub-pixel scroll; treat the band as
// having no travel at all and fill it over whatever the document has.
const MIN_TRAVEL = 24
// Nodes closer together than this are on the same row, not stacked.
const NODE_MIN_SEP = 24
// Steps sharing one row land inside this much of the band's travel. Small
// enough that the last one arrives while the row is still being read; large
// enough that the three still arrive in order rather than together.
const ROW_LAND = 0.34
// Enough slack that a scroll sitting exactly on a node cannot strobe it.
const HYST = 0.012

/* ── one stylesheet, once ─────────────────────────────────────────────────
   Read top to bottom this is the finished composition first and the animation
   second. Nothing here is a colour literal: every colour is a custom property
   this module writes at init from a computed value. */
const CSS = `
[${ATTR}] { position: relative; }

[${ATTR}] .fx-${NAME}__rail {
  position: absolute;
  width: 1px;
  z-index: var(--cwe-z-fx, 20);
  pointer-events: none;
}
[${ATTR}] .fx-${NAME}__track {
  position: absolute;
  inset: 0;
  background: var(--fx-${NAME}-hair, currentColor);
}
[${ATTR}] .fx-${NAME}__ink {
  position: absolute;
  inset: 0;
  background: var(--fx-${NAME}-ink, currentColor);
  transform-origin: 50% 0;
  transform: scaleY(var(--fx-${NAME}-p, 1));
  will-change: transform;
}
[${ATTR}] .fx-${NAME}__node {
  position: absolute;
  left: 50%;
  width: 9px;
  height: 9px;
  margin: -4.5px 0 0 -4.5px;
  border-radius: 50%;
  box-sizing: border-box;
  border: 1px solid var(--fx-${NAME}-ground, transparent);
  background: var(--fx-${NAME}-ink, currentColor);
}

/* A rail down the left is right for a stack and wrong for a row. Three steps
   side by side are all at the same height, so a vertical line beside the first
   column connects nothing: it points down past step one while steps two and
   three sit to its right, and its nodes mark heights no step occupies.

   So in a row the connecting line goes away and each node moves onto the
   hairline its own step already carries, at that step's left edge — a bead
   threaded on the rule. The sequence still reads in order and still fills as
   you scroll; it just reads left to right, which is the direction the layout
   is actually going. The rail element stays as the positioning frame so the
   nodes keep one owner and one teardown. */
[${ATTR}][${AXIS}='row'] .fx-${NAME}__track,
[${ATTR}][${AXIS}='row'] .fx-${NAME}__ink {
  display: none;
}

[${ATTR}] [${STEP}] {
  position: relative;
}

/* The rule under the numeral is the step's own top border, taken over so it
   can be drawn. Width and colour are copied off the computed border, so the
   night band keeps its own hairline and no colour is ever written here.

   The takeover happens ONLY while armed. Unarmed — no JS, a JS error, after
   settle(), after destroy() — the step keeps its real border. That matters
   past tidiness: this replacement draws with a background, and a browser
   printing with background graphics off drops backgrounds and keeps borders,
   so an unconditional takeover would delete the hairlines from every printed
   copy of the page. */
[${ATTR}][${STATE}='armed'] [${STEP}] {
  border-top-color: transparent;
}
[${ATTR}][${STATE}='armed'] [${STEP}]::before {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  top: calc(-1 * var(--fx-${NAME}-bw, 1px));
  height: var(--fx-${NAME}-bw, 1px);
  background: var(--fx-${NAME}-hair, currentColor);
  transform: scaleX(1);
  transform-origin: 0 50%;
  pointer-events: none;
}

/* Phone: the rail moves to the screen edge and the numerals hang in the lane
   beside it. A phone is already one column with a margin, so the ledger gutter
   is more native there than it is on a desktop grid. */
[${ATTR}][${LANE}='gutter'] [${STEP}] {
  padding-left: var(--fx-${NAME}-pad, 0px);
}
[${ATTR}][${LANE}='gutter'] .fx-${NAME}__lane {
  position: absolute;
  left: var(--fx-${NAME}-num-x, 0px);
  top: var(--fx-${NAME}-num-y, 0px);
  margin-bottom: 0;
}

/* ── the armed pre-state ────────────────────────────────────────────────── */

[${ATTR}][${STATE}='armed'] .fx-${NAME}__node {
  transition:
    background-color var(--fx-${NAME}-node-ms) var(--fx-${NAME}-ease),
    border-color var(--fx-${NAME}-node-ms) var(--fx-${NAME}-ease),
    transform var(--fx-${NAME}-node-ms) var(--fx-${NAME}-ease);
}
[${ATTR}][${STATE}='armed'] .fx-${NAME}__num {
  transition:
    opacity var(--fx-${NAME}-num-ms) var(--fx-${NAME}-ease),
    transform var(--fx-${NAME}-num-ms) var(--fx-${NAME}-ease);
}
[${ATTR}][${STATE}='armed'] [${STEP}]::before {
  transition: transform var(--fx-${NAME}-rule-ms) var(--fx-${NAME}-ease);
}
[${ATTR}][${STATE}='armed'] .fx-${NAME}__tile {
  transition: clip-path var(--fx-${NAME}-tile-ms) var(--fx-${NAME}-ease);
}
/* Hand the tile back the moment this module is finished with it. plate.js
   owns clip-path on .tile as well and rewrites it every frame from scroll;
   a transition left sitting on the property makes that per-frame window lag
   by a third of a second and repaint on every one of those frames. The
   transition therefore lives exactly as long as the reveal it is for. */
[${ATTR}][${STATE}='armed'] [${STEP}][${DONE}] .fx-${NAME}__tile {
  transition: none;
}
[${ATTR}][${STATE}='armed'] .fx-${NAME}__copy {
  transition:
    opacity var(--fx-${NAME}-copy-ms) var(--fx-${NAME}-ease),
    transform var(--fx-${NAME}-copy-ms) var(--fx-${NAME}-ease);
}

[${ATTR}][${STATE}='armed'] .fx-${NAME}__node[${BEAT}='0'] {
  background: var(--fx-${NAME}-ground, transparent);
  border-color: var(--fx-${NAME}-faint, currentColor);
  transform: scale(0.72);
}
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='0'] .fx-${NAME}__num {
  opacity: 0;
  transform: translateY(6px);
}
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='0']::before,
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='1']::before {
  transform: scaleX(0);
}
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='0'] .fx-${NAME}__tile,
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='1'] .fx-${NAME}__tile,
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='2'] .fx-${NAME}__tile {
  clip-path: inset(0 0 100% 0);
}
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='0'] .fx-${NAME}__copy,
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='1'] .fx-${NAME}__copy,
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='2'] .fx-${NAME}__copy,
[${ATTR}][${STATE}='armed'] [${STEP}][${BEAT}='3'] .fx-${NAME}__copy {
  opacity: 0;
  transform: translateY(8px);
}

/* The first evaluation on mount must not animate. Someone who lands on /#how
   has already scrolled past these steps and is owed the finished composition,
   not a replay of it — and the steps below the fold must reach their pre-state
   without visibly fading out of the state the stylesheet just drew them in.
   Three attributes deep, so it outranks the transitions above whatever the
   source order. */
[${ATTR}][${STATE}='armed'][${BOOT}] .fx-${NAME}__node,
[${ATTR}][${STATE}='armed'][${BOOT}] .fx-${NAME}__num,
[${ATTR}][${STATE}='armed'][${BOOT}] [${STEP}]::before,
[${ATTR}][${STATE}='armed'][${BOOT}] .fx-${NAME}__tile,
[${ATTR}][${STATE}='armed'][${BOOT}] .fx-${NAME}__copy {
  transition: none;
}

/* ── the two blocks that must never lose ──────────────────────────────────
   These undo the armed pre-state wholesale. They are marked !important
   rather than out-specified, because out-specifying is a bet that nobody
   ever adds an attribute to a selector above — and the beat rules above are
   already one attribute deeper than a plain [step] .copy override would
   be. Reduced motion can be switched on mid-session and a print can happen
   at any point in the sequence; neither may leave copy at opacity 0. Print
   in particular cannot run the JS that would rescue it.

   The rule goes back to being the step's own border here, because a print
   with background graphics off keeps borders and drops the pseudo-element
   that replaced it. */
@media (prefers-reduced-motion: reduce) {
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__ink {
    transform: scaleY(1) !important;
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__node {
    background: var(--fx-${NAME}-ink, currentColor) !important;
    border-color: var(--fx-${NAME}-ground, transparent) !important;
    transform: none !important;
  }
  [${ATTR}][${STATE}='armed'] [${STEP}] {
    border-top-color: var(--fx-${NAME}-hair, currentColor) !important;
  }
  [${ATTR}][${STATE}='armed'] [${STEP}]::before {
    display: none !important;
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__num,
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__copy {
    opacity: 1 !important;
    transform: none !important;
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__tile {
    clip-path: none !important;
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__node,
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__num,
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__tile,
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__copy {
    transition: none !important;
  }
}

@media print {
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__ink {
    transform: scaleY(1) !important;
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__node {
    background: var(--fx-${NAME}-ink, currentColor) !important;
    border-color: var(--fx-${NAME}-ground, transparent) !important;
    transform: none !important;
  }
  [${ATTR}][${STATE}='armed'] [${STEP}] {
    border-top-color: var(--fx-${NAME}-hair, currentColor) !important;
  }
  [${ATTR}][${STATE}='armed'] [${STEP}]::before {
    display: none !important;
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__num,
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__copy {
    opacity: 1 !important;
    transform: none !important;
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__tile {
    clip-path: none !important;
  }
  /* Without this the print rules are a 300ms fade the printer starts and does
     not wait for: the paper catches whatever opacity the transition had
     reached, which on a fast print is most of the way to nothing. */
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__node,
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__num,
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__tile,
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__copy {
    transition: none !important;
  }
}
`

function injectOnce() {
  if (document.querySelector('style[data-fx="' + NAME + '"]')) return
  const el = document.createElement('style')
  el.setAttribute('data-fx', NAME)
  el.textContent = CSS
  document.head.appendChild(el)
}

function inert() {
  return {
    destroy: function () {},
    refresh: function () {},
    progress: function () {
      return 1
    },
    steps: 0,
    mounted: false,
  }
}

function clamp01(v) {
  return v < 0 ? 0 : v > 1 ? 1 : v
}

function now() {
  return typeof performance !== 'undefined' && performance.now
    ? performance.now()
    : Date.now()
}

/* The ground behind a node, so the rail does not show through a hollow one.
   Walks up for the first opaque background rather than assuming cream, because
   the same rail has to work on the night bands. A computed colour, never a
   literal. */
function groundColor(el) {
  let n = el
  while (n && n.nodeType === 1) {
    const bg = getComputedStyle(n).backgroundColor
    const parts = bg.match(/[\d.]+/g)
    if (
      parts &&
      parts.length >= 3 &&
      (parts.length < 4 || Number(parts[3]) > 0.5)
    )
      return bg
    n = n.parentElement
  }
  return ''
}

export function initStepRail(target, config) {
  if (typeof document === 'undefined') return inert()

  const root =
    typeof target === 'string' ? document.querySelector(target) : target || null
  if (!root || root.nodeType !== 1) return inert()

  const cfg = Object.assign({}, DEFAULTS, config || {})
  const steps = Array.prototype.slice.call(
    root.querySelectorAll(cfg.stepSelector)
  )

  /* FAILURE MODE. One step is a statement, not a sequence, and a rail down the
     side of it says nothing. Nothing mounts, nothing is styled, the markup is
     left exactly as the stylesheet drew it. */
  if (steps.length < 2) return inert()

  // The steps' shared parent owns the rail. Falling back to `root` covers
  // markup where the steps are not siblings.
  let host = steps[0].parentElement || root
  for (let i = 1; i < steps.length; i++) {
    if (steps[i].parentElement !== host) {
      host = root
      break
    }
  }
  if (host.hasAttribute(ATTR)) return inert() // already mounted here

  const stage = getStage()

  /* Colours and easing come off the tokens at init. Nothing below writes a
     colour value of its own. */
  const cs = getComputedStyle(document.documentElement)
  function token(name, fallback) {
    const v = cs.getPropertyValue(name).trim()
    return v ? 'var(' + name + ')' : fallback
  }
  const ease = cs.getPropertyValue('--ease').trim() || 'cubic-bezier(0.2,0,0,1)'
  const inkColor = token('--ink', 'currentColor')
  const faintColor = token('--ink-faint', 'currentColor')
  const ground = groundColor(host) || token('--cream', 'transparent')

  /* The unfilled rail is the same hairline the steps are already ruled with.
     Taking it off the computed border rather than the token means the night
     bands hand over their own hairline without this file knowing they exist. */
  const firstStyle = getComputedStyle(steps[0])
  const hairColor =
    (parseFloat(firstStyle.borderTopWidth) || 0) >= 0.5
      ? firstStyle.borderTopColor
      : token('--hair', 'currentColor')

  injectOnce()

  /* ── mount: attributes, classes, the rail element ─────────────────────── */

  const beats =
    Array.isArray(cfg.beats) && cfg.beats.length ? cfg.beats : DEFAULTS.beats
  const lastBeat = beats[beats.length - 1]
  // The slowest transition any beat can start, so a step can be declared done
  // no earlier than the last pixel it is responsible for moving.
  const longestMs = Math.max(
    Number(cfg.numeralMs) || 0,
    Number(cfg.ruleMs) || 0,
    Number(cfg.tileMs) || 0,
    Number(cfg.copyMs) || 0,
    Number(cfg.nodeMs) || 0
  )

  const entries = []
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]
    const numeral = step.querySelector(cfg.numeralSelector)

    // Beat one is the numeral and whatever shares its line.
    const meta = cfg.metaSelector ? step.querySelector(cfg.metaSelector) : null
    const first = meta ? Array.prototype.slice.call(meta.children) : []
    if (numeral && first.indexOf(numeral) < 0) first.push(numeral)

    const tiles = Array.prototype.slice.call(
      step.querySelectorAll(cfg.tileSelector)
    )
    const copy = Array.prototype.slice
      .call(step.querySelectorAll(cfg.copySelector))
      .filter(function (el) {
        return first.indexOf(el) < 0 && !el.closest('picture')
      })

    const stepStyle = getComputedStyle(step)
    const bw = parseFloat(stepStyle.borderTopWidth) || 0
    step.style.setProperty('--fx-' + NAME + '-bw', (bw >= 0.5 ? bw : 1) + 'px')
    if (bw >= 0.5)
      step.style.setProperty('--fx-' + NAME + '-hair', stepStyle.borderTopColor)

    for (let f = 0; f < first.length; f++)
      first[f].classList.add('fx-' + NAME + '__num')
    // Only the numeral itself moves into the phone's gutter lane. The chip
    // stays with the copy, where it reads as a condition on this step and not
    // as a stray label in the margin.
    if (numeral) numeral.classList.add('fx-' + NAME + '__lane')
    for (let t = 0; t < tiles.length; t++)
      tiles[t].classList.add('fx-' + NAME + '__tile')
    for (let c = 0; c < copy.length; c++)
      copy[c].classList.add('fx-' + NAME + '__copy')

    step.setAttribute(STEP, String(i))

    entries.push({
      el: step,
      numeral: numeral,
      on: false,
      endAt: 0,
      timers: [],
      node: null,
      frac: (i + 0.5) / steps.length,
      hold:
        i + 1 === Number(cfg.extraHoldOnStep)
          ? Number(cfg.extraHoldMs) || 0
          : 0,
    })
  }

  const rail = document.createElement('div')
  rail.className = 'fx-' + NAME + '__rail'
  rail.setAttribute('aria-hidden', 'true')
  const track = document.createElement('span')
  track.className = 'fx-' + NAME + '__track'
  const ink = document.createElement('span')
  ink.className = 'fx-' + NAME + '__ink'
  rail.appendChild(track)
  rail.appendChild(ink)
  for (let i = 0; i < entries.length; i++) {
    const node = document.createElement('span')
    node.className = 'fx-' + NAME + '__node'
    node.setAttribute(BEAT, String(beats.length))
    entries[i].node = node
    rail.appendChild(node)
  }

  host.setAttribute(ATTR, '')
  host.style.setProperty('--fx-' + NAME + '-ease', ease)
  host.style.setProperty('--fx-' + NAME + '-ink', inkColor)
  host.style.setProperty('--fx-' + NAME + '-hair', hairColor)
  host.style.setProperty('--fx-' + NAME + '-faint', faintColor)
  host.style.setProperty('--fx-' + NAME + '-ground', ground)
  host.style.setProperty('--fx-' + NAME + '-num-ms', cfg.numeralMs + 'ms')
  host.style.setProperty('--fx-' + NAME + '-rule-ms', cfg.ruleMs + 'ms')
  host.style.setProperty('--fx-' + NAME + '-tile-ms', cfg.tileMs + 'ms')
  host.style.setProperty('--fx-' + NAME + '-copy-ms', cfg.copyMs + 'ms')
  host.style.setProperty('--fx-' + NAME + '-node-ms', cfg.nodeMs + 'ms')
  host.appendChild(rail)

  /* ── measurement ──────────────────────────────────────────────────────── */

  const geom = { top: 0, height: 1, start: 0, end: 1, travel: 0 }

  function measure() {
    const vw = stage.viewport.w || document.documentElement.clientWidth || 0
    const vh = stage.viewport.h || document.documentElement.clientHeight || 1

    // Read the host box first: the lane offsets are derived from how far the
    // step column already sits in from the edge of the screen.
    let hostRect = host.getBoundingClientRect()
    const railLeft =
      vw && vw <= cfg.mobileMax
        ? Math.max(cfg.railInset - hostRect.left, -hostRect.left + 2)
        : -Math.min(cfg.railGap, Math.max(0, hostRect.left - 4))

    // The gutter lane is only honest where the steps are actually stacked; on
    // a two- or three-across grid there is no column to hang numerals in.
    const stacked = isStacked()
    const lane = stacked && vw && vw <= cfg.mobileMax
    if (lane) {
      /* The lane attribute goes on FIRST. The numeral is a block-level <p> in
         normal flow and only shrinks to its own width once the lane rule makes
         it absolute — measured before that, `numW` is the width of the whole
         column and the padding derived from it squeezes the copy to a thread.
         Setting the attribute first means the width read below is the width
         the numeral will actually have, on the first pass, on a phone, with no
         second measurement to rescue it. */
      host.setAttribute(LANE, 'gutter')
      host.style.setProperty(
        '--fx-' + NAME + '-num-x',
        railLeft + cfg.laneGap + 'px'
      )
      const numW = entries[0].numeral
        ? entries[0].numeral.getBoundingClientRect().width || 18
        : 0
      const padTop = parseFloat(getComputedStyle(entries[0].el).paddingTop) || 0
      host.style.setProperty('--fx-' + NAME + '-num-y', padTop + 6 + 'px')
      host.style.setProperty(
        '--fx-' + NAME + '-pad',
        Math.max(0, railLeft + cfg.laneGap + numW + cfg.lanePad) + 'px'
      )
    } else if (host.getAttribute(LANE)) {
      host.removeAttribute(LANE)
    }

    // Moving the numerals reflows the column, so the boxes are read after.
    hostRect = host.getBoundingClientRect()
    let top = Infinity
    let bottom = -Infinity
    for (let i = 0; i < entries.length; i++) {
      const r = entries[i].el.getBoundingClientRect()
      if (r.top < top) top = r.top
      if (r.bottom > bottom) bottom = r.bottom
    }
    if (!Number.isFinite(top) || bottom <= top) return

    const height = bottom - top

    // A node marks its step where the numeral is — unless the steps share a
    // row, in which case there is no per-step height to mark and the node
    // belongs on that step's own hairline instead.
    const ys = []
    const xs = []
    let separate = true
    for (let i = 0; i < entries.length; i++) {
      const el = entries[i].numeral || entries[i].el
      const r = el.getBoundingClientRect()
      ys.push(r.top + r.height / 2 - top)
      xs.push(entries[i].el.getBoundingClientRect().left - hostRect.left)
      if (i && ys[i] - ys[i - 1] < NODE_MIN_SEP) separate = false
    }

    /* The rail is a line down the left of a stack, and a frame with no line of
       its own across a row. Either way it owns the nodes, so it is the same
       element with the same teardown; only its box changes. */
    if (separate) {
      host.removeAttribute(AXIS)
      rail.style.left = railLeft + 'px'
      rail.style.top = top - hostRect.top + 'px'
      rail.style.width = ''
      rail.style.height = height + 'px'
    } else {
      host.setAttribute(AXIS, 'row')
      rail.style.left = '0px'
      rail.style.top = top - hostRect.top + 'px'
      rail.style.width = hostRect.width + 'px'
      rail.style.height = '0px'
    }
    /* Where a step LANDS is a different question from where its node SITS, and
       conflating them is what broke the three-across layout. Stacked, the two
       are the same: you scroll past step two's numeral, step two lands. Sharing
       one row, every step is at the same height, so a landing keyed to the
       node's position down the rail fires step three at 83% of the band's
       travel — by which time the row is halfway off the top of the screen and
       a reader who looked at the section saw two of three steps.

       So in a row the beats are compressed into the first stretch of the
       travel: the stagger survives, left to right, but all three have landed
       while the row is still comfortably in view. */
    for (let i = 0; i < entries.length; i++) {
      const node = entries[i].node
      if (separate) {
        node.style.left = ''
        node.style.top = ys[i] + 'px'
        entries[i].frac = clamp01(ys[i] / height)
      } else {
        node.style.left = xs[i] + 'px'
        node.style.top = '0px'
        entries[i].frac = clamp01((ROW_LAND * (i + 0.5)) / entries.length)
      }
    }

    geom.top = top + stage.scroll.y
    geom.height = height

    /* FAILURE MODE. On a very tall phone the whole band can sit inside one
       viewport, and the travel this is supposed to map onto is zero — the ink
       would sit half-drawn over hidden copy for good. Fill over whatever
       travel the document actually has instead; and where there is not enough
       of that to be worth scrolling for, hand back the finished steps at once.
       An unfinishable rail is a bug. A rail that finished early is a rail. */
    const maxScroll = Math.max(
      0,
      (document.documentElement.scrollHeight || 0) - vh
    )
    let s = geom.top - vh * cfg.enter
    let e = geom.top + height - vh * cfg.exit
    s = Math.max(0, Math.min(s, maxScroll))
    e = Math.max(0, Math.min(e, maxScroll))

    /* Below this much travel the fill is not progress, it is a twitch — and
       the copy behind it would be hidden for a scroll nobody makes. Widen the
       window around the band it belongs to: back from `e` first, then forward
       from `s`. It must never be moved somewhere else in the document — a
       window pinned to the bottom of the page would leave three steps' worth
       of copy at opacity 0 until the reader reached the footer. */
    const wanted = Math.max(MIN_TRAVEL, vh * cfg.minTravel)
    if (e - s < wanted) s = Math.max(0, e - wanted)
    if (e - s < wanted) e = Math.min(maxScroll, s + wanted)
    if (e - s < wanted) {
      // The document cannot supply the travel. Hand back the finished steps.
      s = 0
      e = 0
    }
    geom.start = s
    geom.end = e
    geom.travel = e - s
  }

  function isStacked() {
    let prev = -Infinity
    for (let i = 0; i < entries.length; i++) {
      const t = entries[i].el.getBoundingClientRect().top
      if (t - prev < NODE_MIN_SEP) return false
      prev = t
    }
    return true
  }

  /* ── the beats ────────────────────────────────────────────────────────── */

  let chainFreeAt = 0

  function setBeat(entry, b) {
    const v = String(b)
    entry.el.setAttribute(BEAT, v)
    entry.node.setAttribute(BEAT, v)
  }

  function clearTimers(entry) {
    for (let i = 0; i < entry.timers.length; i++) clearTimeout(entry.timers[i])
    entry.timers.length = 0
  }

  function reChain() {
    let m = now()
    for (let i = 0; i < entries.length; i++)
      if (entries[i].on && entries[i].endAt > m) m = entries[i].endAt
    chainFreeAt = m
  }

  function land(entry, instant) {
    if (entry.on) return
    entry.on = true
    clearTimers(entry)
    const t = now()
    if (instant) {
      setBeat(entry, beats.length)
      entry.el.setAttribute(DONE, '')
      entry.endAt = t
      reChain()
      return
    }
    entry.el.removeAttribute(DONE)
    // Step two's beats do not begin until step one's copy has landed. The
    // chain only ever bites on a fast scroll; at reading speed the nodes are
    // far enough apart that each step is long finished before the next.
    const base = Math.max(0, chainFreeAt - t)
    for (let b = 0; b < beats.length; b++) {
      const at = base + beats[b]
      const n = b + 1
      entry.timers.push(
        setTimeout(function () {
          setBeat(entry, n)
        }, at)
      )
    }
    // One beat past the last: the sequence is over, everything this module put
    // on these elements comes back off, and whatever else is animating them
    // gets them back clean.
    entry.timers.push(
      setTimeout(
        function () {
          entry.el.setAttribute(DONE, '')
        },
        base + lastBeat + entry.hold + longestMs
      )
    )
    entry.endAt = t + base + lastBeat + entry.hold
    reChain()
  }

  function unland(entry) {
    if (!entry.on) return
    entry.on = false
    clearTimers(entry)
    entry.endAt = 0
    entry.el.removeAttribute(DONE)
    setBeat(entry, 0)
    reChain()
  }

  /* ── the loop ─────────────────────────────────────────────────────────── */

  let armed = false
  let booting = false
  let lastP = -1

  function evaluate(instant) {
    const p =
      geom.travel > 0 ? clamp01((stage.scroll.y - geom.start) / geom.travel) : 1
    if (p !== lastP) {
      lastP = p
      host.style.setProperty('--fx-' + NAME + '-p', p.toFixed(4))
    }
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      if (p >= entry.frac) land(entry, instant)
      else if (p < entry.frac - HYST) unland(entry)
    }
  }

  function settle() {
    if (!armed) return
    armed = false
    for (let i = 0; i < entries.length; i++) {
      clearTimers(entries[i])
      entries[i].on = true
      entries[i].endAt = 0
      entries[i].el.setAttribute(DONE, '')
      setBeat(entries[i], beats.length)
    }
    host.style.setProperty('--fx-' + NAME + '-p', '1')
    host.removeAttribute(STATE)
    host.removeAttribute(BOOT)
  }

  let offFrame = function () {}
  let offResize = function () {}
  let ro = null

  measure()

  const canAnimate =
    !stage.reducedMotion && typeof stage.register === 'function'

  if (canAnimate) {
    try {
      offFrame = stage.register(function () {
        try {
          // Reduced motion switched on mid-session: the stylesheet has already
          // undone the pre-state, this drops the machinery behind it.
          if (stage.reducedMotion) {
            settle()
            offFrame()
            offFrame = function () {}
            return
          }
          if (!armed) return
          evaluate(false)
        } catch (e) {
          /* Two things are being protected here. The page keeps the finished
             three steps rather than freezing at whatever beat it had reached —
             and the shared loop is not taken down with this module. stage.js
             iterates its callbacks with no guard of its own, so a throw that
             escapes this function stops every effect on the page, and every
             one of them that hides copy behind a frame callback would stay
             hidden. */
          settle()
          try {
            offFrame()
          } catch (e2) {}
          offFrame = function () {}
        }
      })
      if (typeof offFrame !== 'function') throw new Error('no frame handle')

      // Arm only now: motion is confirmed and the trigger is bound. The first
      // evaluation runs with transitions off so an anchor landing mid-band
      // gets the finished steps rather than a replay.
      armed = true
      booting = true
      host.setAttribute(BOOT, '')
      host.setAttribute(STATE, 'armed')
      for (let i = 0; i < entries.length; i++) setBeat(entries[i], 0)
      evaluate(true)
      void host.offsetWidth // flush, so what follows is a transition, not a jump
      host.removeAttribute(BOOT)
      booting = false

      offResize = stage.onResize(function () {
        measure()
        lastP = -1
      })
      if (typeof ResizeObserver === 'function') {
        ro = new ResizeObserver(function () {
          measure()
          lastP = -1
        })
        ro.observe(host)
      }
    } catch (err) {
      // Anything at all goes wrong arming and the page keeps the finished
      // three steps. There is no failure path that leaves copy hidden.
      settle()
      try {
        offFrame()
      } catch (e2) {}
      offFrame = function () {}
    }
  } else {
    // Reduced motion: rail rendered full, nodes present, all steps landed.
    host.style.setProperty('--fx-' + NAME + '-p', '1')
  }

  return {
    steps: entries.length,
    mounted: true,
    progress: function () {
      return lastP < 0 ? 1 : lastP
    },
    refresh: function () {
      measure()
      lastP = -1
      if (armed && !booting) evaluate(false)
    },
    destroy: function () {
      try {
        offFrame()
      } catch (e) {}
      try {
        offResize()
      } catch (e) {}
      if (ro) ro.disconnect()
      ro = null
      for (let i = 0; i < entries.length; i++) {
        const entry = entries[i]
        clearTimers(entry)
        entry.el.removeAttribute(STEP)
        entry.el.removeAttribute(BEAT)
        entry.el.removeAttribute(DONE)
        entry.el.style.removeProperty('--fx-' + NAME + '-bw')
        entry.el.style.removeProperty('--fx-' + NAME + '-hair')
        if (entry.numeral)
          entry.numeral.classList.remove('fx-' + NAME + '__lane')
        const nums = entry.el.querySelectorAll('.fx-' + NAME + '__num')
        for (let n = 0; n < nums.length; n++)
          nums[n].classList.remove('fx-' + NAME + '__num')
        const tiles = entry.el.querySelectorAll('.fx-' + NAME + '__tile')
        for (let t = 0; t < tiles.length; t++)
          tiles[t].classList.remove('fx-' + NAME + '__tile')
        const copy = entry.el.querySelectorAll('.fx-' + NAME + '__copy')
        for (let c = 0; c < copy.length; c++)
          copy[c].classList.remove('fx-' + NAME + '__copy')
      }
      if (rail.parentNode) rail.parentNode.removeChild(rail)
      host.removeAttribute(ATTR)
      host.removeAttribute(STATE)
      host.removeAttribute(LANE)
      host.removeAttribute(BOOT)
      const props = [
        'ease',
        'ink',
        'hair',
        'faint',
        'ground',
        'num-ms',
        'rule-ms',
        'tile-ms',
        'copy-ms',
        'node-ms',
        'num-x',
        'num-y',
        'pad',
        'p',
      ]
      for (let i = 0; i < props.length; i++)
        host.style.removeProperty('--fx-' + NAME + '-' + props[i])
      armed = false
    },
  }
}
