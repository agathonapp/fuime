/* fx/plate.js — depth. Turns full-bleed photographs from wallpaper into material.
 *
 * Doctrine borrowed from `depth-parallax`, engine rejected: no three.js, no
 * offline depth model, no WebGL. A soft horizon cut into two CSS planes shows
 * cardboard-cutout disocclusion the moment you displace it, so this ships the
 * readable part of the effect — a window, a clip, a scale, a drift — in CSS
 * transforms driven by the one shared rAF.
 *
 * THE WHOLE TRICK, and the reason this module changes no layout whatsoever: a
 * plate clips itself. The photograph is scaled and displaced by a transform,
 * and the clip that holds it is computed as the INVERSE of that transform, so
 * the visible window is always exactly the element's own untransformed layout
 * box. Nothing is wrapped, nothing is repositioned, no container is adopted,
 * no `overflow` or `display` is touched, and the plate can never spill a pixel
 * onto its neighbours or uncover an edge of itself. The first draft adopted the
 * surrounding <picture> as a frame; making an inline <picture> a block moved the
 * seam 48px up the page. Measured, rejected, replaced with this.
 *
 * Two roles, chosen per instance:
 *   reveal — the seam, the three How-it-works tiles, the /parents arch.
 *            Clip-inset opening from the plate's top crease, 1.06 → 1.00 scale
 *            coupled to the plate's own scroll travel, ≤24px counter-drift.
 *   depth  — the hero, and only the hero. NO entrance: the hero is the LCP
 *            element and its reveal belongs to handoff.js's departing scrim.
 *            This module adds the continuous ≤6px pointer depth and ≤3° gyro
 *            displacement there and nothing else.
 *
 * COLOUR: there is not one literal in this file. Every colour, space and type
 * value the module renders is a `var(--token)` in the injected CSS, so a token
 * change in style.css lands here with no edit.
 *
 * MOTION IS OPT-IN. The injected CSS ships the fully-revealed composition as
 * its default; the transform and the clip only exist under
 * `[data-fx-plate-on]`, an attribute JS adds after it has confirmed
 * reduced-motion is off, the geometry is real and the frame callback is bound.
 * A thrown error, a print stylesheet, a reader mode or a stalled image all land
 * on a composed, graded, captioned photograph, which is what it was always
 * going to be at rest.
 */

import { getStage } from 'cwe/stage'

const NAME = 'plate'
const ATTR = 'data-fx-plate'
const ATTR_ON = 'data-fx-plate-on'
const ATTR_LIVE = 'data-fx-plate-live'
const ATTR_ROLE = 'data-fx-plate-role'

const DEFAULTS = {
  clipFrom: 0.88, // revealed fraction at the start of the plate's travel
  scaleFrom: 1.06, // scale at the start, easing to 1.00 where it is composed
  parallax: 24, // px of counter-drift — a ceiling, not a target
  pointerDepth: 6, // px of pointer/gyro displacement, depth role only
  caption: null, // string | string[] | (anchor, i) => string | null
  gyro: 3, // degrees of tilt that saturate the displacement
  // Not in the spec's key list; both auto-detect, and exist only so the
  // orchestrator can override a bad guess without a markup change.
  depth: null, // true → depth role, false → reveal role, null → auto
  tone: null, // 'dark' | 'light' | null → auto
}

/* The reveal window, in viewport heights. The plate starts opening a hair
   before its top crease clears the bottom edge and is fully composed a little
   over half a viewport later — short enough that a fast scroller never meets a
   half-drawn plate, long enough to read as travel rather than a switch. */
const ENTER = 0.94
const TRAVEL = 0.55

/* Gyro sits idle in a pocket otherwise. */
const GYRO_IDLE_MS = 4000
const GYRO_EPS_DEG = 0.6 // below this a reading is noise, not motion
const GYRO_DECAY = 0.92 // per frame, once idle
const GYRO_REST_LERP = 0.0025 // slow re-baseline so posture drift never pegs it

/* Sub-pixel insurance on the cover scale, so a rounding error can never show a
   hairline of page through the edge of a photograph. */
const BLEED = 1

/* ── module-shared state: one style tag, one rAF callback, one observer ──── */

