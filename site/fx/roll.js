/* fx/roll.js — signature support.
 *
 * Two jobs.
 *
 * One: a per-digit odometer on the calculator's figures. Only the glyphs that
 * actually changed move; each one y-translates over `digitMs` with a `stagger`
 * across the number, and `font-variant-numeric: tabular-nums lining` is enforced
 * on the targets so nothing reflows while it happens.
 *
 * Two: the invoice's four rows re-strike in causal order — what you charged,
 * then Stripe's cut, then fuime's 7%, then what lands — `restrikeGap` apart.
 * The arithmetic is shown happening rather than swapped. That sequence is the
 * site's whole pricing argument delivered as motion instead of a claim.
 *
 * Causality is the whole point, so the roll is gated on a hand: it runs only
 * when a real `input`/`pointerdown`/`keydown` landed in the last `handMs`.
 * ledger-bus's own boot publish, a cross-page hydrate from sessionStorage, or
 * any programmatic set with nobody touching anything all SNAP. A number may
 * move because a hand moved, never because a viewport moved. Count-up-on-scroll
 * is the same animation with the opposite signal, and it is banned here by name.
 * `mode: 'scramble'` is likewise banned: numbers that decode from garbage on a
 * page about someone's money actively teach distrust.
 *
 * Structure, per changed glyph:
 *
 *   <span class="fx-roll__d">          ← the digit box; inline-block, relative
 *     <span class="fx-roll__ghost">8   ← the TRUTH: normal flow, holds the box,
 *                                        the width and the baseline, and is what
 *                                        a screen reader and a printer get
 *     <span class="fx-roll__col">      ← the THEATRE: absolute, aria-hidden,
 *       <span class="fx-roll__g">7       old glyph
 *       <span class="fx-roll__g">8       new glyph
 *
 * The CSS default is ghost visible, column not rendered — i.e. the finished,
 * correct, static number. The module opts INTO motion by adding
 * `.fx-roll__d--rolling`, and only after confirming reduced motion is off. If
 * this file throws, if masks are unsupported, if the page is printed, or if the
 * reader has reduced motion on, what is left on screen is the right figure.
 *
 * It subscribes to ledger-bus's `fuime:fee` event and to nothing else. It never
 * reads the DOM for a fee value and never observes site.js. site.js writes the
 * same strings into the same nodes in parallel and both writers agree byte for
 * byte — that parallel write is the JS-fails floor, and it holds until this
 * module's FIRST strike, at which point `claim` takes the node away from it.
 * That trade is deliberate and it is bounded on both ends: every write path in
 * here falls back to plain `textContent` if anything throws, and `destroy()`
 * hands every claimed node back to site.js with the current figure in it, so a
 * teardown restores the floor instead of freezing the page's money forever.
 * `claim: false` keeps the floor permanently, at the cost of a one-frame
 * backwards flick during a drag — see claim().
 */

import { getStage } from 'cwe/stage'

const STYLE_KEY = 'roll'
const MINUS = '−' // U+2212, the same sign site.js writes. Not a hyphen.

/* The four figures this module owns, which is exactly the set `figures()`
   produces. `restrikeOrder` is ordering and nothing else; ownership is this
   list, so a shortened restrikeOrder cannot silently orphan a row.

   Scope matters here beyond tidiness: `[data-out]` also matches
   `[data-out="monthly"]`, a full English sentence that threshold.js owns. That
   node must not be given `data-fx-roll`, because the attribute carries
   `font-variant-numeric: tabular-nums` and putting tabular figures inside prose
   spaces the "$15" and the "$250" like a table. It was never rolled — it has no
   entry in `figures()` — so it was only ever collected to be skipped. */
const FIGURE_KEYS = ['charged', 'stripe', 'fuime', 'lands']

const DEFAULTS = {
  selector: '[data-out]',
  digitMs: 180,
  stagger: 12,
  restrikeOrder: ['charged', 'stripe', 'fuime', 'lands'],
  restrikeGap: 40,
  eventName: 'fuime:fee',
  // A number moves only if a hand moved this recently. Boot publishes snap.
  handMs: 500,
  // Take ownership of a figure node on its first strike, so site.js's parallel
  // textContent write stops fighting the roll. See claim() for why, and for the
  // one-line change that lets the orchestrator turn this off.
  claim: true,
  // House constraint 9. The stagger across one number is compressed rather than
  // allowed to drift past this; the per-glyph roll itself stays at digitMs.
  budgetMs: 300,
}

