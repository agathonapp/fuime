/* fx/arch.js — the arch draws as you arrive at it.
 *
 * One animated property on one element: `border-radius` goes from `var(--r)`
 * to `9999px 9999px var(--r) var(--r)`, scroll-coupled, finished before the
 * band it lives in reaches viewport centre so it is never mid-draw while you
 * are reading the form inside it.
 *
 * Why border-radius and not a stroked SVG path: the browser clamps a radius
 * larger than the box to half the box width, so the finished arch is a true
 * semicircle on straight legs at any size, with no `d` attribute to regenerate
 * on resize and no JS holding it up. The finished arch is what the CSS says by
 * default — this module only ever writes an intermediate, and only after it has
 * confirmed motion is allowed and it has actually measured the band. Every path
 * that fails, throws, prints, or reads the page without scrolling gets the
 * finished arch.
 *
 * This module reads nothing from the DOM but geometry, subscribes to no fee
 * event, and owns no rAF loop of its own.
 */

import { getStage } from 'cwe/stage'

const NAME = 'arch'
const ATTR = 'data-fx-arch'
const DRAWING = 'data-fx-arch-drawing'
const PROP = '--fx-arch-r'
const PROP_TO = '--fx-arch-to'

const DEFAULTS = {
  // The two endpoints, as CSS values. They are resolved against the element
  // itself at init, so `var(--r)` — or anything else a token names — works.
  from: 'var(--r)',
  to: '9999px 9999px var(--r) var(--r)',
  // Normalized band progress at which the draw must be finished. 0.5 is the
  // moment the band's centre meets the viewport's centre.
  completeAt: 0.5,
  // Which elements are archways, and which ancestor's travel drives them.
  selector: '.portal__media, .arch',
  bandSelector: '.band',
}

/* The finished arch is the default value here too, so a stylesheet that lands
   before the module has set --fx-arch-to still renders the brand shape rather
   than a rectangle. Reduced motion and print ignore the animated property
   outright: no amount of JS already written can hold them mid-draw. */
const CSS = `
[${ATTR}] {
  border-radius: var(${PROP}, var(${PROP_TO}, 9999px 9999px var(--r) var(--r)));
}
[${ATTR}][${DRAWING}] {
  will-change: border-radius;
}
@media (prefers-reduced-motion: reduce) {
  [${ATTR}] {
    border-radius: var(${PROP_TO}, 9999px 9999px var(--r) var(--r));
  }
}
@media print {
  [${ATTR}] {
    border-radius: var(${PROP_TO}, 9999px 9999px var(--r) var(--r));
  }
}
`

function injectCSS() {
  if (typeof document === 'undefined') return
  if (document.querySelector('style[data-fx="' + NAME + '"]')) return
  const style = document.createElement('style')
  style.setAttribute('data-fx', NAME)
  style.textContent = CSS
  document.head.appendChild(style)
}

function clamp01(n) {
  return n < 0 ? 0 : n > 1 ? 1 : n
}

/* Smoothstep, not ease-out. The arch enters from the bottom of the screen, so
   an ease-out spends most of its travel on a shape that is still below the
   fold and arrives already finished. Easing in as well puts the fast part of
   the draw in the middle of the screen, where it is the thing you are looking
   at, and still settles rather than stopping. */
function ease(t) {
  return t * t * (3 - 2 * t)
}

/* Computed border-radius comes back in px, except when the author wrote a
   percentage, which stays a percentage. Resolve both against the box. Only the
   horizontal component is read: every radius this module writes is circular, so
   an elliptical author value is approximated by its horizontal half. */
function toPx(value, basis) {
  if (!value) return NaN
  const first = String(value).trim().split(/\s+/)[0]
  const n = parseFloat(first)
  if (!Number.isFinite(n)) return NaN
  return first.slice(-1) === '%' ? (n / 100) * basis : n
}

/* The browser does not render the radii you write. Per CSS Backgrounds §5.5 it
   finds the largest f ≤ 1 such that no pair of radii sharing a side outruns
   that side, then scales *every* corner by that single f. A 9999px top radius
   on a 620px box gives f ≈ 0.031 — which silently drags the 4px foot radius
   down to 0.12px as well.

   That is the trap in reading the computed value and clamping only the top to
   half the width: the foot then animates 4px → 4px and snaps to 0.12px the
   instant the module hands the element back to the stylesheet, and on any arch
   wider than twice its height the *top* is wrong too, because the height is
   what binds f, not the width. Resolve both endpoints to used values and the
   handover is invisible. Linear interpolation between two conforming pairs
   conforms — these are linear constraints — so nothing written here is ever
   rescaled underneath us. */
