/* fx/rows.js — the register.
 *
 * Four ways of getting paid, crossed off a list, in front of you.
 *
 * Three beats per row, in causal order: the hairline rule draws left → right,
 * the inline SVG icon strokes itself in, then a rule is struck through the
 * method label. `'plain'` mode is the rule alone — the money band and the
 * parents ledger get the draw and nothing else, because a price table that
 * performs is a price table that is selling you something.
 *
 * The motion is the copy, executed. A line drawing wants to be drawn and a
 * rejected option wants to be crossed out.
 *
 * Final state — rules present, icons drawn, labels struck — is the CSS
 * default. Every pre-state, the icon's included, lives behind
 * [data-fx-rows-state='armed'], an attribute written only after this module has
 * confirmed that reduced motion is off AND that its IntersectionObserver
 * actually bound, and torn back off by a watchdog if the observer never speaks.
 * A JS error, a print stylesheet, a text-mode reader and a non-scrolling
 * renderer all produce the complete argument.
 *
 * The mount attribute is the MARKUP's, not ours: `data-fx-rows="strike"` in the
 * page declares the mode. We read it, we never treat it as a mounted flag, and
 * we hand it back untouched on destroy.
 *
 * One IntersectionObserver, one shot, then unobserve. No per-frame callback.
 */

import { getStage } from 'cwe/stage'

const NAME = 'rows'
const ATTR = 'data-fx-rows'
const STATE = 'data-fx-rows-state'
const OWNS_RULE = 'data-fx-rows-rule'

/* The mount flag cannot be ATTR: the page markup already ships
   `data-fx-rows="strike"` / `="plain"` to declare the mode, so an
   `if (root.hasAttribute(ATTR)) return` guard bails on every real mount. */
const MOUNTED = typeof WeakSet === 'function' ? new WeakSet() : null

const DEFAULTS = {
  mode: 'strike', // 'strike' | 'plain'
  ruleMs: 240, // 200 in 'plain' mode unless the caller says otherwise
  iconMs: 320,
  strikeMs: 240,
  strikeDelay: 60,
  stagger: 60,

  // 'auto'   — draw a rule only where the markup already rules the row
  //            (a measurable border on either edge, bottom preferred). Never
  //            invents a line the design did not ask for, never doubles one
  //            it did.
  // 'always' — draw one regardless, in the ground's hairline token.
  // 'never'  — skip the rule beat.
  rule: 'auto',

  rowSelector: null,
  labelSelector: null,
  iconSelector: null,

  threshold: 0.15,
  rootMargin: '0px 0px -8% 0px',
  watchdogMs: 1500,
}

const ROW_CANDIDATES = ['[data-fx-row]', '.card--row', '.price--row', '.card']
const LABEL_CANDIDATES = [
  '[data-fx-row-label]',
  '.card__label',
  '.h4',
  'h3',
  'h4',
]
const ICON_CANDIDATES = ['.icon', 'svg']
const SHAPES = 'path, line, polyline, polygon, circle, ellipse, rect'

/* ── one stylesheet, once ─────────────────────────────────────────────────
   Everything below states the FINAL composition. The armed pre-state lives
   behind [data-fx-rows-state='armed'], an attribute only ever written by a
   module that has already proved it can animate. Both the reduced-motion and
   the print block are later in the sheet at equal specificity, so they win
   without needing a single override flag. */
