/* fx/crease.js — every band boundary is a fold, not a colour change.
 *
 * Three parts to one seam:
 *   ridge   1px lit crest at the top of the incoming panel
 *   valley  3px soft shadow immediately beneath the crest
 *   curl   ~40px gradient running back up into the panel above
 *
 * All of it is injected CSS on sibling selectors. Zero rAF, zero JS once the
 * document is up — the only listener is a one-shot DOMContentLoaded, attached
 * solely when init runs before the bands have parsed, and it removes itself.
 * The stage bus is deliberately not imported, because
 * this module has nothing to animate. It is a stylesheet with an init
 * function, and that is the whole point: it is the only signature-adjacent
 * element on the site that is continuously visible instead of confined to a
 * sub-second window. Four seconds after landing, a reader registers that the
 * boundaries are folds and the page stops being a website and starts being an
 * object.
 *
 * Failure mode, by construction: every colour role falls back down a list of
 * tokens to a plain hairline. If a band carries no tone modifier, or the
 * night/cream alternation is not what we expect, the ridge and valley collapse
 * into a flat 1px hairline — still correct, still better than a hard colour
 * edge. There is no input that makes this module draw a defect; there are only
 * weaker versions of it.
 *
 * Nothing here is animated, so reduced motion is a no-op by construction.
 * Mobile is unchanged, and unchanged is where it earns most: a phone is a
 * portrait column and a document is a portrait column, so scrolling a phone
 * through this site reads as unfolding a strip of paper one panel at a time.
 */

const NAME = 'crease'
const STYLE_SELECTOR = 'style[data-fx="' + NAME + '"]'
const SCOPE_ATTR = 'data-fx-' + NAME

/* How many live handles are relying on the injected sheet. The sheet is shared
   by every instance and only leaves on the last destroy(). */
let sheetUsers = 0

/* Style elements this module created. An author-written <style data-fx="crease">
   is adopted but never deleted. */
const OURS = new WeakSet()

const DEFAULTS = {
  selector: '.band',
  ridge: 1,
  valley: 3,
  curl: 40,
  /* The curl can never eat more than this share of the panel it sits in. A
     zero-padding band — the running work strip is 62px tall — would otherwise
     take 40px of shading across its own text. */
  curlCap: 18,
  /* Tone modifiers. The module reads only these class names; anything else is
     an unknown tone and gets the hairline. */
  tones: {
    dark: ['.band--night'],
    lit: ['.band--cream', '.band--paper'],
  },
  /* What can sit directly above a band and still make a fold: another band,
     the hero photograph, or a full-bleed seam picture. */
  follows: ['.band', '.hero', 'picture'],
  /* What has to sit directly below a band for that band to curl away from it.
     A seam photograph is already its own transition and is left alone. */
  precedes: ['.band'],
}

/* Colour roles, each a preference list of custom properties. Resolved once at
   init against the live :root so a missing or renamed token degrades one step
   instead of dropping the whole gradient declaration. currentColor closes every
   list — it cannot be absent, so a fold always draws. */
const ROLES = {
  /* crest on a light panel: brighter than the panel it sits on */
  'lit-lit': ['--paper', '--cream', '--on-dark'],
  /* crest on a dark panel: the only light in the seam */
  'lit-dark': ['--on-dark-faint', '--on-dark-mu', '--hair'],
  /* shadow under the crest on a light panel */
  'valley-lit': ['--shadow-2', '--hair', '--shadow-1'],
  /* on a dark panel nothing tinted with the ground colour reads, so the valley
     is cut from the mask token, which is genuine opaque black */
  'valley-dark': ['--mask-on', '--shadow-2', '--hair'],
  /* The long curl, and the lip where the paper meets the fold. The lip tops
     out at the hairline token — a curl heavy enough to read as a drop shadow
     is a worse boundary than the hard colour edge it replaced. */
  curl: ['--shadow-1', '--hair'],
  'curl-lip': ['--hair', '--shadow-1'],
  /* unknown tone: a flat hairline and nothing more */
  hair: ['--hair', '--shadow-1'],
}

/* A custom property will happily hold a function the browser cannot evaluate —
   the token stream parses, the declaration wins the cascade, and the failure
   only surfaces where the var() is substituted, taking the whole `background`
   down with it. So every color-mix in this module is gated on a real feature
   test rather than on the usual duplicate-declaration fallback, which does not
   work for custom properties. The test string is keywords only. */
