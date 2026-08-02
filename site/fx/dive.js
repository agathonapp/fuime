/* fx/dive.js — the dive. Scroll flies the camera into the laptop on the desk
 * and lands inside the app.
 *
 * The footage is 122 pre-rendered frames of a dolly-in, generated from the hero
 * photograph itself, so the room you leave is the room you were just looking at.
 * Frames are scrubbed on a canvas rather than played from a <video>: browsers
 * will not seek a video at scroll rate, and an image ladder is the only way this
 * effect has ever been shipped.
 *
 * THE PART THAT IS NOT FOOTAGE. A video model renders a laptop screen at this
 * distance as mush, so it never rendered ours: the screen is a flat cyan plate
 * in every frame, keyed and tracked offline (gen/dive/track.py), with the real
 * UI warped onto its four corners by gen/dive/composite.py. That same track
 * ships to this file as JSON, which is what makes the ending possible — a real
 * DOM panel is laid onto the SAME four corners, cross-fades over the baked one
 * while the camera is still moving, and then keeps growing after the footage has
 * run out. The last thing you see is live text at device resolution, not the
 * last frame of a video blown up.
 *
 * Geometry is a homography, not a scale. The screen is a trapezoid in every
 * frame and the panel is a rectangle; mapping one to the other is exactly what
 * `matrix3d` is for, and it is the same transform PIL applied when it baked the
 * plate in, so the two are pixel-registered at the moment of the swap. Corners
 * are interpolated toward an axis-aligned target, so the perspective flattens
 * out on its own as the app comes forward.
 *
 * COLOUR: there is not one literal in this file. Every colour the module renders
 * is a `var(--token)` in the injected CSS.
 *
 * MOTION IS OPT-IN. The markup ships a still of the app open on the laptop and
 * the injected CSS leaves it that way. The sticky stage, the scroll travel, the
 * canvas and the panel only exist under `[data-fx-dive-on]`, which JS adds after
 * it has confirmed reduced-motion is off, the track parsed and the first frames
 * decoded. Reduced motion, no JS, a print stylesheet, save-data, a 404 on the
 * track or a stalled ladder all land on that still, which is the same picture
 * the sequence ends on.
 */

import { getStage } from 'cwe/stage'

const NAME = 'dive'
const ATTR = 'data-fx-dive'
const ATTR_ON = 'data-fx-dive-on'
const ATTR_LADDER = 'data-fx-dive-ladder'

const TRACK_URL = '/dive/track.json'

/* The two ladders build-frames.sh emits. `crop` is the window of the source
   render each one covers, in normalised source coordinates, and it is the only
   reason one track file can serve both: corners are stored against the full
   1920×1080 render, so a cropped ladder simply remaps them.
   MIRRORED FROM gen/dive/build-frames.sh — `crop=810:1080:(iw-810)/2:0`. */
const LADDERS = [
  { upTo: 900, dir: '/dive-m/', crop: { x: 555 / 1920, w: 810 / 1920 } },
  { upTo: Infinity, dir: '/dive/', crop: { x: 0, w: 1 } },
]

const DEFAULTS = {
  /* Pacing is the knob people actually feel. 22px per frame puts the whole
     dolly inside ~2.7 viewport heights of scroll — long enough to read as
     travel, short enough that nobody thinks the page is stuck. */
  pxPerFrame: 22,
  handoffVh: 1.15, // viewport heights spent growing the panel out of the screen
  holdVh: 0.5, // and holding the composed app before the section releases
  pad: 0.05, // margin around the composed panel, as a fraction of min(vw,vh)
  /* Below this width the panel is a phone layout, which cannot be warped into a
     landscape screen without looking crushed. There the swap is a centred
     dissolve instead of a corner match — see startQuad(). */
  phoneUpTo: 820,
}

/* How the handover is timed, in signed handoff progress: 0 is the last frame of
   the scrub, 1 is the panel at rest, and a negative number is still inside the
   scrub. Swapping under motion is invisible; swapping on a held frame is a
   blink, which is why the desktop panel starts arriving before the camera
   stops.

   Desktop hands over by substitution. The panel is registered corner to corner
   on the very screen it is replacing, so both being up at once is still one
   image, and the room can go on dissolving out from under it long after.

   A phone panel is portrait and deliberately not registered — see startQuad —
   so that same overlap is two different UIs superimposed, and the leak around
   the panel's margins reads as a double exposure. There the handover is one
   fast dissolve on a single range with a linear ramp, so the two layers are
   exact complements: never both up, and never both down either. Running them
   back to back instead leaves a frame of empty night, which is worse — a hole
   mid-scroll reads as a bug where a hard swap reads as a cut. */
