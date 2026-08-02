/* fx/strike.js — the headline wipe.
 *
 * One move, and it is a wipe, not a fade. A mask-image gradient travels from
 * the baseline upward and left to right across each line of a heading, 320ms a
 * line, 90ms between lines, on a fully opaque element.
 *
 * Two consequences, and they are the whole reason this technique was chosen
 * over every alternative:
 *
 *   1. The element never touches `opacity`. It cannot regress LCP and it cannot
 *      leave a blank page. The worst failure this file has is a heading that
 *      renders normally with no animation.
 *   2. The headline is *partially revealed* for 320ms rather than *invisible*
 *      for 320ms. The value proposition is never withheld.
 *
 * Per-letter, per-word, scramble, decrypt and typewriter treatments are banned:
 * the headline is the argument, and delaying its legibility to look clever
 * trades the only sentence that matters for a trick.
 *
 * Motion is opted into, never out of. The injected CSS describes the *final*
 * state; the masked start state is a single attribute this file sets only after
 * it has measured the lines, scheduled the failsafe that clears them, and bound
 * its observer. The DOM it builds is transient — the original markup is put
 * back, node for node, the moment the wipe is over, so the steady state of the
 * page is byte-identical to the one the server sent.
 *
 * No per-frame callback. It reads `stage.reducedMotion` once and never
 * registers with the loop.
 */

import { getStage } from 'cwe/stage'

const HOST_ATTR = 'data-fx-strike'
const WIPE_ATTR = 'data-fx-strike-wipe'
const LINE_CLASS = 'fx-strike__line'
const WORD_CLASS = 'fx-strike__w'

/* More line boxes than this and we are not looking at a headline any more —
   treat it as one line rather than choreograph a paragraph. */
const MAX_LINES = 8
/* Slack on the failsafe timer, past the last line's transition. */
const TAIL_MS = 200

/* Headings already owned by a live instance. `HOST_ATTR` cannot be this guard:
   it exists only while a wipe is in flight and is gone again the moment the
   original markup is restored, so a second `initStrike` over the same heading
   would claim it too, snapshot the *first* instance's line spans as the markup
   to restore, and hand back a heading that never had those words in it. Module
   scope, released in `destroy()`. */
const CLAIMED = new WeakSet()

const DEFAULTS = {
  selector: 'h1, .h2',
  lineMs: 320,
  lineGap: 90,
  /* Locked at 0 and read-only. Velocity skew on a fintech headline is where
     premium tips into unstable; the key exists so a caller passing it gets a
     documented no-op rather than a silent one. */
  velocityToSkew: 0,
  autoplay: true,
  threshold: 0.85,
}

/* ── tokens ───────────────────────────────────────────────────────────── */

function token(name, fallback) {
  try {
    const v = getComputedStyle(document.documentElement)
      .getPropertyValue(name)
      .trim()
    return v || fallback
  } catch (e) {
    return fallback
  }
}

/* ── the stylesheet ───────────────────────────────────────────────────── */

/* Geometry, derived rather than guessed: the mask image is 2.4× the line box
   wide, so travelling it from `100% 0` to `0% 0` sweeps 1.4 line-widths. With
   the soft edge sitting between 45% and 55% of that image (0.24 of a line
   width), the wipe is in motion for 89% of its duration — a real edge, not a
   fade with a long wait at each end. The 78° tilt puts the leading corner at
   the bottom left, which is what makes the ink read as laid down from the
   baseline up. The stops carry ~2% of headroom at both ends across every line
   aspect ratio this site produces, so the end state is *fully* opaque and the
   start state is *fully* clear. */
/* `--mask-on` is the opaque end of the mask. The fallback is `currentColor`, a
   keyword, not a value: under `mask-mode: alpha` only its alpha channel is read,
   and a heading's own text colour is opaque by construction. `transparent` is
   the CSS-wide keyword for zero alpha — it carries no palette value and there is
   no gradient without a clear end stop. Neither is a colour literal (AC2). */