const MIX_TEST = 'color-mix(in srgb, currentColor 50%, transparent)'
const FALLBACK_MIX = 'color-mix(in srgb, currentColor 12%, transparent)'
const FALLBACK_FLAT = 'currentColor'

function mixOk() {
  try {
    return (
      typeof CSS !== 'undefined' &&
      !!CSS.supports &&
      CSS.supports('color', MIX_TEST)
    )
  } catch (e) {
    return false
  }
}

function clean(s) {
  return String(s == null ? '' : s)
    .replace(/[{}<>;@]/g, '')
    .trim()
}

function len(v, fallback) {
  if (typeof v === 'number' && isFinite(v)) return v + 'px'
  const s = clean(v)
  if (s && /^[0-9.]+(px|rem|em|%)?$/.test(s))
    return /[a-z%]$/.test(s) ? s : s + 'px'
  return fallback
}

function pct(v, fallback) {
  const n = Number(v)
  if (isFinite(n) && n > 0 && n <= 100) return n + '%'
  return fallback
}

function list(v, fallback) {
  const arr = Array.isArray(v) ? v : typeof v === 'string' ? v.split(',') : null
  if (!arr) return fallback
  const out = arr.map(clean).filter(Boolean)
  return out.length ? out : fallback
}

/* Walk a role's token list and return a live var() reference to the first one
   the document actually defines. The reference, not the resolved value, so the
   fold still tracks the token if the theme is ever swapped underneath it. */
function resolveRole(cs, tokens, fallback) {
  for (let i = 0; i < tokens.length; i++) {
    const v = cs.getPropertyValue(tokens[i]).trim()
    if (v) return 'var(' + tokens[i] + ')'
  }
  return fallback
}

/* Every selector this module emits is built through here, so `selector` can be
   a comma list — `.band, .strip` — without the second half escaping the
   `[data-fx-crease]` scope and leaking rules onto the whole document. */
function scoped(scope, bases, fn) {
  const out = []
  for (let i = 0; i < bases.length; i++) out.push(scope + ' ' + fn(bases[i]))
  return out.join(',\n')
}

/* `a + b::before` for every a in the list, for every b in the list. */
function pairs(scope, befores, afters, pseudo) {
  const out = []
  for (let i = 0; i < befores.length; i++) {
    for (let j = 0; j < afters.length; j++) {
      out.push(scope + ' ' + befores[i] + ' + ' + afters[j] + '::' + pseudo)
    }
  }
  return out.join(',\n')
}

/* `a:has(+ b)::after` for every a in the list, for every b in the list. */
function pairsHas(scope, bases, nexts) {
  const out = []
  for (let i = 0; i < bases.length; i++) {
    for (let j = 0; j < nexts.length; j++) {
      out.push(scope + ' ' + bases[i] + ':has(+ ' + nexts[j] + ')::after')
    }
  }
  return out.join(',\n')
}

function toneRule(scope, bases, mods, body) {
  const out = []
  for (let i = 0; i < bases.length; i++) {
    for (let j = 0; j < mods.length; j++) {
      out.push(scope + ' ' + bases[i] + mods[j])
    }
  }
  return out.join(',\n') + ' {\n' + body + '\n}'
}

