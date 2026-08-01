/* fx/grain.js — 256² static film grain over the night ground.
 *
 * Composed from `cinematic-grade`, grain path only. Bloom, chromatic
 * aberration, DOF and vignette are banned by name: chromatic aberration on a
 * fee table reads as a rendering bug, and the full skill would cost a WebGL
 * renderer plus a 6.39.2 postprocessing stack to add noise that a ~2KB CSS
 * overlay delivers. This build ships zero WebGL.
 *
 * One tiling noise data-URI, repeated 1:1 at `tile` px with no scaling, laid
 * over the night bands and over the hero's existing `.grain` div. It kills the
 * banding a flat dark ground gets on 8-bit and OLED panels and makes that
 * ground read as printed stock rather than a <div>.
 *
 * Static. Never animated. Never disabled at any quality tier — animated grain
 * is a music video; static grain is invisible as an effect and enormous as a
 * quality signal, and it is load-bearing for the look.
 *
 * Everything below runs once. There is no rAF loop, no stage subscription, no
 * event listener and no JS at all after init — grain is not motion, so it does
 * not read `stage.reducedMotion`, and it does not care what the fee is, so it
 * does not subscribe to `fuime:fee`. Injecting the sheet and setting one
 * attribute per host is the whole module.
 *
 * Colour: none. The overlay is a monochrome luminance field composited with
 * mix-blend-mode, so it takes its colour from whatever it sits on and reads no
 * custom property. There is no hex literal in this file because there is no
 * colour in this file.
 */

const NAME = 'grain'
const ATTR = 'data-fx-grain'
const STYLE_SEL = 'style[data-fx="' + NAME + '"]'

const DEFAULTS = {
  /* 0.03 is the whole design. Below 0.02 the dither stops clearing a
     quantisation step; above 0.04 it stops being grain and starts being dirt,
     so the value is clamped to that range rather than trusted. */
  opacity: 0.03,
  bands: '.band--night',
  mounts: '.grain',
  tile: 256,
  blend: 'overlay',
}

const OPACITY_MIN = 0.02
const OPACITY_MAX = 0.04
/* overlay holds the mean of the ground exactly (a 0.5 sample returns the base
   colour untouched) and moves only the variance, which is the one property a
   dither pattern must have. The others are here so a caller can retune the
   hero without editing this file; anything unrecognised falls back to overlay
   rather than emitting a declaration the parser will drop. */
const BLENDS = ['overlay', 'soft-light', 'normal', 'screen', 'multiply']

/* Module-level, because the stylesheet is shared by every instance on the
   page: the second init must not duplicate it and the first destroy must not
   pull it out from under the second instance. */
let sheetEl = null
let sheetOwned = false
let live = 0
/* The config baked into the sheet, or null if the sheet came from somewhere
   this module cannot see. Lets tag() write an inline override only for the
   keys an instance actually disagrees with — which on this site is none. */
let sheetCfg = null

function num(v, lo, hi, fallback) {
  const n = Number(v)
  if (!Number.isFinite(n)) return fallback
  return Math.min(hi, Math.max(lo, n))
}

function normalize(config) {
  const c = Object.assign({}, DEFAULTS, config || {})
  return {
    opacity: num(c.opacity, OPACITY_MIN, OPACITY_MAX, DEFAULTS.opacity),
    tile: Math.round(num(c.tile, 8, 1024, DEFAULTS.tile)),
    blend: BLENDS.indexOf(c.blend) === -1 ? DEFAULTS.blend : c.blend,
    bands: typeof c.bands === 'string' ? c.bands : DEFAULTS.bands,
    mounts: typeof c.mounts === 'string' ? c.mounts : DEFAULTS.mounts,
  }
}

/* The tile.
 *
 * fractalNoise rather than a canvas PNG: random per-pixel noise is
 * incompressible, so a 256² PNG lands near 100KB while this is ~450 bytes
 * encoded. stitchTiles='stitch' snaps the frequencies to the tile so the
 * repeat has no seam, and the filter region is pinned to the tile in user
 * units so the default -10%/+10% region cannot shift it off the grid.
 *
 * saturate 0 removes the chroma — coloured noise on a dark band reads as
 * compression, not film. The linear transfer then stretches the distribution
 * out to the full range around mid grey, which is what gives the overlay
 * enough variance to clear a quantisation step on a ground this dark, and the
 * discrete alpha flattens the tile to fully opaque so opacity is the only
 * strength control.
 *
 * color-interpolation-filters='sRGB' is load-bearing, not boilerplate. The SVG
 * default is linearRGB, and a fractalNoise field centred on 0.5 in linear
 * light encodes to ~0.735 in sRGB — so the tile a browser actually composites
 * would sit three quarters of the way up the range, and `overlay` (2·base·blend
 * on a dark ground) would lift the night band by ~1.4% instead of holding it.
 * Pinned to sRGB, the mean is 0.5 on the wire, overlay is a pure variance
 * operator, and the stretch is symmetric about mid grey the way the transfer
 * above assumes.
 */
