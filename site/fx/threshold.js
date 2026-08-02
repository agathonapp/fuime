/* fx/threshold.js — the pricing model, taught by a tick and a switch.
 *
 * Two things, and the second one is the point.
 *
 * One: a tick on the slider track at the threshold's true proportional
 * position, with a small label under it. The monthly fee stops being a footnote
 * and becomes a place on the instrument you can drag past.
 *
 * Two: the monthly readout changes state with zero easing while every other
 * number on the page interpolates. Thresholds do not interpolate, quantities
 * do. Dragging past the tick throws the readout like a switch, and that single
 * detail teaches the whole pricing model in one drag with no copy.
 *
 * This is the one module in the build where "no animation" is the designed
 * behaviour rather than the degraded one, which is why the reduced-motion path
 * and the full path are the same path.
 *
 * Subscribes to ledger-bus's `fuime:fee`. Never reads the DOM for fee values,
 * never touches site.js, never registers a frame callback — it has nothing to
 * do between crossings.
 */

const DEFAULTS = {
  threshold: 250,
  rangeSelector: '.calc__range',
  readoutSelector: '[data-out="monthly"]',
  // null derives the label from `threshold`, so a changed threshold can never
  // leave a stale number painted on the track.
  label: null,
  eventName: 'fuime:fee',
  // Supply both — here, or as data-threshold-over / data-threshold-under on the
  // readout — and the module owns the copy outright. Leave them null and it
  // learns the page's own two strings the first time it sees each state.
  overText: null,
  underText: null,
}

/* ── injected CSS ─────────────────────────────────────────────────────────
   No entrance, no keyframes, nothing to opt into: the default state below is
   also the final state, so a JS failure, a print stylesheet or a text-mode
   reader all get the page the design intends. Colours are tokens, never
   literals, and read live so a theme change is not this module's problem. */

const CSS = `
[data-fx-threshold] {
  position: relative;
}

/* The geometry the design specifies: 26px thumb on a 28px control under a
   mouse, 28 on 44 under a finger. Phones get the bigger instrument, not the
   smaller effect.

   These are the fallback only. What actually lands on the page is measured off
   the control at init (see measure() below) and written inline on the host,
   because the 44px touch track is not in style.css today and is not on the
   orchestrator's integration list either. Believing the spec over the page
   would draw the mark 14px below the rail, straight through the endpoint
   labels, on every phone. */
[data-fx-threshold] {
  --fx-th-thumb: 26px;
  --fx-th-track: 28px;
  --fx-th-row: var(--s2, 8px);
}
@media (hover: none) and (pointer: coarse) {
  [data-fx-threshold] {
    --fx-th-thumb: 28px;
    --fx-th-track: 44px;
  }
}

/* A range thumb's centre travels from thumb/2 to width − thumb/2, so the true
   proportional position is measured across that inset and not across the box.
   A flat percentage of the width is off by half a thumb at the ends, and a
   tick in the wrong place is a lie about the pricing model. */
.fx-threshold__tick {
  position: absolute;
  top: 0;
  left: calc(
    var(--fx-th-thumb) / 2 + (100% - var(--fx-th-thumb)) * var(--fx-th-frac, 0)
  );
  width: 1px;
  height: 0;
  color: var(--ink-muted, currentColor);
  pointer-events: none;
  -webkit-user-select: none;
  user-select: none;
}
.band--night .fx-threshold__tick {
  color: var(--on-dark-mu, currentColor);
}

.fx-threshold__mark {
  position: absolute;
  left: 0;
  top: calc(var(--fx-th-track) / 2 - 6px);
  width: 1px;
  height: calc(var(--fx-th-track) / 2 + 4px);
  background: currentColor;
}

/* Sits on the same baseline as the slider's own endpoint labels, so the track
   reads as one scale with three annotated points instead of a caption bolted
   underneath. */
.fx-threshold__label {
  position: absolute;
  left: 0;
  top: calc(var(--fx-th-track) + var(--fx-th-row));
  transform: translateX(-50%);
  font-size: var(--t-small, 0.875rem);
  line-height: 1.55;
  letter-spacing: 0.42px;
  font-variant-numeric: tabular-nums lining;
  white-space: nowrap;
}

/* Near either end a centred label would sit on top of the endpoint label, so
   it hangs off the tick instead. The mark itself never moves. */
.fx-threshold__tick[data-anchor='start'] .fx-threshold__label {
  transform: translateX(8px);
}
.fx-threshold__tick[data-anchor='end'] .fx-threshold__label {
  transform: translateX(calc(-100% - 8px));
}

/* The one !important in this build, and the reason the module exists. The
   monthly readout is a threshold, not a quantity: it has to arrive already
   switched. An inherited transition — the site's .num colour fade, a digit
   roll on [data-out] — would ease the single change on this page whose whole
   meaning is that it does not ease. */
[data-fx-threshold-readout],
[data-fx-threshold-readout] * {
  transition: none !important;
}
`