const SEAM = {
  desk: { room: [0.14, 0.76], panel: [-0.18, 0.3], ease: smoothstep },
  phone: { room: [0.03, 0.2], panel: [0.03, 0.2], ease: clamp01 },
}

function span(v, r) {
  return (v - r[0]) / (r[1] - r[0] || 1)
}

/* Mirrors composite.py's bloom lift. The baked plate is pushed toward the
   screen light it replaces, hard at the head of the shot where a laptop across
   a dark room is a block of light rather than a readable page, decaying to
   nothing by LIFT_END. The DOM panel has to carry the same lift or the
   cross-fade is a brightness pop. Same numbers, same curve, deliberately
   duplicated with this note — by the time the panel exists the lift is
   already spent, and it stays in the maths so the two cannot drift apart if
   LIFT_END ever moves. */
const LIFT_END = 0.86
const LIFT_MAX = 0.55

const LOAD_CONC = 6
const NEAR_VH = 2 // start fetching the ladder this many viewports out

let styleEl = null
let stage = null
let offFrame = null
let offResize = null
let io = null
const registry = new Set()

function clamp01(v) {
  return v < 0 ? 0 : v > 1 ? 1 : v
}
function smoothstep(t) {
  t = clamp01(t)
  return t * t * (3 - 2 * t)
}

/* ── CSS ─────────────────────────────────────────────────────────────────── */

const SHEET = `
/* Armed. Every declaration in this sheet exists only while JS holds the
   attribute; the default in style.css is a still of the finished app. */
[${ATTR_ON}] .dive__track { height: var(--fx-dive-travel); }
[${ATTR_ON}] .dive__stage {
  position: sticky;
  top: 0;
  /* svh, not vh: on a phone the toolbar retracts as you scroll and vh would
     resize the pinned stage mid-dive. The vh fallback is for browsers without
     the small-viewport units — an unsupported height here collapses the stage,
     because everything inside it is absolutely positioned. */
  height: 100vh;
  height: 100svh;
  overflow: clip;
}
[${ATTR_ON}] .dive__still { display: none; }
[${ATTR_ON}] .dive__canvas {
  display: block;
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  opacity: var(--fx-dive-room, 1);
}
[${ATTR_ON}] .dive__app {
  display: grid;
  position: absolute;
  left: 0;
  top: 0;
  transform-origin: 0 0;
  transform: var(--fx-dive-m, none);
  opacity: var(--fx-dive-app, 0);
  /* Hidden until the panel has geometry — one frame of an unplaced 1600px
     panel at the top-left corner is a flash of the whole app. */
  visibility: var(--fx-dive-vis, hidden);
}
/* The bloom the baked plate carries, so the cross-fade is a substitution and
   not a change in exposure. */
[${ATTR_ON}] .dive__app::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: var(--dive-bloom);
  opacity: var(--fx-dive-lift, 0);
}

@media (prefers-reduced-motion: reduce) {
  [${ATTR_ON}] .dive__track { height: auto !important; }
  [${ATTR_ON}] .dive__stage { position: static !important; height: auto !important; }
  [${ATTR_ON}] .dive__still { display: block !important; }
  [${ATTR_ON}] .dive__cue { display: none !important; }
  [${ATTR_ON}] .dive__canvas { display: none !important; }
  /* The panel goes with the canvas — except a join panel, which is a sign-up
     rather than a picture of one. Take that away and the page has no exit. */
  [${ATTR_ON}] .dive__app:not(.dive__app--join) { display: none !important; }
  [${ATTR_ON}] .dive__app--join {
    position: static !important;
    transform: none !important;
    opacity: 1 !important;
    visibility: visible !important;
    width: auto !important;
    height: auto !important;
  }
  [${ATTR_ON}] .dive__app--join::after { display: none !important; }
}
@media print {
  [${ATTR_ON}] .dive__track { height: auto !important; }
  [${ATTR_ON}] .dive__stage { position: static !important; height: auto !important; }
  [${ATTR_ON}] .dive__still { display: block !important; }
  [${ATTR_ON}] .dive__cue { display: none !important; }
  [${ATTR_ON}] .dive__canvas { display: none !important; }
  /* The panel goes with the canvas — except a join panel, which is a sign-up
     rather than a picture of one. Take that away and the page has no exit. */
  [${ATTR_ON}] .dive__app:not(.dive__app--join) { display: none !important; }
  [${ATTR_ON}] .dive__app--join {
    position: static !important;
    transform: none !important;
    opacity: 1 !important;
    visibility: visible !important;
    width: auto !important;
    height: auto !important;
  }
  [${ATTR_ON}] .dive__app--join::after { display: none !important; }
}
`

