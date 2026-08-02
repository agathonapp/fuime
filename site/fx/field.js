/* fx/field.js — the conversion surface.
 *
 * The two things a visitor actually does on this site are type an email into
 * `.capture` and read what it costs. Everything else on the page is persuasion.
 * This module is the only one that touches those controls, and it is deliberately
 * the most conservative module in the build:
 *
 *   • focus-visible rings on both capture forms — `.capture input` ships
 *     `outline: none` with no replacement, which is a WCAG 2.4.7 failure before
 *     it is a craft gap;
 *   • 44x44 hit areas on the mobile form;
 *   • a 0.97 press scale on the CTAs, 120ms;
 *   • <=5px of magnetic pull on the primary CTA and the waitlist submit, and
 *     nothing else on this site is magnetic;
 *   • <=300ms error and success choreography, driven off the attributes site.js
 *     already writes, never off its internals.
 *
 * The three magnetic-cursor overrides are not preferences. `hideNativeCursor`
 * is false because the email input needs its I-beam. `blend` is false because a
 * difference-blend ring inverting across the cream/night band boundary looks
 * broken. `maxPull` is 5 because past that the target physically moves away from
 * the cursor of a 45-year-old parent, which is a measurable conversion loss. All
 * three are clamped in code, so passing `blend: true` in config does nothing.
 *
 * Motion is opt-in, never opt-out. Every animated rule is scoped under
 * `[data-fx-field~='motion']`, an attribute this module sets on the root only
 * after it has confirmed `stage.reducedMotion === false` and bound its trigger.
 * A JS error, a print stylesheet or a text-mode reader gets the full static
 * design with working focus rings, because the rings are not gated on motion —
 * focus indication is accessibility, not decoration, and is never removed.
 *
 * Failure mode. Magnet bounds are measured at init, so a layout shift that never
 * calls `recalc()` leaves the magnet pulling toward a stale rect. That is why
 * the 5px cap exists as much as for the conversion argument: the worst case is a
 * 5px error nobody perceives, on an element that is still exactly where the
 * pointer sees it. Three cheap defences narrow it further — resize and
 * `fuime:fee` both trigger a recalc, and an engaged magnet re-measures its own
 * rect at most twice a second — but none of them is load-bearing. The cap is.
 *
 * One case the cap does NOT cover, so it is handled instead of tolerated: `.nav`
 * is `position: fixed` and the primary CTA is inside it. A fixed element's rect
 * never moves with the document, so caching it in document space bakes in the
 * scroll offset at measure time and the influence zone walks off the top of the
 * screen as the visitor scrolls. Each magnet therefore records its own
 * coordinate space and the pointer is converted per element. See probeFixed.
 */

import { getStage } from 'cwe/stage'

const NAME = 'field'
const ROOT_ATTR = 'data-fx-field'
const MAGNET_ATTR = 'data-fx-field-magnet'
const STATE_ATTR = 'data-fx-field-state'
const STYLE_SELECTOR = 'style[data-fx="' + NAME + '"]'

const DEFAULTS = {
  /* The selector the orchestrator marks up. See the integration note at the
     bottom of this file: `data-magnetic` does not exist in the HTML yet. */
  magnetSelector: '[data-magnetic]',
  /* Used only when magnetSelector matches nothing, so the module is useful the
     day it lands rather than the day the attribute does. This list is exactly
     the two elements the spec allows to be magnetic. */
  magnetFallbackSelector:
    '.nav__links .btn--accent, form.capture button[type="submit"]',

  magnetStrength: 0.28, // hard cap 0.3
  magnetRadius: 80,
  maxPull: 5, // hard cap 5, in px
  hideNativeCursor: false, // forced false
  blend: false, // forced false
  hoverScale: 1.02, // hard cap 1.3
  pressScale: 0.97,
  pressMs: 120,

  focusMs: 120,
  errorMs: 220,
  successMs: 240,

  captureSelector: 'form.capture',
  ringWidth: 2,
  ringOffset: 3,

  /* An engaged magnet re-reads its own rect no more often than this. Two
     getBoundingClientRect calls a second, only while the pointer is inside the
     influence zone, only on two elements. */
  rectMaxAgeMs: 500,
  followLerp: 12, // per-second approach rate

  feeEvent: 'fuime:fee',
  recalcOnFee: true,
}