let styleEl = null
const registry = new Set()
let stage = null
let offFrame = null
let offResize = null
let io = null
let onWinLoad = null
let onFirstMove = null
let pointerSeen = false
let lastReduced = null

const gyro = {
  wanted: false,
  bound: false,
  gain: 0,
  rest: null,
  beta: 0,
  gamma: 0,
  last: 0,
  onOrient: null,
  onTouch: null,
}

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v
}
function clamp01(v) {
  return v < 0 ? 0 : v > 1 ? 1 : v
}

/* ── CSS ─────────────────────────────────────────────────────────────────── */

const SHEET = `
/* Armed. Everything in this rule is the only motion in the module, and it
   exists only while JS holds the attribute. Every default is the composed,
   fully-revealed, untransformed photograph.

   The attribute is DOUBLED on purpose. style.css owns
     .hero__media img { transform: scale(1.06) translate3d(var(--px), var(--py), 0) }
   at (0,1,1), which outranks a single attribute selector at (0,1,0). The hero
   is the one place this module's depth role applies, and there the transform
   was being discarded by the cascade while the clip-path — which nothing else
   in the sheet declares — still landed: a window cut for a displacement that
   never happened, i.e. a permanent hairline of page down the right edge of the
   LCP photograph and no depth at all. Two attributes is (0,2,0) and settles it.
   The !important blocks at the bottom of this sheet still outrank this. */
[${ATTR_ON}][${ATTR_ON}] {
  clip-path: inset(
    var(--fx-plate-t, 0px) var(--fx-plate-r, 0px)
    var(--fx-plate-b, 0px) var(--fx-plate-l, 0px)
  );
  transform:
    translate3d(var(--fx-plate-x, 0px), var(--fx-plate-y, 0px), 0)
    scale(var(--fx-plate-s, 1));
  /* Right edge, not the centre. A scaled-up element must overflow its box on
     one side of each axis to cover it; a centred origin splits that overflow
     onto both sides, and the right-hand half of a full-bleed plate lands in
     the document's scrollable overflow — clip-path hides it but does not
     remove it, so a 1.06 seam added 47px of horizontal scroll. Pinning the
     origin right puts the whole horizontal overscan on the LEFT, which in LTR
     is unreachable and is not counted. The page cannot scroll sideways because
     there is nothing to the right of it, not because a parent hides it. */
  transform-origin: 100% 50%;
  backface-visibility: hidden;
}
[${ATTR_ON}][${ATTR_LIVE}] { will-change: transform, clip-path; }

/* The same rule ships \`transition: transform 1200ms\`, written for site.js's
   pointer parallax, which is a different effect and is superseded here. Left
   alone it smears a per-frame transform into mush and makes 6px of depth read
   as a 1.2s drag. Killed on armed IMAGES only, by element type: the hero's
   <video> is also an armed plate layer and it keeps the 900ms opacity
   crossfade live.js drives. Disarm restores whatever the sheet said. */
img[${ATTR_ON}][${ATTR_ON}] { transition: none; }

/* The caption. Site type, one step down, tracked out, never uppercase, never
   mono — the costume two judges killed. */
.fx-${NAME}__cap {
  margin-top: var(--s3);
  font-size: var(--t-small);
  font-weight: var(--w-body);
  box-sizing: border-box;
  line-height: 1.5;
  letter-spacing: var(--track-hud, 0.04em);
  text-transform: none;
  color: var(--fx-plate-cap-ink, var(--ink-muted));
  text-wrap: pretty;
}
.fx-${NAME}__cap--bleed {
  max-width: var(--wrap);
  margin-inline: auto;
  margin-top: var(--s4);
  padding-inline: var(--gut);
}
.fx-${NAME}__cap--dark { --fx-plate-cap-ink: var(--on-dark-mu); }

/* Two renderers that must produce the static design, belt and braces, in case
   an instance is armed when the preference flips. */
@media (prefers-reduced-motion: reduce) {
  [${ATTR_ON}] {
    clip-path: none !important;
    transform: none !important;
    will-change: auto !important;
  }
}
@media print {
  [${ATTR_ON}] {
    clip-path: none !important;
    transform: none !important;
  }
}
`