function css() {
  const on = token('--mask-on', 'currentColor')
  const ease = token('--ease', 'ease-out')
  const grad =
    'linear-gradient(78deg, ' + on + ' 0%, ' + on + ' 45%, transparent 55%)'

  return `
[${HOST_ATTR}] {
  /* A block formatting context, so the first line's negative top margin cannot
     collapse out through the heading and move it. */
  display: flow-root;
}
[${HOST_ATTR}] .${LINE_CLASS} {
  display: block;
  /* mask-clip is the border box, so ink outside it — descenders, accents —
     would be cut for as long as the mask is mounted. Pad the box out and pull
     the padding straight back off. Between two lines the -2x bottom margin
     collapses with the -1x top margin to -2x, which is exactly the two paddings
     it has to cancel; the first and last edges cancel their own. */
  padding-block: 0.18em;
  margin-block: -0.18em -0.36em;
  -webkit-mask-image: ${grad};
  mask-image: ${grad};
  mask-mode: alpha;
  -webkit-mask-repeat: no-repeat;
  mask-repeat: no-repeat;
  -webkit-mask-size: 240% 100%;
  mask-size: 240% 100%;
  -webkit-mask-position: 0% 0%;
  mask-position: 0% 0%;
  transition-property: -webkit-mask-position, mask-position;
  transition-duration: var(--fx-strike-ms, 0ms);
  /* The stagger is carried by a custom property, not by an inline
     transition-delay. An inline declaration would outrank every rule below and
     survive into the start state, where a non-zero delay makes the combined
     duration non-zero - which starts a transition instead of a jump, holds the
     line at its old value for the length of the delay, and lets the very next
     line of JS cancel it. Every line but the first would then never move. */
  transition-delay: var(--fx-strike-delay, 0ms);
  transition-timing-function: ${ease};
}
[${HOST_ATTR}] .${LINE_CLASS}:last-child {
  margin-block-end: -0.18em;
}
[${HOST_ATTR}] .${WORD_CLASS} {
  display: inline;
}
/* The masked start state. One attribute, set for one frame, removed to fire the
   transition. It is the only thing in this file that can hide a glyph. */
[${HOST_ATTR}][${WIPE_ATTR}] .${LINE_CLASS} {
  -webkit-mask-position: 100% 0%;
  mask-position: 100% 0%;
  /* Duration *and* delay: combined duration zero is what makes entering this
     state a jump rather than a transition. */
  transition-duration: 0ms;
  transition-delay: 0ms;
}
@media (prefers-reduced-motion: reduce) {
  [${HOST_ATTR}] .${LINE_CLASS},
  [${HOST_ATTR}][${WIPE_ATTR}] .${LINE_CLASS} {
    -webkit-mask-image: none;
    mask-image: none;
    transition: none;
  }
}
@media print {
  [${HOST_ATTR}] .${LINE_CLASS},
  [${HOST_ATTR}][${WIPE_ATTR}] .${LINE_CLASS} {
    -webkit-mask-image: none;
    mask-image: none;
    transition: none;
  }
}
`
}

function ensureStyle() {
  if (document.querySelector('style[data-fx="strike"]')) return true
  const el = document.createElement('style')
  el.setAttribute('data-fx', 'strike')
  el.textContent = css()
  document.head.appendChild(el)
  return true
}

/* ── capability ───────────────────────────────────────────────────────── */

/* Property sniff rather than CSS.supports(), so no colour literal of any kind
   has to exist in this file to ask the question. */
function maskable() {
  try {
    const s = document.documentElement.style
    return 'maskImage' in s || 'webkitMaskImage' in s
  } catch (e) {
    return false
  }
}

/* ── the splitter ─────────────────────────────────────────────────────── */

function detach(el) {
  while (el.firstChild) el.removeChild(el.firstChild)
}

/* Only plain text and <br> can be re-flowed into line boxes safely. Anything
   else — a <span>, an <em>, a link — could straddle a line break, and cutting
   an element in half to animate it is a worse outcome than not animating. */
function splittable(nodes) {
  for (let i = 0; i < nodes.length; i++) {
    const n = nodes[i]
    if (n.nodeType === 3) continue
    if (n.nodeType === 1 && n.tagName === 'BR') continue
    return false
  }
  return true
}

/* Measure where the browser actually put the line breaks, then rebuild the
   heading as one block per line. Returns the line elements, or null if it could
   not resolve line boxes — a font swap landing mid-measure is the realistic
   cause, and the caller's answer to null is one line, not no animation. */