function injectCSS() {
  if (styleEl && styleEl.isConnected) return
  const found = document.querySelector('style[data-fx="' + NAME + '"]')
  if (found) {
    styleEl = found
    return
  }
  styleEl = document.createElement('style')
  styleEl.setAttribute('data-fx', NAME)
  styleEl.textContent = SHEET
  document.head.appendChild(styleEl)
}

/* ── homography ──────────────────────────────────────────────────────────── */

/* Solve the 8 unknowns of the projective map taking the panel's own untransformed
   corners to four arbitrary points. Gaussian elimination with partial pivoting —
   8×8 once per frame is nothing, and it is the only honest way to hit a
   trapezoid with a rectangle. */
function homography(src, dst) {
  const a = []
  for (let i = 0; i < 4; i++) {
    const x = src[i][0]
    const y = src[i][1]
    const u = dst[i][0]
    const v = dst[i][1]
    a.push([x, y, 1, 0, 0, 0, -u * x, -u * y, u])
    a.push([0, 0, 0, x, y, 1, -v * x, -v * y, v])
  }
  for (let c = 0; c < 8; c++) {
    let piv = c
    for (let r = c + 1; r < 8; r++) {
      if (Math.abs(a[r][c]) > Math.abs(a[piv][c])) piv = r
    }
    if (Math.abs(a[piv][c]) < 1e-9) return null // degenerate quad, skip the frame
    const t = a[c]
    a[c] = a[piv]
    a[piv] = t
    const p = a[c]
    for (let r = 0; r < 8; r++) {
      if (r === c) continue
      const k = a[r][c] / p[c]
      if (!k) continue
      for (let j = c; j < 9; j++) a[r][j] -= k * p[j]
    }
  }
  const h = new Array(8)
  for (let i = 0; i < 8; i++) h[i] = a[i][8] / a[i][i]
  return h
}

/* CSS matrix3d is column-major, and a 2D homography rides in it as the four
   corners of the 3×3 with the perspective row in w. */
function matrix3d(h) {
  return (
    'matrix3d(' +
    [h[0], h[3], 0, h[6], h[1], h[4], 0, h[7], 0, 0, 1, 0, h[2], h[5], 0, 1]
      .map(function (n) {
        return Math.abs(n) < 1e-7 ? 0 : Number(n.toFixed(6))
      })
      .join(',') +
    ')'
  )
}

/* ── the ladder ──────────────────────────────────────────────────────────── */

function ladderFor(w) {
  for (let i = 0; i < LADDERS.length; i++) {
    if (w <= LADDERS[i].upTo) return LADDERS[i]
  }
  return LADDERS[LADDERS.length - 1]
}

function frameURL(dir, i) {
  return dir + 'f_' + String(i + 1).padStart(4, '0') + '.webp'
}

/* Frames arrive in order, at a fixed concurrency, and the last one jumps the
   queue: it is the frame the panel is registered against and the one the
   handoff holds, so a ladder that stalls two thirds of the way in still ends
   where it is supposed to. */