function usedRadii(top, foot, w, h) {
  if (!Number.isFinite(top) || !Number.isFinite(foot)) return null
  if (!(w > 0) || !(h > 0)) return null
  const a = top > 0 ? top : 0
  const b = foot > 0 ? foot : 0
  let f = 1
  if (a > 0) f = Math.min(f, w / (a + a)) // top edge
  if (b > 0) f = Math.min(f, w / (b + b)) // bottom edge
  if (a + b > 0) f = Math.min(f, h / (a + b)) // left and right edges
  if (!Number.isFinite(f) || f > 1) f = 1
  if (f < 0) f = 0
  return { top: a * f, foot: b * f }
}

function resolveTargets(target, selector) {
  if (typeof document === 'undefined') return []
  const all = root =>
    Array.prototype.slice.call(root.querySelectorAll(selector))
  if (!target) return all(document)
  if (typeof target === 'string') {
    return Array.prototype.slice.call(document.querySelectorAll(target))
  }
  if (target.nodeType === 9 || target.nodeType === 11) return all(target)
  if (target.nodeType === 1) {
    if (target.matches && target.matches(selector)) return [target]
    /* A container that happens to hold no archway is not itself an archway.
       Falling back to [target] here stamps this module's attribute — and with
       it a 9999px top radius — onto whatever section was handed in. Handing
       back nothing is the answer that cannot deface the page. */
    return all(target)
  }
  if (typeof target.length === 'number') {
    return Array.prototype.slice.call(target).filter(n => n && n.nodeType === 1)
  }
  return []
}