function noiseUrl(tile) {
  const svg =
    "<svg xmlns='http://www.w3.org/2000/svg' width='" +
    tile +
    "' height='" +
    tile +
    "'>" +
    "<filter id='fx-grain-n' color-interpolation-filters='sRGB' filterUnits='userSpaceOnUse' x='0' y='0' width='" +
    tile +
    "' height='" +
    tile +
    "'>" +
    "<feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3' stitchTiles='stitch' seed='11'/>" +
    "<feColorMatrix type='saturate' values='0'/>" +
    '<feComponentTransfer>' +
    "<feFuncR type='linear' slope='3' intercept='-1'/>" +
    "<feFuncG type='linear' slope='3' intercept='-1'/>" +
    "<feFuncB type='linear' slope='3' intercept='-1'/>" +
    "<feFuncA type='discrete' tableValues='1'/>" +
    '</feComponentTransfer>' +
    '</filter>' +
    "<rect width='" +
    tile +
    "' height='" +
    tile +
    "' filter='url(#fx-grain-n)'/>" +
    '</svg>'
  return 'url("data:image/svg+xml,' + encodeURIComponent(svg) + '")'
}

/* Two hosts, two layers.
 *
 * A band gets a ::after rather than an injected child, so no markup moves and
 * no :nth-child in style.css can be knocked off by one. isolation:isolate on
 * the band turns it into a stacking context, which is what lets the veil sit
 * at z-index -1: above the band's own background, below every scrap of content
 * in it. Text is therefore never composited through the grain and every
 * measured contrast ratio on the page stays exactly what it was.
 *
 * The hero's existing `.grain` div is a real element, already absolute and
 * already at z-index 1 over the photograph. The attribute is doubled up so the
 * rule outranks `.grain` in style.css no matter what order the sheets land in,
 * and the layout properties are restated so the module still works if that
 * rule is ever removed.
 *
 * The four custom properties are declared here as the floor and re-declared
 * inline on each host at tag time. The sheet is injected once and only once —
 * so without the inline pass a second init with a different `opacity` or
 * `tile` would silently render at the first init's numbers. Inline wins the
 * cascade, so every instance gets its own config; identical configs (the
 * single-init case this site actually ships) resolve to identical values and
 * nothing changes. `background-image:none` in the forced-colours block is a
 * real property, not a variable, so it still outranks both.
 */
function sheet(c, img) {
  return (
    '[' +
    ATTR +
    ']{--fx-grain-img:' +
    img +
    ';--fx-grain-size:' +
    c.tile +
    'px;--fx-grain-op:' +
    c.opacity +
    ';--fx-grain-blend:' +
    c.blend +
    '}\n' +
    '[' +
    ATTR +
    "='band']{isolation:isolate}\n" +
    '[' +
    ATTR +
    "='band']::after{content:'';position:absolute;inset:0;z-index:-1;" +
    'pointer-events:none;opacity:var(--fx-grain-op);' +
    'mix-blend-mode:var(--fx-grain-blend);background-image:var(--fx-grain-img);' +
    'background-size:var(--fx-grain-size) var(--fx-grain-size);' +
    'background-repeat:repeat}\n' +
    '[' +
    ATTR +
    "='mount'][" +
    ATTR +
    ']{position:absolute;inset:0;z-index:1;pointer-events:none;' +
    'opacity:var(--fx-grain-op);mix-blend-mode:var(--fx-grain-blend);' +
    'background-image:var(--fx-grain-img);' +
    'background-size:var(--fx-grain-size) var(--fx-grain-size);' +
    'background-repeat:repeat}\n' +
    /* In forced colours the ground is the user's, not ours, and a blend layer
       over it is noise in the literal sense. */
    '@media (forced-colors: active){[' +
    ATTR +
    "='band']::after{content:none}[" +
    ATTR +
    "='mount'][" +
    ATTR +
    ']{background-image:none}}\n'
  )
}

/* Returns true only when THIS call created the sheet, so a caller that then
   fails can take its own litter back out. */
function ensureSheet(c, img) {
  const found = document.querySelector(STYLE_SEL)
  if (found) {
    sheetEl = found
    return false
  }
  const el = document.createElement('style')
  el.setAttribute('data-fx', NAME)
  el.textContent = sheet(c, img)
  ;(document.head || document.documentElement).appendChild(el)
  sheetEl = el
  sheetOwned = true
  sheetCfg = c
  return true
}