function sheet(cfg) {
  const scope = '[' + SCOPE_ATTR + ']'
  const S = cfg.selectors

  return [
    '/* fx/crease — band boundaries rendered as folds. No motion, no rAF. */',

    /* Defaults live on every band: the unknown-tone hairline. A band with no
       recognised modifier lands here and reads as a plain 1px rule. */
    scoped(scope, S, function (s) {
      return s
    }) +
      ' {\n' +
      '  --fx-crease-lit: var(--fx-crease-hair);\n' +
      '  --fx-crease-valley: var(--fx-crease-hair);\n' +
      '  --fx-crease-curl-mid: var(--fx-crease-curl-soft);\n' +
      '  --fx-crease-curl-lip: var(--fx-crease-hair);\n' +
      '}',

    /* Light panels: white crest, real shadow beneath it. */
    toneRule(
      scope,
      S,
      cfg.tones.lit,
      '  --fx-crease-lit: var(--fx-crease-lit-lit);\n' +
        '  --fx-crease-valley: var(--fx-crease-valley-lit);\n' +
        '  --fx-crease-curl-mid: var(--fx-crease-curl-soft);\n' +
        '  --fx-crease-curl-lip: var(--fx-crease-curl-hard);'
    ),

    /* Dark panels, plain version. Everything here is a bare var() reference, so
       it survives on any engine. */
    toneRule(
      scope,
      S,
      cfg.tones.dark,
      '  --fx-crease-lit: var(--fx-crease-lit-dark);\n' +
        '  --fx-crease-valley: var(--fx-crease-valley-lit);\n' +
        '  --fx-crease-curl-mid: var(--fx-crease-curl-soft);\n' +
        '  --fx-crease-curl-lip: var(--fx-crease-curl-hard);'
    ),

    /* Dark panels, better version. The valley is stepped down through a
       colour-mix because nothing tinted with the ground colour separates from
       the ground colour. This is inside @supports and not simply layered as a
       second declaration: a custom property accepts an unsupported function at
       parse time and only fails where it is substituted, which would take the
       whole `background` down and delete the fold rather than weaken it. */
    '@supports (color: ' +
      MIX_TEST +
      ') {\n' +
      toneRule(
        scope,
        S,
        cfg.tones.dark,
        '  --fx-crease-valley: color-mix(in srgb, var(--fx-crease-valley-dark) 42%, transparent);\n' +
          '  --fx-crease-curl-mid: color-mix(in srgb, var(--fx-crease-valley-dark) 10%, transparent);\n' +
          '  --fx-crease-curl-lip: color-mix(in srgb, var(--fx-crease-valley-dark) 26%, transparent);'
      ) +
      '\n}',

    /* The ridge and the valley, one pseudo-element on the incoming panel.
       z-index 0 keeps it under `.band > .wrap`, which is z-index 1. */
    pairs(scope, cfg.follows, S, 'before') +
      ' {\n' +
      "  content: '';\n" +
      '  position: absolute;\n' +
      '  left: 0;\n' +
      '  right: 0;\n' +
      '  top: 0;\n' +
      '  z-index: 0;\n' +
      '  pointer-events: none;\n' +
      '  height: calc(var(--fx-crease-ridge) + var(--fx-crease-valley-h));\n' +
      '  background: linear-gradient(\n' +
      '    to bottom,\n' +
      '    var(--fx-crease-lit) 0%,\n' +
      '    var(--fx-crease-lit) var(--fx-crease-ridge),\n' +
      '    var(--fx-crease-valley) var(--fx-crease-ridge),\n' +
      '    transparent 100%\n' +
      '  );\n' +
      '  -webkit-print-color-adjust: exact;\n' +
      '  print-color-adjust: exact;\n' +
      '}',

    /* The curl, on the outgoing panel, running back up into it. :has() is the
       only way to reach the panel above a boundary; where it is unsupported the
       ridge and valley carry the fold on their own. */
    '@supports selector(:has(+ *)) {\n' +
      pairsHas(scope, S, cfg.precedes) +
      ' {\n' +
      "  content: '';\n" +
      '  position: absolute;\n' +
      '  left: 0;\n' +
      '  right: 0;\n' +
      '  bottom: 0;\n' +
      '  z-index: 0;\n' +
      '  pointer-events: none;\n' +
      '  height: min(var(--fx-crease-curl), var(--fx-crease-curl-cap));\n' +
      '  background: linear-gradient(\n' +
      '    to bottom,\n' +
      '    transparent 0%,\n' +
      '    var(--fx-crease-curl-mid) 64%,\n' +
      '    var(--fx-crease-curl-lip) 100%\n' +
      '  );\n' +
      '  -webkit-print-color-adjust: exact;\n' +
      '  print-color-adjust: exact;\n' +
      '}\n' +
      '}',
  ].join('\n\n')
}