function loadLadder(inst) {
  const n = inst.track.frames
  const order = [n - 1]
  for (let i = 0; i < n; i++) if (i !== n - 1) order.push(i)

  /* Which ladder this pump is for. Crossing the breakpoint mid-load starts a
     second pump against a different directory and a fresh imgs array, and
     without this the first pump's outstanding requests still land in it — full
     1600px frames written into a phone ladder, drawn through the phone's crop
     and tracked to corners that are not where they were drawn. */
  const gen = inst.gen
  const dir = inst.ladder.dir
  let next = 0
  let live = 0
  const pump = function () {
    while (live < LOAD_CONC && next < order.length) {
      if (inst.dead || inst.gen !== gen) return
      const i = order[next++]
      live++
      const img = new Image()
      img.decoding = 'async'
      img.onload = function () {
        // Landed after the breakpoint was crossed: this frame belongs to the
        // ladder we walked away from, and writing it into the live array puts a
        // 1600px frame behind a phone crop.
        if (inst.gen !== gen) return
        inst.imgs[i] = img
        inst.loaded++
        // The scrub draws the nearest frame it holds, so until this one arrived
        // its slot was showing a neighbour. Forget what was drawn, or a reader
        // sitting still keeps that substitute for good.
        inst.drawn = -1
        live--
        pump()
      }
      img.onerror = function () {
        if (inst.gen !== gen) return
        // A hole in the ladder is survivable — the scrub falls back to the
        // nearest frame it does have. A ladder that never starts is not.
        inst.missing++
        live--
        if (i === 0 || inst.missing > 8) inst.dead = true
        pump()
      }
      img.src = frameURL(dir, i)
    }
  }
  pump()
}

/* The nearest frame we actually hold. Never blocks the scrub on a fetch. */
function nearest(inst, i) {
  const imgs = inst.imgs
  if (imgs[i]) return imgs[i]
  const n = imgs.length
  for (let d = 1; d < n; d++) {
    if (i - d >= 0 && imgs[i - d]) return imgs[i - d]
    if (i + d < n && imgs[i + d]) return imgs[i + d]
  }
  return null
}

/* ── geometry ────────────────────────────────────────────────────────────── */

/* Where the ladder's image lands in the viewport, cover-fitted. Returned as an
   origin and a drawn size so a normalised point maps with one multiply. */
function cover(inst, vw, vh) {
  const aspect = inst.frameAspect
  let dw = vw
  let dh = vw / aspect
  if (dh < vh) {
    dh = vh
    dw = vh * aspect
  }
  return { x: (vw - dw) / 2, y: (vh - dh) / 2, w: dw, h: dh }
}

/* The screen's four corners, in viewport pixels, at a fractional frame. Corners
   are stored against the uncropped render, so a cropped ladder remaps x through
   its own window first. */
function screenQuad(inst, f, box) {
  const q = inst.track.quads
  const i = Math.min(
    Math.max(Math.floor(f), inst.track.firstTracked),
    q.length - 1
  )
  const a = q[i] || q[inst.track.firstTracked]
  const b = q[Math.min(i + 1, q.length - 1)] || a
  const t = clamp01(f - i)
  const cx = inst.ladder.crop.x
  const cw = inst.ladder.crop.w
  const out = []
  for (let k = 0; k < 4; k++) {
    const u = (a[k][0] + (b[k][0] - a[k][0]) * t - cx) / cw
    const v = a[k][1] + (b[k][1] - a[k][1]) * t
    out.push([box.x + u * box.w, box.y + v * box.h])
  }
  return out
}

/* The site nav is fixed and opaque, so it sits on top of a stage pinned at
   top:0 and would clip the panel's own header. Measured rather than mirrored,
   because the nav's height is a constant in five places in style.css and a
   sixth copy here would be the one that goes stale. */
function navInset() {
  const n = document.querySelector('.nav')
  if (!n) return 0
  return getComputedStyle(n).position === 'fixed' ? n.offsetHeight : 0
}

/* Where the panel comes to rest: fitted into what the viewport actually leaves
   free, with a margin. The panel is a 1600px console on a wide screen and a
   420px phone app below phoneUpTo — style.css owns that switch — so this is the
   same fit either way and the type lands legible in both. */
function targetQuad(inst, vw, vh) {
  const pw = inst.panel.offsetWidth
  const ph = inst.panel.offsetHeight
  if (!pw || !ph) return null
  const pad = Math.min(vw, vh) * inst.cfg.pad
  const top = inst.nav + pad
  const free = vh - top - pad
  const s = Math.min((vw - pad * 2) / pw, free / ph)
  const ox = vw / 2 - (pw * s) / 2
  const oy = top + (free - ph * s) / 2
  return [
    [ox, oy],
    [ox + pw * s, oy],
    [ox + pw * s, oy + ph * s],
    [ox, oy + ph * s],
  ]
}

/* Where the panel starts. A desktop panel is registered corner-to-corner on the
   screen it is replacing. A phone panel is portrait and would be crushed by that
   map, so it dissolves in centred on the screen instead, at a scale that keeps
   it inside the glass. */
