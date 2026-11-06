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

// Overridable so two checkouts (or two agents) can run this at once without
// one of them failing on EADDRINUSE and blaming the server.
const PORT = Number(process.env.TEST_PORT) || 8791
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

// Every page server.js answers 200 for. Hardcoded rather than globbed for the
// same reason the rspec guards are: the list IS the guard. Since 2026-11-06 that
// is the rebuilt front door plus the one legacy page kept up through the
// dispute window; every other page is in RETIRED and 307s to /. Keep in step
// with CLOSED_PAGES in server.js and the lists in
// spec/fuime_marketing_copy_spec.rb and test/copy-guard.mjs.
const PAGES = ['/', '/why-has-fuime-charged-me']
const LEGACY_PAGES = PAGES.filter(p => p !== '/')
const RETIRED = [
  '/pricing',
  '/parents',
  '/payment-links',
  '/subscriptions',
  '/books',
  '/taxes',
  '/api',
  '/merchant-of-record',
  '/for/tutoring',
  '/for/photo-video',
  '/for/lawn-care',
  '/for/schools',
  '/compare',
  '/compare/venmo',
  '/compare/paddle',
  '/compare/waiting',
  '/roadmap',
  '/faq',
]

try {
  await waitForBoot()

  await run('serves the landing page at /', async () => {
    const r = await get('/')
    assert.equal(r.status, 200)
    assert.match(r.headers.get('content-type'), /text\/html/)
    const body = await r.text()
    // index.html is the one-page site rebuilt on 2026-11-06.
    assert.match(body, /<main id="join">/, 'root should be index.html')
  })

  await run('the front door is the stealth page and keeps the app contract', async () => {
    // 2026-11-06: the mark, one typed instruction line, and a quiet invite
    // form. No nav, and at most the one form, tagged as a waitlist.
    const body = await (await get('/')).text()
    assert.match(body, /<img class="mark" src="\/img\/v2\/logo.svg"/, 'lost the mark')
    assert.doesNotMatch(body, /<nav/, 'the stealth page grew a nav')
    const forms = [...body.matchAll(/<form\s[^>]*data-source="([^"]+)"/g)].map(m => m[1])
    assert.ok(forms.length <= 1, 'the stealth page grew a second form')
    for (const f of forms) assert.match(f, /-waitlist$/, `form "${f}" is not a waitlist form`)
    // The Rails app sends a sign-in that finds no account to /?account=none#join
    // (Fuime::Signups), and the page explains why in [data-account-none].
    assert.match(body, /id="join"/, 'lost the #join target the app redirects to')
    assert.match(body, /data-account-none/, 'lost the account=none explanation')
  })

  await run('every same-origin link on the front door is actually served', async () => {
    // server.js serves from an ALLOWLIST, so a link to a file missing from
    // PUBLIC_FILES answers 404. /login is the one intended redirect.
    const body = await (await get('/')).text()
    const refs = [
      ...body.matchAll(/(?:href|src)="(\/[^"#]*)"/g),
    ].map(m => m[1]).filter(h => h !== '/login')
    for (const h of new Set(refs)) {
      const r = await get(h)
      assert.equal(r.status, 200, `/ links ${h}, which answers ${r.status}`)
    }
  })

  await run('retired pages 307 to the front door, in one hop', async () => {
    // Closed on 2026-11-06, not deleted: they describe the retired teen
    // product. 307 so no browser caches it, and both spellings land on / in
    // one hop.
    for (const p of RETIRED) {
      for (const spelling of [p, `${p}.html`]) {
        const r = await get(spelling)
        assert.equal(r.status, 307, `${spelling} status`)
        assert.equal(r.headers.get('location'), '/', `${spelling} -> /`)
      }
    }
  })

  await run('the old closed-era addresses still land somewhere', async () => {
    // /home was index.html's address for as long as the site was closed, and it
    // is in the index and in sent mail. 308 is right for these and 307 was
    // right for the closure: the closure was reversible and this move is not.
    for (const [p, to] of [['/home', '/'], ['/index', '/']]) {
      const r = await get(p)
      assert.equal(r.status, 308, `${p} status`)
      assert.equal(r.headers.get('location'), to, `${p} -> ${to}`)
    }
  })

  await run('the sitemap lists only what is served', async () => {
    // A sitemap that disagrees with the canonical tag is worse than no sitemap,
    // so this checks every listed URL answers 200 rather than pinning a list
    // that would need editing with every page. It held exactly one entry while
    // the site was closed.
    const body = await (await get('/sitemap.xml')).text()
    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m => m[1])
    assert.ok(locs.length >= 1, 'the sitemap lists nothing')
    for (const loc of locs) {
      const path = new URL(loc).pathname
      const r = await get(path)
      assert.equal(r.status, 200, `sitemap lists ${path}, which answers ${r.status}`)
    }
  })

  await run('moved pages redirect in a single hop', async () => {
    // /start is the sign-up door, asserted alongside /login below. The dive's
    // own spellings are moved pages now that it is deleted.
    for (const [from, to] of [['/start.html', '/'], ['/start-scroll.html', '/']]) {
      const r = await get(from)
      assert.equal(r.status, 308, `${from} status`)
      assert.equal(r.headers.get('location'), to, `${from} -> ${to}`)
    }
  })

  await run('serves static assets with correct content types', async () => {
    const cases = [
      ['/style.css', /text\/css/],
      ['/site.js', /javascript/],
      ['/landing.css', /text\/css/],
      ['/landing.js', /javascript/],
      ['/robots.txt', /text\/plain/],
      ['/sitemap.xml', /xml/],
      ['/img/mark.svg', /image\/svg/],
    ]
    for (const [p, type] of cases) {
      const r = await get(p)
      assert.equal(r.status, 200, `${p} should be 200, got ${r.status}`)
      assert.match(r.headers.get('content-type'), type, p)
    }
  })

  await run('/login 307s to the app origin', async () => {
    const r = await get('/login')
    assert.equal(r.status, 307)
    assert.equal(r.headers.get('location'), 'https://app.example.test/users/auth')
  })

  await run('/get-started, /start and /signup 307 to the app sign-up, not the sign-in', async () => {
    // Same posture as /login — a 307 to the configured app origin, never a
    // cached permanent redirect — but carrying ?signup=true, which is what
    // turns the app's /users/auth page from "Sign in" into "Start your
    // business" (app/views/logins/new.html.erb). Without it every visitor the
    // marketing pages send over lands on a sign-in form.
    //
    // /get-started is the canonical one and the one every CTA points at: it
    // has never answered anything but this 307, so no browser holds a stale
    // permanent redirect for it. /start did — it was "308 → /" for weeks with
    // no Cache-Control — which is why it is kept working but no longer linked.
    for (const p of ['/get-started', '/start', '/signup']) {
      const r = await get(p)
      assert.equal(r.status, 307, p)
      assert.equal(
        r.headers.get('location'),
        'https://app.example.test/users/auth?signup=true',
        p
      )
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
    // This asserted a confirmation block on EVERY page while the site was five
    // pages and four of them carried a form. It is now parity, conditional on
    // the page having a form at all: the app is open, so the primary action is
    // the /get-started button and most of the twenty pages correctly carry no
    // capture form. Demanding one would have put a waitlist back on pages that
    // have no business showing one.
    for (const p of PAGES) {
      const body = await (await get(p)).text()
      const forms = (body.match(/<form\s[^>]*class="capture/g) || []).length
      const dones = (body.match(/class="capture__done"/g) || []).length
      const planes = (body.match(/class="capture__plane"/g) || []).length
      if (forms === 0) continue
      assert.ok(dones > 0, `${p} has a capture form and no confirmation block`)
      assert.equal(planes, dones, `${p}: ${planes} planes for ${dones} forms`)
    }
  })

  await run('the marketing pages send a visitor into the app, not a queue', async () => {
    // ⚠️ Superseded in part on 2026-10-01: sign-ups are closed, and the app
    // sends a visitor without an account back to the waitlist on /. The
    // checks below still hold. /get-started is still every page's door, and the
    // phrase bans stay because the waitlist copy never needed those words.
    //
    // The app is open: anyone can create an account. For a while the only thing
    // these pages offered was a waitlist form, which parked every warm visitor
    // in Redis (docs/fuime/ONBOARDING_PLAN.md §1 #1). The primary button now
    // goes to /get-started, "Log in" is on every page, and the waitlist remains
    // only as the form for schools, teachers and closed cohorts — so no page
    // may imply a queue, and no capture form may still be tagged as a
    // founder sign-up (a teacher and a legacy teen signup would be
    // indistinguishable in the admin roster).
    //
    // Fetched over HTTP now that nothing is closed, so this checks what a
    // visitor is actually served rather than what is on disk next to it.
    // 2026-11-06: the front door left this loop. It has no /get-started CTA
    // (sign-ups are closed) and is checked by its own test above.
    for (const n of LEGACY_PAGES) {
      const body = await (await get(n)).text()
      assert.match(
        body,
        /<a\s[^>]*href="\/get-started"[^>]*>\s*(Start your business|Have your teen start)\s*</,
        `${n} has no primary CTA → /get-started`
      )
      assert.match(
        body,
        /<a\s[^>]*href="\/login"[^>]*>\s*Log in\s*</,
        `${n} lost its Log in link`
      )
      // /start is kept as a redirect for old links, never as a target: it has
      // a cached-308 history that /get-started does not.
      assert.doesNotMatch(body, /href="\/start"/, `${n} still links to /start`)
      assert.doesNotMatch(body, /early access/i, `${n} still says "early access"`)
      assert.doesNotMatch(body, /your turn/i, `${n} still implies a queue`)
      assert.doesNotMatch(
        body,
        /onboarding the first businesses/i,
        `${n} still implies a queue`
      )
      assert.doesNotMatch(
        body,
        /href="#join"[^>]*>\s*Get early access/,
        `${n} primary CTA still points at the waitlist`
      )
      // 2026-10-01: sign-ups are closed in the app (Fuime::Signups), so the
      // waitlist is real again and / carries a founder form, tagged -waitlist.
      // The tag is what separates it from a teacher's -cohort enquiry in the
      // roster; an untagged form still fails.
      for (const m of body.matchAll(/<form\s[^>]*class="capture[^"]*"[^>]*data-source="([^"]+)"/g)) {
        assert.match(m[1], /-(cohort|waitlist)$/, `${n} form "${m[1]}" is tagged neither -cohort nor -waitlist`)
      }
    }
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
    const asset = await get('/img/mark.svg')
    assert.match(asset.headers.get('cache-control'), /immutable/)
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