/* Nothing below may exceed these, whatever config says. */
const CAP = {
  magnetStrength: 0.3,
  maxPull: 5,
  hoverScale: 1.3,
  uiMs: 300, // house constraint 9
  reducedMs: 120,
}

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v
}

/* `Number(null)`, `Number('')`, `Number([])` and `Number(false)` are all 0, and
   0 is finite, so the naive version quietly turns a null config value into a
   zero rather than into the default: `maxPull: null` would disable the magnet,
   `ringWidth: null` would erase the focus ring. An explicit 0 still passes
   through, because `maxPull: 0` is a real instruction. */
function num(v, fallback) {
  if (v === null || v === undefined || v === '' || typeof v === 'boolean') {
    return fallback
  }
  const n = Number(v)
  return Number.isFinite(n) ? n : fallback
}

/* Safari did not get MediaQueryList.addEventListener until 14. On anything
   older the bare call throws, and a throw here would abort init after the root
   attribute is already set — rings and hit areas would survive, but press
   feedback, the magnet and the capture choreography would never bind and the
   caller would never receive a handle to destroy. Returns an unsubscribe. */
function bindMQ(mq, fn) {
  const noop = function () {}
  if (!mq) return noop
  if (typeof mq.addEventListener === 'function') {
    mq.addEventListener('change', fn)
    return function () {
      mq.removeEventListener('change', fn)
    }
  }
  if (typeof mq.addListener === 'function') {
    mq.addListener(fn)
    return function () {
      mq.removeListener(fn)
    }
  }
  return noop
}

/* Colours come from :root at init and never from a literal. A missing token
   resolves to a keyword, never to a hex, so a stripped stylesheet degrades to a
   currentColor ring rather than to no ring at all. */
function readTokens() {
  const cs = getComputedStyle(document.documentElement)
  const get = function (prop, fallback) {
    let v = ''
    try {
      v = cs.getPropertyValue(prop).trim()
    } catch (e) {
      v = ''
    }
    return v || fallback
  }
  return {
    ring: get('--accent', 'currentColor'),
    ringLit: get('--accent-lit', 'currentColor'),
    ringOnFill: get('--paper', 'currentColor'),
    ease: get('--ease', 'ease'),
  }
}

