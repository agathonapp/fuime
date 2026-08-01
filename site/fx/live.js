/* fx/live.js — every still→video handoff on the site.
 *
 * The photograph is the hero. The clip is a privilege the page earns: it is
 * not fetched until the band is nearly on screen, it is not swapped in until
 * the browser says it can play the whole thing without stalling, it plays
 * exactly once, and then it freezes on its last frame. Nothing here scrubs a
 * <video>. Keyframe seeking stutters, iOS throttles seeks, and every clip on
 * this site is a crossfade instead.
 *
 * The default state of the markup — with this file deleted, throwing, or never
 * reached — is the still, fully composed. Every rule below only ever adds the
 * video on top. That is the whole safety story: a play() rejection, a codec
 * refusal, a throttled connection and a text-mode reader all land on the same
 * correct page.
 *
 * Two seams this module is responsible for and CSS alone cannot close:
 *   • the stills carry a parallax transform (scale + drift). The video mirrors
 *     the still's computed transform every frame, so the swap does not pop 6%.
 *   • sub-pixel drift between a compressed first video frame and the shipped
 *     still is masked by blurring the outgoing still for the length of the
 *     crossfade, then dropping the filter once the video is opaque.
 */

import { getStage } from 'cwe/stage'

const DEFAULTS = {
  plays: 1,
  crossfadeMs: 250,
  blur: 6,
  holdLastFrame: true,
  rootMargin: '200px',
  // Everything on this site that is a <video> is one of these handoffs.
  selector: 'video',
  // The layout breakpoint (integration item 19), not a phone-detect.
  portraitQuery: '(max-width: 900px)',
  // Below that breakpoint, play only clips that have declared a portrait cut.
  portraitNeedsCut: true,
  // How much of the band has to be on screen before the one play is spent.
  playRatio: 0.2,
}

const STYLE_MARK = 'style[data-fx="live"]'
const NETWORK_LOADING = 2 // HTMLMediaElement.NETWORK_LOADING
const HAVE_FUTURE_DATA = 3 // HTMLMediaElement.HAVE_FUTURE_DATA

/* The still is the default and the final state. Everything below only fades a
   video in on top of it. `[data-fx-live]` is set by JS, so with JS off none of
   this applies and the markup renders exactly as authored. */
const CSS = `
[data-fx-live] .fx-live__video {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  opacity: 0;
  pointer-events: none;
  transition: opacity var(--fx-live-fade, 250ms) var(--fx-live-ease, linear);
}
[data-fx-live][data-fx-live-state='live'] .fx-live__video,
[data-fx-live][data-fx-live-state='settled'] .fx-live__video {
  opacity: 1;
}
/* Sub-pixel drift between a compressed first video frame and the shipped still
   is masked by blurring the outgoing layer for the length of the crossfade
   only. At 'settled' the rule stops matching and the filter is dropped, which
   hands a phone back the compositing layer. Declaring the transition on this
   rule and not the base one is deliberate: the blur fades in over the
   crossfade and is cut instantly at the end, under an already-opaque video. */
[data-fx-live][data-fx-live-state='live'] .fx-live__still {
  filter: blur(var(--fx-live-blur, 6px));
  transition: filter var(--fx-live-fade, 250ms) var(--fx-live-ease, linear);
}
@media (prefers-reduced-motion: reduce) {
  [data-fx-live] .fx-live__video,
  [data-fx-live][data-fx-live-state='live'] .fx-live__still {
    transition-duration: 1ms;
  }
}
/* Paper gets the photograph, and gets it sharp. */
@media print {
  [data-fx-live] .fx-live__video {
    display: none;
  }
  [data-fx-live][data-fx-live-state='live'] .fx-live__still {
    filter: none;
  }
}
`

function noop() {}

function injectStyle() {
  if (document.querySelector(STYLE_MARK)) return
  const el = document.createElement('style')
  el.setAttribute('data-fx', 'live')
  el.textContent = CSS
  document.head.appendChild(el)
}

function resolveRoot(target) {
  if (!target) return document
  if (typeof target === 'string')
    return document.querySelector(target) || document
  if (target.querySelectorAll) return target
  return document
}

/* One motion gate, owned by ledger-bus. If the boot script hands us the bus we
   read its live object; otherwise we ask the same questions locally so this
   module is still correct when initialised on its own. */
