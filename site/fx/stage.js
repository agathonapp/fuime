/**
 * stage.js — the shared runtime for crazy-web-effects (CWE).
 * ─────────────────────────────────────────────────────────────────────────
 * This is the concrete implementation of CONTRACT.md. Every effect-skill plugs
 * into ONE Stage so that a page running five engines at once has:
 *   • a single requestAnimationFrame loop (no double-rAF jank),
 *   • one source of truth for pointer + scroll + viewport,
 *   • one prefers-reduced-motion gate,
 *   • disciplined teardown.
 *
 * Effects never attach their own rAF/scroll listeners. They do:
 *
 *   import { getStage } from '<webgl-scene-kit>/stage.js'
 *   const stage = config.stage || getStage()
 *   const off = stage.register((dt, t) => {
 *     if (stage.reducedMotion) return
 *     // read stage.pointer.{x,y,nx,ny,vx,vy}, stage.scroll.{y,progress,velocity}
 *   })
 *   // teardown: off()
 *
 * `smooth-scroll-stage` owns scroll: it calls stage.setScroll(...) each frame.
 * If no smooth-scroll is present, the Stage falls back to native window scroll.
 *
 * Self-contained, dependency-free, no build step. Works from a <script type=module>
 * or bundled into React. SSR-safe (returns an inert stage when there's no window).
 */

const RM_QUERY = '(prefers-reduced-motion: reduce)';
const KEY = '__CWE_STAGE__';

function createInert() {
  const noop = () => {};
  return {
    inert: true, reducedMotion: false,
    pointer: { x: 0, y: 0, nx: 0, ny: 0, vx: 0, vy: 0, down: false },
    scroll: { y: 0, progress: 0, velocity: 0 },
    viewport: { w: 0, h: 0, dpr: 1 },
    register: () => noop, onResize: () => noop,
    setScroll: noop, start: noop, destroy: noop,
  };
}

/**
 * Create a Stage. Normally you don't call this directly — use getStage(), which
 * lazily creates a singleton and stashes it on window so every effect on the
 * page shares it.
 */