function startQuad(inst, sq) {
  const pw = inst.panel.offsetWidth
  const ph = inst.panel.offsetHeight
  if (!inst.phone) return sq
  let x0 = Infinity
  let y0 = Infinity
  let x1 = -Infinity
  let y1 = -Infinity
  for (let i = 0; i < 4; i++) {
    if (sq[i][0] < x0) x0 = sq[i][0]
    if (sq[i][0] > x1) x1 = sq[i][0]
    if (sq[i][1] < y0) y0 = sq[i][1]
    if (sq[i][1] > y1) y1 = sq[i][1]
  }
  const s = Math.min((x1 - x0) / pw, (y1 - y0) / ph) * 0.86
  const ox = (x0 + x1) / 2 - (pw * s) / 2
  const oy = (y0 + y1) / 2 - (ph * s) / 2
  return [
    [ox, oy],
    [ox + pw * s, oy],
    [ox + pw * s, oy + ph * s],
    [ox, oy + ph * s],
  ]
}

/* ── measurement ─────────────────────────────────────────────────────────── */

/* The height every coordinate in this module is expressed in — and it is the
   pinned stage's own box, not window.innerHeight.
   The two are not the same number on a phone. The stage is 100svh, which is the
   viewport with the browser toolbar SHOWN, while innerHeight grows to the large
   viewport as soon as the toolbar retracts — 60-80px on an 844px phone. Measure
   against innerHeight and three things break in the same frame: the canvas is
   drawn for a box ~9% taller than the one it is stretched into, the panel's quad
   is in real CSS px inside that shorter box so it no longer lands on the baked
   screen it is replacing, and the rest position is centred below the visible
   area. The clamp is for a browser with no svh, where the height declaration is
   dropped and the stage — everything inside it absolutely positioned — collapses. */
function stageHeight(inst) {
  const vh = (stage && stage.viewport.h) || window.innerHeight
  if (!inst.on || !inst.stageEl) return vh
  const h = inst.stageEl.clientHeight
  return h > vh * 0.5 ? h : vh
}

function measure(inst) {
  const vw = (stage && stage.viewport.w) || window.innerWidth
  const vh = stageHeight(inst)
  const cfg = inst.cfg
  const ladder = ladderFor(vw)
  if (ladder !== inst.ladder) {
    // A width change that crosses the breakpoint is a different set of files.
    // Drop what we hold and refetch; it is rare, and holding both is 6MB.
    inst.ladder = ladder
    inst.gen++
    inst.imgs = new Array(inst.track.frames)
    inst.loaded = 0
    inst.missing = 0
    inst.drawn = -1
    inst.frameAspect = (inst.track.frameW * ladder.crop.w) / inst.track.frameH
    inst.section.setAttribute(ATTR_LADDER, ladder.dir)
    loadLadder(inst)
  }
  inst.phone = vw <= cfg.phoneUpTo
  inst.scrubPx = inst.track.frames * cfg.pxPerFrame
  inst.handoffPx = vh * cfg.handoffVh
  inst.travel = inst.scrubPx + inst.handoffPx + vh * cfg.holdVh
  // The dive is paid for in document height: the travel it needs, plus the one
  // viewport the pinned stage occupies while it is spent.
  inst.trackEl.style.setProperty(
    '--fx-dive-travel',
    Math.round(inst.travel + vh) + 'px'
  )
  inst.nav = navInset()
  inst.target = targetQuad(inst, vw, vh)

  const dpr = Math.min((stage && stage.viewport.dpr) || 1, 2)
  const bw = Math.round(vw * dpr)
  const bh = Math.round(vh * dpr)
  if (inst.canvas.width !== bw || inst.canvas.height !== bh) {
    inst.canvas.width = bw
    inst.canvas.height = bh
    inst.drawn = -1
  }
  inst.vw = vw
  inst.vh = vh
  inst.dpr = dpr
}

/* ── the loop ────────────────────────────────────────────────────────────── */