function injectCSS() {
  if (styleEl && styleEl.isConnected) return
  const found = document.querySelector('style[data-fx="' + NAME + '"]')
  if (found) {
    styleEl = found
    return
  }
  styleEl = document.createElement('style')
  styleEl.setAttribute('data-fx', NAME)
  styleEl.textContent = SHEET
  document.head.appendChild(styleEl)
}

/* ── resolving a target into an anchor + its media ───────────────────────── */

function toElements(target) {
  if (!target) return []
  if (typeof target === 'string') {
    return Array.prototype.slice.call(document.querySelectorAll(target))
  }
  if (target.nodeType === 1) return [target]
  if (typeof target.length === 'number') {
    return Array.prototype.slice.call(target).filter(function (n) {
      return n && n.nodeType === 1
    })
  }
  return []
}

/* The media is what moves. The anchor is only ever used for bookkeeping and to
   place the caption in the flow — it is never styled, moved or measured. */
function resolve(el) {
  const tag = el.tagName
  if (tag === 'IMG' || tag === 'VIDEO' || tag === 'CANVAS') {
    return { anchor: el.closest('picture') || el, media: [el] }
  }
  const media = Array.prototype.slice
    .call(el.querySelectorAll('img, video, canvas'))
    .filter(function (m) {
      return !m.closest('svg')
    })
  if (!media.length) return null
  return { anchor: el, media: media }
}

/* ── captions ────────────────────────────────────────────────────────────── */

function captionFor(cfg, el, anchor, i) {
  const attr =
    el.getAttribute('data-fx-caption') || anchor.getAttribute('data-fx-caption')
  if (attr) return attr
  const c = cfg.caption
  if (c == null) return null
  if (typeof c === 'function') {
    try {
      return c(anchor, i) || null
    } catch (e) {
      return null
    }
  }
  if (Array.isArray(c)) return c[i] || null
  return String(c) || null
}

function mountCaption(inst, text) {
  const p = document.createElement('p')
  p.className = 'fx-' + NAME + '__cap'
  p.textContent = text
  if (inst.dark) p.classList.add('fx-' + NAME + '__cap--dark')
  inst.anchor.insertAdjacentElement('afterend', p)
  inst.cap = p
  syncCaptionWidth(inst)
}

/* A full-bleed plate's caption is set to the page wrap; a plate inside a column
   is already inside one. Measured, not guessed, and re-measured on resize
   because the seam is full-bleed at every width and a tile never is. */
function syncCaptionWidth(inst) {
  if (!inst.cap) return
  const doc = document.documentElement.clientWidth
  const bleed = Math.abs(inst.media[0].offsetWidth - doc) <= 2
  inst.cap.classList.toggle('fx-' + NAME + '__cap--bleed', bleed)
}

/* ── arming ──────────────────────────────────────────────────────────────── */

function mediaReady(inst) {
  for (let i = 0; i < inst.media.length; i++) {
    const m = inst.media[i]
    if (m.tagName !== 'IMG') continue
    // naturalWidth is the only honest signal; `complete` is also true for an
    // image that failed. Measuring a plate around an unloaded image measures
    // zero, so the instance waits instead.
    if (!(m.complete && m.naturalWidth > 0)) return false
  }
  return true
}

function armable(inst) {
  if (inst.failed) return false
  if (!stage || stage.inert) return false
  if (stage.reducedMotion) return false
  return mediaReady(inst)
}

function disarm(inst) {
  if (!inst.on) return
  inst.media.forEach(function (m) {
    m.removeAttribute(ATTR_ON)
    m.removeAttribute(ATTR_LIVE)
  })
  const s = inst.anchor.style
  s.removeProperty('--fx-plate-x')
  s.removeProperty('--fx-plate-y')
  s.removeProperty('--fx-plate-s')
  s.removeProperty('--fx-plate-t')
  s.removeProperty('--fx-plate-r')
  s.removeProperty('--fx-plate-b')
  s.removeProperty('--fx-plate-l')
  inst.on = false
  inst.live = false
  inst.w = {}
}

/* Custom properties inherit, so one write on the anchor drives every layer of
   the plate — the hero's still and its video stay registered to the pixel. */