let styleRefs = 0

/* ── the stylesheet ───────────────────────────────────────────────────────
   Colour comes in as resolved token values read at init — there is no literal
   here, and nothing paints ink: a figure that flashes a colour while it changes
   is a colour flash, and this module does not do one. */

function sheet(tok) {
  return `
/* The spec calls this "tabular-nums lining"; the valid keyword is lining-nums,
   and writing it the other way silently drops the whole declaration. */
[data-fx-roll] {
  font-variant-numeric: tabular-nums lining-nums;
  font-feature-settings: 'tnum' 1, 'lnum' 1;
}
[data-fx-roll] .fx-roll__d {
  display: inline-block;
  position: relative;
}
/* Default = final state. The ghost is the number; the column does not exist
   until this module decides motion is allowed. */
[data-fx-roll] .fx-roll__ghost {
  opacity: 1;
}
[data-fx-roll] .fx-roll__col {
  display: none;
}
[data-fx-roll] .fx-roll__d--rolling {
  -webkit-mask-image: linear-gradient(
    to bottom,
    transparent 0,
    ${tok.maskOn} 0.38em,
    ${tok.maskOn} calc(100% - 0.38em),
    transparent 100%
  );
  mask-image: linear-gradient(
    to bottom,
    transparent 0,
    ${tok.maskOn} 0.38em,
    ${tok.maskOn} calc(100% - 0.38em),
    transparent 100%
  );
  -webkit-mask-repeat: no-repeat;
  mask-repeat: no-repeat;
  -webkit-mask-position: center;
  mask-position: center;
  /* A soft mask, not a hard clip, and only in one axis. Vertically the gradient
     box overhangs the digit box by 0.5em top and bottom: the opaque band runs
     0.12em past the box on each side so a glyph that sticks out of a
     line-height: 1 box at hero size keeps its ink, and the fade lives entirely
     in the remaining overhang. Horizontally it is deliberately four times too
     wide, because a mask that ends at the box edge clips any glyph the fallback
     font renders wider than the box and a sliced figure reads as a broken page
     at exactly the moment someone is checking the money. */
  -webkit-mask-size: 400% calc(100% + 1em);
  mask-size: 400% calc(100% + 1em);
}
[data-fx-roll] .fx-roll__d--rolling .fx-roll__ghost {
  opacity: 0;
}
[data-fx-roll] .fx-roll__d--rolling .fx-roll__col {
  display: block;
  position: absolute;
  left: 0;
  top: 0;
  width: 100%;
  /* Two rows at a pitch of 1.34× the digit box, so there is 0.34em of blank
     between them at line-height 1. That blank is what the mask's soft overhang
     lands in: without it the overhang shows the top of the next glyph, which at
     hero size reads as a stray mark next to the number. */
  height: 268%;
  transform: translateY(-50%);
  will-change: transform;
}
[data-fx-roll] .fx-roll__g {
  display: block;
  height: 50%;
}
/* Two renderers that must always get the finished number, whatever this module
   was mid-way through: a printer and a reader who asked for less motion. */
@media (prefers-reduced-motion: reduce) {
  [data-fx-roll] .fx-roll__d--rolling {
    -webkit-mask-image: none;
    mask-image: none;
  }
  [data-fx-roll] .fx-roll__d--rolling .fx-roll__ghost {
    opacity: 1;
  }
  [data-fx-roll] .fx-roll__d--rolling .fx-roll__col {
    display: none;
  }
}
@media print {
  [data-fx-roll] .fx-roll__d--rolling {
    -webkit-mask-image: none;
    mask-image: none;
  }
  [data-fx-roll] .fx-roll__d--rolling .fx-roll__ghost {
    opacity: 1;
  }
  [data-fx-roll] .fx-roll__d--rolling .fx-roll__col {
    display: none;
  }
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

/* ── formatting ───────────────────────────────────────────────────────────
   Byte-identical to what site.js writes, because both writers hit the same
   nodes and disagreement between them would read as a bug in the pricing. */

function makeMoney() {
  try {
    const nf = new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    })
    return function (n) {
      return nf.format(n)
    }
  } catch (e) {
    return function (n) {
      return '$' + (Math.round(n * 100) / 100).toFixed(2)
    }
  }
}

function figures(d, money) {
  return {
    charged: money(d.charge),
    stripe: MINUS + money(d.stripe),
    fuime: MINUS + money(d.fuime),
    lands: money(d.lands),
  }
}

/* A string is rollable if it is a formatted number: it has digits and no prose.
   `data-out="monthly"` is a sentence, so it never gets here anyway — this is the
   guard for anything the markup grows later. */
function rollable(s) {
  return typeof s === 'string' && /\d/.test(s) && !/[A-Za-z]/.test(s)
}

function isDigit(c) {
  return c >= '0' && c <= '9'
}

/* Right-aligned diff, which is how an odometer actually behaves: $400.00 →
   $1,000.00 leaves the cents alone and rolls the head.

   Only digits roll. The $, the comma, the decimal point and the minus sign snap
   into place, because they are not quantities and because they are not the same
   width as a digit — tabular figures make every digit interchangeable and
   nothing else. Rolling a $ through a comma's box clips it to a sliver, which
   looks like the page is broken at exactly the moment the reader is checking
   the money. */
function changedMask(oldS, newS) {
  const shift = newS.length - oldS.length
  const out = new Array(newS.length)
  for (let j = 0; j < newS.length; j++) {
    const i = j - shift
    const nc = newS.charAt(j)
    const oc = i >= 0 && i < oldS.length ? oldS.charAt(i) : ''
    out[j] = nc !== oc && isDigit(nc) && (oc === '' || isDigit(oc))
  }
  return out
}

export function initRoll(root, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})

  // No document, nothing to roll. Import-time side effects: none, this is the
  // first line of work in the file that touches anything.
  if (typeof document === 'undefined') {
    return {
      refresh: function () {},
      destroy: function () {},
    }
  }

  let scope = root || document
  if (typeof scope === 'string')
    scope = document.querySelector(scope) || document

  const stage = getStage() // for reducedMotion only — no per-frame registration.
  const money = makeMoney()

  /* `--mask-on` is the opaque end of the mask, read as a token, never written as
     a value (AC2 / house constraint 3). The fallback is `currentColor`, a
     keyword rather than a colour: under an alpha mask only its alpha channel is
     read, and a figure's own text colour is opaque by construction. `transparent`
     in the gradient is the CSS-wide keyword for zero alpha and carries no palette
     value — there is no gradient without a clear end stop. Neither is a literal.
     Same convention as strike.js, deliberately. */
  const cs = getComputedStyle(document.documentElement)
  const tok = {
    ease: cs.getPropertyValue('--ease').trim() || 'ease-out',
    maskOn: cs.getPropertyValue('--mask-on').trim() || 'currentColor',
  }

  /* A style element can be in the DOM and still not be applied: a `style-src`
     CSP without `unsafe-inline` blocks it, and `sheet` stays null. That matters
     more here than in most modules, because the digit spans are born carrying
     `--rolling` — without the stylesheet the column is not `display: none`, so
     both the old and the new glyph render, unpositioned, on top of the figure.
     A money figure that reads as garbage is worse than one that does not move,
     so an unapplied sheet means this module never animates and only ever snaps.
     Motion is opted into, and this is one more thing it is opted in behind. */
  const styleEl = injectStyle(tok)
  let styleLive = false
  try {
    styleLive = !!(
      styleEl &&
      styleEl.sheet &&
      styleEl.sheet.cssRules &&
      styleEl.sheet.cssRules.length
    )
  } catch (e) {
    styleLive = false
  }

  /* ── targets ──────────────────────────────────────────────────────────── */

  // el → { key, shown, pending, timer, claimed, origin }
  // `origin` is site.js's node when this record has claimed one, so the swap can
  // be undone. See claim() / restore().
  const rec = new Map()

  function collect() {
    const found = scope.querySelectorAll(cfg.selector)
    const seen = new Set()
    for (let i = 0; i < found.length; i++) {
      const el = found[i]
      const key = el.getAttribute('data-out')
      if (!key) continue
      if (FIGURE_KEYS.indexOf(key) < 0) continue // not ours; not even marked
      seen.add(el)
      let r = rec.get(el)
      if (!r) {
        r = {
          key: key,
          shown: el.textContent.trim(),
          pending: null,
          timer: 0,
          claimed: false,
          origin: null,
        }
        rec.set(el, r)
      } else {
        r.key = key
      }
      el.setAttribute('data-fx-roll', '')
    }
    // Anything that left the document stops being ours.
    rec.forEach(function (r, el) {
      if (!seen.has(el)) {
        // Fold any roll still in the air down to plain text first, so what gets
        // handed back is a whole number and not a half-rolled one.
        settleNow(el, r)
        if (r.timer) clearTimeout(r.timer)
        el.removeAttribute('data-fx-roll')
        // If this was a claimed clone, hand site.js's original back.
        restore(r, el)
        rec.delete(el)
      }
    })
  }

  collect()

  /* ── the hand gate ────────────────────────────────────────────────────── */

  let handAt = -Infinity
  function markHand() {
    handAt = now()
  }
  function now() {
    return typeof performance !== 'undefined' && performance.now
      ? performance.now()
      : Date.now()
  }
  function byHand() {
    return now() - handAt < cfg.handMs
  }

  // Capture, so this lands before ledger-bus's own listener on the range and
  // before the event it publishes in response.
  const handOpts = { capture: true, passive: true }
  document.addEventListener('input', markHand, handOpts)
  document.addEventListener('pointerdown', markHand, handOpts)
  document.addEventListener('keydown', markHand, handOpts)
  document.addEventListener('touchstart', markHand, handOpts)

  /* ── committing ───────────────────────────────────────────────────────── */

  function commit(el, r, text) {
    if (r.timer) {
      clearTimeout(r.timer)
      r.timer = 0
    }
    r.pending = null
    el.textContent = text
    r.shown = text
  }

  // Fold an in-flight roll down to its end value. Interrupting always leaves a
  // valid, complete number on screen — never a half-rolled digit.
  function settleNow(el, r) {
    if (r.timer || r.pending !== null) commit(el, r, r.pending || r.shown)
  }

  /* ── the queue ────────────────────────────────────────────────────────────
     One strike per key, and a row is not touched at all until its own moment
     arrives. Building all four rows up front and merely delaying their
     transitions was the obvious way to do this and it is wrong: the new string
     has a different comma and a different width, so for the length of its delay
     the row shows the new punctuation around the old digits — "$ ,360.10" — and
     the largest thing on the page is briefly not a number.

     A burst of drag events refreshes the queued value without moving the
     deadline, so the sequence still strikes once, in order, per burst, and
     never stalls behind a hand that keeps moving. */

  const queues = new Map()

  function enqueue(key, items, value, delay) {
    const q = queues.get(key)
    if (q) {
      q.value = value
      q.items = items
      return
    }
    const next = { value: value, items: items, timer: 0 }
    queues.set(key, next)
    next.timer = setTimeout(function () {
      queues.delete(key)
      strike(next.items, next.value)
    }, delay)
  }

  function dropQueues(commitThem) {
    queues.forEach(function (q) {
      clearTimeout(q.timer)
      if (!commitThem) return
      for (let i = 0; i < q.items.length; i++) {
        commit(q.items[i].el, q.items[i].r, q.value)
      }
    })
    queues.clear()
  }

  /* Claiming a node, which is the one piece of coordination this module cannot
     avoid. site.js's calculator writes these same four figures with textContent
     on every input, from a NodeList it captured once at its own init. Two
     writers on one node with different timing models cannot both be right: the
     roll would start from a value site.js had already replaced, so the figure
     would flick backwards and then roll forwards, which is a worse readout than
     no motion at all.

     So on its FIRST strike — not at init — this module swaps the node for a
     clone carrying whatever is rendered at that moment. site.js's stale
     reference keeps receiving its writes off-document and stops fighting for
     the pixels; every other thing site.js does to these figures (the data-live
     attribute, the range fill) is re-queried per render and is untouched.

     First strike, not init, is the whole point: until this module has proven it
     can render a figure, site.js remains the floor and the page is correct
     without it. The cost is one change of warm-up, which during a drag is a
     single frame. The orchestrator can retire all of this by making site.js
     skip nodes carrying data-fx-roll, and then setting claim: false.

     The swap is remembered, not forgotten: `r.origin` holds site.js's node and
     `restore()` puts it back carrying the current figure. Without that, a
     destroy — or a page that keeps roll.js while ledger-bus stops publishing —
     would leave site.js writing into a node that is no longer on screen, and the
     largest number on the pricing page would sit frozen at a stale value while
     the slider moved. A wrong figure is a worse failure than a still one. */

  function claim(el, r) {
    if (r.claimed) return el
    r.claimed = true
    if (!cfg.claim || !el.parentNode) return el
    const clone = el.cloneNode(false)
    clone.textContent = el.textContent
    el.parentNode.replaceChild(clone, el)
    r.origin = el
    rec.delete(el)
    rec.set(clone, r)
    // Whatever is on screen right now is the truth to roll from, whoever wrote
    // it. This is also what repairs any drift from the parallel writer.
    r.shown = clone.textContent
    return clone
  }

  /* The inverse of claim(). Safe to call on a record that never claimed.

     The value handed back is the record's own truth — `pending` if a roll was
     still in the air, otherwise `shown` — never `el.textContent`, which mid-roll
     is the ghost and both column glyphs concatenated and would put "$4443.10"
     into a node site.js is about to stop being able to correct. */
  function restore(r, el) {
    const origin = r.origin
    r.origin = null
    if (!origin || origin === el) return
    try {
      const truth = r.pending || r.shown || el.textContent
      origin.textContent = truth
      origin.removeAttribute('data-fx-roll')
      if (el.parentNode) el.parentNode.replaceChild(origin, el)
    } catch (e) {}
  }

  /* Every path that can throw ends in plain text at the right value.
     `replaceChildren` is missing on older Safari, a mask can be refused, a node
     can be swapped out from under us mid-strike. Whatever the reason, the
     recovery is the same and it is the only acceptable one on a page about
     someone's money: write the figure as text. Silently leaving the old number
     up is the failure this catch exists to prevent — after `claim` there is no
     second writer left to correct it. */
  function fallback(items, value) {
    for (let i = 0; i < items.length; i++) {
      try {
        commit(items[i].el, items[i].r, value)
      } catch (e) {}
    }
  }

  function strike(items, value) {
    try {
      strikeInner(items, value)
    } catch (e) {
      fallback(items, value)
    }
  }

  function strikeInner(items, value) {
    const cols = []
    for (let i = 0; i < items.length; i++) {
      const el = claim(items[i].el, items[i].r)
      items[i].el = el
      roll(el, items[i].r, value, cols)
    }
    if (!cols.length) return

    // One forced reflow for the whole row, then every column transitions from
    // its inline "before" transform back to the stylesheet's finished state.
    // This is why the module needs no rAF of its own and no Stage callback.
    void document.documentElement.offsetHeight

    for (let i = 0; i < cols.length; i++) {
      const c = cols[i]
      c.col.style.transition =
        'transform ' +
        cfg.digitMs +
        'ms ' +
        tok.ease +
        ' ' +
        Math.round(c.delay) +
        'ms'
      c.col.style.transform = ''
    }
  }

  /* ── one change ───────────────────────────────────────────────────────── */

  function roll(el, r, next, cols) {
    const oldS = r.shown
    const mask = changedMask(oldS, next)
    let n = 0
    for (let i = 0; i < mask.length; i++) if (mask[i]) n++
    // The strings differ but no digit does — a separator moved, nothing else.
    // Snap it; there is nothing to roll and a stale string is not an option.
    if (!n) {
      commit(el, r, next)
      return
    }

    const budget = Math.max(0, cfg.budgetMs - cfg.digitMs)
    const step = n > 1 ? Math.min(cfg.stagger, budget / (n - 1)) : 0
    const shift = next.length - oldS.length

    const frag = document.createDocumentFragment()
    let k = 0
    for (let j = 0; j < next.length; j++) {
      const ch = next.charAt(j)
      if (!mask[j]) {
        frag.appendChild(document.createTextNode(ch))
        continue
      }
      const i = j - shift
      const prev = i >= 0 && i < oldS.length ? oldS.charAt(i) : ''

      const d = document.createElement('span')
      d.className = 'fx-roll__d fx-roll__d--rolling'

      const ghost = document.createElement('span')
      ghost.className = 'fx-roll__ghost'
      ghost.textContent = ch

      const col = document.createElement('span')
      col.className = 'fx-roll__col'
      col.setAttribute('aria-hidden', 'true')
      col.style.transition = 'none'
      col.style.transform = 'translateY(0)'

      const g0 = document.createElement('span')
      g0.className = 'fx-roll__g'
      g0.textContent = prev
      const g1 = document.createElement('span')
      g1.className = 'fx-roll__g'
      g1.textContent = ch
      col.appendChild(g0)
      col.appendChild(g1)

      d.appendChild(ghost)
      d.appendChild(col)
      frag.appendChild(d)

      cols.push({ col: col, delay: k * step })
      k++
    }

    el.replaceChildren(frag)
    r.pending = next

    const total = (n - 1) * step + cfg.digitMs + 40
    r.timer = setTimeout(function () {
      r.timer = 0
      commit(el, r, next)
    }, total)
  }

  /* ── the subscription ─────────────────────────────────────────────────── */

  /* All four, and finite. Checking `charge` alone is not enough: a detail that
     is missing `lands` does not throw on the way through Intl — `format(undefined)`
     returns the string "$NaN" — so a half-built event would have painted "$NaN"
     over the one number on this page that the reader is here to trust. Refusing
     the whole event leaves site.js's figures standing, which is the floor. */
  function usable(d) {
    if (!d) return false
    for (let i = 0; i < FIGURE_KEYS.length; i++) {
      const v = d[FIGURE_KEYS[i] === 'charged' ? 'charge' : FIGURE_KEYS[i]]
      if (typeof v !== 'number' || !isFinite(v)) return false
    }
    return true
  }

  // The snap path, and also the recovery path: correct, tabular, no reflow, all
  // four rows in the same frame.
  function snapAll(values) {
    dropQueues(false)
    rec.forEach(function (r, el) {
      const next = values[r.key]
      if (typeof next !== 'string') return
      settleNow(el, r)
      if (r.shown !== next) commit(el, r, next)
    })
  }

  function apply(detail) {
    if (!usable(detail)) return
    let values
    try {
      values = figures(detail, money)
    } catch (e) {
      return
    }

    // Reduced motion snaps: the number changes instantly and is correct,
    // tabular, no reflow, and all four rows land in the same frame. The
    // argument survives intact — the arithmetic was never the animation.
    const animate = styleLive && stage.reducedMotion === false && byHand()

    if (!animate) {
      snapAll(values)
      return
    }

    const byKey = new Map()
    rec.forEach(function (r, el) {
      const next = values[r.key]
      if (typeof next !== 'string') return // not a figure we own — leave it alone

      settleNow(el, r)
      // A key already in the queue keeps every one of its nodes in the batch,
      // even the ones that happen to read correctly right now.
      if (r.shown === next && !queues.has(r.key)) return

      if (!rollable(r.shown) || !rollable(next)) {
        commit(el, r, next)
        return
      }

      let list = byKey.get(r.key)
      if (!list) {
        list = []
        byKey.set(r.key, list)
      }
      list.push({ el: el, r: r })
    })

    byKey.forEach(function (items, key) {
      const idx = cfg.restrikeOrder.indexOf(key)
      enqueue(key, items, values[key], idx > 0 ? idx * cfg.restrikeGap : 0)
    })
  }

  /* An exception on the animated path must not cost the page the update. Once a
     node is claimed there is no second writer to fall back on, so the catch
     re-runs the change as a snap: the figure is right, it just did not move. */
  function onFee(e) {
    try {
      apply(e.detail)
    } catch (err) {
      try {
        if (usable(e.detail)) snapAll(figures(e.detail, money))
      } catch (e2) {}
    }
  }
  document.addEventListener(cfg.eventName, onFee)

  /* ── handle ───────────────────────────────────────────────────────────── */

  return {
    // Re-scan after markup changes. Never animates: a refresh is not a hand.
    refresh: function () {
      dropQueues(true)
      rec.forEach(function (r, el) {
        settleNow(el, r)
      })
      collect()
    },
    destroy: function () {
      document.removeEventListener(cfg.eventName, onFee)
      document.removeEventListener('input', markHand, handOpts)
      document.removeEventListener('pointerdown', markHand, handOpts)
      document.removeEventListener('keydown', markHand, handOpts)
      document.removeEventListener('touchstart', markHand, handOpts)
      // Whatever was queued or in flight lands as plain text at its real value.
      // Tearing this module down must never cost the page a figure.
      dropQueues(true)
      rec.forEach(function (r, el) {
        settleNow(el, r)
        el.removeAttribute('data-fx-roll')
        // Hand the node back. site.js's captured NodeList still points at the
        // original, so putting it back on screen with the current figure in it
        // makes the parallel writer live again. Skipping this would leave the
        // page permanently unable to update its own money after a destroy.
        restore(r, el)
      })
      rec.clear()
      releaseStyle()
    },
  }
}