/* ── helpers ──────────────────────────────────────────────────────────── */

function resolveRoot(target) {
  if (typeof target === 'string')
    return document.querySelector(target) || document
  if (target && target.nodeType === 1) return target
  return document
}

/* An absent min/max reads as '' off the element, and Number('') is 0 — which
   would place the tick confidently in the wrong spot. Parse the attribute or
   admit we do not know. */
function numAttr(el, name) {
  const raw = el.getAttribute(name)
  if (raw == null || String(raw).trim() === '') return NaN
  const n = Number(raw)
  return Number.isFinite(n) ? n : NaN
}

/* An unsupported pseudo-element makes getComputedStyle hand back the element's
   own style rather than nothing, so a bad read looks like a plausible number —
   the range's full width. Bound it to something a thumb could actually be. */
function pseudoWidth(el, pseudo) {
  let cs = null
  try {
    cs = getComputedStyle(el, pseudo)
  } catch (err) {
    return NaN
  }
  if (!cs) return NaN
  const w = parseFloat(cs.width)
  return Number.isFinite(w) && w > 0 && w < 200 ? w : NaN
}

/* Measure the instrument instead of asserting it. Returns null when the
   control has no layout yet — hidden tab, display:none ancestor — and the CSS
   fallback above stands. */
function measure(range) {
  const track = range.getBoundingClientRect().height
  if (!(track > 0)) return null
  let thumb = pseudoWidth(range, '::-webkit-slider-thumb')
  if (!(thumb > 0)) thumb = pseudoWidth(range, '::-moz-range-thumb')
  // Last resort: the two specified pairs are 26-on-28 and 28-on-44, so a thumb
  // is the control less its breathing room, capped where the design caps it.
  // Never wider than the track it rides in.
  if (!(thumb > 0) || thumb > track) thumb = Math.min(track - 2, 28)
  if (!(thumb > 0)) return null
  return { track: track, thumb: thumb }
}

function ensureStyle() {
  let el = document.querySelector('style[data-fx="threshold"]')
  if (!el) {
    el = document.createElement('style')
    el.setAttribute('data-fx', 'threshold')
    el.textContent = CSS
    document.head.appendChild(el)
  }
  // Ref-counted so two calculators on one page share one sheet and the first
  // destroy() does not pull it out from under the second instance.
  el.dataset.uses = String((Number(el.dataset.uses) || 0) + 1)
  return el
}

function releaseStyle(el) {
  if (!el || !el.parentNode) return
  const n = (Number(el.dataset.uses) || 1) - 1
  if (n <= 0) el.parentNode.removeChild(el)
  else el.dataset.uses = String(n)
}

/* ── module ───────────────────────────────────────────────────────────── */

