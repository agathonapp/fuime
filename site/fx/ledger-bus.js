/* fx/ledger-bus.js — the shared dependency.
 *
 * Two jobs and no others.
 *
 * One: the fee is a pure function of the slider value. This module recomputes
 * the arithmetic itself rather than scraping what site.js writes into the DOM,
 * so the day someone renames `.calc__figure` nothing downstream breaks. site.js
 * keeps writing its own values in parallel and that is deliberate — it is the
 * floor the page falls back to when JS modules fail.
 *
 * Two: one motion gate. Reduced-motion, coarse-pointer, save-data and the
 * frame-time quality tier live in exactly one file, so there is exactly one
 * thing to test.
 *
 * Every other fx module subscribes to the published event and never to the DOM
 * and never to site.js.
 */

import { getStage } from 'cwe/stage'

const DEFAULTS = {
  stripePct: 0.029,
  stripeFixed: 0.3,
  fuimePct: 0.07,
  monthlyThreshold: 250,
  monthlyFee: 15,
  sliderSelector: '.calc__range',
  storageKey: 'fuime.fee',
  eventName: 'fuime:fee',
}

/* sessionStorage throws outright in some private modes and embedded webviews,
   so every access goes through here. Losing cross-page continuity is a silent,
   acceptable degradation; a thrown error on a marketing page is not. */
function safeStore() {
  try {
    const k = '__fuime_probe__'
    sessionStorage.setItem(k, '1')
    sessionStorage.removeItem(k)
    return sessionStorage
  } catch (e) {
    return null
  }
}

export function initLedgerBus(config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})
  const store = safeStore()
  const stage = getStage()

  const slider = document.querySelector(cfg.sliderSelector)

  /* ── the arithmetic ─────────────────────────────────────────────────── */

  function compute(charge) {
    const stripe = charge * cfg.stripePct + cfg.stripeFixed
    const fuime = charge * cfg.fuimePct
    const lands = charge - stripe - fuime
    const over = charge >= cfg.monthlyThreshold
    return { charge, stripe, fuime, lands, over }
  }

  const state = compute(readInitialCharge())

  function readInitialCharge() {
    // The slider is the truth where one exists. Everywhere else — /parents has
    // no calculator — we carry the last reading across the session so all three
    // pages open showing the same number.
    if (slider) return Number(slider.value)
    if (store) {
      const raw = store.getItem(cfg.storageKey)
      if (raw) {
        try {
          const v = Number(JSON.parse(raw).charge)
          if (Number.isFinite(v) && v > 0) return v
        } catch (e) {}
      }
    }
    return 400
  }

  function publish() {
    if (store) {
      try {
        store.setItem(
          cfg.storageKey,
          JSON.stringify({ charge: state.charge, over: state.over })
        )
      } catch (e) {}
    }
    document.dispatchEvent(
      new CustomEvent(cfg.eventName, { detail: Object.assign({}, state) })
    )
  }

  function set(charge) {
    const n = Number(charge)
    if (!Number.isFinite(n) || n <= 0) return
    if (n === state.charge) return
    Object.assign(state, compute(n))
    publish()
  }

  function onInput(e) {
    set(e.target.value)
  }
  if (slider) slider.addEventListener('input', onInput)

  /* ── the one motion gate ────────────────────────────────────────────── */

  const reducedQ = matchMedia('(prefers-reduced-motion: reduce)')
  const coarseQ = matchMedia('(hover: none) and (pointer: coarse)')

  const motion = {
    reduced: reducedQ.matches,
    coarse: coarseQ.matches,
    saveData: !!(navigator.connection && navigator.connection.saveData),
    tier: 'high',
  }

  function onReduced(e) {
    motion.reduced = e.matches
  }
  function onCoarse(e) {
    motion.coarse = e.matches
  }
  reducedQ.addEventListener('change', onReduced)
  coarseQ.addEventListener('change', onCoarse)

  /* Quality tier off a rolling 60-frame mean. Hysteresis plus a cooldown so a
     single stalled frame — a font swap, a decode — can't flip the whole site
     into its low tier and back. */
  let frames = 0
  let acc = 0
  let cooldown = 0
  const offFrame = stage.register(function (dt) {
    const ms = dt * 1000
    // A backgrounded tab produces enormous dt on return; that is not jank.
    if (ms > 200) return
    acc += ms
    frames++
    if (cooldown > 0) cooldown--
    if (frames < 60) return
    const mean = acc / frames
    frames = 0
    acc = 0
    if (cooldown > 0) return
    if (motion.tier === 'high' && mean > 22) {
      motion.tier = 'low'
      cooldown = 3
    } else if (motion.tier === 'low' && mean < 12) {
      motion.tier = 'high'
      cooldown = 3
    }
  })

  // One event at init so a page with no slider still renders its split, and so
  // subscribers that mount after us are not left waiting for a drag.
  publish()

  return {
    state,
    set,
    motion,
    destroy: function () {
      if (slider) slider.removeEventListener('input', onInput)
      reducedQ.removeEventListener('change', onReduced)
      coarseQ.removeEventListener('change', onCoarse)
      offFrame()
    },
  }
}
