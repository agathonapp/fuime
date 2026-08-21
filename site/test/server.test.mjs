// Boots server.js on a real port and drives it over HTTP.
// Run: node test/server.test.mjs
//
// The first version of resolveFile() 404'd every path because ROOT carried a
// trailing slash and the containment check compared against a doubled
// separator. Everything looked fine in review. These are the tests that would
// have caught it in a second.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const PORT = 8791
const BASE = `http://127.0.0.1:${PORT}`
const SERVER = fileURLToPath(new URL('../server.js', import.meta.url))

const child = spawn(process.execPath, [SERVER], {
  env: {
    ...process.env,
    PORT: String(PORT),
    APP_ORIGIN: 'https://app.example.test',
    // No sinks: /api/waitlist should answer 503, which is a fine signal that
    // the route is wired without needing a store or Resend in CI.
    WAITLIST_REDIS_URL: '',
    RESEND_API_KEY: '',
    WAITLIST_NOTIFY_TO: '',
  },
  stdio: ['ignore', 'pipe', 'pipe'],
})

async function waitForBoot(timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    try {
      await fetch(`${BASE}/robots.txt`, { redirect: 'manual' })
      return
    } catch {
      await new Promise(r => setTimeout(r, 100))
    }
  }
  throw new Error('server did not boot')
}

const results = []
async function run(name, fn) {
  try {
    await fn()
    console.log(`  ok  ${name}`)
    results.push(true)
  } catch (e) {
    console.log(`FAIL  ${name}\n      ${e.message}`)
    results.push(false)
  }
}

const get = (p, init) => fetch(BASE + p, { redirect: 'manual', ...init })

