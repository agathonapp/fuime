/* fx/handoff.js — the loader stops being a curtain and becomes the chrome.
 *
 * Three things, in order.
 *
 *   1. The receipt. Three ruled lines beside the filling arch, each one landing
 *      as that manifest step actually resolves, with the real transferred size
 *      beside it. Same-origin resources report bytes. Cross-origin faces with no
 *      Timing-Allow-Origin, and cache hits, genuinely report zero — those read
 *      `OK`. Nothing here ever prints a fabricated number and nothing prints
 *      `0 KB`.
 *
 *   2. The FLIP. At loader completion the filled arch travels to the nav mark's
 *      measured rect and scales to fit. Nothing fades. The wordmark follows to
 *      the nav wordmark and the receipt collapses rightward into the nav.
 *
 *   3. The LCP-safe reveal. The hero <img> is already painted, full size,
 *      unmasked, untransformed, and is never animated. What animates is a
 *      night-coloured, arch-shaped scrim above it that shrinks away, blurred for
 *      the first 180ms so the moving edge has no seam.
 *
 * It reads site.js's output and never its source: site.js sets data-done on
 * #boot when its manifest completes, and a MutationObserver on that attribute is
 * the entire hook. No source change anywhere else.
 *
 * Failure is planned for, not hoped against. The FLIP runs in the same stacking
 * context as the fixed nav, and style.css already carries the warning that a
 * transform in the wrong place turns the nav's containing block into an animated
 * element and drops it out of the viewport. So the module measures the nav one
 * frame after the transform lands, and if the nav moved it reverts the travel on
 * the spot and downgrades to opacity plus scale(1.02 → 1.00) on the hero media,
 * receipt still collapsing. If the nav mark cannot be measured at all there is no
 * FLIP and the loader cross-dissolves. The animation is allowed to not happen.
 * A white flash and a black hole are not.
 */

import { getStage } from 'cwe/stage'

const NAME = 'handoff'
const ATTR = 'data-fx-handoff'
const SETTLED = 'data-fx-handoff-settled'
const HERO_ATTR = 'data-fx-handoff-hero'

const DEFAULTS = {
  markSelector: '.mark__glyph',
  flipMs: 620,
  easing: 'var(--ease)',
  receipt: true,
  blurMask: 6,

  bootSelector: '#boot',
  archSelector: '.boot__arch',
  wordSelector: '.boot__word',
  navSelector: '.nav',
  navInnerSelector: '.nav__in',
  navWordSelector: '.nav .mark > span',
  heroSelector: '.hero__media',
  imgSelector: '.hero__media img',

  /* The receipt is not allowed to wait forever for a step that is never going
     to resolve; past this it prints what it has and shows every row. */
  receiptCapMs: 1400,
  okText: 'OK',
  rows: [
    { key: 'fonts', label: 'Typefaces' },
    { key: 'photo', label: 'Photograph' },
    { key: 'rest', label: 'Everything else' },
  ],
}

/* ── the stylesheet ─────────────────────────────────────────────────────────
   Injected once. Every selector is either .fx-handoff__* or sits under the
   [data-fx-handoff] attribute this module puts on <html> itself, so nothing
   here can reach a page that did not opt in.

   The default state of every animated thing below is its FINAL state. Motion is
   added by moving [data-fx-handoff] from "still" to "motion" to "flip", and each
   of those steps only happens after the measurement it depends on has already
   succeeded. A throw at any point leaves the page complete. */