function put(inst, prop, key, value, eps, unit, digits) {
  const prev = inst.w[key]
  if (prev !== undefined && Math.abs(prev - value) < eps) return
  inst.w[key] = value
  inst.anchor.style.setProperty(prop, value.toFixed(digits || 3) + unit)
}

/* ── gyro ────────────────────────────────────────────────────────────────── */

function bindOrientation() {
  if (gyro.bound) return
  gyro.onOrient = function (e) {
    const b = e.beta
    const g = e.gamma
    if (typeof b !== 'number' || typeof g !== 'number') return
    if (gyro.rest === null) gyro.rest = { beta: b, gamma: g }
    if (
      Math.abs(b - gyro.beta) > GYRO_EPS_DEG ||
      Math.abs(g - gyro.gamma) > GYRO_EPS_DEG
    ) {
      gyro.last = performance.now()
      gyro.gain = 1
    }
    gyro.beta = b
    gyro.gamma = g
  }
  window.addEventListener('deviceorientation', gyro.onOrient, { passive: true })
  gyro.bound = true
  gyro.last = performance.now()
  gyro.gain = 1
}

function unbindOrientation() {
  if (!gyro.bound) return
  window.removeEventListener('deviceorientation', gyro.onOrient)
  gyro.onOrient = null
  gyro.bound = false
  gyro.gain = 0
  // Re-arm on the next touch. Permission, where there was one, is already
  // granted, so this costs nothing and asks nothing.
  armGyroOnFirstTouch()
}

/* Silent. One capture-phase, self-removing touchstart anywhere on the page.
   Never a prompt of ours, never an instruction, never a "tilt your phone"
   affordance. Denied, thrown or absent, the same displacement is driven by
   scroll and nobody can tell. */
function armGyroOnFirstTouch() {
  if (!gyro.wanted || gyro.bound || gyro.onTouch) return
  if (typeof window.DeviceOrientationEvent === 'undefined') return
  gyro.onTouch = function () {
    window.removeEventListener('touchstart', gyro.onTouch, true)
    gyro.onTouch = null
    const DOE = window.DeviceOrientationEvent
    if (!DOE) return
    if (typeof DOE.requestPermission !== 'function') {
      bindOrientation()
      return
    }
    let p
    try {
      p = DOE.requestPermission()
    } catch (e) {
      return // throws → scroll-driven displacement, silently
    }
    Promise.resolve(p)
      .then(function (r) {
        if (r === 'granted') bindOrientation()
      })
      .catch(function () {})
  }
  window.addEventListener('touchstart', gyro.onTouch, {
    capture: true,
    passive: true,
    once: true,
  })
}

function gyroOffsets(deg) {
  if (!gyro.bound || gyro.gain <= 0 || gyro.rest === null) return null
  return {
    x: clamp((gyro.gamma - gyro.rest.gamma) / deg, -1, 1) * gyro.gain,
    y: clamp((gyro.beta - gyro.rest.beta) / deg, -1, 1) * gyro.gain,
  }
}

/* ── the one loop, shared by every plate on the page ─────────────────────── */