function measureLines(el, saved) {
  const words = []
  const probe = document.createDocumentFragment()

  for (let i = 0; i < saved.length; i++) {
    const node = saved[i]
    if (node.nodeType === 1) {
      probe.appendChild(document.createElement('br'))
      continue
    }
    /* Breaking whitespace only. `\s` would eat U+00A0 as well, and a non-breaking
       space in a headline is load-bearing — it is there to stop an orphan. Split
       on it and the measured line boxes are not the authored ones, and the
       rebuild silently replaces it with a space the browser may break at. */
    const parts = String(node.nodeValue).split(/([ \t\r\n\f]+)/)
    for (let p = 0; p < parts.length; p++) {
      const part = parts[p]
      if (!part) continue
      if (/^[ \t\r\n\f]+$/.test(part)) {
        probe.appendChild(document.createTextNode(' '))
        continue
      }
      const w = document.createElement('span')
      w.className = WORD_CLASS
      w.textContent = part
      words.push(w)
      probe.appendChild(w)
    }
  }
  if (!words.length) return null

  detach(el)
  el.appendChild(probe)

  const groups = []
  let top = null
  for (let i = 0; i < words.length; i++) {
    const t = words[i].offsetTop
    if (top === null || Math.abs(t - top) > 2) {
      groups.push([])
      top = t
    }
    groups[groups.length - 1].push(words[i].textContent)
  }
  if (!groups.length || groups.length > MAX_LINES) return null

  detach(el)
  const lines = []
  for (let g = 0; g < groups.length; g++) {
    /* One collapsible space between the line boxes. Without it the heading's
       textContent is the lines run together — "Money thatmoves when" — for as
       long as the split is mounted, which is what a screen reader announces and
       what anything reading the DOM sees. Whitespace between two block-level
       siblings generates no box, so it costs nothing on screen. */
    if (g) el.appendChild(document.createTextNode(' '))
    const line = document.createElement('span')
    line.className = LINE_CLASS
    line.textContent = groups[g].join(' ')
    el.appendChild(line)
    lines.push(line)
  }
  return lines
}

/* The failure mode, and it is a first-class path: the whole heading becomes one
   line and wipes in 320ms. The original nodes are *moved* into the wrapper, not
   re-serialised, so nested markup survives intact and restoring is a move back
   out. */
function oneLine(el, saved) {
  detach(el)
  const line = document.createElement('span')
  line.className = LINE_CLASS
  for (let i = 0; i < saved.length; i++) line.appendChild(saved[i])
  el.appendChild(line)
  return [line]
}

/* ── module ───────────────────────────────────────────────────────────── */

