/**
 * scene.js — three.js bootstrap bound to the shared Stage.
 * ─────────────────────────────────────────────────────────────────────────
 * The WebGL half of webgl-scene-kit. Gives every 3D/shader effect a renderer,
 * camera, resize handling, pointer/scroll/time uniforms, an optional
 * postprocessing composer, and a GLTF loader — all driven by the ONE Stage loop
 * (see stage.js / CONTRACT.md). One WebGL context, shared.
 *
 *   import { getStage } from './stage.js'
 *   import { initScene } from './scene.js'
 *
 *   const scene = initScene(container, {
 *     alpha: true,
 *     onFrame: ({ scene, camera, renderer, uniforms, dt }) => { mesh.rotation.y += dt }
 *   })
 *   // scene.scene / scene.camera / scene.renderer / scene.uniforms
 *   // scene.destroy()
 *
 * Deps (static track): three from esm.sh. Pinned via import map in template.html
 * so plain `import * as THREE from 'three'` resolves with no build step.
 */

import * as THREE from 'three';
import { getStage } from './stage.js';

const DEFAULTS = {
  alpha: true,            // transparent canvas (lets DOM/CSS show through)
  antialias: true,
  cameraFov: 45,
  cameraZ: 5,
  ortho: false,           // use an orthographic full-screen camera (for shader quads)
  clearColor: 0x000000,
  clearAlpha: 0,
  maxDpr: 2,
  zIndex: 'var(--cwe-z-bg, 0)',
  onFrame: null,          // ({ scene, camera, renderer, uniforms, dt, t }) => void
  onResize: null,         // ({ w, h }) => void
};

/** Shared uniforms every shader can read: time, resolution, pointer, scroll. */
function makeUniforms(stage) {
  return {
    uTime: { value: 0 },
    uResolution: { value: new THREE.Vector2(stage.viewport.w, stage.viewport.h) },
    uPointer: { value: new THREE.Vector2(0, 0) },   // -1..1
    uPointerVel: { value: new THREE.Vector2(0, 0) },
    uScroll: { value: 0 },                           // 0..1
    uScrollVel: { value: 0 },
    uDpr: { value: stage.viewport.dpr },
  };
}

export function initScene(container, config = {}) {
  const C = Object.assign({}, DEFAULTS, config);
  const stage = config.stage || getStage();

  const renderer = new THREE.WebGLRenderer({ alpha: C.alpha, antialias: C.antialias, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(stage.viewport.dpr, C.maxDpr));
  renderer.setClearColor(C.clearColor, C.clearAlpha);

  const canvas = renderer.domElement;
  canvas.setAttribute('data-cwe', 'webgl-scene-kit');
  Object.assign(canvas.style, { position: 'absolute', inset: '0', width: '100%', height: '100%', zIndex: C.zIndex, display: 'block' });
  container.appendChild(canvas);

  const w = container.clientWidth || stage.viewport.w;
  const h = container.clientHeight || stage.viewport.h;
  renderer.setSize(w, h, false);

  const scene = new THREE.Scene();
  let camera;
  if (C.ortho) {
    camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1); // full-screen quad camera
  } else {
    camera = new THREE.PerspectiveCamera(C.cameraFov, w / h, 0.1, 100);
    camera.position.z = C.cameraZ;
  }

  const uniforms = makeUniforms(stage);

  function resize() {
    const cw = container.clientWidth || stage.viewport.w;
    const ch = container.clientHeight || stage.viewport.h;
    renderer.setPixelRatio(Math.min(stage.viewport.dpr, C.maxDpr));
    renderer.setSize(cw, ch, false);
    if (!C.ortho) { camera.aspect = cw / ch; camera.updateProjectionMatrix(); }
    uniforms.uResolution.value.set(cw, ch);
    uniforms.uDpr.value = Math.min(stage.viewport.dpr, C.maxDpr);
    if (C.onResize) C.onResize({ w: cw, h: ch });
  }

  function frame(dt, t) {
    const p = stage.pointer, s = stage.scroll;
    uniforms.uTime.value = t / 1000;
    uniforms.uPointer.value.set(p.nx, p.ny);
    uniforms.uPointerVel.value.set(p.vx, p.vy);
    uniforms.uScroll.value = s.progress;
    uniforms.uScrollVel.value = s.velocity;

    if (stage.reducedMotion) { renderer.render(scene, camera); return; } // single static frame
    if (C.onFrame) C.onFrame({ scene, camera, renderer, uniforms, dt, t });
    renderer.render(scene, camera);
  }

  const offFrame = stage.register(frame);
  const offResize = stage.onResize(resize);

  return {
    THREE, scene, camera, renderer, uniforms, stage, canvas,
    /** Lazy GLTF loader (imported on demand to keep the base bundle small). */
    async loadGLTF(url) {
      const { GLTFLoader } = await import('three/addons/loaders/GLTFLoader.js');
      const loader = new GLTFLoader();
      return new Promise((res, rej) => loader.load(url, res, undefined, rej));
    },
    destroy() {
      offFrame(); offResize();
      scene.traverse((o) => {
        o.geometry?.dispose?.();
        const m = o.material;
        if (Array.isArray(m)) m.forEach((x) => x.dispose?.());
        else m?.dispose?.();
      });
      renderer.dispose();
      canvas.remove();
    },
  };
}

export { THREE, getStage };
export default initScene;