export function initThreshold(target, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})
  const inert = { destroy: function () {} }
  if (typeof document === 'undefined') return inert

  const root = resolveRoot(target)
  const range =
    root.matches && root.matches(cfg.rangeSelector)
      ? root
      : root.querySelector(cfg.rangeSelector)
  const readout = root.querySelector(cfg.readoutSelector)

  // /parents has neither. Mount nothing, inject nothing, throw nothing.
  if (!range && !readout) return inert

  const style = ensureStyle()

  /* ── one: the tick ──────────────────────────────────────────────────── */

  let tick = null
  let host = null

  if (range) {
    const min = numAttr(range, 'min')
    const max = numAttr(range, 'max')
    const frac = (cfg.threshold - min) / (max - min)

    // Failure mode: if the bounds cannot be read as numbers — or the threshold
    // falls outside them — the tick is not drawn at all. A tick pinned to an
    // end, or guessed from a default range, misstates where the fee begins,
    // and that is worse than no tick.
    if (Number.isFinite(frac) && frac >= 0 && frac <= 1) {
      host = range.parentElement
      if (host) {
        const geo = measure(range)
        if (geo) {
          host.style.setProperty('--fx-th-track', geo.track + 'px')
          host.style.setProperty('--fx-th-thumb', geo.thumb + 'px')
        }

        const label =
          cfg.label != null
            ? String(cfg.label)
            : '$' + Number(cfg.threshold).toLocaleString('en-US') + ' / 30 days'

        tick = document.createElement('div')
        tick.className = 'fx-threshold__tick'
        // The slider announces its own value; a floating duplicate label is
        // noise in a screen reader, and the readout already says it in words.
        tick.setAttribute('aria-hidden', 'true')
        tick.setAttribute(
          'data-anchor',
          frac < 0.12 ? 'start' : frac > 0.88 ? 'end' : 'mid'
        )
        tick.style.setProperty('--fx-th-frac', String(frac))

        const mark = document.createElement('span')
        mark.className = 'fx-threshold__mark'
        const cap = document.createElement('span')
        cap.className = 'fx-threshold__label'
        cap.textContent = label

        tick.appendChild(mark)
        tick.appendChild(cap)
        host.setAttribute('data-fx-threshold', '')
        host.appendChild(tick)
      }
    }
  }

  /* ── two: the switch ────────────────────────────────────────────────── */

  /* The page's own copy, if the markup hands it over. With both strings in
     hand the module owns the throw outright and does not care whether site.js
     is alive; without them it learns as it goes (below). */
  const text = {
    over:
      cfg.overText != null
        ? String(cfg.overText)
        : readout && readout.dataset.thresholdOver != null
          ? readout.dataset.thresholdOver
          : null,
    under:
      cfg.underText != null
        ? String(cfg.underText)
        : readout && readout.dataset.thresholdUnder != null
          ? readout.dataset.thresholdUnder
          : null,
  }
  const slot = function (over) {
    return over ? 'over' : 'under'
  }
  const otherSlot = function (over) {
    return over ? 'under' : 'over'
  }

  /* The page ships its own two strings and site.js keeps writing them — that
     is the JS-fails floor and it stays. We read each one once, so that if the
     floor ever goes out from under us we can still throw the readout
     ourselves. If the text still says what the *other* state says, nobody
     rewrote it, so there is nothing true to learn. */
  function learn(over) {
    if (!readout) return
    const t = (readout.textContent || '').trim()
    if (!t) return
    const mine = text[slot(over)]
    const theirs = text[otherSlot(over)]
    if (mine == null) {
      // Nothing known for this state. If the screen still says what the other
      // state says, whoever writes this text has not run yet on this tick and
      // there is nothing true to learn.
      if (t !== theirs) text[slot(over)] = t
      return
    }
    // This state is already known and the screen disagrees, which means we are
    // reading the state we just left. That is the only chance to learn its
    // string when site.js writes after us instead of before us — without this
    // branch a listener-order flip leaves the module able to throw the readout
    // in one direction only, forever.
    if (t !== mine && theirs == null) text[otherSlot(over)] = t
  }

  function apply(over) {
    if (!readout) return
    readout.setAttribute('data-fx-threshold-over', over ? 'true' : 'false')
    const want = text[slot(over)]
    if (want != null && (readout.textContent || '').trim() !== want) {
      readout.textContent = want
    }
  }

  let last = null

  if (readout) {
    readout.setAttribute('data-fx-threshold-readout', '')
    // Seed from the instrument, not from an event: if ledger-bus never mounts,
    // the readout is already in the right state and simply never moves.
    if (range) {
      const v = Number(range.value)
      if (Number.isFinite(v)) {
        last = v >= cfg.threshold
        learn(last)
        apply(last)
      }
    }
  }

  function onFee(e) {
    const d = e && e.detail
    if (!d || typeof d.over === 'undefined') return
    const over = !!d.over

    if (last === null) {
      last = over
      learn(over)
      apply(over)
      return
    }
    // Frequency-appropriate motion: this element updates on every keystroke of
    // a drag and has exactly two states. Only a crossing is news.
    if (over === last) return
    last = over
    learn(over)
    apply(over)
  }

  document.addEventListener(cfg.eventName, onFee)

  // The style sheet is shared and ref-counted, so a second destroy() on this
  // handle would decrement someone else's count and pull the sheet out from
  // under a live instance. Teardown happens once.
  let dead = false

  return {
    destroy: function () {
      if (dead) return
      dead = true
      document.removeEventListener(cfg.eventName, onFee)
      if (tick && tick.parentNode) tick.parentNode.removeChild(tick)
      // Our tick is gone by now, so anything still in there belongs to another
      // instance mounted on the same slider. Pulling the attribute would strip
      // that tick's containing block and its measured geometry and throw it
      // across the page, which is exactly the kind of tidy-up that only shows
      // up in production.
      if (host && !host.querySelector('.fx-threshold__tick')) {
        host.removeAttribute('data-fx-threshold')
        host.style.removeProperty('--fx-th-track')
        host.style.removeProperty('--fx-th-thumb')
      }
      if (readout) {
        readout.removeAttribute('data-fx-threshold-readout')
        readout.removeAttribute('data-fx-threshold-over')
      }
      releaseStyle(style)
    },
  }
}