function dropSheet() {
  if (sheetOwned && sheetEl && sheetEl.parentNode) {
    sheetEl.parentNode.removeChild(sheetEl)
  }
  if (sheetOwned) {
    sheetEl = null
    sheetOwned = false
    sheetCfg = null
  }
}

function query(root, selector) {
  if (!selector) return []
  try {
    return Array.prototype.slice.call(root.querySelectorAll(selector))
  } catch (e) {
    /* A bad selector from config is a config bug, not a page bug. */
    return []
  }
}

/**
 * @param {ParentNode|object} [target] root to scan, or the config object
 * @param {object} [config] { opacity, bands, mounts, tile, blend }
 * @returns {{ destroy(): void, refresh(): number, count: number }}
 */
export function initGrain(target, config) {
  const inert = {
    destroy: function () {},
    refresh: function () {
      return 0
    },
    get count() {
      return 0
    },
  }
  if (typeof document === 'undefined') return inert

  let root = target
  let cfg = config
  if (root && typeof root.querySelectorAll !== 'function') {
    /* initGrain(config) — the signature in the spec — as well as
       initGrain(root, config), the house signature. */
    cfg = root
    root = null
  }
  root = root || document

  const c = normalize(cfg)
  const tagged = []
  const VARS = [
    '--fx-grain-img',
    '--fx-grain-size',
    '--fx-grain-op',
    '--fx-grain-blend',
  ]
  let img = ''
  let destroyed = false

  function tag(el, kind) {
    if (!el || el.nodeType !== 1) return false
    /* Already grained by an earlier instance: leave it alone so that
       instance's destroy() stays the only thing that can untag it. */
    if (el.hasAttribute(ATTR)) return false
    el.setAttribute(ATTR, kind)
    /* This instance's config, on this instance's hosts, but only where it
       disagrees with the sheet — otherwise a single-init page would carry a
       redundant copy of the ~700-byte data URI on every band. See sheet(). */
    try {
      if (!sheetCfg || sheetCfg.tile !== c.tile) {
        el.style.setProperty(VARS[0], img)
        el.style.setProperty(VARS[1], c.tile + 'px')
      }
      if (!sheetCfg || sheetCfg.opacity !== c.opacity) {
        el.style.setProperty(VARS[2], String(c.opacity))
      }
      if (!sheetCfg || sheetCfg.blend !== c.blend) {
        el.style.setProperty(VARS[3], c.blend)
      }
    } catch (e) {}
    tagged.push(el)
    return true
  }

  function scan() {
    const before = tagged.length
    const bands = query(root, c.bands)
    for (let i = 0; i < bands.length; i++) tag(bands[i], 'band')
    const mounts = query(root, c.mounts)
    for (let j = 0; j < mounts.length; j++) tag(mounts[j], 'mount')
    return tagged.length - before
  }

  function untag() {
    for (let i = 0; i < tagged.length; i++) {
      try {
        tagged[i].removeAttribute(ATTR)
        for (let v = 0; v < VARS.length; v++) {
          tagged[i].style.removeProperty(VARS[v])
        }
      } catch (e) {}
    }
    tagged.length = 0
  }

  let mine = false
  try {
    img = noiseUrl(c.tile)
    mine = ensureSheet(c, img)
    scan()
  } catch (e) {
    /* Failure mode: there isn't one to speak of, and this is why. Grain is a
       background image on a pointer-events:none overlay that carries no
       content and blocks nothing. If the sheet cannot be injected, if the data
       URI never decodes, if the markup is missing entirely — the band is flat,
       which is exactly what ships today. So the only correct response to a
       throw is to put the DOM back and stand down quietly.

       `mine && live === 0` is the orphan case: this call got the sheet in and
       then threw, and it never reached `live++`, so no handle exists that
       would ever take the sheet out again. Anything already live keeps it. */
    untag()
    if (mine && live === 0) dropSheet()
    return inert
  }

  live++

  return {
    get count() {
      return tagged.length
    },
    /* Nothing on this site inserts a night band after load. This is here for
       the case where something one day does. */
    refresh: function () {
      if (destroyed) return 0
      try {
        return scan()
      } catch (e) {
        return 0
      }
    },
    /* Guarded, because `live` is module-wide. An unguarded second destroy()
       on one handle would decrement the count for an instance that is still
       mounted, pull the shared sheet, and silently un-grain the page. */
    destroy: function () {
      if (destroyed) return
      destroyed = true
      untag()
      live = Math.max(0, live - 1)
      if (live === 0) dropSheet()
    },
  }
}