export function initStrike(target, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})
  cfg.velocityToSkew = 0
  const lineMs = Math.max(0, Number(cfg.lineMs) || 0)
  const lineGap = Math.max(0, Number(cfg.lineGap) || 0)

  const records = []
  let io = null
  let live = false
  let destroyed = false

  /* ── restore ────────────────────────────────────────────────────────── */

  function restore(rec) {
    const el = rec.el
    try {
      if (rec.saved) {
        detach(el)
        for (let i = 0; i < rec.saved.length; i++) el.appendChild(rec.saved[i])
        rec.saved = null
      }
      el.removeAttribute(WIPE_ATTR)
      el.style.removeProperty('--fx-strike-ms')
      el.removeAttribute(HOST_ATTR)
    } catch (e) {
      /* Nothing here can hide text: the mask lives on children that are being
         thrown away, and the attribute that hides them is gone first. */
    }
    rec.lines = []
  }

  function finish(rec) {
    if (rec.timer) {
      clearTimeout(rec.timer)
      rec.timer = 0
    }
    try {
      rec.el.removeAttribute(WIPE_ATTR)
    } catch (e) {}
    rec.playing = false
    rec.played = true
    restore(rec)
  }

  /* ── split ──────────────────────────────────────────────────────────── */

  function split(rec) {
    const el = rec.el
    if (!el.textContent || !el.textContent.trim()) return 0

    const saved = []
    for (let n = el.firstChild; n; n = n.nextSibling) saved.push(n)
    rec.saved = saved

    let lines = null
    if (splittable(saved)) {
      try {
        lines = measureLines(el, saved)
      } catch (e) {
        lines = null
      }
    }
    el.setAttribute(HOST_ATTR, '')
    if (!lines || !lines.length) lines = oneLine(el, saved)

    rec.lines = lines
    return lines.length
  }

  /* ── play ───────────────────────────────────────────────────────────── */

  function play(rec) {
    if (destroyed || rec.playing || rec.played) return

    rec.playing = true
    let count = 0
    try {
      count = split(rec)
    } catch (e) {
      count = 0
    }
    if (!count) {
      finish(rec)
      return
    }

    /* Scheduled before a single glyph can be masked. Whatever happens below —
       a throw, a detached node, a style engine that ignores the whole rule —
       this clears the mask and puts the heading back. */
    rec.timer = setTimeout(
      function () {
        finish(rec)
      },
      lineMs + lineGap * count + TAIL_MS
    )

    try {
      rec.el.style.setProperty('--fx-strike-ms', lineMs + 'ms')
      for (let i = 0; i < rec.lines.length; i++) {
        rec.lines[i].style.setProperty('--fx-strike-delay', i * lineGap + 'ms')
      }
      rec.el.setAttribute(WIPE_ATTR, '')
    } finally {
      /* Commit the masked start state with one forced layout read, then release
         it. This is the frame the ink starts landing on, and it runs whether or
         not the arming above got all the way through. No rAF: the flush is
         synchronous, so there is no frame in which the heading is hidden with
         nothing scheduled to reveal it. */
      void rec.el.offsetWidth
      rec.el.removeAttribute(WIPE_ATTR)
    }
  }

  /* ── observer ───────────────────────────────────────────────────────── */

  function bind() {
    if (typeof IntersectionObserver === 'undefined') return false
    const t = Math.max(0, Math.min(1, Number(cfg.threshold)))
    /* `threshold` is a trigger line down the viewport, not a ratio: shrink the
       root's bottom edge up to it so a heading fires when its top crosses. */
    const bottom = -Math.round((1 - t) * 100)
    try {
      io = new IntersectionObserver(
        function (entries) {
          for (let i = 0; i < entries.length; i++) {
            const e = entries[i]
            if (!e.isIntersecting) continue
            if (io) io.unobserve(e.target)
            for (let r = 0; r < records.length; r++) {
              if (records[r].el === e.target) play(records[r])
            }
          }
        },
        { rootMargin: '0px 0px ' + bottom + '% 0px', threshold: 0 }
      )
    } catch (e) {
      io = null
      return false
    }
    return true
  }

  /* ── init ───────────────────────────────────────────────────────────── */

  const handle = {
    replay: function () {
      if (destroyed || !live) return
      for (let i = 0; i < records.length; i++) {
        const rec = records[i]
        if (io) io.unobserve(rec.el)
        finish(rec)
        rec.played = false
        rec.playing = false
        play(rec)
      }
    },
    destroy: function () {
      destroyed = true
      if (io) {
        try {
          io.disconnect()
        } catch (e) {}
        io = null
      }
      for (let i = 0; i < records.length; i++) {
        finish(records[i])
        /* Release the claim, or a re-init after destroy finds every heading
           taken and silently animates nothing. */
        CLAIMED.delete(records[i].el)
      }
      records.length = 0
      live = false
    },
  }

  try {
    if (typeof document === 'undefined') return handle

    const root =
      typeof target === 'string'
        ? document.querySelector(target)
        : target && target.nodeType === 1
          ? target
          : document

    const els = []
    if (root.nodeType === 1 && root.matches && root.matches(cfg.selector)) {
      els.push(root)
    }
    const found = root.querySelectorAll(cfg.selector)
    for (let i = 0; i < found.length; i++) els.push(found[i])

    /* Reduced motion: the headline is simply present, fully legible, at first
       paint. There is nothing to remove because nothing is ever added — no
       stylesheet, no attribute, no split. Same for an engine with no mask
       support and for a page with no headings. Asked once, at init; the
       stylesheet's own reduced-motion block covers a switch mid-flight. */
    if (!els.length) return handle
    const stage = getStage()
    if (!stage || stage.inert || stage.reducedMotion) return handle
    if (!maskable()) return handle

    ensureStyle()

    for (let i = 0; i < els.length; i++) {
      const el = els[i]
      if (el.hasAttribute(HOST_ATTR) || CLAIMED.has(el)) continue
      CLAIMED.add(el)
      records.push({
        el: el,
        lines: [],
        saved: null,
        timer: 0,
        playing: false,
        played: false,
      })
    }
    if (!records.length) return handle

    live = true

    if (cfg.autoplay) {
      if (bind()) {
        for (let i = 0; i < records.length; i++) io.observe(records[i].el)
      }
      /* No IntersectionObserver: nothing is armed and every heading renders
         exactly as authored. A missing trigger costs the animation, never the
         words. */
    }
  } catch (e) {
    /* Anything unexpected between here and the first mask leaves the page in
       its authored state. Put back whatever was already touched, and give up
       the claims so a later init is not locked out by a failed one. */
    for (let i = 0; i < records.length; i++) {
      finish(records[i])
      CLAIMED.delete(records[i].el)
    }
    records.length = 0
    live = false
  }

  return handle
}