export function initCrease(target, config) {
  /* The spec for this module calls it as initCrease(config); the house
     signature is init<Name>(target, config). Accept both — a plain object in
     the first slot is a config, not a target. */
  let root = target
  let cfgIn = config
  if (
    target &&
    typeof target === 'object' &&
    typeof target.nodeType !== 'number'
  ) {
    cfgIn = target
    root = null
  }

  const raw = cfgIn || {}
  const tonesIn = raw.tones || {}
  const selectors = list(raw.selector, [DEFAULTS.selector])
  const cfg = {
    /* A comma list is a legitimate selector — every other module in this build
       takes one — so it is kept as a list and each part is scoped separately.
       Interpolating `.band, .strip` into one rule would leave the second half
       outside `[data-fx-crease]` and paint the whole document. */
    selectors: selectors,
    selector: selectors.join(', '),
    ridge: len(raw.ridge, DEFAULTS.ridge + 'px'),
    valley: len(raw.valley, DEFAULTS.valley + 'px'),
    curl: len(raw.curl, DEFAULTS.curl + 'px'),
    curlCap: pct(raw.curlCap, DEFAULTS.curlCap + '%'),
    tones: {
      dark: list(tonesIn.dark, DEFAULTS.tones.dark),
      lit: list(tonesIn.lit, DEFAULTS.tones.lit),
    },
    follows: list(raw.follows, DEFAULTS.follows),
    precedes: list(raw.precedes, DEFAULTS.precedes),
  }

  const doc = (root && root.ownerDocument) || document
  const scope =
    root && root.nodeType === 1 ? root : doc.documentElement || doc.body

  /* Colours, read once from :root. Never a literal — a hex in an fx file is a
     build failure, and every value below is a live var() reference. */
  const cs = getComputedStyle(doc.documentElement)
  const F = mixOk() ? FALLBACK_MIX : FALLBACK_FLAT
  const vars = {
    '--fx-crease-hair': resolveRole(cs, ROLES.hair, F),
    '--fx-crease-lit-lit': resolveRole(cs, ROLES['lit-lit'], F),
    '--fx-crease-lit-dark': resolveRole(cs, ROLES['lit-dark'], F),
    '--fx-crease-valley-lit': resolveRole(cs, ROLES['valley-lit'], F),
    '--fx-crease-valley-dark': resolveRole(cs, ROLES['valley-dark'], F),
    '--fx-crease-curl-soft': resolveRole(cs, ROLES.curl, F),
    '--fx-crease-curl-hard': resolveRole(cs, ROLES['curl-lip'], F),
    '--fx-crease-ridge': cfg.ridge,
    '--fx-crease-valley-h': cfg.valley,
    '--fx-crease-curl': cfg.curl,
    '--fx-crease-curl-cap': cfg.curlCap,
  }

  /* One sheet per document, shared by every instance. Ownership is recorded on
     the element, not on the instance that happened to inject it: the last
     handle out takes the sheet with it whatever order the destroys arrive in. */
  let styleEl = doc.head ? doc.head.querySelector(STYLE_SELECTOR) : null
  if (!styleEl && doc.head) {
    styleEl = doc.createElement('style')
    styleEl.setAttribute('data-fx', NAME)
    styleEl.textContent = sheet(cfg)
    doc.head.appendChild(styleEl)
    OURS.add(styleEl)
  }
  if (styleEl) sheetUsers++

  const keys = Object.keys(vars)
  for (let i = 0; i < keys.length; i++) {
    scope.style.setProperty(keys[i], vars[keys[i]])
  }

  /* Nothing to fold under two panels, and nothing to fold if the markup this
     was pointed at never arrived. The sheet is inert without the attribute, so
     the page renders exactly as it does today. */
  function count() {
    return scope.querySelectorAll
      ? scope.querySelectorAll(cfg.selector).length
      : 0
  }

  let dead = false
  let onReady = null
  const handle = {
    /* Diagnostics only — nothing reads these, and nothing should. */
    applied: false,
    panels: count(),
    config: cfg,

    destroy: function () {
      if (dead) return
      dead = true
      if (onReady) {
        doc.removeEventListener('DOMContentLoaded', onReady)
        onReady = null
      }
      scope.removeAttribute(SCOPE_ATTR)
      for (let i = 0; i < keys.length; i++) {
        scope.style.removeProperty(keys[i])
      }
      if (styleEl) {
        sheetUsers = Math.max(0, sheetUsers - 1)
        if (sheetUsers === 0 && OURS.has(styleEl) && styleEl.parentNode) {
          styleEl.parentNode.removeChild(styleEl)
        }
      }
    },
  }

  handle.applied = handle.panels >= 2
  if (handle.applied) scope.setAttribute(SCOPE_ATTR, '')

  /* Called from a non-deferred script in <head> the bands do not exist yet and
     the count is 0, which would silently retire the module for the life of the
     page. One shot, at parse end, then it is gone — still zero JS once the
     document is up, and destroy() takes it with it if it never fires. */
  if (!handle.applied && doc.readyState === 'loading') {
    onReady = function () {
      onReady = null
      if (dead) return
      handle.panels = count()
      handle.applied = handle.panels >= 2
      if (handle.applied) scope.setAttribute(SCOPE_ATTR, '')
    }
    doc.addEventListener('DOMContentLoaded', onReady, { once: true })
  }

  return handle
}
