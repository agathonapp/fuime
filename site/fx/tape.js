/* fx/tape.js — depth.
 *
 * The running tape of trades, coupled to the reader's own scroll.
 *
 * Composed from `smooth-scroll-stage`, VELOCITY DOCTRINE ONLY. Lenis is
 * rejected outright: it takes ownership of the scrollbar and puts latency on
 * the one control the reader actually owns, and a parent scrolling fast on a
 * phone who feels the page lag behind their thumb has just been handed a reason
 * to doubt the product. So: native scroll, read through `stage.scroll.velocity`,
 * nothing written back to it.
 *
 * What it does. The marquee's base rate is exactly what ships today — the
 * duration is READ from the stylesheet at init rather than restated here, so
 * the two can never drift. On top of that base the rate is multiplied by
 * scroll velocity: scroll down and the tape runs with you up to `ceiling`,
 * scroll back up and it slows to `floor` (0.35×), never to a stop, then eases
 * back to 1× over `decayMs`. Attack is immediate and decay is slow, because the
 * reader's own hand should register instantly and the settle should not.
 *
 * It pauses under the pointer and when it is off-screen, and it costs nothing
 * while paused.
 *
 * How the rate is applied, and why not the obvious way. Rewriting
 * `animation-duration` every frame is the obvious way and it is wrong: a CSS
 * animation keeps its ELAPSED time across a duration change, so progress
 * (elapsed / duration) jumps, and the tape teleports sideways on every frame we
 * touch it. So the live driver is `Animation.playbackRate` off `getAnimations()`
 * — same animation, same phase, new speed, no jump. The custom property is
 * still declared and still set, because it is the module's published surface
 * and it is the fallback where the Web Animations API is missing; there it is
 * quantised to 250ms steps so the phase artefact is rare instead of constant.
 *
 * The accessibility fix it also carries. The strip's seamless loop needs its
 * contents twice, and the duplicate is decoration. Hiding the whole row from
 * assistive tech to achieve that — which is what the site did — takes the real
 * trade list out of the accessibility tree along with it. This module unhides
 * the source row and puts `aria-hidden` on the runtime duplicates instead,
 * whatever shape they arrive in (cloned items, or a cloned row), whenever they
 * arrive: at init, on the first frame, at DOMContentLoaded, and on any later
 * mutation. Every pass is idempotent and writes only on a real difference, so a
 * settled DOM produces no work and no observer feedback loop.
 *
 * The one causality exception in this build, disclosed. Recon D permits ambient
 * motion only in the photographic and environmental layer, and a marquee is not
 * that layer. It is taken anyway on three grounds: the base rate is unchanged
 * from what ships today, every departure from it is the reader's own scroll,
 * and a labelled tape of job types is nearer environment than UI. If review
 * disagrees, it degrades to a static wrapped list — which is already the
 * reduced-motion state, so the fallback is built and tested by construction.
 *
 * Failure modes, both built. No `.strip__row` anywhere in scope and the module
 * does not mount, injects no CSS and marks no DOM. A NaN velocity reading —
 * some engines produce one on the first frame — clamps to base instead of
 * propagating into `animation-duration`, where it would freeze the tape
 * mid-run.
 *
 * Reads nothing from site.js, nothing from the DOM's fee figures, and holds no
 * opinion about the ledger. It subscribes to `stage` and to nothing else.
 */

import { getStage } from 'cwe/stage'

const STYLE_KEY = 'tape'
const ATTR = 'data-fx-tape'
const ROW_CLASS = 'fx-tape__row'
// The duplicate marker. Deliberately NOT `aria-hidden`: site.js writes that
// attribute too, and a `display: none` keyed on someone else's attribute is the
// `.rise` trap wearing a different hat — one stray `aria-hidden="true"` on the
// source row and the whole trade list vanishes with no JS error to explain it.
// This class is written by this module and by nothing else.
const DUPE_CLASS = 'fx-tape__dupe'
const DUR_VAR = '--fx-tape-dur'