function tick() {
  if (!stage) return
  const reduced = !!stage.reducedMotion

  if (reduced !== lastReduced) {
    lastReduced = reduced
    if (reduced) registry.forEach(disarm)
  }

  const vh = stage.viewport.h || window.innerHeight || 1
  const now = performance.now()

  if (gyro.bound && gyro.gain > 0 && now - gyro.last > GYRO_IDLE_MS) {
    gyro.gain *= GYRO_DECAY
    if (gyro.gain < 0.004) unbindOrientation() // never burns down a pocket
  }
  if (gyro.bound && gyro.rest) {
    gyro.rest.beta += (gyro.beta - gyro.rest.beta) * GYRO_REST_LERP
    gyro.rest.gamma += (gyro.gamma - gyro.rest.gamma) * GYRO_REST_LERP
  }

  // Pass one: reads. Every rect is taken before any write, so a frame can
  // never cost more than one layout no matter how many plates are on screen.
  registry.forEach(function (inst) {
    inst.ok = false
    if (reduced || !inst.inView) return
    if (!inst.on && !armable(inst)) return
    const r = inst.media[0].getBoundingClientRect()
    if (r.height <= 0 || r.width <= 0) return
    // getBoundingClientRect reports the TRANSFORMED box, and this module is
    // what transformed it. Undo it: the centre of a box scaled about its own
    // centre only moves by the translation, and the untransformed size is the
    // measured size over the scale. Exact, and re-derived every frame, so it
    // can never accumulate.
    const s = inst.w.s || 1
    inst.h = r.height / s
    inst.wd = r.width / s
    inst.top = r.top + r.height / 2 - (inst.w.y || 0) - inst.h / 2
    inst.ok = true
  })

  // Pass two: writes.
  registry.forEach(function (inst) {
    if (!inst.ok) return

    const cfg = inst.cfg
    const h = inst.h
    const w = inst.wd
    const centre = clamp(
      (inst.top + h / 2 - vh / 2) / (vh / 2 + h / 2 || 1),
      -1,
      1
    )

    let x = 0
    let y = 0
    let s = 1
    let cut = 0

    if (inst.role === 'depth') {
      // No entrance here. The hero's reveal is handoff.js's departing scrim;
      // this is the continuous depth and nothing else.
      const d = Math.min(cfg.pointerDepth, h * 0.02)
      if (d > 0) {
        const g = inst.gyro ? gyroOffsets(cfg.gyro || DEFAULTS.gyro) : null
        if (g) {
          // gyroOffsets is already scaled by gyro.gain, which decays to zero
          // over about a second once the device goes still and then unbinds.
          // Ramp the scroll fallback in over exactly that decay, so the handover
          // at the moment the listener drops is continuous rather than a 6px
          // pop from nothing to the scroll displacement.
          x = g.x * d
          y = g.y * d - centre * d * (1 - gyro.gain)
        } else if (inst.pointer && pointerSeen) {
          x = stage.pointer.nx * d
          y = -stage.pointer.ny * d
        } else {
          // Gyro denied, unavailable or asleep — and a desktop pointer that has
          // not moved yet. The same displacement, driven by the plate's own
          // scroll travel. Nobody can tell.
          y = -centre * d
        }
        // The transform origin is the right edge, so a leftward displacement
        // would pull the plate's right edge inside its own window and leave a
        // hairline of page. Bias the whole axis positive: the eye reads the
        // ±d of travel, and a constant d of offset inside a cover crop has no
        // reference to be read against.
        x += d
      }
    } else {
      const p = clamp01((vh * ENTER - inst.top) / (vh * TRAVEL || 1))
      cut = (1 - cfg.clipFrom) * (1 - p) * h
      s = 1 + (cfg.scaleFrom - 1) * (1 - p)
      // ≤24px, and never more drift than the 1.06 scale can pay for. A 210px
      // sliver of seam gets ±6px; a tall plate gets the full 24. Without this
      // bound the cover scale below would blow a thin plate up by 23% to hide
      // an edge, which is a different effect and a worse one.
      y = -centre * Math.min(cfg.parallax, ((cfg.scaleFrom - 1) * h) / 2)
    }

    // The photograph must never uncover an edge of its own window. The drift
    // buys back exactly the scale it needs and no more, so 1.00 is reached
    // where it is seen — plate composed at the centre of the viewport, drift
    // at zero — and the scale never exceeds scaleFrom.
    s = Math.max(
      s,
      1 + (2 * Math.abs(y) + BLEED) / Math.max(h, 1),
      1 + (x + BLEED) / Math.max(w, 1)
    )

    // Settle the scale to the exact number the DOM will hold BEFORE the
    // inverse is computed off it — both the serialisation and the write
    // threshold, which is why this is not simply left to put(). The browser
    // applies the value it was given; a clip derived from any other one opens
    // a fraction of a pixel of daylight down the edge of a 1440px plate.
    s = Math.round(s * 1e5) / 1e5
    if (inst.w.s !== undefined && Math.abs(inst.w.s - s) < 0.0004) s = inst.w.s

    // The clip is the inverse of the transform, so the window it leaves is
    // exactly this element's own untransformed layout box, minus the reveal.
    // Vertical origin centred, horizontal origin at the right edge: a point L
    // lands at o + s(L - o) + t, so the inverse is L = o + (P - o - t)/s.
    const t = Math.max(0, h / 2 - (h / 2 + y) / s)
    const b = Math.max(0, h / 2 - (h / 2 - cut - y) / s)
    const l = Math.max(0, w - (w + x) / s)
    const rr = Math.max(0, x / s)

    put(inst, '--fx-plate-x', 'x', x, 0.05, 'px')
    put(inst, '--fx-plate-y', 'y', y, 0.05, 'px')
    put(inst, '--fx-plate-s', 's', s, 1e-9, '', 5)
    put(inst, '--fx-plate-t', 't', t, 0.05, 'px')
    put(inst, '--fx-plate-r', 'r', rr, 0.05, 'px')
    put(inst, '--fx-plate-b', 'b', b, 0.05, 'px')
    put(inst, '--fx-plate-l', 'l', l, 0.05, 'px')

    // Values first, attribute second, inside one JS turn: a plate is never
    // painted in a half-armed state.
    if (!inst.on) {
      inst.media.forEach(function (m) {
        m.setAttribute(ATTR_ROLE, inst.role)
        m.setAttribute(ATTR_ON, '')
      })
      inst.on = true
    }
    if (!inst.live) {
      inst.media.forEach(function (m) {
        m.setAttribute(ATTR_LIVE, '')
      })
      inst.live = true
    }
  })

  // Anything that left the viewport hands its compositor layer back.
  registry.forEach(function (inst) {
    if (inst.live && !inst.inView) {
      inst.media.forEach(function (m) {
        m.removeAttribute(ATTR_LIVE)
      })
      inst.live = false
    }
  })
}