function tick() {
  if (!stage) return
  const reduced = !!stage.reducedMotion

  registry.forEach(function (inst) {
    if (reduced) {
      if (inst.on) disarm(inst)
      return
    }
    if (!inst.near) return
    // A ladder can die after the section has armed — a half-deployed directory,
    // a CDN falling over, the reader going offline. Bailing without disarming
    // would leave them scrolling four thousand pixels of pinned black.
    if (inst.dead) {
      if (inst.on) disarm(inst)
      return
    }
    // Reduced motion held the fetch back; this instance is in view and motion is
    // on now, so start it.
    if (inst.deferred) begin(inst)
    if (!inst.track) return

    // Nothing is armed until there is something to draw. Until then the still
    // holds the section and the layout never moves.
    if (!inst.on) {
      if (inst.loaded < 2) return
      // Arming replaces a ~0.6 viewport still with ~4.3 viewports of travel. If
      // the reader has already gone past the section, that inserts four screens
      // of document ABOVE them and throws them back — Chrome absorbs it with
      // scroll anchoring, iOS does not. So it arms on the next approach instead.
      if (inst.trackEl.getBoundingClientRect().bottom <= 0) return
      // Attribute first, measurement second, and in that order for a real
      // reason: the panel is display:none until it lands, so measuring before
      // it does reads a 0×0 box and the section can never arm. The travel, the
      // sticky stage and the stage's own height only exist after it too, so the
      // rect read below has to come last.
      inst.section.setAttribute(ATTR_ON, '')
      inst.on = true
      measure(inst)
    }
    if (!inst.target) return

    const p = scrollProgress(inst)

    const scrubEnd = inst.scrubPx / inst.travel
    const n = inst.track.frames - 1
    // Signed handoff progress, so the seam ranges above can reach back into the
    // scrub without a second parameterisation of the same scroll.
    const hs = (p - scrubEnd) / (inst.handoffPx / inst.travel || 1)
    const h = clamp01(hs)
    const f = p <= scrubEnd ? (p / (scrubEnd || 1)) * n : n

    drawFrames(inst, f)

    const box = cover(inst, inst.vw, inst.vh)
    const sq = startQuad(inst, screenQuad(inst, f, box))
    const e = smoothstep(h)
    const quad = []
    for (let k = 0; k < 4; k++) {
      quad.push([
        sq[k][0] + (inst.target[k][0] - sq[k][0]) * e,
        sq[k][1] + (inst.target[k][1] - sq[k][1]) * e,
      ])
    }

    const pw = inst.panel.offsetWidth
    const ph = inst.panel.offsetHeight
    const hm = homography(
      [
        [0, 0],
        [pw, 0],
        [pw, ph],
        [0, ph],
      ],
      quad
    )

    const seam = inst.phone ? SEAM.phone : SEAM.desk
    const rev = seam.ease(span(hs, seam.panel))
    const t = f / (n || 1)
    const lift = LIFT_MAX * (1 - smoothstep(t / LIFT_END))
    const room = 1 - seam.ease(span(hs, seam.room))

    const s = inst.section.style
    if (hm) put(inst, s, '--fx-dive-m', 'm', matrix3d(hm))
    put(inst, s, '--fx-dive-app', 'a', rev.toFixed(3))
    put(inst, s, '--fx-dive-lift', 'l', lift.toFixed(3))
    put(inst, s, '--fx-dive-room', 'r', room.toFixed(3))
    put(inst, s, '--fx-dive-vis', 'v', hm ? 'visible' : 'hidden')
    live(inst, rev >= 0.995)
  })
}

/* The panel can hold real controls — on /start it is the sign-up, and the form
   inside it is the only thing on the page anyone can do. For most of the dive
   that panel is up at opacity 0, and an opacity-0 form is still clickable and
   still in the tab order: a reader pressing Tab on the first screen would land
   in an email field nobody can see, sitting somewhere off in the middle of a
   dolly shot. So the panel is inert until it is actually at rest, and inert is
   what turns it off for the pointer, the keyboard AND the screen reader at
   once. `visibility` already covers the stretch before the panel has geometry;
   this covers the stretch after, while it is flying. */
function live(inst, on) {
  if (inst.live === on) return
  inst.live = on
  if (on) inst.panel.removeAttribute('inert')
  else inst.panel.setAttribute('inert', '')
}

function scrollProgress(inst) {
  return clamp01(-inst.trackEl.getBoundingClientRect().top / (inst.travel || 1))
}

function put(inst, style, prop, key, value) {
  if (inst.w[key] === value) return
  inst.w[key] = value
  style.setProperty(prop, value)
}