const DEFAULTS = {
  rowSelector: '.strip__row',
  // The stylesheet's own duration wins over this; it is the last resort.
  baseMs: 42000,
  floor: 0.35,
  ceiling: 2.2,
  decayMs: 900,
  // Multiplier gained per pixel of scroll in one frame. A brisk trackpad flick
  // is ~100px/frame, which lands on the ceiling; ordinary reading scroll sits
  // around 1.3×, which is felt rather than seen.
  gain: 0.012,
  // Mobile is a design, not a fallback: thumb travel is shorter than a wheel's,
  // so a phone gets roughly twice the gain to reach the same expressiveness.
  touchGain: 2,
  // Optional ledger-bus `motion` object. Given one, its gate wins.
  motion: null,
  rootMargin: '96px 0px',
}

let styleRefs = 0

/* ── the stylesheet ───────────────────────────────────────────────────────
   Every rule is scoped under an attribute this module sets on the strip
   itself. With the attribute absent — module not loaded, module threw before
   marking anything, print, text-mode reader — none of this applies and the
   page keeps the stylesheet's own marquee, unchanged. Spacing arrives as
   resolved token values read at init. Nothing here paints. */

function sheet(tok) {
  return `
[${ATTR}] .${ROW_CLASS} {
  animation-duration: var(${DUR_VAR}, ${tok.dur});
}

/* Off-screen, and under a real pointer, the tape holds still. The hover pause
   is gated on (hover: hover) so a tap on a phone cannot leave it stuck. */
[${ATTR}='rest'] .${ROW_CLASS} {
  animation-play-state: paused;
}
@media (hover: hover) {
  [${ATTR}='run']:hover .${ROW_CLASS} {
    animation-play-state: paused;
  }
}
/* The stylesheet's own pause rule is NOT gated on (hover: hover), and :hover
   sticks on a phone after a tap — which would leave the tape frozen for the
   rest of the visit on exactly the device this module claims to design for.
   The attribute is doubled to out-specify a (0,3,0) hover rule on the row;
   'run' and 'rest' are mutually exclusive so this cannot unpause an off-screen
   strip. */
@media (hover: none) {
  [${ATTR}='run'][${ATTR}='run'] .${ROW_CLASS} {
    animation-play-state: running;
  }
}

/* 'hold' is the state the module sets FIRST and leaves in place unless it can
   prove motion is wanted: eleven trades wrapped onto as many lines as they
   need, every one of them visible at once, edge fade off because there is
   nothing running off the edge to fade. This is the reduced-motion design and
   it is a better read than the moving version. The duplicates the seamless
   loop needs are decoration, and decoration does not belong in a list someone
   is actually reading, so they go. */
[${ATTR}='hold'] {
  -webkit-mask-image: none;
  mask-image: none;
}
/* max-width + gutter, i.e. the site's own .wrap measure, so the list lines up
   with the label above it instead of sitting 40px to its left. */
[${ATTR}='hold'] .${ROW_CLASS} {
  animation: none;
  width: auto;
  max-width: ${tok.wrap};
  margin-inline: auto;
  padding-inline: ${tok.gut};
  flex-wrap: wrap;
  column-gap: ${tok.s6};
  row-gap: ${tok.s4};
}
[${ATTR}='hold'] .${ROW_CLASS}.${DUPE_CLASS},
[${ATTR}='hold'] .${ROW_CLASS} > .${DUPE_CLASS} {
  display: none;
}
/* The item dot is a separator. Standing still, the last one on the list
   separates the list from nothing, so it goes. Two rules and not one because
   the shapes differ: with a cloned ROW the real last item is :last-child, with
   cloned ITEMS it is the one before the first duplicate. Where :has() is
   unsupported the second rule is dropped, the first still fires, and the worst
   case is one trailing dot on a list that is otherwise entirely correct. */
[${ATTR}='hold'] .${ROW_CLASS} > *:last-child::after {
  display: none;
}
[${ATTR}='hold'] .${ROW_CLASS} > *:has(+ .${DUPE_CLASS})::after {
  display: none;
}
`
}

function injectStyle(tok) {
  let el = document.querySelector('style[data-fx="' + STYLE_KEY + '"]')
  if (!el) {
    el = document.createElement('style')
    el.setAttribute('data-fx', STYLE_KEY)
    el.textContent = sheet(tok)
    document.head.appendChild(el)
  }
  styleRefs++
  return el
}

function releaseStyle() {
  styleRefs = Math.max(0, styleRefs - 1)
  if (styleRefs > 0) return
  const el = document.querySelector('style[data-fx="' + STYLE_KEY + '"]')
  if (el && el.parentNode) el.parentNode.removeChild(el)
}