/* ── shared subscriptions ────────────────────────────────────────────────── */

function ensureShared() {
  if (offFrame) return
  stage = getStage()
  lastReduced = !!stage.reducedMotion

  if (typeof IntersectionObserver === 'function') {
    io = new IntersectionObserver(
      function (entries) {
        for (let i = 0; i < entries.length; i++) {
          const inst = entries[i].target.__fxPlate
          if (inst) inst.inView = entries[i].isIntersecting
        }
      },
      { rootMargin: '20% 0px 20% 0px', threshold: 0 }
    )
  }

  offResize = stage.onResize(function () {
    registry.forEach(syncCaptionWidth)
  })

  // The stage lerps its pointer up from 0,0 toward the real cursor over the
  // first frames, which reads as a shove on the hero. The depth waits for a
  // pointer that genuinely exists; until then the scroll drives it.
  onFirstMove = function () {
    pointerSeen = true
    window.removeEventListener('mousemove', onFirstMove)
    onFirstMove = null
  }
  window.addEventListener('mousemove', onFirstMove, {
    passive: true,
    once: true,
  })

  // The literal failure mode: an image with no naturalWidth at init is not
  // measured at zero, it is deferred to load. Arming needs nothing here — the
  // gate is polled every frame, so the instance arms itself the moment the
  // pixels land. Captions do: their width is measured off a photograph that
  // may have had none yet, and an unloaded one measures as in-column.
  onWinLoad = function () {
    onWinLoad = null
    registry.forEach(syncCaptionWidth)
  }
  window.addEventListener('load', onWinLoad, { once: true })

  offFrame = stage.register(tick)
}

function teardownShared() {
  if (registry.size) return
  if (offFrame) offFrame()
  if (offResize) offResize()
  if (io) io.disconnect()
  if (onWinLoad) window.removeEventListener('load', onWinLoad)
  if (onFirstMove) window.removeEventListener('mousemove', onFirstMove)
  if (gyro.onTouch) window.removeEventListener('touchstart', gyro.onTouch, true)
  if (gyro.bound) window.removeEventListener('deviceorientation', gyro.onOrient)
  offFrame = offResize = io = onWinLoad = onFirstMove = null
  gyro.bound = false
  gyro.wanted = false
  gyro.gain = 0
  gyro.rest = null
  gyro.onOrient = null
  gyro.onTouch = null
  stage = null
  lastReduced = null
  pointerSeen = false
  if (styleEl && styleEl.parentNode) styleEl.parentNode.removeChild(styleEl)
  styleEl = null
}

/* ── public ──────────────────────────────────────────────────────────────── */