export function createStage(options = {}) {
  if (typeof window === 'undefined') return createInert();

  const {
    respectReducedMotion = true,
    // Pointer smoothing toward the raw cursor (0 = instant, 1 = frozen). The
    // award sites lerp the pointer so WebGL uniforms feel weighty.
    pointerLerp = 0.12,
  } = options;

  const mql = respectReducedMotion ? window.matchMedia(RM_QUERY) : null;

  const state = {
    inert: false,
    reducedMotion: !!(mql && mql.matches),
    pointer: { x: 0, y: 0, nx: 0, ny: 0, vx: 0, vy: 0, down: false },
    scroll: { y: window.scrollY || 0, progress: 0, velocity: 0 },
    viewport: { w: window.innerWidth, h: window.innerHeight, dpr: Math.min(window.devicePixelRatio || 1, 2) },
  };

  // Raw pointer target (we lerp `pointer` toward this every frame).
  const rawPointer = { x: window.innerWidth / 2, y: window.innerHeight / 2 };
  let prevPX = rawPointer.x, prevPY = rawPointer.y;

  const frameCbs = new Set();   // (dt, t) => void
  const resizeCbs = new Set();  // (viewport) => void

  let rafId = 0, lastT = 0, destroyed = false;
  // True until a smooth-scroll provider calls setScroll(); then the Stage stops
  // reading native scroll and trusts the provider.
  let scrollOwnedExternally = false;

  /* ---- pointer ---------------------------------------------------------- */
  function onPointerMove(e) {
    const t = e.touches ? e.touches[0] : e;
    rawPointer.x = t.clientX;
    rawPointer.y = t.clientY;
  }
  function onPointerDown() { state.pointer.down = true; }
  function onPointerUp() { state.pointer.down = false; }

  /* ---- scroll (native fallback) ----------------------------------------- */
  function readNativeScroll() {
    const max = document.documentElement.scrollHeight - state.viewport.h;
    const y = window.scrollY || 0;
    const prevY = state.scroll.y;
    state.scroll.y = y;
    state.scroll.progress = max > 0 ? y / max : 0;
    state.scroll.velocity = y - prevY;
  }

  /**
   * Called by smooth-scroll-stage every frame to hand the Stage the smoothed
   * scroll values. Switches the Stage out of native-scroll mode.
   */
  function setScroll({ y, progress, velocity }) {
    scrollOwnedExternally = true;
    if (typeof y === 'number') state.scroll.y = y;
    if (typeof progress === 'number') state.scroll.progress = progress;
    if (typeof velocity === 'number') state.scroll.velocity = velocity;
  }

  /* ---- viewport / resize ------------------------------------------------ */
  function onResize() {
    state.viewport.w = window.innerWidth;
    state.viewport.h = window.innerHeight;
    state.viewport.dpr = Math.min(window.devicePixelRatio || 1, 2);
    for (const cb of resizeCbs) cb(state.viewport);
  }

  /* ---- reduced-motion live switching ------------------------------------ */
  function onMotionChange() { state.reducedMotion = !!(mql && mql.matches); }

  /* ---- the single loop -------------------------------------------------- */
  function loop(t) {
    if (destroyed) return;
    const dt = lastT ? Math.min((t - lastT) / 1000, 0.1) : 0.016;
    lastT = t;

    // Smooth pointer + compute velocity & normalized coords.
    const p = state.pointer;
    p.x += (rawPointer.x - p.x) * (1 - pointerLerp);
    p.y += (rawPointer.y - p.y) * (1 - pointerLerp);
    p.vx = p.x - prevPX;
    p.vy = p.y - prevPY;
    prevPX = p.x; prevPY = p.y;
    p.nx = state.viewport.w ? (p.x / state.viewport.w) * 2 - 1 : 0;   // -1..1
    p.ny = state.viewport.h ? -((p.y / state.viewport.h) * 2 - 1) : 0; // -1..1, y up

    if (!scrollOwnedExternally) readNativeScroll();

    for (const cb of frameCbs) cb(dt, t);
    rafId = requestAnimationFrame(loop);
  }

  /* ---- boot ------------------------------------------------------------- */
  window.addEventListener('mousemove', onPointerMove, { passive: true });
  window.addEventListener('touchmove', onPointerMove, { passive: true });
  window.addEventListener('mousedown', onPointerDown, { passive: true });
  window.addEventListener('mouseup', onPointerUp, { passive: true });
  window.addEventListener('touchstart', onPointerDown, { passive: true });
  window.addEventListener('touchend', onPointerUp, { passive: true });
  window.addEventListener('resize', onResize, { passive: true });
  mql?.addEventListener?.('change', onMotionChange);

  const api = {
    get inert() { return false; },
    get reducedMotion() { return state.reducedMotion; },
    get pointer() { return state.pointer; },
    get scroll() { return state.scroll; },
    get viewport() { return state.viewport; },
    /** Register a per-frame callback on the shared loop. Returns an unsubscribe fn. */
    register(cb) { frameCbs.add(cb); return () => frameCbs.delete(cb); },
    /** Register a resize callback. Returns an unsubscribe fn. */
    onResize(cb) { resizeCbs.add(cb); return () => resizeCbs.delete(cb); },
    setScroll,
    start() { if (!rafId) rafId = requestAnimationFrame(loop); },
    destroy() {
      destroyed = true;
      if (rafId) cancelAnimationFrame(rafId);
      rafId = 0;
      window.removeEventListener('mousemove', onPointerMove);
      window.removeEventListener('touchmove', onPointerMove);
      window.removeEventListener('mousedown', onPointerDown);
      window.removeEventListener('mouseup', onPointerUp);
      window.removeEventListener('touchstart', onPointerDown);
      window.removeEventListener('touchend', onPointerUp);
      window.removeEventListener('resize', onResize);
      mql?.removeEventListener?.('change', onMotionChange);
      frameCbs.clear(); resizeCbs.clear();
      if (typeof window !== 'undefined' && window[KEY] === api) delete window[KEY];
    },
  };

  api.start();
  return api;
}

/**
 * Singleton accessor. The first effect to ask for a Stage creates it; everyone
 * else shares it. This is what guarantees one rAF loop per page.
 */
export function getStage(options) {
  if (typeof window === 'undefined') return createInert();
  if (!window[KEY]) window[KEY] = createStage(options);
  return window[KEY];
}

export default getStage;
