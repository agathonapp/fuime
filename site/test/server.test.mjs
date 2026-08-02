// Boots server.js on a real port and drives it over HTTP.
// Run: node test/server.test.mjs
//
// The first version of resolveFile() 404'd every path because ROOT carried a
// trailing slash and the containment check compared against a doubled
// separator. Everything looked fine in review. These are the tests that would
// have caught it in a second.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
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
    // the route is wired without needing Upstash or Resend in CI.
    UPSTASH_REDIS_REST_URL: '',
    UPSTASH_REDIS_REST_TOKEN: '',
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

  await run('serves index.html at /', async () => {
    const r = await get('/')
    assert.equal(r.status, 200)
    assert.match(r.headers.get('content-type'), /text\/html/)
    assert.match(await r.text(), /fuime/i)
  })

  await run('serves every top-level page extensionless', async () => {
    for (const p of ['/pricing', '/parents', '/start']) {
      const r = await get(p)
      assert.equal(r.status, 200, `${p} should be 200, got ${r.status}`)
      assert.match(r.headers.get('content-type'), /text\/html/, p)
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
    const html = await get('/pricing.html')
    assert.equal(html.status, 308)
    assert.equal(html.headers.get('location'), '/pricing')

    const slash = await get('/parents/')
    assert.equal(slash.status, 308)
    assert.equal(slash.headers.get('location'), '/parents')
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