function resolveMotion(cfg) {
  if (cfg.motion) return cfg.motion
  if (cfg.ledgerBus && cfg.ledgerBus.motion) return cfg.ledgerBus.motion
  const reducedQ = matchMedia('(prefers-reduced-motion: reduce)')
  return {
    get reduced() {
      return reducedQ.matches
    },
    get saveData() {
      return !!(navigator.connection && navigator.connection.saveData)
    },
    tier: 'high',
  }
}

function slowLink() {
  const conn = navigator.connection
  if (!conn) return false
  return /(^|-)2g$/.test(conn.effectiveType || '')
}

function typeFor(url) {
  if (/\.webm(\?|$)/i.test(url)) return 'video/webm'
  if (/\.mp4(\?|$)/i.test(url)) return 'video/mp4'
  if (/\.mov(\?|$)/i.test(url)) return 'video/quicktime'
  return ''
}

/* The still is whatever actually paints underneath, or an explicit element
   named by `data-fx-live-still`. The <img> is preferred over its <picture>
   wrapper on purpose: the img is the element carrying the parallax transform
   and the object-fit framing we have to match, and the wrapper carries
   neither. No still at all means no floor to fall back to, and a module whose
   default state is "nothing" is the bug this whole build exists to fix — so we
   decline the element and leave the markup exactly as authored. */
function findStill(video) {
  const sel = video.getAttribute('data-fx-live-still')
  if (sel) {
    const named =
      (video.parentElement && video.parentElement.querySelector(sel)) ||
      document.querySelector(sel)
    if (named && named !== video) return named
  }
  // Deliberately one level only. A handoff is two layers of one media box; a
  // walk up the tree finds an unrelated photograph three sections away and
  // hides a video behind it, which is worse than doing nothing.
  const scope = video.parentElement
  if (!scope) return null
  // `img, canvas` already reaches inside a <picture>, so a <picture> fallback
  // could only ever match one holding no <img> — an element that paints
  // nothing. Crossfading onto that is the "no floor" case wearing a costume.
  const found = scope.querySelector('img, canvas')
  if (found && found !== video && !video.contains(found)) return found
  return null
}

/* The box both layers share. Walk up from the video until we find the ancestor
   that also holds the still — that is the frame the crossfade happens inside. */
function findContainer(video, still) {
  let el = video.parentElement
  for (let i = 0; i < 4 && el; i++) {
    if (el.contains(still)) return el
    el = el.parentElement
  }
  return null
}