export function initPlate(target, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})
  const skipped = []
  const mine = []

  if (typeof document === 'undefined') {
    return { plates: 0, skipped: skipped, destroy: function () {} }
  }

  injectCSS()

  const els = toElements(
    target || '.hero__media, .seam, .tile, .arch, [data-fx-plate-target]'
  )
  const coarse =
    typeof matchMedia === 'function'
      ? matchMedia('(hover: none) and (pointer: coarse)')
      : null

  els.forEach(function (el, i) {
    const parts = resolve(el)
    if (!parts) {
      skipped.push(el)
      return
    }
    // Never adopt the same photograph twice, whoever asked.
    if (
      parts.media.some(function (m) {
        return m.__fxPlate
      })
    ) {
      return
    }

    const isDepth =
      cfg.depth === true
        ? true
        : cfg.depth === false
          ? false
          : parts.anchor.hasAttribute('data-fx-plate-depth') ||
            !!parts.anchor.closest('.hero')

    const dark =
      cfg.tone === 'dark'
        ? true
        : cfg.tone === 'light'
          ? false
          : !!parts.anchor.closest('.band--night, .hero')

    const inst = {
      anchor: parts.anchor,
      media: parts.media,
      cfg: cfg,
      role: isDepth ? 'depth' : 'reveal',
      dark: dark,
      // No pointer effects on a phone; ≤3° gyro on the hero plate only.
      pointer: isDepth && !(coarse && coarse.matches),
      gyro: isDepth && !!(coarse && coarse.matches) && cfg.gyro > 0,
      inView: true,
      on: false,
      live: false,
      ok: false,
      failed: false,
      cap: null,
      top: 0,
      h: 0,
      wd: 0,
      w: {}, // last written values, by key
      pending: null,
    }

    parts.media.forEach(function (m) {
      m.setAttribute(ATTR, '')
      m.__fxPlate = inst
    })

    const text = captionFor(cfg, el, parts.anchor, i)
    if (text) mountCaption(inst, text)

    // Deferred measurement. Until every image reports a naturalWidth the
    // instance stays at the CSS default — a composed photograph — and arms
    // itself once loaded rather than measuring a plate around nothing. A
    // lazy-loaded plate can therefore skip its entrance entirely, which is the
    // correct direction to fail in.
    if (!mediaReady(inst)) {
      inst.pending = []
      inst.media.forEach(function (m) {
        if (m.tagName !== 'IMG') return
        if (m.complete && m.naturalWidth > 0) return
        const onErr = function () {
          inst.failed = true // a photograph that never arrives gets no motion
        }
        // A lazy plate can load long after `window.load`, and a caption whose
        // width was measured against an image of zero width keeps the in-column
        // treatment on a full-bleed photograph forever. Re-measure on arrival.
        const onLoad = function () {
          syncCaptionWidth(inst)
        }
        m.addEventListener('error', onErr, { once: true })
        m.addEventListener('load', onLoad, { once: true })
        inst.pending.push([m, 'error', onErr], [m, 'load', onLoad])
      })
    }

    if (inst.gyro) gyro.wanted = true
    registry.add(inst)
    mine.push(inst)
  })

  if (mine.length) {
    ensureShared()
    if (io) {
      mine.forEach(function (inst) {
        io.observe(inst.media[0])
      })
    }
    if (gyro.wanted) armGyroOnFirstTouch()
  }

  return {
    plates: mine.length,
    skipped: skipped,
    destroy: function () {
      mine.forEach(function (inst) {
        disarm(inst)
        if (io) io.unobserve(inst.media[0])
        if (inst.pending) {
          inst.pending.forEach(function (p) {
            p[0].removeEventListener(p[1], p[2])
          })
        }
        inst.media.forEach(function (m) {
          m.removeAttribute(ATTR)
          m.removeAttribute(ATTR_ROLE)
          delete m.__fxPlate
        })
        if (!inst.anchor.getAttribute('style')) {
          inst.anchor.removeAttribute('style')
        }
        if (inst.cap && inst.cap.parentNode) {
          inst.cap.parentNode.removeChild(inst.cap)
        }
        registry.delete(inst)
      })
      mine.length = 0
      teardownShared()
    },
  }
}