function css(cfg) {
  return `
[${ATTR}] .fx-${NAME}__receipt {
  position: absolute;
  left: 50%;
  top: calc(25% + 57px);
  transform: translateX(-50%);
  transform-origin: 100% 50%;
  width: min(300px, calc(100% - var(--gut) * 2));
  display: grid;
  gap: var(--s2);
  pointer-events: none;
  clip-path: inset(0 0 0 0);
}
[${ATTR}] .fx-${NAME}__row {
  display: flex;
  align-items: baseline;
  gap: var(--s2);
  font-size: var(--t-small);
  letter-spacing: 0.42px;
}
[${ATTR}] .fx-${NAME}__label {
  color: var(--on-dark-mu);
  white-space: nowrap;
}
[${ATTR}] .fx-${NAME}__leader {
  flex: 1 1 auto;
  min-width: var(--s5);
  border-bottom: 1px dotted var(--on-dark-faint);
  transform: translateY(-0.28em);
}
[${ATTR}] .fx-${NAME}__fig {
  color: var(--on-dark);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

/* Motion, opted into. A row is hidden only once its trigger is bound and a
   timer is running that will show it regardless. */
[${ATTR}='motion'] .fx-${NAME}__row,
[${ATTR}='flip'] .fx-${NAME}__row,
[${ATTR}='dissolve'] .fx-${NAME}__row {
  transition:
    opacity 260ms var(--ease),
    transform 260ms var(--ease);
}
[${ATTR}='motion'] .fx-${NAME}__row[data-pending='true'],
[${ATTR}='flip'] .fx-${NAME}__row[data-pending='true'],
[${ATTR}='dissolve'] .fx-${NAME}__row[data-pending='true'] {
  opacity: 0;
  transform: translateY(6px);
}

/* The scrim. Night, viewport-sized, above the page and below the travelling
   arch. Its arched top edge sweeps down and the layer shrinks to nothing.

   Its default here is its FINAL state — gone. Covering the viewport is an
   attribute the module writes and then removes, never a CSS default, because a
   scrim whose default is "opaque night over everything" is a black hole waiting
   for one throw between creating it and animating it. This way the worst case
   for an error anywhere after creation is a page that was never covered. */
[${ATTR}] .fx-${NAME}__scrim {
  position: fixed;
  inset: 0;
  z-index: 998;
  background: var(--night);
  pointer-events: none;
  clip-path: inset(100% 0 0 0 round var(--r-arch, 6vw) var(--r-arch, 6vw) 0 0);
  filter: blur(0px);
  transition:
    clip-path ${cfg.flipMs}ms ${cfg.easing},
    filter 180ms linear;
  /* style.css fades every body child in over 760ms once .boot-out lands. That
     rule carries an id in a :not(), so !important is the only way past it, and
     the scrim is the one element on the page that must not be faded in. */
  animation: none !important;
}
[${ATTR}] .fx-${NAME}__scrim[data-cover='true'] {
  clip-path: inset(0 0 0 0 round var(--r-arch, 6vw) var(--r-arch, 6vw) 0 0);
  filter: blur(${Math.max(0, Number(cfg.blurMask) || 0)}px);
}

/* The takeover. Only while the scrim is real and the transforms are applied:
   the loader stops fading, because the scrim is now the thing that leaves. */
[${ATTR}='flip'] ${cfg.bootSelector}[data-done='true'] {
  opacity: 1;
  visibility: visible;
  background: transparent;
  transition: none;
}
/* And the page underneath does not fade in, because it was never covered by
   anything but the scrim and the hero photograph is already painted. */
[${ATTR}][${SETTLED}] body > *:not(${cfg.bootSelector}) {
  animation: none !important;
}

/* The travel. Distances are measured and written inline; this is only the
   transition that carries them. */
[${ATTR}='flip'] ${cfg.bootSelector}[data-done='true'] ${cfg.archSelector},
[${ATTR}='flip'] ${cfg.bootSelector}[data-done='true'] ${cfg.wordSelector} {
  transform-origin: 0 0;
}

/* Downgraded mid-flight: the travel is reverted and the loader leaves quickly
   instead. The scrim is untouched — it is not an ancestor of the nav and cannot
   be what broke. */
[${ATTR}='dissolve'] ${cfg.bootSelector}[data-done='true'] {
  opacity: 0;
  visibility: hidden;
  background: transparent;
  transition:
    opacity 180ms var(--ease),
    visibility 0s linear 180ms;
}
[${ATTR}='dissolve'] ${cfg.bootSelector}[data-done='true'] ${cfg.archSelector},
[${ATTR}='dissolve'] ${cfg.bootSelector}[data-done='true'] ${cfg.wordSelector} {
  transform: none;
  transition: transform 180ms var(--ease);
}
[${ATTR}] [${HERO_ATTR}='run'] {
  animation: fx-${NAME}-hero ${cfg.flipMs}ms var(--ease) both;
}
@keyframes fx-${NAME}-hero {
  from {
    opacity: 0;
    transform: scale(1.02);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

/* Reduced motion, and every downgrade that ends in a cross-dissolve: the arch is
   already full, the receipt is already complete and real, and the loader leaves
   in 120ms with no travel. The visitor loses the camera move, not the idea. */
[${ATTR}='still'] ${cfg.bootSelector}[data-done='true'] {
  transition:
    opacity 120ms linear,
    visibility 0s linear 120ms;
}
[${ATTR}='still'] ${cfg.bootSelector}[data-done='true'] ${cfg.archSelector},
[${ATTR}='still'] ${cfg.bootSelector}[data-done='true'] ${cfg.wordSelector} {
  transform: none;
  transition: none;
}
@media (prefers-reduced-motion: reduce) {
  [${ATTR}] .fx-${NAME}__row,
  [${ATTR}] .fx-${NAME}__receipt,
  [${ATTR}] .fx-${NAME}__scrim {
    transition-duration: 1ms;
  }
  [${ATTR}] [${HERO_ATTR}='run'] {
    animation-duration: 1ms;
  }
}
`
}