export function initLive(target, config) {
  if (typeof document === 'undefined') return { destroy: noop, count: 0 }

  const cfg = Object.assign({}, DEFAULTS, config || {})
  const root = resolveRoot(target)
  const stage = getStage()
  const motion = resolveMotion(cfg)
  const rootPx = parseFloat(cfg.rootMargin) || 0
  // A unitless margin makes the IntersectionObserver constructor throw, which
  // would take the whole init down with the DOM already half-marked.
  const rootMargin = /^-?[\d.]+$/.test(String(cfg.rootMargin).trim())
    ? rootPx + 'px'
    : cfg.rootMargin

  const ease =
    getComputedStyle(document.documentElement)
      .getPropertyValue('--ease')
      .trim() || 'linear'

  /* Reduced motion, save-data, a 2G link or a device already dropping frames:
     the video is never requested. The poster frame and the still are the same
     photograph, so there is nothing to notice — and it is 120KB unspent on the
     page with the tightest budget. */
  function blocked() {
    return (
      stage.reducedMotion ||
      motion.reduced ||
      motion.saveData ||
      motion.tier === 'low' ||
      slowLink()
    )
  }

  const items = []
  const observers = []
  const timers = []

  /* ── one item ───────────────────────────────────────────────────────── */

  function mount(video) {
    if (video.dataset.fxLiveBound === '1') return null
    if (video.hasAttribute('data-fx-live-skip')) return null

    const still = findStill(video)
    if (!still) return null
    const container = findContainer(video, still)
    if (!container) return null

    // Decided before anything is touched, so a blocked page keeps the exact
    // markup and behaviour it shipped with.
    if (blocked()) return null

    /* Mobile is a design, not the desktop version with things switched off. At
       the portrait breakpoint the phone is looking at a 4:5 photograph, and
       cross-dissolving a 2.37:1 landscape clip into it is two different
       pictures rather than one handoff. So the phone plays a clip only when a
       portrait cut of it has been declared — and it costs nothing until then.
       A clip that is already portrait declares itself as its own cut. */
    if (
      cfg.portraitNeedsCut &&
      matchMedia(cfg.portraitQuery).matches &&
      !video.getAttribute('data-fx-live-portrait')
    ) {
      return null
    }

    const item = {
      video,
      still,
      container,
      state: 'idle',
      primed: false,
      ready: false,
      wanted: false,
      done: false,
      played: 0,
      endedAt: 0,
      lastTransform: '',
      swapped: null,
      tookPosition: false,
      prevPosition: '',
      prevPreload: video.getAttribute('preload'),
    }

    // Before a single class is added, so a throw anywhere below cannot leave a
    // marked element on a page whose rules for it never arrived.
    injectStyle()

    video.dataset.fxLiveBound = '1'
    video.classList.add('fx-live__video')
    still.classList.add('fx-live__still')

    // The attribute is removed by integration item 18; the property is what
    // actually governs playback, and it is ours to set either way.
    video.loop = false
    video.muted = true
    video.playsInline = true
    video.controls = false
    video.disablePictureInPicture = true
    video.disableRemotePlayback = true
    if (!video.hasAttribute('aria-hidden'))
      video.setAttribute('aria-hidden', 'true')
    if (!video.hasAttribute('tabindex')) video.setAttribute('tabindex', '-1')

    // Never in the stylesheet: `.hero__media` is already absolute and a
    // blanket `position: relative` in injected CSS would fight it.
    if (getComputedStyle(container).position === 'static') {
      item.tookPosition = true
      item.prevPosition = container.style.position
      container.style.position = 'relative'
    }

    container.setAttribute('data-fx-live', '')
    container.setAttribute('data-fx-live-state', 'idle')
    container.style.setProperty('--fx-live-fade', cfg.crossfadeMs + 'ms')
    container.style.setProperty('--fx-live-ease', ease)
    container.style.setProperty('--fx-live-blur', cfg.blur + 'px')

    syncBox(item)
    mirror(item)

    item.onCanPlay = function () {
      item.ready = true
      maybePlay(item)
    }
    item.onPlaying = function () {
      crossfade(item)
    }
    item.onEnded = function () {
      item.played++
      if (item.played < cfg.plays) {
        try {
          video.currentTime = 0
        } catch (e) {}
        play(item)
        return
      }
      item.done = true
      item.endedAt = video.currentTime || video.duration || 0
      // holdLastFrame: the browser keeps the last decoded frame on a paused,
      // ended video. That freeze is the shot. Turn it off and we hand the
      // frame back to the still.
      if (!cfg.holdLastFrame) revert(item)
    }
    item.onError = function () {
      item.done = true
      revert(item)
    }
    /* site.js keeps its own hero pass and re-calls play() every time the band
       scrolls back into view. On an ended clip that seeks to 0 and runs the
       whole thing again, which is not "plays exactly once and freezes". The one
       play is spent here, so put the frame back and stop. Not a scrub: it is a
       single restore of the frame we were already holding. */
    item.onPlay = function () {
      if (!item.done || !cfg.holdLastFrame) return
      try {
        video.pause()
      } catch (e) {}
      if (item.endedAt > 0 && video.currentTime < item.endedAt) {
        try {
          video.currentTime = item.endedAt
        } catch (e) {}
      }
    }

    video.addEventListener('canplaythrough', item.onCanPlay)
    video.addEventListener('playing', item.onPlaying)
    video.addEventListener('ended', item.onEnded)
    video.addEventListener('error', item.onError)
    video.addEventListener('play', item.onPlay)

    // site.js keeps its own hero pass as the no-modules floor. If it got there
    // first and the clip is genuinely running, adopt it rather than starting a
    // second pass.
    if (!video.paused && !video.ended && video.currentTime > 0) crossfade(item)

    return item
  }

  /* ── geometry ───────────────────────────────────────────────────────── */

  // Match the still's framing exactly, so the crossfade is two versions of one
  // photograph rather than two crops of it.
  function syncBox(item) {
    const tag = item.still.tagName
    if (tag !== 'IMG' && tag !== 'VIDEO') return
    const cs = getComputedStyle(item.still)
    item.video.style.objectFit = cs.objectFit
    item.video.style.objectPosition = cs.objectPosition
  }

  // The stills are scaled 1.06 and drift with the pointer and with scroll. The
  // video has to carry the same transform or the swap is a 6% jump.
  function mirror(item) {
    const t = getComputedStyle(item.still).transform
    if (t && t !== 'none') {
      if (t !== item.lastTransform) {
        item.lastTransform = t
        item.video.style.transform = t
      }
    } else if (item.lastTransform) {
      item.lastTransform = ''
      item.video.style.transform = ''
    }
  }

  /* ── playback ───────────────────────────────────────────────────────── */

  // Nothing is fetched until this runs. `preload="none"` in the markup is what
  // keeps the 409KB portal clip off a first paint eleven screens above it.
  function prime(item) {
    if (item.primed || item.done) return
    // Re-asked at the last possible moment: the gate can close between mount
    // and the band arriving, and "the video is never requested" has to mean it.
    if (blocked()) return
    item.primed = true
    const swapped = swapPortrait(item)
    const v = item.video
    try {
      v.preload = 'auto'
      // site.js keeps its own hero pass as the floor for a no-modules page. If
      // it got the fetch started first, calling load() again would throw those
      // bytes away and ask for them a second time.
      const busy = v.readyState > 0 || v.networkState === NETWORK_LOADING
      if (swapped || !busy) v.load()
    } catch (e) {}
  }

  function want(item) {
    item.wanted = true
    maybePlay(item)
  }

  function maybePlay(item) {
    if (item.done || !item.ready || !item.wanted) return
    if (blocked()) return
    play(item)
  }

  function play(item) {
    try {
      const p = item.video.play()
      // Autoplay refusal is normal, not exceptional. The still stays.
      if (p && p.catch) p.catch(noop)
    } catch (e) {}
  }

  function crossfade(item) {
    if (item.state !== 'idle') return
    // Spent, errored, or stopped by a mid-session preference change. `playing`
    // can still arrive after any of those — site.js re-plays the hero clip
    // every time the band comes back — and the swap is a one-way door.
    if (item.done) return
    // The swap is gated on the clip being genuinely playable, never on
    // metadata and never on `paused` — `paused` flips to false the instant
    // anything calls play(), including on a video whose bytes never arrive.
    if (item.video.readyState < HAVE_FUTURE_DATA) return
    item.state = 'live'
    mirror(item)
    item.container.setAttribute('data-fx-live-state', 'live')

    // Once the video is opaque the blurred still is invisible, so drop the
    // filter and give a phone back the compositing layer.
    const t = setTimeout(function () {
      if (item.state !== 'live') return
      item.state = 'settled'
      item.container.setAttribute('data-fx-live-state', 'settled')
    }, cfg.crossfadeMs + 60)
    timers.push(t)
  }

  function revert(item) {
    item.state = 'idle'
    item.container.setAttribute('data-fx-live-state', 'idle')
  }

  /* ── the portrait cut ───────────────────────────────────────────────── */

  /* `<source media>` is ignored inside <video> by every shipping browser, so
     the phone cut is chosen here, once, before the first byte is requested. A
     rotation afterwards does not re-fetch: a second download to change a crop
     is a worse deal than the crop. */
  function swapPortrait(item) {
    const raw = item.video.getAttribute('data-fx-live-portrait')
    if (!raw) return false
    if (!matchMedia(cfg.portraitQuery).matches) return false
    const urls = raw
      .split(',')
      .map(s => s.trim())
      .filter(Boolean)
    if (!urls.length) return false

    const originals = Array.prototype.slice.call(
      item.video.querySelectorAll('source')
    )
    const same =
      originals.length === urls.length &&
      originals.every(function (s, i) {
        return s.getAttribute('src') === urls[i]
      })
    // A clip that is already portrait names itself as its own cut. Nothing to
    // swap, and nothing to put back on destroy.
    if (same) return false

    originals.forEach(function (s) {
      item.video.removeChild(s)
    })
    urls.forEach(function (url) {
      const s = document.createElement('source')
      s.setAttribute('src', url)
      const type = typeFor(url)
      if (type) s.setAttribute('type', type)
      item.video.appendChild(s)
    })
    item.swapped = originals
    return true
  }

  /* ── mounting ───────────────────────────────────────────────────────── */

  const found = Array.prototype.slice.call(root.querySelectorAll(cfg.selector))
  found.forEach(function (v) {
    if (v.tagName !== 'VIDEO') return
    const item = mount(v)
    if (item) items.push(item)
  })

  // Not "does this browser have IO" but "did we actually get two working
  // observers onto these elements". A constructor that throws on a bad margin
  // has to fall through to the rAF gates, not silently stop mounting clips.
  let usingIO = false

  if (items.length && typeof IntersectionObserver !== 'undefined') {
    try {
      // Two stages on purpose. The first buys the bytes early enough that the
      // clip is ready when the band arrives; the second spends the single play
      // only once the band is actually being looked at.
      const loadIO = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (e) {
            if (!e.isIntersecting) return
            const item = itemFor(e.target)
            if (item) prime(item)
            loadIO.unobserve(e.target)
          })
        },
        { rootMargin: rootMargin, threshold: 0 }
      )
      const playIO = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (e) {
            if (!e.isIntersecting) return
            const item = itemFor(e.target)
            if (item) want(item)
            playIO.unobserve(e.target)
          })
        },
        { rootMargin: '0px', threshold: cfg.playRatio }
      )
      items.forEach(function (item) {
        loadIO.observe(item.container)
        playIO.observe(item.container)
      })
      observers.push(loadIO, playIO)
      usingIO = true
    } catch (e) {
      observers.forEach(function (o) {
        o.disconnect()
      })
      observers.length = 0
      usingIO = false
    }
  }

  function itemFor(el) {
    for (let i = 0; i < items.length; i++) {
      if (items[i].container === el) return items[i]
    }
    return null
  }

  /* ── the shared loop ────────────────────────────────────────────────── */

  let tick = 0
  const offFrame = items.length
    ? stage.register(function () {
        tick++
        for (let i = 0; i < items.length; i++) {
          const item = items[i]
          if (item.state !== 'idle') mirror(item)
          // No IntersectionObserver: the same two gates, measured on the one
          // rAF loop four times a second. Still nothing fetched at t=0.
          if (!usingIO && !item.done && tick % 15 === 0) {
            const r = item.container.getBoundingClientRect()
            const h = stage.viewport.h || window.innerHeight
            if (!item.primed && r.top < h + rootPx && r.bottom > -rootPx) {
              prime(item)
            }
            if (!item.wanted && r.top < h && r.bottom > 0) want(item)
          }
        }
      })
    : noop

  const offResize = items.length
    ? stage.onResize(function () {
        items.forEach(syncBox)
      })
    : noop

  /* ── live preference changes ────────────────────────────────────────── */

  // Turning reduced motion on mid-session stops the clip and hands the frame
  // back to the photograph. Nothing restarts it; the swap is a one-way door.
  const reducedQ = matchMedia('(prefers-reduced-motion: reduce)')
  function onReduced(e) {
    if (!e.matches) return
    items.forEach(function (item) {
      item.done = true
      try {
        item.video.pause()
      } catch (err) {}
      revert(item)
    })
  }
  if (items.length && reducedQ.addEventListener) {
    reducedQ.addEventListener('change', onReduced)
  }

  return {
    count: items.length,
    destroy: function () {
      offFrame()
      offResize()
      if (reducedQ.removeEventListener) {
        reducedQ.removeEventListener('change', onReduced)
      }
      observers.forEach(function (o) {
        o.disconnect()
      })
      timers.forEach(clearTimeout)
      items.forEach(function (item) {
        const v = item.video
        v.removeEventListener('canplaythrough', item.onCanPlay)
        v.removeEventListener('playing', item.onPlaying)
        v.removeEventListener('ended', item.onEnded)
        v.removeEventListener('error', item.onError)
        v.removeEventListener('play', item.onPlay)
        try {
          v.pause()
        } catch (e) {}
        // prime() raised this to 'auto'. Handing the element back still hungry
        // would have the next reader fetch a clip nobody asked for.
        if (item.prevPreload === null) v.removeAttribute('preload')
        else v.setAttribute('preload', item.prevPreload)
        v.disablePictureInPicture = false
        v.disableRemotePlayback = false
        if (item.swapped) {
          Array.prototype.slice
            .call(v.querySelectorAll('source'))
            .forEach(function (s) {
              v.removeChild(s)
            })
          item.swapped.forEach(function (s) {
            v.appendChild(s)
          })
        }
        v.classList.remove('fx-live__video')
        item.still.classList.remove('fx-live__still')
        v.style.transform = ''
        v.style.objectFit = ''
        v.style.objectPosition = ''
        delete v.dataset.fxLiveBound
        item.container.removeAttribute('data-fx-live')
        item.container.removeAttribute('data-fx-live-state')
        item.container.style.removeProperty('--fx-live-fade')
        item.container.style.removeProperty('--fx-live-ease')
        item.container.style.removeProperty('--fx-live-blur')
        if (item.tookPosition) item.container.style.position = item.prevPosition
      })
      items.length = 0
      // The <style> tag stays: it is shared by every instance and guarded
      // against duplication, and tearing it out would strip a sibling mount.
    },
  }
}