/* Draw the frame under the scroll, mixing in the next one where that helps.
   122 frames is thin for a scrub, and an interpolated ladder would have cost
   3MB and a pile of minterpolate artefacts on a fast dolly, so the fractional
   part is spent on a blend instead — but only where the blend is honest. See
   blendGate. */
function drawFrames(inst, f) {
  if (Math.abs(f - inst.drawn) < 0.004) return
  const i = Math.min(Math.floor(f), inst.imgs.length - 1)
  const a = nearest(inst, i)
  // Not recorded as drawn unless something was: with nothing in the ladder yet
  // this has to run again on the next frame, not go quiet holding an empty
  // canvas under a panel that is already placed on the screen it should show.
  if (!a) return
  inst.drawn = f
  const ctx = inst.ctx
  const box = cover(inst, inst.vw, inst.vh)
  const d = inst.dpr
  ctx.setTransform(d, 0, 0, d, 0, 0)
  ctx.clearRect(0, 0, inst.vw, inst.vh)
  ctx.globalAlpha = 1
  ctx.drawImage(a, box.x, box.y, box.w, box.h)
  const frac = f - i
  const w = frac > 0.02 ? frac * blendGate(inst, i, box) : 0
  const b = w > 0.01 && i + 1 < inst.imgs.length ? inst.imgs[i + 1] : null
  if (b) {
    ctx.globalAlpha = w
    ctx.drawImage(b, box.x, box.y, box.w, box.h)
    ctx.globalAlpha = 1
  }
}

/* How much of the next frame to mix in, by how far the shot travels between the
   two. Blending adjacent frames only smooths a scrub while the images nearly
   coincide; once the dolly is moving, two frames superimposed are not a
   half-step between them, they are a double exposure — at the end of this take
   the screen grows by 20px a frame and every line of the UI reads twice. So the
   mix is gated on the tracked screen's own displacement: full where the camera
   is barely moving, off where it is, and the scrub steps frame to frame like
   any other image sequence. */
const BLEND_PX = [1.5, 5] // full mix below, none above
function blendGate(inst, i, box) {
  const q = inst.track.quads
  const a = q[i]
  const b = q[i + 1]
  if (!a || !b) return 0
  const sx = box.w / inst.ladder.crop.w
  let d = 0
  for (let k = 0; k < 4; k++) {
    d = Math.max(
      d,
      Math.abs(b[k][0] - a[k][0]) * sx,
      Math.abs(b[k][1] - a[k][1]) * box.h
    )
  }
  return 1 - smoothstep((d - BLEND_PX[0]) / (BLEND_PX[1] - BLEND_PX[0]))
}

function disarm(inst) {
  if (!inst.on) return
  inst.section.removeAttribute(ATTR_ON)
  const s = inst.section.style
  s.removeProperty('--fx-dive-m')
  s.removeProperty('--fx-dive-app')
  s.removeProperty('--fx-dive-lift')
  s.removeProperty('--fx-dive-room')
  s.removeProperty('--fx-dive-vis')
  inst.trackEl.style.removeProperty('--fx-dive-travel')
  // Unarmed, the panel is back in normal flow and fully visible — a reduced-
  // motion reader gets it as a plain block. Leaving it inert here would hand
  // them a sign-up form they can see and cannot fill in.
  live(inst, true)
  inst.w = {}
  inst.on = false
  inst.drawn = -1
}

/* ── shared subscriptions ────────────────────────────────────────────────── */

function ensureShared() {
  if (offFrame) return
  stage = getStage()

  if (typeof IntersectionObserver === 'function') {
    io = new IntersectionObserver(
      function (entries) {
        for (let i = 0; i < entries.length; i++) {
          const inst = entries[i].target.__fxDive
          if (!inst) continue
          inst.near = entries[i].isIntersecting
          if (inst.near && !inst.started) {
            inst.started = true
            begin(inst)
          }
        }
      },
      { rootMargin: NEAR_VH * 100 + '% 0px ' + NEAR_VH * 100 + '% 0px' }
    )
  }

  /* Every instance holding a track, armed or not. An unarmed one still has to
     see a breakpoint crossing: skip it and the swap is deferred to the measure()
     that runs at arm time, which wipes the ladder one line after the `loaded >=
     2` gate let the section arm — armed with nothing to draw. */
  offResize = stage.onResize(function () {
    registry.forEach(function (inst) {
      // Not just the armed ones. An instance that has its track but has not
      // armed yet still has to see the breakpoint go by, or the swap fires
      // inside the arm-time measure() and wipes the frames it just counted.
      if (inst.track && !inst.dead) measure(inst)
    })
  })

  offFrame = stage.register(tick)
}

