/* fx/boot.js — the wiring.
 *
 * Integration item 32. The one place that knows what order the fifteen
 * modules come up in, and the only file that imports more than one of them.
 *
 * Three properties this file has to have, in priority order:
 *
 *   1. No module can take down another. Every load and every init sits in its
 *      own catch. Fifteen modules written independently against a spec have
 *      never run in the same document until now, and the honest assumption is
 *      that at least one of them throws on first contact. When it does, the
 *      other fourteen still come up and the page still works.
 *
 *   2. The order is the spec's, not a preference. Four of the steps below are
 *      real dependencies and are commented as such. The rest are grouped
 *      peers and run concurrently.
 *
 *   3. Fetching is not ordering. All sixteen files are requested in one
 *      parallel wave the moment this module evaluates, and only their `init`
 *      calls are sequenced. Serialising the network too would put `handoff`
 *      sixteen round-trips deep, and handoff has a real deadline.
 *
 * Nothing here is load-bearing for the page. Delete this script and every
 * mount point falls back to the static design it ships in the markup — that
 * is the whole point of Phase 0 and it is worth re-testing every time this
 * file changes.
 */

import { getStage } from 'cwe/stage'

/* Fetch order is irrelevant, so this list is written in init order purely so
   the two can be diffed by eye. */
const NAMES = [
  'ledger-bus',
  'crease',
  'grain',
  'handoff',
  'live',
  'plate',
  'dive',
  'steprail',
  'tape',
  'strike',
  'rows',
  'arch',
  'roll',
  'split',
  'threshold',
  'field',
]

/* One wave. A module that 404s or fails to parse resolves to null here and is
   simply skipped later — it never rejects, so it cannot unwind the sequence. */
const pending = new Map()
for (const name of NAMES) {
  pending.set(
    name,
    import(`./${name}.js`).catch(function (err) {
      console.warn('[fx] ' + name + ' failed to load —', err && err.message)
      return null
    })
  )
}

/* What actually came up. Exposed below for the verification pass, which needs
   to tell "this module chose not to mount" apart from "this module threw". */
const started = Object.create(null)

async function start(name, run) {
  try {
    const mod = await pending.get(name)
    if (!mod) {
      started[name] = 'unloaded'
      return null
    }
    const handle = run(mod)
    // `null` is reserved by `each` for "the selector matched nothing", which is
    // a legitimate state on a page that does not carry that object — and it has
    // to be distinguishable from a real mount or verification learns nothing.
    started[name] = handle === null ? 'no mount point' : handle || 'mounted'
    return handle
  } catch (err) {
    started[name] = 'threw: ' + (err && err.message)
    console.warn('[fx] ' + name + ' did not start —', err)
    return null
  }
}

/* Thirteen of the fifteen fall back to `document` when handed no target. `rows`
   and `steprail` do not — handed nothing they return an inert stub, and an
   inert stub is a truthy object, so a boot that calls them bare reports success
   and animates nothing. Both are called once per mount, explicitly, and so is
   `split`, which binds exactly one element per call by design. */
function each(selector, run) {
  const els = document.querySelectorAll(selector)
  return els.length ? Array.prototype.map.call(els, run) : null
}

/* ── the sequence ──────────────────────────────────────────────────────── */

// The Stage singleton owns the only requestAnimationFrame loop on the page.
// Everything below reads pointer, scroll and reduced-motion from it.
const stage = getStage()

// The bus publishes `fuime:fee`. Every figure on the site is downstream of it,
// so it is genuinely first and not merely early.
const bus = await start('ledger-bus', m => m.initLedgerBus())
const motion = (bus && bus.motion) || null

// CSS-only, no layout dependency. Safe anywhere; here because they are cheap
// and the page looks finished sooner with them in.
await Promise.all([
  start('crease', m => m.initCrease()),
  start('grain', m => m.initGrain()),
])

// Dependency, not preference: handoff observes #boot, and site.js lifts #boot
// on a 1200ms cap. Binding after the lift means the transition never runs.
await start('handoff', m => m.initHandoff())

// Scroll readers. Independent of each other.
await Promise.all([
  start('live', m => m.initLive()),
  start('plate', m => m.initPlate()),
  start('dive', m => m.initDive()),
  // The mount attribute is deliberately not `data-fx-steprail`: the module
  // writes that one onto its host to mark itself mounted, so shipping it in
  // the markup would make steprail bail on sight.
  start('steprail', m => each('[data-fx-steps]', el => m.initStepRail(el))),
  start('tape', m => m.initTape(null, motion ? { motion } : {})),
])

// One-shot entrances, driven by IntersectionObserver.
await Promise.all([
  start('strike', m => m.initStrike()),
  start('rows', m => each('[data-fx-rows]', el => m.initRows(el))),
  start('arch', m => m.initArch()),
])

// The console. These three are peers in the spec, so the order inside this
// group is ours: roll first, because split can borrow its odometer writer for
// the figures under the rule instead of setting textContent directly.
const roll = await start('roll', m => m.initRoll())
const writer = roll && typeof roll.write === 'function' ? roll : null

// A page carries more than one rule — the 2px dock under the nav and, on two
// of the three pages, the full 10px rule under the calculator. initSplit binds
// exactly one mount, so it is called once per mount rather than once per page.
await start('split', m =>
  each('[data-fx-split]', mount =>
    m.initSplit(mount, { bus, motion, roll: writer })
  )
)

await start('threshold', m => m.initThreshold())

// Last, and this one is a real constraint: field measures its magnet bounds at
// init, so any layout shift caused by a module above would silently invalidate
// them and the cursor would pull toward where things used to be.
await start('field', m => m.initField())

/* The verification pass reads this to check what mounted at each width, and it
   is the fastest way to tell from a console whether a module is missing or
   merely had nothing to attach to on this page. */
window.__fx = { stage, bus, started }