try {
  await waitForBoot()

  await run('serves the dive at /', async () => {
    const r = await get('/')
    assert.equal(r.status, 200)
    assert.match(r.headers.get('content-type'), /text\/html/)
    const body = await r.text()
    // The dive, not the old marketing home: it preloads the frame track.
    assert.match(body, /dive\/track\.json/, 'root should be start.html')
    assert.match(body, /class="capture"/, 'root should carry the sign-up')
  })

  await run('the closed marketing pages bounce to the front door', async () => {
    // The site is not open yet, so / is the only page anyone reaches. Every
    // spelling of the other three goes there in ONE hop — /pricing.html must
    // not bounce through /pricing on the way, which is why the CLOSED check
    // sits above both the moved-page map and the .html canonicaliser.
    for (const p of [
      '/home',
      '/index',
      '/index.html',
      '/pricing',
      '/pricing.html',
      '/parents',
      '/parents.html',
    ]) {
      const r = await get(p)
      // 307 and not 308: these pages are coming back, and a permanent redirect
      // would outlive the decision in every browser cache that saw it.
      assert.equal(r.status, 307, `${p} status`)
      assert.equal(r.headers.get('location'), '/', `${p} -> /`)
    }
  })

  await run('nothing on the front door leads off it', async () => {
    // The whole point of the closure is undone by one stale href, and a link to
    // a page that 307s back is a worse experience than no link at all.
    const body = await (await get('/')).text()
    // <a> only. The head is full of hrefs that are not navigation — the
    // canonical, the preconnects, the icons — and none of them are a way out.
    const hrefs = [...body.matchAll(/<a\s[^>]*href="([^"]+)"/g)].map(m => m[1])
    const out = hrefs.filter(
      h => /^\/(home|pricing|parents|index)\b/.test(h) || /^https?:/.test(h)
    )
    assert.deepEqual(out, [], `front door links out: ${out.join(', ')}`)
  })

  await run('the sitemap lists only what is served', async () => {
    const body = await (await get('/sitemap.xml')).text()
    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m => m[1])
    assert.deepEqual(locs, ['https://fuime.com/'])
  })

  await run('moved pages redirect in a single hop', async () => {
    for (const [from, to] of [
      ['/start', '/'],
      ['/start.html', '/'],
    ]) {
      const r = await get(from)
      assert.equal(r.status, 308, `${from} status`)
      assert.equal(r.headers.get('location'), to, `${from} -> ${to}`)
    }
  })

  await run('serves static assets with correct content types', async () => {
    const cases = [
      ['/style.css', /text\/css/],
      ['/site.js', /javascript/],
      ['/robots.txt', /text\/plain/],
      ['/sitemap.xml', /xml/],
      ['/dive/f_0001.webp', /image\/webp/],
    ]
    for (const [p, type] of cases) {
      const r = await get(p)
      assert.equal(r.status, 200, `${p} should be 200, got ${r.status}`)
      assert.match(r.headers.get('content-type'), type, p)
    }
  })

  await run('/login and /signup 307 to the app origin', async () => {
    for (const p of ['/login', '/signup']) {
      const r = await get(p)
      assert.equal(r.status, 307, p)
      assert.equal(r.headers.get('location'), 'https://app.example.test/users/auth')
    }
  })

  await run('canonicalises .html and trailing slashes', async () => {
    // Every real page's .html spelling is currently shadowed by CLOSED, which
    // sends it to / in one hop instead — asserted above. This exercises the
    // generic rule underneath on a path that reaches it, so the canonicaliser
    // does not quietly rot while the site is closed.
    const html = await get('/nope.html')
    assert.equal(html.status, 308)
    assert.equal(html.headers.get('location'), '/nope')

    const slash = await get('/parents/')
    assert.equal(slash.status, 308)
    assert.equal(slash.headers.get('location'), '/parents')
  })

  await run('every sign-up carries the paper plane', async () => {
    // The confirmation animates the address away. If the markup drifts out of
    // one page the CSS silently does nothing there, which is invisible in
    // review and obvious to a user.
    //
    // Only / is served while the marketing site is closed, and the other three
    // are read off disk rather than dropped: they are coming back, and a
    // closure that quietly halves this file's coverage is how they come back
    // broken. Swap these for fetches when CLOSED empties.
    const pages = [
      ['/', await (await get('/')).text()],
      ...['index', 'pricing', 'parents'].map(n => [
        `${n}.html`,
        readFileSync(fileURLToPath(new URL(`../${n}.html`, import.meta.url)), 'utf8'),
      ]),
    ]
    for (const [p, body] of pages) {
      const dones = (body.match(/class="capture__done"/g) || []).length
      const planes = (body.match(/class="capture__plane"/g) || []).length
      assert.ok(dones > 0, `${p} has no confirmation block`)
      assert.equal(planes, dones, `${p}: ${planes} planes for ${dones} forms`)
    }
  })

  await run('the front door says what the product is', async () => {
    // / is a scroll-driven film, and a film is easy to keep polishing until the
    // first screen is a mood with no nouns on it. That is the state this
    // assertion exists to catch: a visitor who cannot tell what fuime is
    // without scrolling does not scroll.
    const body = await (await get('/')).text()
    assert.match(body, /class="dive__lede"/, 'no lede on the first screen')
    assert.match(body, /13 to 17/, 'the lede never says who this is for')
    // And a way past the flight for a thumb, landing on the composed sign-up.
    assert.match(body, /class="lede__skip" href="#signup"/, 'no skip link')
    assert.match(body, /id="signup"/, 'skip link points at nothing')
  })

  await run('security headers on every response', async () => {
    for (const p of ['/', '/nope', '/style.css']) {
      const r = await get(p)
      assert.equal(r.headers.get('x-content-type-options'), 'nosniff', p)
      assert.equal(r.headers.get('x-frame-options'), 'SAMEORIGIN', p)
      assert.equal(
        r.headers.get('referrer-policy'),
        'strict-origin-when-cross-origin',
        p
      )
      const csp = r.headers.get('content-security-policy-report-only')
      assert.ok(csp, `${p} missing CSP report-only`)
      assert.match(csp, /default-src 'self'/, p)
      assert.match(csp, /object-src 'none'/, p)
      assert.match(csp, /frame-ancestors 'self'/, p)
      assert.equal(r.headers.get('content-security-policy'), null, p)
    }
  })

  await run('immutable caching only for content-addressed dirs', async () => {
    const frame = await get('/dive/f_0001.webp')
    assert.match(frame.headers.get('cache-control'), /immutable/)
    // HTML must revalidate or a deploy goes unseen.
    const page = await get('/')
    assert.match(page.headers.get('cache-control'), /must-revalidate/)
  })

  await run('404s a missing page', async () => {
    const r = await get('/definitely-not-here')
    assert.equal(r.status, 404)
  })

  await run('survives a malformed percent-escape instead of crashing', async () => {
    // decodeURIComponent throws URIError on `/%`. Uncaught, that propagated out
    // of the request handler and killed the process — one scanner was enough to
    // restart the whole marketing site. Seen repeatedly in production logs.
    const r = await get('/%')
    assert.equal(r.status, 404)
    // And the server is still alive to answer the next request.
    const after = await get('/robots.txt')
    assert.equal(after.status, 200, 'server died on a malformed path')
  })

  await run('refuses path traversal', async () => {
    // Both raw and percent-encoded, since decodeURIComponent runs first.
    const attempts = [
      '/../package.json',
      '/../../render.yaml',
      '/%2e%2e/package.json',
      '/..%2f..%2frender.yaml',
      '/../../config/master.key',
    ]
    for (const p of attempts) {
      const r = await get(p)
      assert.notEqual(r.status, 200, `${p} served content`)
    }
  })

  await run('does not serve its own source or config', async () => {
    // These live in the same directory as index.html because the site root is
    // also the deploy root. None of them are public.
    const private_ = [
      '/package.json',
      '/server.js',
      '/.env',
      '/.env.example',
      '/test/server.test.mjs',
      '/test/waitlist.test.mjs',
      '/api/waitlist.js',
    ]
    for (const p of private_) {
      const r = await get(p)
      assert.notEqual(r.status, 200, `${p} is reachable`)
    }
  })

  await run('/api/waitlist is wired and rejects GET', async () => {
    const r = await get('/api/waitlist')
    assert.equal(r.status, 405)
    assert.equal(r.headers.get('allow'), 'POST')
  })

  await run('/api/waitlist validates the address', async () => {
    const r = await get('/api/waitlist', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'nope' }),
    })
    assert.equal(r.status, 400)
    assert.equal((await r.json()).error, 'bad_email')
  })

  await run('/api/waitlist 503s with no sink configured', async () => {
    const r = await get('/api/waitlist', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'real@example.com' }),
    })
    assert.equal(r.status, 503)
    assert.equal((await r.json()).error, 'not_configured')
  })

  await run('/api/waitlist caps the request body', async () => {
    const r = await get('/api/waitlist', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'a@b.com', source: 'x'.repeat(20000) }),
    }).catch(e => ({ status: 413, _err: e }))
    assert.ok(r.status === 413 || r.status === 400, `got ${r.status}`)
  })

  await run('HEAD returns headers without a body', async () => {
    const r = await get('/', { method: 'HEAD' })
    assert.equal(r.status, 200)
    assert.equal(await r.text(), '')
  })
} finally {
  child.kill('SIGTERM')
}

const failed = results.filter(r => !r).length
console.log(`\n${results.length - failed}/${results.length} passed`)
process.exit(failed ? 1 : 0)