function css() {
  return `
/* fx/field — scoped under [data-fx-field]. Values arrive as --fx-field-*
   custom properties written onto the root at init from :root tokens. */

/* ── focus: never gated on motion ──────────────────────────────────────── */

[${ROOT_ATTR}] .capture input:focus-visible {
  outline: var(--fx-field-ring-w) solid var(--fx-field-ring);
  outline-offset: 2px;
}

/* Nothing here may touch border-radius. An outline already follows the
   element's own corners, and .btn is a 999px pill — setting a radius in a
   :focus-visible rule squares off every CTA the moment it is tabbed to. */
[${ROOT_ATTR}] .btn:focus-visible,
[${ROOT_ATTR}] .tlink:focus-visible,
[${ROOT_ATTR}] .nav__link:focus-visible,
[${ROOT_ATTR}] .nav__burger:focus-visible,
[${ROOT_ATTR}] .mark:focus-visible {
  outline: var(--fx-field-ring-w) solid var(--fx-field-ring);
  outline-offset: var(--fx-field-ring-off);
}
/* The burger is the one control with square corners and no radius of its own. */
[${ROOT_ATTR}] .nav__burger:focus-visible {
  border-radius: var(--r, 4px);
}

/* The accent button carries its own fill, so the ring goes inside it in paper.
   That reads at full contrast on cream and on night without an outline
   spilling past the pill and over a band edge. */
[${ROOT_ATTR}] .btn--accent:focus-visible {
  outline: var(--fx-field-ring-w) solid var(--fx-field-ring-on-fill);
  outline-offset: -3px;
}

/* Dark surfaces take the lit accent; the capture row is always paper, so it
   takes the base accent back. Both inherit, so one declaration each. */
[${ROOT_ATTR}] .band--night,
[${ROOT_ATTR}] .portal__in,
[${ROOT_ATTR}] .nav--over {
  --fx-field-ring: var(--fx-field-ring-lit);
}
[${ROOT_ATTR}] .capture__row {
  --fx-field-ring: var(--fx-field-ring-base);
  transition: box-shadow var(--fx-field-focus-ms) var(--fx-field-ease);
}

/* Browsers without :focus-visible fall back to :focus rather than to nothing. */
@supports not selector(:focus-visible) {
  [${ROOT_ATTR}] .capture input:focus,
  [${ROOT_ATTR}] .btn:focus,
  [${ROOT_ATTR}] .nav__link:focus {
    outline: var(--fx-field-ring-w) solid var(--fx-field-ring);
    outline-offset: var(--fx-field-ring-off);
  }
}

/* ── hit areas: never gated on motion ──────────────────────────────────── */

@media (max-width: 720px), (pointer: coarse) {
  [${ROOT_ATTR}] .capture input,
  [${ROOT_ATTR}] .capture .btn {
    min-height: 44px;
  }
  [${ROOT_ATTR}] .capture a {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
  }
  /* 20px of bar in 12px of padding is a 44x38.5 target. Padding, not display,
     so the nav's own layout rules stay where they are. */
  [${ROOT_ATTR}] .nav__burger {
    padding: var(--s4, 16px) var(--s3, 12px);
  }
}

/* ── press + magnet: gated on motion ───────────────────────────────────── */

[${ROOT_ATTR}~='motion'] .btn {
  transition: scale var(--fx-field-press-ms) var(--fx-field-ease);
}
[${ROOT_ATTR}~='motion'] [${MAGNET_ATTR}] {
  will-change: translate;
}
[${ROOT_ATTR}~='motion'] [${MAGNET_ATTR}]:hover {
  scale: var(--fx-field-hover);
}
[${ROOT_ATTR}~='motion'] .btn:active,
[${ROOT_ATTR}~='motion'] [${MAGNET_ATTR}]:active {
  scale: var(--fx-field-press);
}
[${ROOT_ATTR}~='motion'] .btn[disabled],
[${ROOT_ATTR}~='motion'] .btn[disabled]:active {
  scale: 1;
}

/* ── capture choreography: gated on motion, <=300ms ────────────────────── */

@keyframes fx-field-nudge {
  0% {
    translate: 0;
  }
  28% {
    translate: -4px;
  }
  58% {
    translate: 3px;
  }
  82% {
    translate: -1px;
  }
  100% {
    translate: 0;
  }
}
@keyframes fx-field-settle {
  from {
    opacity: 0;
    translate: 0 6px;
  }
  to {
    opacity: 1;
    translate: 0 0;
  }
}
@keyframes fx-field-say {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

[${ROOT_ATTR}~='motion'] .capture[${STATE_ATTR}='error'] .capture__row {
  animation: fx-field-nudge var(--fx-field-error-ms) var(--fx-field-ease) both;
}
[${ROOT_ATTR}~='motion'] .capture[${STATE_ATTR}='done'] .capture__done {
  animation: fx-field-settle var(--fx-field-success-ms) var(--fx-field-ease)
    both;
}
/* The message itself fades in at focus speed under any motion setting: it is a
   live region announcing a validation result, not decoration. */
[${ROOT_ATTR}] .capture[${STATE_ATTR}='error'] .capture__msg,
[${ROOT_ATTR}] .capture[${STATE_ATTR}='sent'] .capture__msg {
  animation: fx-field-say var(--fx-field-focus-ms) var(--fx-field-ease) both;
}
`
}

function injectStyle() {
  let tag = document.head.querySelector(STYLE_SELECTOR)
  if (tag) return tag
  tag = document.createElement('style')
  tag.setAttribute('data-fx', NAME)
  tag.textContent = css()
  document.head.appendChild(tag)
  return tag
}