function teardownShared() {
  if (registry.size) return
  if (offFrame) offFrame()
  if (offResize) offResize()
  if (io) io.disconnect()
  offFrame = offResize = io = null
  stage = null
  if (styleEl && styleEl.parentNode) styleEl.parentNode.removeChild(styleEl)
  styleEl = null
}

/* 3.5MB of ladder is a real cost and there are readers who should not pay it.
   Save-data and a 2g-class connection both fall through to the still, which is
   the same picture the sequence lands on. */
function affordable() {
  const c = navigator.connection
  if (!c) return true
  if (c.saveData) return false
  const t = c.effectiveType || ''
  return t !== 'slow-2g' && t !== '2g'
}

function begin(inst) {
  if (!affordable()) {
    inst.dead = true
    return
  }
  /* Reduced motion is never shown a single one of these frames, so it should
     not download 3.5MB of them either — the cohort most likely to be on a
     metered or low-power device was the one paying in full. Deferred rather
     than killed: the setting can be turned off mid-session, and tick() starts
     the instance the moment it is. */
  if (stage && stage.reducedMotion) {
    inst.deferred = true
    return
  }
  inst.deferred = false
  fetch(TRACK_URL, { credentials: 'same-origin' })
    .then(function (r) {
      if (!r.ok) throw new Error('track ' + r.status)
      return r.json()
    })
    .then(function (t) {
      if (!t || !t.quads || !t.quads.length) throw new Error('empty track')
      inst.track = t
      inst.imgs = new Array(t.frames)
      inst.ladder = null // forces measure() to pick one and start the fetch
      measure(inst)
    })
    .catch(function (err) {
      inst.dead = true
      console.warn('[fx] dive stayed still —', err && err.message)
    })
}

/* ── public ──────────────────────────────────────────────────────────────── */

export function initDive(target, config) {
  const cfg = Object.assign({}, DEFAULTS, config || {})
  if (typeof document === 'undefined') return null

  const els = Array.prototype.slice.call(
    document.querySelectorAll(target || '[' + ATTR + ']')
  )
  if (!els.length) return null

  injectCSS()
  const mine = []

  els.forEach(function (section) {
    if (section.__fxDive) return
    const trackEl = section.querySelector('.dive__track')
    const canvas = section.querySelector('.dive__canvas')
    const panel = section.querySelector('.dive__app')
    if (!trackEl || !canvas || !panel) return
    const stageEl = section.querySelector('.dive__stage')
    const ctx = canvas.getContext('2d', { alpha: true })
    if (!ctx) return

    const inst = {
      section: section,
      trackEl: trackEl,
      stageEl: stageEl,
      canvas: canvas,
      ctx: ctx,
      panel: panel,
      cfg: cfg,
      track: null,
      ladder: null,
      gen: 0, // bumped on a ladder swap; strands the old pump's callbacks
      imgs: [],
      loaded: 0,
      missing: 0,
      frameAspect: 16 / 9,
      near: false,
      started: false,
      deferred: false, // in view, but reduced motion is holding the fetch
      dead: false,
      on: false,
      live: null, // tri-state: null means the inert attribute is unwritten
      phone: false,
      drawn: -1,
      vw: 0,
      vh: 0,
      dpr: 1,
      travel: 0,
      scrubPx: 0,
      handoffPx: 0,
      target: null,
      w: {}, // last written custom-property values
    }
    section.__fxDive = inst
    registry.add(inst)
    mine.push(inst)
  })

  if (!mine.length) return null

  ensureShared()
  if (io) {
    mine.forEach(function (inst) {
      io.observe(inst.section)
    })
  } else {
    // No IntersectionObserver: fetch immediately rather than never.
    mine.forEach(function (inst) {
      inst.near = true
      inst.started = true
      begin(inst)
    })
  }

  return {
    dives: mine.length,
    destroy: function () {
      mine.forEach(function (inst) {
        inst.dead = true
        disarm(inst)
        if (io) io.unobserve(inst.section)
        delete inst.section.__fxDive
        registry.delete(inst)
      })
      mine.length = 0
      teardownShared()
    },
  }
}