/* ── helpers ──────────────────────────────────────────────────────────────
   Everything below treats a non-finite number as "no reading" and returns the
   base case, which is house constraint 5 expressed in arithmetic. */

function clamp(n, lo, hi) {
  return n < lo ? lo : n > hi ? hi : n
}

function num(v, fallback) {
  const n = Number(v)
  return Number.isFinite(n) ? n : fallback
}

/* '42s' → 42000. A list ('42s, 1s') takes the first entry, which is the one
   attached to the transform we care about. */
function parseMs(value) {
  if (!value) return 0
  const first = String(value).split(',')[0].trim()
  const n = parseFloat(first)
  if (!Number.isFinite(n)) return 0
  return /ms\s*$/.test(first) ? n : n * 1000
}

function collectRows(scope, selector) {
  const found = []
  try {
    if (scope.nodeType === 1 && scope.matches && scope.matches(selector))
      found.push(scope)
    const list = scope.querySelectorAll(selector)
    for (let i = 0; i < list.length; i++) found.push(list[i])
  } catch (e) {
    return []
  }
  const out = []
  for (let i = 0; i < found.length; i++) {
    const el = found[i]
    if (out.indexOf(el) !== -1) continue
    // No parent means nothing to scope the CSS to, and the class means another
    // instance already owns this row. Both are silent skips.
    if (!el.parentElement) continue
    if (el.classList.contains(ROW_CLASS)) continue
    out.push(el)
  }
  return out
}