const CSS = `
[${ATTR}] .fx-${NAME}__row { position: relative; }

[${ATTR}] .fx-${NAME}__row[${OWNS_RULE}='top'] { border-top-color: transparent; }
[${ATTR}] .fx-${NAME}__row[${OWNS_RULE}='bottom'] {
  border-bottom-color: transparent;
}
[${ATTR}] .fx-${NAME}__row[${OWNS_RULE}]::before {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  top: var(--fx-${NAME}-top, 0px);
  height: var(--fx-${NAME}-bw, 1px);
  background: var(--fx-${NAME}-hair, currentColor);
  transform: scaleX(1);
  transform-origin: 0 50%;
  pointer-events: none;
}
[${ATTR}][${STATE}='in'] .fx-${NAME}__row[${OWNS_RULE}]::before {
  transition: transform var(--fx-${NAME}-rule-ms) var(--fx-${NAME}-ease)
    var(--fx-${NAME}-d-rule, 0ms);
}
[${ATTR}][${STATE}='armed'] .fx-${NAME}__row[${OWNS_RULE}]::before {
  transform: scaleX(0);
}

/* Drawn is the default here too. The dash OFFSET — the only value that can
   hide a path — is set by the armed selector and nothing else, so an icon
   cannot be left blank by a print, a stalled trigger or a thrown error the way
   an inline pre-state would leave it. The dasharray is inline and harmless:
   with offset 0 the stroke renders whole. */
[${ATTR}] .fx-${NAME}__icon * { stroke-dashoffset: 0; }
[${ATTR}][${STATE}='in'] .fx-${NAME}__icon * {
  transition: stroke-dashoffset var(--fx-${NAME}-icon-ms) linear
    var(--fx-${NAME}-d-icon, 0ms);
}
[${ATTR}][${STATE}='armed'] .fx-${NAME}__icon * {
  stroke-dashoffset: var(--fx-${NAME}-len, 0);
}

[${ATTR}='strike'] .fx-${NAME}__label {
  background-image: linear-gradient(currentColor, currentColor);
  background-repeat: no-repeat;
  background-position: 0 var(--fx-${NAME}-strike-y);
  background-size: 100% var(--fx-${NAME}-strike-w);
  -webkit-box-decoration-break: clone;
  box-decoration-break: clone;
}
[${ATTR}='strike'][${STATE}='in'] .fx-${NAME}__label {
  transition: background-size var(--fx-${NAME}-strike-ms) var(--fx-${NAME}-ease)
    var(--fx-${NAME}-d-strike, 0ms);
}
[${ATTR}='strike'][${STATE}='armed'] .fx-${NAME}__label {
  background-size: 0% var(--fx-${NAME}-strike-w);
}

@media (prefers-reduced-motion: reduce) {
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__row[${OWNS_RULE}]::before {
    transform: scaleX(1);
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__icon * {
    stroke-dashoffset: 0;
  }
  [${ATTR}='strike'][${STATE}='armed'] .fx-${NAME}__label {
    background-size: 100% var(--fx-${NAME}-strike-w);
  }
}

@media print {
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__row[${OWNS_RULE}]::before {
    transform: scaleX(1);
  }
  [${ATTR}][${STATE}='armed'] .fx-${NAME}__icon * {
    stroke-dashoffset: 0;
  }
  [${ATTR}='strike'][${STATE}='armed'] .fx-${NAME}__label {
    background-size: 100% var(--fx-${NAME}-strike-w);
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
  return { destroy: function () {}, reveal: function () {}, rows: 0 }
}

/* First selector that actually matches wins, so the module works on today's
   `.card` markup and on the `.card--row` variant that replaces it without a
   config change on either side. */
function pick(root, explicit, candidates) {
  if (explicit) {
    const found = root.querySelectorAll(explicit)
    return found.length ? Array.prototype.slice.call(found) : []
  }
  for (let i = 0; i < candidates.length; i++) {
    const found = root.querySelectorAll(candidates[i])
    if (found.length) return Array.prototype.slice.call(found)
  }
  return []
}

function pickOne(row, explicit, candidates) {
  const list = explicit ? [explicit] : candidates
  for (let i = 0; i < list.length; i++) {
    const el = row.querySelector(list[i])
    if (el) return el
  }
  return null
}

/* Which ground is this row sitting on? Only consulted for `rule: 'always'`,
   where there is no border colour to inherit. Colours come from the tokens,
   never from a literal. */
function isDarkGround(el) {
  let n = el
  while (n) {
    const parts = getComputedStyle(n).backgroundColor.match(/[\d.]+/g)
    if (
      parts &&
      parts.length >= 3 &&
      (parts.length < 4 || Number(parts[3]) > 0.5)
    ) {
      const lum =
        (0.2126 * Number(parts[0]) +
          0.7152 * Number(parts[1]) +
          0.0722 * Number(parts[2])) /
        255
      return lum < 0.5
    }
    n = n.parentElement
  }
  return false
}

export function initRows(target, config) {
  if (typeof document === 'undefined') return inert()

  const root =
    typeof target === 'string' ? document.querySelector(target) : target
  if (!root || root.nodeType !== 1) return inert()
  if (MOUNTED && MOUNTED.has(root)) return inert() // already mounted

  const cfg = Object.assign({}, DEFAULTS, config || {})

  /* `data-fx-rows="plain"` in the page is the author declaring the mode, the
     same way `data-split-mode` is. An explicit config wins; the markup is the
     fallback; DEFAULTS is the floor. Whatever the author wrote is remembered
     and handed back on destroy. */
  const hadAttr = root.hasAttribute(ATTR)
  const priorAttr = hadAttr ? root.getAttribute(ATTR) : null
  const declared = hadAttr ? (priorAttr || '').trim() : ''
  const asked = config && config.mode ? config.mode : declared || DEFAULTS.mode
  const mode = asked === 'plain' ? 'plain' : 'strike'
  cfg.mode = mode
  // The money band and the parents ledger get 200ms and 60ms and nothing else.
  if (mode === 'plain' && !(config && config.ruleMs !== undefined))
    cfg.ruleMs = 200

  const rows = pick(root, cfg.rowSelector, ROW_CANDIDATES)
  if (!rows.length) return inert()

  const stage = getStage()
  const cs = getComputedStyle(document.documentElement)
  const ease = cs.getPropertyValue('--ease').trim() || 'ease-out'
  const hairLight = cs.getPropertyValue('--hair').trim()
  const hairDark = cs.getPropertyValue('--on-dark-faint').trim()

  injectOnce()

  if (MOUNTED) MOUNTED.add(root)
  root.setAttribute(ATTR, mode)
  root.style.setProperty('--fx-' + NAME + '-ease', ease)
  root.style.setProperty('--fx-' + NAME + '-rule-ms', cfg.ruleMs + 'ms')
  root.style.setProperty('--fx-' + NAME + '-icon-ms', cfg.iconMs + 'ms')
  root.style.setProperty('--fx-' + NAME + '-strike-ms', cfg.strikeMs + 'ms')
  root.style.setProperty('--fx-' + NAME + '-strike-w', '1.5px')
  root.style.setProperty('--fx-' + NAME + '-strike-y', '56%')

  /* ── measure each row once, decide which beats it actually has ────────── */

  const entries = []
  let settleMs = 0

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i]
    row.classList.add('fx-' + NAME + '__row')

    const rowStyle = getComputedStyle(row)
    const btw = parseFloat(rowStyle.borderTopWidth) || 0
    const bbw = parseFloat(rowStyle.borderBottomWidth) || 0

    /* Which edge did the design actually draw? A converted `.card--row` rules
       itself with a border-BOTTOM — the container owns the set's top edge — so
       probing only border-top finds nothing on every row on the site and the
       rule beat, which is the ONLY beat 'plain' mode has, silently never runs.
       Bottom first, because in a stacked ledger the rule under the row is the
       one that reads as the row's own. */
    const side = bbw >= 0.5 ? 'bottom' : btw >= 0.5 ? 'top' : null

    // In 'auto' we take ownership only of a rule the markup already draws, so
    // an unconverted `.card` (a full inset ring, no border at all) is left
    // exactly as designed instead of gaining a stray line.
    let hasRule = false
    if (cfg.rule === 'always' || (cfg.rule === 'auto' && side)) {
      hasRule = true
      const owned = side || 'bottom'
      const w = side === 'bottom' ? bbw : side === 'top' ? btw : 1
      row.style.setProperty('--fx-' + NAME + '-bw', w + 'px')
      // The pseudo-element is positioned off the padding box: a top rule sits
      // one border-width above it, a bottom rule starts exactly at 100%.
      row.style.setProperty(
        '--fx-' + NAME + '-top',
        owned === 'top' ? -w + 'px' : '100%'
      )
      row.style.setProperty(
        '--fx-' + NAME + '-hair',
        side === 'bottom'
          ? rowStyle.borderBottomColor
          : side === 'top'
            ? rowStyle.borderTopColor
            : isDarkGround(row)
              ? hairDark
              : hairLight
      )
      row.setAttribute(OWNS_RULE, owned)
    }

    // Icon. The paths already exist in the markup, so this costs nothing —
    // unless they have no measurable length, in which case the beat is
    // dropped and the row keeps its rule and its strike.
    const shapes = []
    if (mode === 'strike') {
      const icon = pickOne(row, cfg.iconSelector, ICON_CANDIDATES)
      if (icon) {
        const nodes = icon.querySelectorAll(SHAPES)
        for (let s = 0; s < nodes.length; s++) {
          const node = nodes[s]
          let len = 0
          try {
            if (typeof node.getTotalLength === 'function')
              len = node.getTotalLength()
          } catch (e) {
            len = 0
          }
          if (!Number.isFinite(len) || len <= 0) continue
          if (getComputedStyle(node).stroke === 'none') continue
          shapes.push({ node: node, len: len })
        }
        if (shapes.length) icon.classList.add('fx-' + NAME + '__icon')
      }
    }

    // Strike. All children move into one inline span so the rule crosses the
    // text and not the block, and so a label that wraps gets a strike on each
    // line rather than one bar across the whitespace.
    let label = null
    if (mode === 'strike') {
      const host = pickOne(row, cfg.labelSelector, LABEL_CANDIDATES)
      if (host && host.firstChild) {
        label = document.createElement('span')
        label.className = 'fx-' + NAME + '__label'
        while (host.firstChild) label.appendChild(host.firstChild)
        host.appendChild(label)
      }
    }

    const base = i * cfg.stagger
    const dRule = base
    const dIcon = base + (hasRule ? cfg.ruleMs : 0)
    const dStrike = dIcon + (shapes.length ? cfg.iconMs : 0) + cfg.strikeDelay

    row.style.setProperty('--fx-' + NAME + '-d-rule', dRule + 'ms')
    row.style.setProperty('--fx-' + NAME + '-d-icon', dIcon + 'ms')
    row.style.setProperty('--fx-' + NAME + '-d-strike', dStrike + 'ms')

    let end = hasRule ? dRule + cfg.ruleMs : base
    if (shapes.length) end = Math.max(end, dIcon + cfg.iconMs)
    if (label) end = Math.max(end, dStrike + cfg.strikeMs)
    if (end > settleMs) settleMs = end

    entries.push({
      row: row,
      shapes: shapes,
      label: label,
      host: label && label.parentNode,
    })
  }

  /* ── the two states ───────────────────────────────────────────────────── */

  let armed = false
  let settled = false
  let settleTimer = 0
  let watchdog = 0

  function arm() {
    for (let i = 0; i < entries.length; i++) {
      const shapes = entries[i].shapes
      for (let s = 0; s < shapes.length; s++) {
        // Dasharray alone cannot hide a path. The offset that can is applied
        // by the armed selector, so it comes off with the attribute.
        shapes[s].node.style.strokeDasharray = shapes[s].len + 'px'
        shapes[s].node.style.setProperty(
          '--fx-' + NAME + '-len',
          shapes[s].len + 'px'
        )
      }
    }
    root.setAttribute(STATE, 'armed')
    void root.offsetWidth // flush, so the reveal is a transition and not a jump
    armed = true
  }

  // Strip every trace of the animation and leave the finished composition:
  // the rules present, the icons drawn, the labels struck.
  function settle() {
    if (settled) return
    settled = true
    if (settleTimer) clearTimeout(settleTimer)
    settleTimer = 0
    // Attribute first: the pre-state is gone before the props it read are.
    root.removeAttribute(STATE)
    for (let i = 0; i < entries.length; i++) {
      const shapes = entries[i].shapes
      for (let s = 0; s < shapes.length; s++) {
        shapes[s].node.style.strokeDasharray = ''
        shapes[s].node.style.removeProperty('--fx-' + NAME + '-len')
      }
    }
    armed = false
  }

  function reveal() {
    if (settled) return
    if (!armed) {
      settle()
      return
    }
    // One attribute flip runs all three beats: dropping 'armed' returns the
    // rule to scaleX(1), the label to 100% and the dash offset to 0, and the
    // 'in' block supplies the transition for each.
    root.setAttribute(STATE, 'in')
    if (settleTimer) clearTimeout(settleTimer)
    settleTimer = setTimeout(settle, settleMs + 80)
  }

  /* ── the trigger: one observer, one shot ──────────────────────────────── */

  let io = null
  let spoke = false

  function onIntersect(list) {
    if (!spoke) {
      spoke = true
      if (watchdog) clearTimeout(watchdog)
      watchdog = 0
    }
    for (let i = 0; i < list.length; i++) {
      if (!list[i].isIntersecting) continue
      if (io) {
        io.disconnect()
        io = null
      }
      reveal()
      return
    }
  }

  const canAnimate =
    !stage.reducedMotion && typeof IntersectionObserver === 'function'

  if (canAnimate) {
    try {
      io = new IntersectionObserver(onIntersect, {
        threshold: cfg.threshold,
        rootMargin: cfg.rootMargin,
      })
      for (let i = 0; i < entries.length; i++) io.observe(entries[i].row)
      arm() // only now: motion confirmed, trigger bound
      // An observer that never delivers a single callback — not even the
      // initial non-intersecting one — is a broken trigger, and a broken
      // trigger must not be allowed to hold the argument off the page.
      watchdog = setTimeout(function () {
        watchdog = 0
        if (!spoke) settle()
      }, cfg.watchdogMs)
    } catch (e) {
      if (io) {
        io.disconnect()
        io = null
      }
      settle()
    }
  }

  // The OS setting can flip mid-scroll. If it does, land immediately.
  const rmq = matchMedia('(prefers-reduced-motion: reduce)')
  function onReduced(e) {
    if (!e.matches) return
    if (io) {
      io.disconnect()
      io = null
    }
    settle()
  }
  if (rmq.addEventListener) rmq.addEventListener('change', onReduced)

  return {
    rows: entries.length,
    reveal: reveal,
    destroy: function () {
      if (io) {
        io.disconnect()
        io = null
      }
      if (watchdog) clearTimeout(watchdog)
      if (settleTimer) clearTimeout(settleTimer)
      watchdog = 0
      settleTimer = 0
      settled = true
      if (rmq.removeEventListener) rmq.removeEventListener('change', onReduced)

      for (let i = 0; i < entries.length; i++) {
        const e = entries[i]
        const shapes = e.shapes
        for (let s = 0; s < shapes.length; s++) {
          shapes[s].node.style.strokeDasharray = ''
          shapes[s].node.style.strokeDashoffset = ''
          shapes[s].node.style.removeProperty('--fx-' + NAME + '-len')
        }
        if (e.label && e.host) {
          while (e.label.firstChild) e.host.appendChild(e.label.firstChild)
          if (e.label.parentNode === e.host) e.host.removeChild(e.label)
        }
        const icon = e.row.querySelector('.fx-' + NAME + '__icon')
        if (icon) icon.classList.remove('fx-' + NAME + '__icon')
        e.row.classList.remove('fx-' + NAME + '__row')
        e.row.removeAttribute(OWNS_RULE)
        e.row.style.removeProperty('--fx-' + NAME + '-bw')
        e.row.style.removeProperty('--fx-' + NAME + '-top')
        e.row.style.removeProperty('--fx-' + NAME + '-hair')
        e.row.style.removeProperty('--fx-' + NAME + '-d-rule')
        e.row.style.removeProperty('--fx-' + NAME + '-d-icon')
        e.row.style.removeProperty('--fx-' + NAME + '-d-strike')
      }

      root.removeAttribute(STATE)
      // The mode attribute is the page's, not ours. Give it back as written.
      if (hadAttr) root.setAttribute(ATTR, priorAttr)
      else root.removeAttribute(ATTR)
      if (MOUNTED) MOUNTED.delete(root)
      root.style.removeProperty('--fx-' + NAME + '-ease')
      root.style.removeProperty('--fx-' + NAME + '-rule-ms')
      root.style.removeProperty('--fx-' + NAME + '-icon-ms')
      root.style.removeProperty('--fx-' + NAME + '-strike-ms')
      root.style.removeProperty('--fx-' + NAME + '-strike-w')
      root.style.removeProperty('--fx-' + NAME + '-strike-y')
    },
  }
}