export function initArch(target, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})

  let completeAt = Number(cfg.completeAt)
  if (!Number.isFinite(completeAt) || completeAt <= 0 || completeAt > 1) {
    completeAt = DEFAULTS.completeAt
  }

  const stage = getStage()
  const els = resolveTargets(target, cfg.selector)

  injectCSS()

  /* The attribute hands the element to this module's stylesheet, so the value
     it will fall back to has to be in place first. If anything below throws,
     what is on screen is the finished arch. */
  const entries = els.map(function (el) {
    el.style.setProperty(PROP_TO, cfg.to)
    el.setAttribute(ATTR, '')
    return {
      el: el,
      band: (el.closest && el.closest(cfg.bandSelector)) || el,
      bandTop: 0,
      bandH: 0,
      topFrom: 0,
      topTo: 0,
      footFrom: 0,
      footTo: 0,
      ok: false,
      drawing: false,
      done: false,
      last: -1,
    }
  })

  /* ── geometry ───────────────────────────────────────────────────────── */

  /* Reads the band's travel and both radius endpoints in px. Returns false if
     the element has no layout yet — display:none, a detached node, a zero-height
     band — which is the failure mode: no measurement, no callback, finished arch. */
  function measure(entry) {
    const el = entry.el
    if (!el.isConnected) return false
    const bandRect = entry.band.getBoundingClientRect()
    const elRect = el.getBoundingClientRect()
    if (!(bandRect.height > 0) || !(elRect.width > 0) || !(elRect.height > 0)) {
      return false
    }

    entry.bandTop = bandRect.top + stage.scroll.y
    entry.bandH = bandRect.height

    const w = elRect.width
    const h = elRect.height
    const prev = el.style.getPropertyValue(PROP)
    /* Live object: each read below flushes style, so it reflects the write on
       the line above it. */
    const cs = getComputedStyle(el)

    el.style.setProperty(PROP, cfg.from)
    const from = usedRadii(
      toPx(cs.borderTopLeftRadius, w),
      toPx(cs.borderBottomLeftRadius, w),
      w,
      h
    )

    el.style.setProperty(PROP, cfg.to)
    const to = usedRadii(
      toPx(cs.borderTopLeftRadius, w),
      toPx(cs.borderBottomLeftRadius, w),
      w,
      h
    )

    if (prev) el.style.setProperty(PROP, prev)
    else el.style.removeProperty(PROP)

    if (!from || !to) return false

    entry.topFrom = from.top
    entry.topTo = to.top
    entry.footFrom = from.foot
    entry.footTo = to.foot
    entry.last = -1
    return true
  }

  function measureAll() {
    let any = false
    for (let i = 0; i < entries.length; i++) {
      const ok = measure(entries[i])
      entries[i].ok = ok
      if (!ok) complete(entries[i])
      any = any || ok
    }
    return any
  }

  /* ── render ─────────────────────────────────────────────────────────── */

  /* Idempotent on purpose. `completeAt` is 0.5, so an element is finished for
     the entire second half of its band's travel and for every frame of the rest
     of the page — and reduced motion finishes it for the whole session. Without
     the latch this is one CSSOM write per element per frame, forever, to remove
     a property that is already gone. */
  function complete(entry) {
    if (entry.done) return
    if (entry.drawing) {
      entry.el.removeAttribute(DRAWING)
      entry.drawing = false
    }
    entry.el.style.removeProperty(PROP)
    entry.last = -1
    entry.done = true
  }

  function draw(entry, drawn) {
    if (drawn >= 1) {
      complete(entry)
      return
    }
    const e = ease(drawn)
    const top = entry.topFrom + (entry.topTo - entry.topFrom) * e
    const foot = entry.footFrom + (entry.footTo - entry.footFrom) * e

    /* Within half a pixel of the finished arch there is nothing left to see,
       so hand the element back to the stylesheet now rather than clinging to
       an inline override and a will-change hint for the last few frames. */
    if (
      Math.abs(top - entry.topTo) <= 0.5 &&
      Math.abs(foot - entry.footTo) <= 0.5
    ) {
      complete(entry)
      return
    }

    // Half-pixel granularity: below that nothing on screen changes and the
    // write is a wasted style recalc on every frame of a long scroll.
    const key = Math.round(top * 2)
    if (key === entry.last) return
    entry.last = key
    entry.done = false

    const t = Math.round(top * 100) / 100
    const f = Math.round(foot * 100) / 100
    entry.el.style.setProperty(
      PROP,
      t + 'px ' + t + 'px ' + f + 'px ' + f + 'px'
    )
    if (!entry.drawing) {
      entry.el.setAttribute(DRAWING, '')
      entry.drawing = true
    }
  }

  /* 0 when the band's top edge is at the bottom of the viewport, 1 when its
     bottom edge has left the top. 0.5 is band centre on viewport centre. */
  function bandProgress(entry) {
    const vh = stage.viewport.h || 0
    const travel = vh + entry.bandH
    if (!(travel > 0)) return 1
    return clamp01((vh - (entry.bandTop - stage.scroll.y)) / travel)
  }

  /* ── bind ───────────────────────────────────────────────────────────── */

  let offFrame = null
  let offResize = null
  let ro = null
  let dirty = false
  let destroyed = false

  function markDirty() {
    dirty = true
  }

  function frame() {
    if (destroyed) return

    // Reduced motion can be switched on mid-session. When it is, the arch is
    // finished, immediately, and stays finished until it is switched off.
    if (stage.reducedMotion) {
      for (let i = 0; i < entries.length; i++) complete(entries[i])
      return
    }

    if (dirty) {
      dirty = false
      measureAll()
    }

    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      if (!entry.ok) continue
      draw(entry, clamp01(bandProgress(entry) / completeAt))
    }
  }

  // Measure once, synchronously, before deciding to animate anything. If the
  // band cannot be measured the callback is never registered at all.
  const measurable = entries.length > 0 && measureAll()

  if (measurable && !stage.reducedMotion && !stage.inert) {
    offFrame = stage.register(frame)
    offResize = stage.onResize(markDirty)

    /* A band's own height changes when a lazy image decodes; a band's *offset*
       changes when anything above it does, which on this site is most of the
       page. Watching the root element catches both — the document growing by a
       few thousand pixels after load is the normal case here, not the edge one.
       Cheaper and more honest than re-measuring every frame. */
    if (typeof ResizeObserver === 'function') {
      ro = new ResizeObserver(markDirty)
      ro.observe(document.documentElement)
      if (document.body) ro.observe(document.body)
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].ok) ro.observe(entries[i].band)
      }
    }

    // Paint the correct state on the first frame rather than one frame late.
    frame()
  } else {
    for (let i = 0; i < entries.length; i++) complete(entries[i])
  }

  return {
    elements: entries.map(function (entry) {
      return entry.el
    }),
    /** Re-read the band offsets — after a font swap, a filter, an accordion. */
    refresh: function () {
      if (destroyed) return
      markDirty()
    },
    destroy: function () {
      destroyed = true
      if (offFrame) offFrame()
      if (offResize) offResize()
      if (ro) ro.disconnect()
      offFrame = null
      offResize = null
      ro = null
      for (let i = 0; i < entries.length; i++) {
        const el = entries[i].el
        complete(entries[i])
        el.style.removeProperty(PROP_TO)
        el.removeAttribute(ATTR)
      }
    },
  }
}