function injectCSS(cfg) {
  if (document.querySelector(`style[data-fx="${NAME}"]`)) return
  const style = document.createElement('style')
  style.setAttribute('data-fx', NAME)
  style.textContent = css(cfg)
  document.head.appendChild(style)
}

/* ── bytes ─────────────────────────────────────────────────────────────────
   Resource Timing hands out encodedBodySize for same-origin resources and for
   cross-origin ones that send Timing-Allow-Origin. The Fontshare faces send
   neither, and a warm cache reports zero for everything. Both cases are real
   answers, not missing data, and both print OK. */

function sameOrigin(url) {
  try {
    return new URL(url, location.href).origin === location.origin
  } catch (e) {
    return false
  }
}

function resources() {
  try {
    return performance.getEntriesByType('resource') || []
  } catch (e) {
    return []
  }
}

function isFont(entry) {
  return /\.(woff2?|otf|ttf)(\?|#|$)/i.test(entry.name)
}

function bytesOf(entry) {
  if (!entry || !sameOrigin(entry.name)) return 0
  const n = Number(entry.encodedBodySize)
  return Number.isFinite(n) && n > 0 ? n : 0
}

function format(bytes, okText) {
  if (!bytes || bytes <= 0) return okText
  if (bytes < 1024) return bytes + ' B'
  return Math.round(bytes / 1024) + ' KB'
}

/* ── module ────────────────────────────────────────────────────────────────*/

export function initHandoff(a, b) {
  /* The section spec writes initHandoff(config); the house constraint writes
     init<Name>(target, config). Both call sites work. */
  const twoArg =
    b !== undefined ||
    typeof a === 'string' ||
    (a && typeof a === 'object' && a.nodeType === 1)
  const config = (twoArg ? b : a) || {}
  const cfg = Object.assign({}, DEFAULTS, config)
  if (config.rows) cfg.rows = config.rows

  const root = document.documentElement
  const boot = document.querySelector(cfg.bootSelector)

  const timers = []
  const offs = []
  let receipt = null
  let scrim = null
  let observer = null
  let ownsReceipt = false
  let done = false
  let destroyed = false

  const later = (fn, ms) => {
    timers.push(setTimeout(fn, ms))
  }

  const inert = {
    destroy() {},
    get tier() {
      return 'none'
    },
  }

  /* Nothing to hand off from: no loader on the page, a loader that has already
     finished, or a returning visitor who never saw one. */
  if (
    !boot ||
    boot.hasAttribute('hidden') ||
    boot.getAttribute('data-done') === 'true' ||
    root.classList.contains('booted')
  ) {
    return inert
  }

  const stage = config.stage || getStage()
  const reduced = !!stage.reducedMotion

  /* If style.css never arrived, --night is empty, and a scrim painted in
     nothing is a white flash. That is the one outcome this module exists to
     prevent, so in that case it does not run at all. */
  const night = getComputedStyle(root).getPropertyValue('--night').trim()

  injectCSS(cfg)

  const arch = boot.querySelector(cfg.archSelector)
  const word = boot.querySelector(cfg.wordSelector)
  const glyph = document.querySelector(cfg.navSelector + ' ' + cfg.markSelector)
  const navIn = document.querySelector(
    cfg.navSelector + ' ' + cfg.navInnerSelector
  )
  const navWord = document.querySelector(cfg.navWordSelector)
  const hero = document.querySelector(cfg.heroSelector)

  const measurable = el => {
    if (!el) return null
    const r = el.getBoundingClientRect()
    return r.width > 0 && r.height > 0 ? r : null
  }

  /* Decided before anything moves: can the FLIP be measured at all? A nav that
     has not laid out yet gives a 0×0 mark, and there is no destination to fly
     to. That is a cross-dissolve, decided now rather than mid-flight. */
  const canFlip = !reduced && !!night && !!arch && !!measurable(glyph)
  let tier = canFlip ? 'flip' : 'still'

  root.setAttribute(ATTR, canFlip ? 'motion' : 'still')

  /* ── the receipt ─────────────────────────────────────────────────────── */

  const cells = {}

  function buildReceipt() {
    if (!cfg.receipt) return
    if (boot.querySelector('.fx-' + NAME + '__receipt')) return
    receipt = document.createElement('div')
    receipt.className = 'fx-' + NAME + '__receipt'
    /* #boot is role="status". Byte counts arriving in a live region would be
       read out one by one, which is not what a loading announcement is for. */
    receipt.setAttribute('aria-hidden', 'true')

    for (const row of cfg.rows) {
      const el = document.createElement('div')
      el.className = 'fx-' + NAME + '__row'
      el.setAttribute('data-row', row.key)

      const label = document.createElement('span')
      label.className = 'fx-' + NAME + '__label'
      label.textContent = row.label

      const leader = document.createElement('span')
      leader.className = 'fx-' + NAME + '__leader'

      const fig = document.createElement('span')
      fig.className = 'fx-' + NAME + '__fig'

      el.appendChild(label)
      el.appendChild(leader)
      el.appendChild(fig)
      receipt.appendChild(el)
      cells[row.key] = { row: el, fig: fig }

      /* Under reduced motion every row is present from the first frame and only
         its figure fills in. Under motion the row is hidden — but only here,
         after it exists and after the cap timer above is already running. */
      if (canFlip) el.setAttribute('data-pending', 'true')
    }

    /* Absolutely positioned on purpose. #boot is a grid whose auto rows stretch,
       so a third in-flow child would re-space the arch and the wordmark across
       the viewport. This sits outside that flow and moves nothing. */
    boot.appendChild(receipt)
    ownsReceipt = true
    placeReceipt()
  }

  /* Measured rather than guessed, so the receipt still sits under the arch if
     the loader's composition ever changes. The CSS default is the fallback. */
  function placeReceipt() {
    if (!receipt || !arch) return
    const a = arch.getBoundingClientRect()
    if (a.height <= 0) return
    receipt.style.top = Math.round(a.bottom + 32) + 'px'
  }

  function resolveRow(key, bytes) {
    const cell = cells[key]
    if (!cell) return
    cell.fig.textContent = format(bytes, cfg.okText)
    cell.row.removeAttribute('data-pending')
  }

  function showAllRows() {
    for (const key in cells) {
      if (!cells[key].fig.textContent) cells[key].fig.textContent = cfg.okText
      cells[key].row.removeAttribute('data-pending')
    }
  }

  function fontBytes() {
    let sum = 0
    for (const e of resources()) if (isFont(e)) sum += bytesOf(e)
    return sum
  }

  function photoEntry() {
    const img = document.querySelector(cfg.imgSelector)
    const src = img && (img.currentSrc || img.src)
    if (!src) return null
    for (const e of resources()) if (e.name === src) return e
    return null
  }

  function restBytes() {
    const img = document.querySelector(cfg.imgSelector)
    const src = (img && (img.currentSrc || img.src)) || ''
    let sum = 0
    for (const e of resources()) {
      if (isFont(e) || e.name === src) continue
      sum += bytesOf(e)
    }
    try {
      const nav = performance.getEntriesByType('navigation')[0]
      if (nav) sum += bytesOf(nav)
    } catch (e) {}
    return sum
  }

  /* The same three real events site.js waits on, observed independently. This
     module never reads site.js's progress, only the browser's. */
  function bindReceipt() {
    if (!cfg.receipt || !receipt) return

    const onFonts = () => resolveRow('fonts', fontBytes())
    if (document.fonts && document.fonts.ready)
      document.fonts.ready.then(onFonts).catch(onFonts)
    else onFonts()

    const img = document.querySelector(cfg.imgSelector)
    const onPhoto = () => resolveRow('photo', bytesOf(photoEntry()))
    if (!img) onPhoto()
    else if (img.complete && img.naturalWidth > 0) onPhoto()
    else {
      img.addEventListener('load', onPhoto, { once: true })
      /* A photograph that failed still ends the wait; the loader does the same. */
      img.addEventListener('error', onPhoto, { once: true })
      offs.push(() => {
        img.removeEventListener('load', onPhoto)
        img.removeEventListener('error', onPhoto)
      })
    }

    const onRest = () => resolveRow('rest', restBytes())
    if (document.readyState === 'complete') onRest()
    else {
      window.addEventListener('load', onRest, { once: true })
      offs.push(() => window.removeEventListener('load', onRest))
    }
  }

  /* The hard cap, armed before a single row can be marked pending. Whatever has
     not resolved by then is printed as it stands, so no row can be left
     invisible — not by an event that never fires, and not by a throw between
     hiding the rows and binding the things that unhide them. */
  later(showAllRows, cfg.receiptCapMs)

  /* The receipt is decoration on top of the handoff. If it cannot be built or
     bound, the handoff still runs; the reverse would trade the whole reveal for
     three ruled lines. */
  try {
    buildReceipt()
    bindReceipt()
  } catch (e) {
    showAllRows()
  }

  if (typeof stage.onResize === 'function')
    offs.push(stage.onResize(placeReceipt))

  /* ── the handoff ─────────────────────────────────────────────────────── */

  function makeScrim() {
    if (!night) return null
    const el = document.createElement('div')
    el.className = 'fx-' + NAME + '__scrim'
    el.setAttribute('aria-hidden', 'true')
    /* Covering is written, not defaulted — see the stylesheet. Same task as the
       append, so no frame is ever painted with an uncovered scrim. */
    el.setAttribute('data-cover', 'true')
    /* Body, not #boot: the scrim has to outlive the loader's own opacity, and
       it must never be an ancestor or a descendant of anything that fades. */
    document.body.appendChild(el)
    return el
  }

  function removeScrim() {
    if (scrim && scrim.parentNode) scrim.parentNode.removeChild(scrim)
    scrim = null
  }

  function flip(el, to, fallbackScale) {
    if (!el) return null
    el.style.transition = 'none'
    el.style.transform = 'none'
    el.style.transformOrigin = '0 0'
    const from = el.getBoundingClientRect() // also commits the reset above
    if (from.width <= 0 || from.height <= 0) return null
    const scale = to ? to.width / from.width : fallbackScale
    const dx = to ? to.left - from.left : 0
    const dy = to ? to.top - from.top : 0
    el.style.transition = `transform ${cfg.flipMs}ms ${cfg.easing}`
    el.style.transform = `translate3d(${dx.toFixed(1)}px, ${dy.toFixed(1)}px, 0) scale(${scale.toFixed(4)})`
    return { dx, dy, scale }
  }

  function collapseReceipt() {
    if (!receipt) return
    const r = receipt.getBoundingClientRect()
    if (r.width <= 0) return
    const navRect = navIn ? navIn.getBoundingClientRect() : null
    const targetX = navRect ? navRect.right : stage.viewport.w || r.right
    const targetY = navRect ? navRect.top + navRect.height / 2 : 36
    const dx = targetX - r.right
    const dy = targetY - (r.top + r.height / 2)
    /* Two decisions here, both about the same 280ms.
       The whole collapse is over in 45% of the flip, and it accelerates out of
       its own resting position rather than easing into the destination: the nav's
       right edge is where the primary CTA lives, and a receipt still legible when
       it arrives is a moving object over the conversion action. Ease-in keeps it
       legible where it starts and clipped out before it gets there.
       The wipe itself is linear, so whatever is left is always a clean vertical
       slice of the rows. An eased wipe spends its last 60ms at 98%, which reads
       as three chopped glyphs floating over the photograph, not as a collapse. */
    const wipeMs = Math.round(cfg.flipMs * 0.45)
    receipt.style.transition = `transform ${wipeMs}ms cubic-bezier(0.55, 0, 1, 1), clip-path ${wipeMs}ms linear`
    receipt.style.transform = `translate3d(calc(-50% + ${dx.toFixed(1)}px), ${dy.toFixed(1)}px, 0) scale(0.5)`
    receipt.style.clipPath = 'inset(0 0 0 100%)'
  }

  /* The named failure mode. The nav is fixed and lives in the same stacking
     context this transform runs in; if anything here has turned it into a
     transformed element's descendant it will have moved by now. One frame on the
     shared loop is enough to see it, and it costs one measurement. */
  function guardNav(before) {
    if (before == null) return
    if (typeof stage.register !== 'function') return
    const off = stage.register(() => {
      off()
      if (destroyed) return
      const nav = document.querySelector(cfg.navSelector)
      if (!nav) return
      const now = nav.getBoundingClientRect()
      if (
        Math.abs(now.top - before.top) <= 1 &&
        Math.abs(now.left - before.left) <= 1
      )
        return
      downgrade()
    })
    offs.push(off)
  }

  /* Tier two, decided in advance: lose the travel, keep the thesis. Opacity plus
     a 1.02 → 1.00 on the hero media, receipt still collapsing into the nav. */
  function downgrade() {
    if (tier !== 'flip') return
    tier = 'hero'
    root.setAttribute(ATTR, 'dissolve')
    if (arch) {
      arch.style.transform = ''
      arch.style.transition = ''
    }
    if (word) {
      word.style.transform = ''
      word.style.transition = ''
    }
    if (hero) hero.setAttribute(HERO_ATTR, 'run')
  }

  function run() {
    if (done || destroyed) return
    done = true

    showAllRows()

    if (!canFlip) {
      /* Cross-dissolve. style.css already knows how; this only shortens it and
         the receipt goes with the loader. */
      root.setAttribute(ATTR, 'still')
      return
    }

    const to = measurable(glyph)
    if (!to) {
      root.setAttribute(ATTR, 'still')
      tier = 'still'
      return
    }

    const nav = document.querySelector(cfg.navSelector)
    const before = nav ? nav.getBoundingClientRect() : null

    scrim = makeScrim()
    if (!scrim) {
      root.setAttribute(ATTR, 'still')
      tier = 'still'
      return
    }

    /* Armed before the night goes up, not after it. Nothing is allowed to
       depend on a transitionend that may never fire, and nothing — including a
       throw in the measurement below — is allowed to leave the scrim on the
       page. It comes off on a timer, unconditionally, and the loader is hidden
       if site.js has not already done it. */
    later(() => {
      removeScrim()
      if (
        boot &&
        !boot.hasAttribute('hidden') &&
        boot.getAttribute('data-done')
      )
        boot.setAttribute('hidden', '')
    }, cfg.flipMs + 260)

    /* Only now, with a real scrim holding the night, does the loader stop
       fading and the page stop settling. Both are one-way and both leave the
       final design in place if anything after this throws. */
    root.setAttribute(SETTLED, '')
    root.setAttribute(ATTR, 'flip')

    /* Every measurement below is decoration on top of a reveal that is already
       guaranteed to happen. A throw in here must not cost the reveal, so it
       costs only the travel. */
    try {
      const moved = flip(arch, to, 1)
      /* The wordmark follows its own target where there is one; otherwise it
         travels with the arch so the lockup stays a lockup. */
      const navWordRect = measurable(navWord)
      if (word) {
        if (navWordRect) flip(word, navWordRect, 1)
        else if (moved) {
          word.style.transition = 'none'
          word.style.transform = 'none'
          word.style.transformOrigin = '0 0'
          word.getBoundingClientRect()
          word.style.transition = `transform ${cfg.flipMs}ms ${cfg.easing}`
          word.style.transform = `translate3d(${moved.dx.toFixed(1)}px, ${moved.dy.toFixed(1)}px, 0) scale(${moved.scale.toFixed(4)})`
        }
      }

      collapseReceipt()
    } catch (e) {}

    /* One committed frame at full cover before the scrim is told to leave, or
       the transition has nothing to start from. */
    void scrim.offsetWidth
    scrim.removeAttribute('data-cover')

    guardNav(before)
  }

  /* site.js sets data-done on #boot when its manifest completes. That attribute
     is the whole contract; site.js needs no change to provide it. */
  observer = new MutationObserver(records => {
    for (const r of records) {
      if (r.attributeName !== 'data-done') continue
      if (boot.getAttribute('data-done') === 'true') {
        observer.disconnect()
        run()
        return
      }
    }
  })
  observer.observe(boot, { attributes: true, attributeFilter: ['data-done'] })

  return {
    get tier() {
      return done ? tier : canFlip ? 'flip' : 'still'
    },
    destroy() {
      destroyed = true
      if (observer) observer.disconnect()
      observer = null
      for (const t of timers) clearTimeout(t)
      timers.length = 0
      for (const off of offs) {
        try {
          off()
        } catch (e) {}
      }
      offs.length = 0
      removeScrim()
      if (ownsReceipt && receipt && receipt.parentNode)
        receipt.parentNode.removeChild(receipt)
      receipt = null
      if (arch) {
        arch.style.transform = ''
        arch.style.transition = ''
        arch.style.transformOrigin = ''
      }
      if (word) {
        word.style.transform = ''
        word.style.transition = ''
        word.style.transformOrigin = ''
      }
      if (hero) hero.removeAttribute(HERO_ATTR)
      root.removeAttribute(ATTR)
      root.removeAttribute(SETTLED)
    },
  }
}