export function initField(target, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})

  /* The three overrides are enforced here, not trusted from config. */
  const overrides = {
    hideNativeCursor: false,
    blend: false,
    maxPull: clamp(num(cfg.maxPull, DEFAULTS.maxPull), 0, CAP.maxPull),
  }
  cfg.hideNativeCursor = false
  cfg.blend = false
  cfg.maxPull = overrides.maxPull
  cfg.magnetStrength = clamp(
    num(cfg.magnetStrength, DEFAULTS.magnetStrength),
    0,
    CAP.magnetStrength
  )
  cfg.hoverScale = clamp(
    num(cfg.hoverScale, DEFAULTS.hoverScale),
    1,
    CAP.hoverScale
  )
  cfg.magnetRadius = Math.max(0, num(cfg.magnetRadius, DEFAULTS.magnetRadius))
  cfg.pressScale = clamp(num(cfg.pressScale, DEFAULTS.pressScale), 0.9, 1)
  cfg.pressMs = clamp(num(cfg.pressMs, DEFAULTS.pressMs), 0, CAP.uiMs)
  cfg.focusMs = clamp(num(cfg.focusMs, DEFAULTS.focusMs), 0, CAP.reducedMs)
  cfg.errorMs = clamp(num(cfg.errorMs, DEFAULTS.errorMs), 0, CAP.uiMs)
  cfg.successMs = clamp(num(cfg.successMs, DEFAULTS.successMs), 0, CAP.uiMs)

  /* These two are concatenated straight into an `outline` declaration. A junk
     value there is not a cosmetic bug: the whole declaration is dropped, the
     ring disappears, and the module has reintroduced the exact WCAG 2.4.7
     failure it exists to fix. The floor is 1px, never 0. */
  cfg.ringWidth = clamp(num(cfg.ringWidth, DEFAULTS.ringWidth), 1, 6)
  cfg.ringOffset = clamp(num(cfg.ringOffset, DEFAULTS.ringOffset), 0, 8)

  /* NaN in followLerp poisons every magnet coordinate, and `translate: NaNpx`
     never equals its own cached value, so the module would rewrite an invalid
     inline style every single frame for the life of the page. */
  cfg.followLerp = clamp(num(cfg.followLerp, DEFAULTS.followLerp), 1, 60)
  cfg.rectMaxAgeMs = clamp(
    num(cfg.rectMaxAgeMs, DEFAULTS.rectMaxAgeMs),
    100,
    5000
  )

  const root =
    (typeof target === 'string' ? document.querySelector(target) : target) ||
    document.body

  /* SSR / no document / detached root: hand back an inert handle rather than
     throwing into the boot script's try/catch and losing the rest of the page. */
  if (!root || typeof document === 'undefined') {
    return {
      recalc: function () {},
      destroy: function () {},
      inert: true,
    }
  }

  const stage = getStage()
  const tokens = readTokens()
  injectStyle()

  /* ── custom properties, written from :root tokens, no literals ───────── */

  root.style.setProperty('--fx-field-ring-base', tokens.ring)
  root.style.setProperty('--fx-field-ring-lit', tokens.ringLit)
  root.style.setProperty('--fx-field-ring-on-fill', tokens.ringOnFill)
  root.style.setProperty('--fx-field-ring', tokens.ring)
  root.style.setProperty('--fx-field-ease', tokens.ease)
  root.style.setProperty('--fx-field-ring-w', cfg.ringWidth + 'px')
  root.style.setProperty('--fx-field-ring-off', cfg.ringOffset + 'px')
  root.style.setProperty('--fx-field-focus-ms', cfg.focusMs + 'ms')
  root.style.setProperty('--fx-field-press-ms', cfg.pressMs + 'ms')
  root.style.setProperty('--fx-field-error-ms', cfg.errorMs + 'ms')
  root.style.setProperty('--fx-field-success-ms', cfg.successMs + 'ms')
  root.style.setProperty('--fx-field-press', String(cfg.pressScale))
  root.style.setProperty('--fx-field-hover', String(cfg.hoverScale))

  /* Called through `window` on purpose: a detached `matchMedia` reference is an
     illegal invocation in a module's strict-mode scope. */
  function mq(query) {
    if (typeof window === 'undefined' || !window.matchMedia) return null
    try {
      return window.matchMedia(query)
    } catch (e) {
      return null
    }
  }
  const coarseQ = mq('(hover: none) and (pointer: coarse)')
  const reducedQ = mq('(prefers-reduced-motion: reduce)')

  function motionOK() {
    return !stage.reducedMotion && !(reducedQ && reducedQ.matches)
  }

  /* Rings and hit areas mount immediately. The motion token is added only once
     everything below has bound, so a throw between here and the end of init
     leaves the page in its correct static state. */
  root.setAttribute(ROOT_ATTR, 'on')

  /* ── magnet ──────────────────────────────────────────────────────────── */

  let magnets = []
  let offFrame = null
  let offResize = null
  let usedFallback = false

  /* stage.pointer starts at 0,0 and lerps to the viewport centre on the first
     frames, so a magnet sitting near the middle of a narrow window would hold a
     few pixels of pull before the visitor has touched the mouse. Nothing moves
     until a real move event has happened. This is one boolean, not a second
     input pipeline — every coordinate still comes from the stage. */
  let pointerSeen = false
  function onFirstMove() {
    pointerSeen = true
    window.removeEventListener('mousemove', onFirstMove)
  }
  window.addEventListener('mousemove', onFirstMove, { passive: true })

  function collect() {
    let list = []
    try {
      list = Array.prototype.slice.call(
        root.querySelectorAll(cfg.magnetSelector)
      )
    } catch (e) {
      list = []
    }
    if (!list.length && cfg.magnetFallbackSelector) {
      try {
        list = Array.prototype.slice.call(
          root.querySelectorAll(cfg.magnetFallbackSelector)
        )
        usedFallback = list.length > 0
      } catch (e) {
        list = []
      }
    }
    return list
  }

  /* `.nav` is `position: fixed`, and the primary CTA lives inside it. A fixed
     element does not move with the document, so its rect is already in viewport
     space and must stay there. Caching it in document space — rect + scroll —
     freezes the scroll value at measure time, and from then on the influence
     zone slides up the screen by exactly the distance scrolled: past about
     120px the nav CTA stops pulling entirely and the live zone sits off the top
     of the viewport. recalc() on resize and on `fuime:fee` would not fix it,
     because neither fires on scroll. So each magnet records which space it
     belongs to and the pointer is converted per element. */
  function probeFixed(el) {
    let n = el
    while (n && n.nodeType === 1) {
      let pos = ''
      try {
        pos = getComputedStyle(n).position
      } catch (e) {
        pos = ''
      }
      if (pos === 'fixed') return true
      n = n.parentElement
    }
    return false
  }

  function measure(m) {
    const b = m.el.getBoundingClientRect()
    const sx = m.fixed ? 0 : window.scrollX || 0
    const sy = m.fixed ? 0 : (stage.scroll && stage.scroll.y) || 0
    /* Subtract whatever offset is currently applied, so the cached centre is
       the element's resting centre and the magnet cannot chase itself. */
    m.w = b.width
    m.h = b.height
    m.cx = b.left + sx + b.width / 2 - m.wx
    m.cy = b.top + sy + b.height / 2 - m.wy
    m.measuredAt = performance.now()
  }

  function write(m) {
    const nx = Math.round(m.x * 10) / 10
    const ny = Math.round(m.y * 10) / 10
    if (nx === m.wx && ny === m.wy) return
    m.wx = nx
    m.wy = ny
    if (nx === 0 && ny === 0) m.el.style.removeProperty('translate')
    else m.el.style.translate = nx + 'px ' + ny + 'px'
  }

  function frame(dt) {
    if (!magnets.length) return
    const p = stage.pointer
    if (!p) return
    if (!pointerSeen) return
    const sx = window.scrollX || 0
    const sy = (stage.scroll && stage.scroll.y) || 0
    const now = performance.now()
    const k = clamp(num(dt, 0.016) * cfg.followLerp, 0, 1)

    for (let i = magnets.length - 1; i >= 0; i--) {
      const m = magnets[i]
      if (!m.el.isConnected) {
        m.el.removeAttribute(MAGNET_ATTR)
        magnets.splice(i, 1)
        continue
      }

      /* Whatever space this element's centre was cached in. */
      const px = p.x + (m.fixed ? 0 : sx)
      const py = p.y + (m.fixed ? 0 : sy)

      let tx = 0
      let ty = 0

      if (m.w > 0 && m.h > 0) {
        let dx = px - m.cx
        let dy = py - m.cy
        let lx = m.w / 2 + cfg.magnetRadius
        let ly = m.h / 2 + cfg.magnetRadius

        if (Math.abs(dx) <= lx && Math.abs(dy) <= ly) {
          /* Engaged. This is the only place a rect is re-read outside recalc,
             and it is throttled: worst case two reads a second on two
             elements, and only while the pointer is already on top of them. */
          if (now - m.measuredAt > cfg.rectMaxAgeMs) {
            measure(m)
            dx = px - m.cx
            dy = py - m.cy
            lx = m.w / 2 + cfg.magnetRadius
            ly = m.h / 2 + cfg.magnetRadius
          }
          if (m.w > 0 && m.h > 0 && Math.abs(dx) <= lx && Math.abs(dy) <= ly) {
            const fall = 1 - Math.max(Math.abs(dx) / lx, Math.abs(dy) / ly)
            tx = clamp(
              dx * cfg.magnetStrength * fall,
              -cfg.maxPull,
              cfg.maxPull
            )
            ty = clamp(
              dy * cfg.magnetStrength * fall,
              -cfg.maxPull,
              cfg.maxPull
            )
          }
        }
      }

      m.x += (tx - m.x) * k
      m.y += (ty - m.y) * k
      if (tx === 0 && Math.abs(m.x) < 0.05) m.x = 0
      if (ty === 0 && Math.abs(m.y) < 0.05) m.y = 0
      write(m)
    }
  }

  function unmountMagnets() {
    if (offFrame) {
      offFrame()
      offFrame = null
    }
    if (offResize) {
      offResize()
      offResize = null
    }
    for (const m of magnets) {
      m.el.style.removeProperty('translate')
      m.el.removeAttribute(MAGNET_ATTR)
    }
    magnets = []
  }

  function mountMagnets() {
    unmountMagnets()
    /* No magnet under reduced motion, and none on a coarse pointer — there is
       no cursor for it to answer to. Hit areas, focus rings and press feedback
       all still mount; this is the only thing a phone loses. */
    if (!motionOK() || (coarseQ && coarseQ.matches) || cfg.maxPull <= 0) return

    const els = collect()
    magnets = els.map(function (el) {
      el.setAttribute(MAGNET_ATTR, '')
      const m = {
        el: el,
        x: 0,
        y: 0,
        wx: 0,
        wy: 0,
        w: 0,
        h: 0,
        cx: 0,
        cy: 0,
        measuredAt: 0,
        fixed: false,
      }
      m.fixed = probeFixed(el)
      measure(m)
      return m
    })
    if (!magnets.length) return
    offFrame = stage.register(frame)
    offResize = stage.onResize(function () {
      recalc()
    })
  }

  /* Public. Called by the orchestrator after the console re-renders and after
     the mobile drawer opens or closes. Cheap enough to call freely. */
  function recalc() {
    for (const m of magnets) {
      if (m.el.isConnected) {
        /* Re-probed here, not cached forever: a breakpoint can drop the nav out
           of `position: fixed`, and resize is one of recalc's callers. */
        m.fixed = probeFixed(m.el)
        measure(m)
      }
    }
  }

  /* ── capture choreography ────────────────────────────────────────────── */

  /* site.js owns the form. It writes data-state on .capture__msg and data-done
     on the form, and this module reads nothing else from it — no fee values, no
     internals, no re-implemented validation. If the observer never fires the
     page still renders and behaves exactly as it does today, one animation
     poorer. That is the whole point of driving this off published attributes. */

  const captures = []

  function flash(form, kind, ms) {
    const rec = captures.find(function (c) {
      return c.form === form
    })
    if (!rec) return
    if (rec.timer) clearTimeout(rec.timer)
    if (form.getAttribute(STATE_ATTR)) {
      form.removeAttribute(STATE_ATTR)
      /* One forced reflow per submit attempt, so a second identical error
         re-runs the nudge instead of sitting there silently. */
      void form.offsetWidth
    }
    form.setAttribute(STATE_ATTR, kind)
    rec.timer = setTimeout(function () {
      rec.timer = 0
      form.removeAttribute(STATE_ATTR)
    }, ms + 40)
  }

  function bindCaptures() {
    let forms = []
    try {
      forms = Array.prototype.slice.call(
        root.querySelectorAll(cfg.captureSelector)
      )
    } catch (e) {
      forms = []
    }
    if (typeof MutationObserver === 'undefined') return

    forms.forEach(function (form) {
      const msg = form.querySelector('.capture__msg')
      const rec = { form: form, obs: null, timer: 0 }
      captures.push(rec)

      rec.obs = new MutationObserver(function (records) {
        for (const r of records) {
          if (r.target === form && r.attributeName === 'data-done') {
            if (form.getAttribute('data-done') === 'true')
              flash(form, 'done', cfg.successMs)
          } else if (r.attributeName === 'data-state') {
            const state = r.target.getAttribute('data-state')
            if (state === 'error') flash(form, 'error', cfg.errorMs)
            else if (state === 'ok') flash(form, 'sent', cfg.focusMs)
          }
        }
      })
      rec.obs.observe(form, {
        attributes: true,
        attributeFilter: ['data-done'],
      })
      if (msg) {
        rec.obs.observe(msg, {
          attributes: true,
          attributeFilter: ['data-state'],
        })
      }
    })
  }

  /* ── iOS :active ──────────────────────────────────────────────────────── */

  /* Safari on iOS withholds :active from anchors unless something on the page
     listens for touch. The hero CTA is an <a class="btn">, and press feedback
     is the confirmation a thumb needs, so this stays. No markup, no cost. */
  function noop() {}
  document.addEventListener('touchstart', noop, { passive: true })

  /* ── layout-shift hooks ──────────────────────────────────────────────── */

  function onFee() {
    recalc()
  }
  if (cfg.recalcOnFee) document.addEventListener(cfg.feeEvent, onFee)

  function onMotionChange() {
    applyMotion()
  }
  const offReducedQ = bindMQ(reducedQ, onMotionChange)
  const offCoarseQ = bindMQ(coarseQ, onMotionChange)

  function applyMotion() {
    if (motionOK()) {
      root.setAttribute(ROOT_ATTR, 'on motion')
      mountMagnets()
    } else {
      unmountMagnets()
      root.setAttribute(ROOT_ATTR, 'on')
    }
  }

  bindCaptures()
  applyMotion()

  /* Webfont swap resizes every pill on the page. One free recalc. */
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready
      .then(function () {
        recalc()
      })
      .catch(function () {})
  }

  return {
    recalc: recalc,
    destroy: function () {
      unmountMagnets()
      window.removeEventListener('mousemove', onFirstMove)
      offReducedQ()
      offCoarseQ()
      document.removeEventListener(cfg.feeEvent, onFee)
      document.removeEventListener('touchstart', noop)
      captures.forEach(function (rec) {
        if (rec.obs) rec.obs.disconnect()
        if (rec.timer) clearTimeout(rec.timer)
        rec.form.removeAttribute(STATE_ATTR)
      })
      captures.length = 0
      root.removeAttribute(ROOT_ATTR)
      ;[
        '--fx-field-ring-base',
        '--fx-field-ring-lit',
        '--fx-field-ring-on-fill',
        '--fx-field-ring',
        '--fx-field-ease',
        '--fx-field-ring-w',
        '--fx-field-ring-off',
        '--fx-field-focus-ms',
        '--fx-field-press-ms',
        '--fx-field-error-ms',
        '--fx-field-success-ms',
        '--fx-field-press',
        '--fx-field-hover',
      ].forEach(function (p) {
        root.style.removeProperty(p)
      })
    },
    /* Diagnostics for the orchestrator's verification pass. */
    get magnetCount() {
      return magnets.length
    },
    get usedFallbackSelector() {
      return usedFallback
    },
    overrides: overrides,
  }
}