export function initTape(target, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})

  const dead = { mounted: false, rows: 0, destroy: function () {} }

  // No document, nothing to run. This is the first line of work in the file
  // that touches anything: importing this module does nothing at all.
  if (typeof document === 'undefined') return dead

  let scope = target || document
  if (typeof scope === 'string')
    scope = document.querySelector(scope) || document
  if (!scope) return dead

  // FAILURE MODE: no strip, no mount. No CSS injected, no attribute set, no
  // observers bound — /pricing and /parents load this module and it costs them
  // one function call.
  const rows = collectRows(scope, cfg.rowSelector)
  if (!rows.length) return dead

  const stage = getStage()

  let coarseQ = null
  try {
    coarseQ = window.matchMedia('(hover: none) and (pointer: coarse)')
  } catch (e) {
    coarseQ = null
  }

  /* ── entries ───────────────────────────────────────────────────────────
     The base duration is read from computed style BEFORE anything of ours is
     injected or marked, so what comes back is the stylesheet's own 42s and the
     one forced style flush happens here rather than mid-frame. An explicit
     config.baseMs overrides it; the default does not. */

  const explicitBase =
    config && Number.isFinite(Number(config.baseMs)) ? Number(config.baseMs) : 0

  const entries = rows.map(function (row) {
    let read = 0
    try {
      read = parseMs(getComputedStyle(row).animationDuration)
    } catch (e) {
      read = 0
    }
    // A marquee's period is seconds by definition. Anything shorter is not the
    // tape's duration, it is the stylesheet's blanket reduced-motion rule
    // (`animation-duration: 0.01ms !important`) answering instead — read at a
    // moment when the reader had motion off, that number would be captured for
    // the session and hand back a frozen tape if they ever turned it on.
    const sane = read >= 1000 ? read : 0
    const base = explicitBase || sane || num(cfg.baseMs, 42000)
    return {
      row: row,
      host: row.parentElement,
      base: base,
      state: '',
      visible: true,
      anim: null,
      lastDur: 0,
    }
  })

  const cs = getComputedStyle(document.documentElement)
  const tok = {
    dur: Math.round(entries[0].base) + 'ms',
    gut: cs.getPropertyValue('--gut').trim() || 'clamp(20px, 5vw, 40px)',
    wrap: cs.getPropertyValue('--wrap').trim() || '1180px',
    s4: cs.getPropertyValue('--s4').trim() || '16px',
    s6: cs.getPropertyValue('--s6').trim() || '32px',
  }

  injectStyle(tok)

  for (let i = 0; i < entries.length; i++) {
    const e = entries[i]
    e.row.classList.add(ROW_CLASS)
    e.host.style.setProperty(DUR_VAR, Math.round(e.base) + 'ms')
    // Opt IN to motion: the static, fully legible state goes on first and comes
    // off only once the frame callback is bound and reduced motion is off.
    e.host.setAttribute(ATTR, 'hold')
    e.state = 'hold'
  }

  /* ── the accessibility fix ─────────────────────────────────────────────
     Unhide the source row; hide the duplicates. Duplicates are identified by
     content, not by provenance, so this holds whether the runtime cloned items
     into the row or cloned the row itself, and it holds no matter which of us
     ran first. Writes only on a real difference — a settled DOM produces zero
     mutations, which is what keeps the observer below from feeding itself. */

  const hosts = []
  for (let i = 0; i < entries.length; i++)
    if (hosts.indexOf(entries[i].host) === -1) hosts.push(entries[i].host)

  function key(el) {
    return (el.textContent || '').replace(/\s+/g, ' ').trim()
  }

  // Everything this pass classed, so destroy() can hand the DOM back exactly as
  // it found it. `entries` only covers the rows that existed at init; a cloned
  // row discovered later is marked here and would otherwise keep our classes
  // after teardown.
  const marked = []
  function markRow(row) {
    if (marked.indexOf(row) === -1) marked.push(row)
  }

  function ariaFix() {
    for (let h = 0; h < hosts.length; h++) {
      // Re-queried rather than cached: the duplicate may not have existed when
      // this module mounted, and may be a whole cloned row rather than cloned
      // items. Both shapes get read here.
      let list = []
      try {
        list = hosts[h].querySelectorAll(cfg.rowSelector)
      } catch (e) {
        list = []
      }
      const seenRows = []
      for (let i = 0; i < list.length; i++) {
        const row = list[i]
        const rowKey = key(row)
        if (rowKey !== '' && seenRows.indexOf(rowKey) !== -1) {
          // A whole cloned row: decoration, top to bottom. It keeps the row
          // class so it animates with the source and disappears with it, and
          // the dupe class so the static state can drop it.
          if (!row.classList.contains(ROW_CLASS)) row.classList.add(ROW_CLASS)
          if (!row.classList.contains(DUPE_CLASS)) row.classList.add(DUPE_CLASS)
          markRow(row)
          if (row.getAttribute('aria-hidden') !== 'true')
            row.setAttribute('aria-hidden', 'true')
          continue
        }
        seenRows.push(rowKey)

        // The source. This is the line the site currently hides.
        if (row.classList.contains(DUPE_CLASS)) row.classList.remove(DUPE_CLASS)
        if (row.getAttribute('aria-hidden') === 'true')
          row.removeAttribute('aria-hidden')

        const seen = []
        const kids = row.children
        for (let k = 0; k < kids.length; k++) {
          const kid = kids[k]
          const k2 = key(kid)
          if (!k2) continue
          if (seen.indexOf(k2) !== -1) {
            if (!kid.classList.contains(DUPE_CLASS)) {
              kid.classList.add(DUPE_CLASS)
              markRow(kid)
            }
            if (kid.getAttribute('aria-hidden') !== 'true')
              kid.setAttribute('aria-hidden', 'true')
          } else {
            seen.push(k2)
            if (kid.classList.contains(DUPE_CLASS))
              kid.classList.remove(DUPE_CLASS)
            if (kid.getAttribute('aria-hidden') === 'true')
              kid.removeAttribute('aria-hidden')
          }
        }
      }
    }
  }

  // Guarded: a throw here would abort init before the trigger is bound, leaving
  // the strip in 'hold' with no way out. The static list is the right fallback,
  // but it should be the gate's decision, not an exception's.
  try {
    ariaFix()
  } catch (e) {}

  let ariaDirty = true // one more pass on the first frame, whoever ran first

  // `ariaDirty` is consumed by the frame callback, so with no frame callback it
  // is consumed by nobody: if stage.register failed, the accessibility repair
  // has to run inline or it never runs at all. Both call sites are async
  // (microtask / DOMContentLoaded), so `bound` is always initialised by then.
  // ariaFix writes only on a real difference, so the second pass this triggers
  // through the observer is a no-op and the loop terminates.
  function pumpAria() {
    ariaDirty = true
    if (bound || destroyed) return
    ariaDirty = false
    try {
      ariaFix()
    } catch (e) {}
  }

  let mo = null
  if (typeof MutationObserver === 'function') {
    mo = new MutationObserver(function () {
      pumpAria()
    })
    for (let i = 0; i < hosts.length; i++) {
      try {
        mo.observe(hosts[i], {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['aria-hidden'],
        })
      } catch (e) {}
    }
  }

  function onReady() {
    pumpAria()
  }
  if (document.readyState === 'loading')
    document.addEventListener('DOMContentLoaded', onReady)

  /* ── the gate ──────────────────────────────────────────────────────────── */

  function isReduced() {
    if (cfg.motion && cfg.motion.reduced) return true
    return !!stage.reducedMotion
  }

  function isCoarse() {
    if (cfg.motion && typeof cfg.motion.coarse === 'boolean')
      return cfg.motion.coarse
    return coarseQ ? !!coarseQ.matches : false
  }

  /* ── rate ─────────────────────────────────────────────────────────────── */

  const floor = num(cfg.floor, DEFAULTS.floor)
  const ceiling = Math.max(num(cfg.ceiling, DEFAULTS.ceiling), floor)
  const decayMs = Math.max(num(cfg.decayMs, DEFAULTS.decayMs), 1)
  const gain = num(cfg.gain, DEFAULTS.gain)
  const touchGain = num(cfg.touchGain, DEFAULTS.touchGain)

  let excess = 0 // the multiplier's departure from 1
  let mult = 1

  // The live driver. Same animation, same phase, new speed — a duration rewrite
  // would keep elapsed time and jump the phase instead.
  function getAnim(entry) {
    if (entry.anim && entry.anim.playState !== 'idle') return entry.anim
    entry.anim = null
    const row = entry.row
    if (typeof row.getAnimations !== 'function') return null
    let list = null
    try {
      list = row.getAnimations()
    } catch (e) {
      return null
    }
    for (let i = 0; i < list.length; i++) {
      // animationName is what separates a CSS animation from a transition.
      if (list[i] && typeof list[i].animationName === 'string') {
        entry.anim = list[i]
        return entry.anim
      }
    }
    return null
  }

  function applyRate(entry, m) {
    const a = getAnim(entry)
    if (a) {
      if (Math.abs(num(a.playbackRate, 1) - m) > 0.004) {
        try {
          a.playbackRate = m
        } catch (e) {
          entry.anim = null
        }
      }
      return
    }
    // No Web Animations API: the declared custom property, quantised to 250ms
    // so the phase artefact of a duration change is occasional rather than
    // every frame.
    let dur = entry.base / m
    if (!Number.isFinite(dur) || dur <= 0) dur = entry.base
    const q = Math.max(250, Math.round(dur / 250) * 250)
    if (q === entry.lastDur) return
    entry.lastDur = q
    entry.host.style.setProperty(DUR_VAR, q + 'ms')
  }

  /* ── state ────────────────────────────────────────────────────────────── */

  let bound = false
  let destroyed = false

  function stateFor(entry) {
    if (!bound || isReduced()) return 'hold'
    if (!entry.visible) return 'rest'
    return 'run'
  }

  function sync(entry) {
    const s = stateFor(entry)
    if (s === entry.state) return
    entry.state = s
    // Leaving or entering 'hold' replaces the CSS animation object outright.
    entry.anim = null
    entry.host.setAttribute(ATTR, s)
    if (s === 'run') applyRate(entry, mult)
  }

  function syncAll() {
    for (let i = 0; i < entries.length; i++) sync(entries[i])
  }

  /* ── off-screen ───────────────────────────────────────────────────────── */

  let io = null
  if (typeof IntersectionObserver === 'function') {
    io = new IntersectionObserver(
      function (recs) {
        for (let i = 0; i < recs.length; i++) {
          const rec = recs[i]
          for (let j = 0; j < entries.length; j++) {
            if (entries[j].host !== rec.target) continue
            entries[j].visible = rec.isIntersecting
            sync(entries[j])
          }
        }
      },
      { rootMargin: cfg.rootMargin }
    )
    for (let i = 0; i < entries.length; i++) {
      try {
        io.observe(entries[i].host)
      } catch (e) {}
    }
  }

  /* ── the frame ────────────────────────────────────────────────────────── */

  let lastReduced = isReduced()

  function tick(dt) {
    if (destroyed) return

    if (ariaDirty) {
      ariaDirty = false
      ariaFix()
    }

    const reduced = isReduced()
    if (reduced !== lastReduced) {
      lastReduced = reduced
      syncAll()
    }
    if (reduced) {
      // Held at base while motion is off, so switching it back on does not
      // resume at whatever multiplier the last pre-reduced frame happened to
      // leave behind.
      excess = 0
      mult = 1
      return
    }

    // FAILURE MODE: a non-finite velocity — some engines hand one back on the
    // first frame — is read as no scroll, not propagated into the rate.
    const s = stage.scroll
    let v = s ? Number(s.velocity) : 0
    if (!Number.isFinite(v)) v = 0
    const dtMs = clamp(num(dt, 0.016) * 1000, 0, 200)

    let inst = v * gain * (isCoarse() ? touchGain : 1)
    if (!Number.isFinite(inst)) inst = 0
    inst = clamp(inst, floor - 1, ceiling - 1)

    // Attack is immediate — a stronger impulse, or one in the other direction,
    // takes over on the same frame the hand produced it. Decay is the slow
    // half: an exponential settle whose time constant is decayMs/3, so the tape
    // is ~95% of the way home at decayMs rather than 63% with a long tail
    // nobody asked for. `decayMs` means what it says: back to base by then.
    const stronger = Math.abs(inst) > Math.abs(excess)
    const reversed = inst < 0 !== excess < 0
    if (inst !== 0 && (stronger || reversed)) {
      excess = inst
    } else {
      excess *= Math.exp((-3 * dtMs) / decayMs)
    }
    if (!Number.isFinite(excess)) excess = 0
    if (Math.abs(excess) < 0.002) excess = 0

    let m = clamp(1 + excess, floor, ceiling)
    if (!Number.isFinite(m) || m <= 0) m = 1
    mult = m

    for (let i = 0; i < entries.length; i++) {
      const e = entries[i]
      if (e.state === 'run') applyRate(e, mult)
    }
  }

  /* stage.js runs `for (const cb of frameCbs) cb(dt, t)` and only then schedules
     the next rAF, with no guard of its own — one throw from this module would
     stop the shared loop for every effect on the page. It stops here instead,
     and what it falls back to is the full static design: constraint 5 is a
     runtime behaviour, not just a stylesheet ordering. */
  let failed = false

  function frame(dt) {
    if (failed) return
    try {
      tick(dt)
    } catch (e) {
      // Not `destroyed`: the caller's destroy() still has observers, a
      // stylesheet and marked DOM to hand back.
      failed = true
      bound = false
      try {
        if (typeof unregister === 'function') unregister()
      } catch (e2) {}
      try {
        syncAll()
      } catch (e2) {}
    }
  }

  let unregister = null
  try {
    const off = stage.register(frame)
    if (typeof off === 'function') {
      unregister = off
      bound = true
    }
  } catch (e) {
    bound = false
  }

  // Motion is opted into here and nowhere else: the trigger is bound, the gate
  // says go. Anything short of both and the strip stays a wrapped static list.
  syncAll()

  return {
    mounted: true,
    rows: entries.length,
    destroy: function () {
      if (destroyed) return
      destroyed = true
      if (typeof unregister === 'function') unregister()
      if (io) io.disconnect()
      if (mo) mo.disconnect()
      document.removeEventListener('DOMContentLoaded', onReady)
      for (let i = 0; i < entries.length; i++) {
        const e = entries[i]
        const a = getAnim(e)
        if (a) {
          try {
            a.playbackRate = 1
          } catch (err) {}
        }
        e.row.classList.remove(ROW_CLASS)
        e.row.classList.remove(DUPE_CLASS)
        e.host.removeAttribute(ATTR)
        e.host.style.removeProperty(DUR_VAR)
      }
      // Rows and items ariaFix classed after init — a clone that did not exist
      // when this module mounted still carries our classes until this runs.
      // The aria-hidden it also wrote is left alone on purpose: that is the
      // accessibility repair, and it is correct with or without this module.
      for (let i = 0; i < marked.length; i++) {
        marked[i].classList.remove(DUPE_CLASS)
        marked[i].classList.remove(ROW_CLASS)
      }
      releaseStyle()
    },
  }
}
