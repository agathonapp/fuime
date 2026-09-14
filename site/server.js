// Static file server + the one dynamic route, for Render.
//
// Render has no serverless functions, so the site and /api/waitlist are one
// origin served by one process. That is a feature here: no CORS, no second
// deploy target, and the redirects that used to live in vercel.json are just
// code now.
//
// api/waitlist.js is untouched and still speaks the Express-ish
// res.status().json() shape it was written against, so the 13 tests in
// test/waitlist.test.mjs cover the deployed path exactly. shim() below is the
// whole adapter.
import { createServer } from 'node:http'
import { readFile, stat } from 'node:fs/promises'
import { extname, join, normalize, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import waitlist from './api/waitlist.js'

// fileURLToPath on a directory URL keeps a trailing separator. Strip it, or
// the containment check below compares against a doubled slash and rejects
// every legitimate path.
const ROOT = fileURLToPath(new URL('.', import.meta.url)).replace(/[/\\]+$/, '')
const PORT = Number(process.env.PORT) || 3000

// The Rails app. /login and /get-started have to leave this origin, and where
// they go differs between production and a PR preview, so it is config rather
// than a constant.
const APP_ORIGIN = process.env.APP_ORIGIN || 'https://app.fuime.com'

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
}

// Was the "headers" block in vercel.json.
//
// CSP is report-only, matching the Rails app. The dive injects <style>
// tags (fx/roll.js) and the pages ship an inline importmap, so enforcing
// script-src/style-src without those allowances would blank the front door.
// Fontshare is the only third party the HTML actually preconnects to.
const MARKETING_CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline' https://api.fontshare.com",
  "font-src 'self' https://cdn.fontshare.com",
  "img-src 'self' data:",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "frame-ancestors 'self'",
].join('; ')

function securityHeaders(res) {
  res.setHeader('X-Content-Type-Options', 'nosniff')
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin')
  res.setHeader('X-Frame-Options', 'SAMEORIGIN')
  res.setHeader('Content-Security-Policy-Report-Only', MARKETING_CSP)
}

// Was the "redirects" block. 307 and not 308 for the same reason as before: a
// permanent redirect to a host we may still move is a permanent mistake in
// somebody's browser cache.
//
// /get-started is the marketing pages' primary call to action. The app is open
// — anyone can create an account at /users/auth — and ?signup=true is what
// makes that page read like signing up rather than signing in
// (app/views/logins/new.html.erb).
//
// Why a new path and not /start: for weeks /start answered "308 → /" with no
// Cache-Control, and a 308 is exactly the redirect a browser is allowed to
// keep forever. Any visitor who saw it may still have it, and would land on
// the dive instead of the sign-up no matter what this file says now. A path
// with no redirect history has no such cache to fight. /start and /signup
// stay as 307s to the same door so every old link still works.
const REDIRECTS = new Map([
  ['/login', `${APP_ORIGIN}/users/auth`],
  ['/get-started', `${APP_ORIGIN}/users/auth?signup=true`],
  ['/start', `${APP_ORIGIN}/users/auth?signup=true`],
  ['/signup', `${APP_ORIGIN}/users/auth?signup=true`],
])

// The dive moved to /, so start.html no longer sits where the generic .html
// rule below would put it. The old file URL still works; it just lands on the
// one canonical address. (/start itself is no longer the dive's address: it is
// the sign-up door in REDIRECTS above, which the handler checks before this
// map, so an entry for it here would never be reached.)
const INTERNAL_REDIRECTS = new Map([
  // start.html is the dive, and the dive is no longer the front door.
  ['/start.html', '/dive'],
  // /home was index.html's address for as long as the site was closed. It is
  // in Google's index and in sent mail, and index.html is now /.
  ['/home', '/'],
  ['/index', '/'],
])

// The marketing site is open. This set is what closed it: while it had entries,
// every page but the front door 307'd to /.
//
// It is kept, empty, rather than deleted, because closing the site again is a
// real operation — a legal review, a pricing change mid-flight — and the three
// properties it had to have are hard-won and worth not re-deriving:
//
//   307, not 308. These pages come back. A permanent redirect is a permanent
//   entry in somebody's browser cache.
//
//   A redirect, not a 404. The URLs are indexed and linked from mail. A 404 on
//   a URL that used to work reads as a broken site.
//
//   Crawlable. Deliberately NOT disallowed in robots.txt: a crawler blocked
//   from fetching them never sees the redirect, and the URL sits in the index
//   as a bare link forever.
const CLOSED = new Set([])

// Everything the public may fetch. The site root doubles as the deploy root on
// Render, so package.json, server.js, .env and test/ all sit in the same
// directory as index.html — serving the whole directory would publish them.
// Allowlist rather than denylist: a new secret dropped in this folder should
// be private by default, not private only if someone remembered to exclude it.
// `docs` was in this list until 2026-09-14, which published site/docs/BRIEF.md
// — the internal build contract, including the list of claims the site may not
// make — at https://fuime.com/docs/BRIEF.md. Nothing ever linked it; it was
// reachable because the directory sat next to the pages. Removed.
const PUBLIC_DIRS = /^\/(img|vid|dive|dive-m|fx|fonts)\//
const PUBLIC_FILES = new Set([
  // the spine
  '/index.html',
  '/pricing.html',
  '/parents.html',
  '/start.html',
  '/start-scroll.html',
  // product
  '/payment-links.html',
  '/subscriptions.html',
  '/books.html',
  '/taxes.html',
  '/api.html',
  // the money
  '/merchant-of-record.html',
  '/why-has-fuime-charged-me.html',
  // who it's for
  '/for/tutoring.html',
  '/for/photo-video.html',
  '/for/lawn-care.html',
  '/for/schools.html',
  // compare
  '/compare.html',
  '/compare/venmo.html',
  '/compare/paddle.html',
  '/compare/waiting.html',
  // company
  '/roadmap.html',
  '/faq.html',
  // assets served from the root
  '/style.css',
  '/site.js',
  '/favicon.ico',
  '/robots.txt',
  '/sitemap.xml',
])

function isPublic(rel) {
  return PUBLIC_FILES.has(rel) || PUBLIC_DIRS.test(rel)
}

// Vercel's cleanUrls: /pricing serves pricing.html, and /pricing.html
// redirects to /pricing so only one URL is canonical.
async function resolveFile(pathname) {
  // decodeURIComponent throws URIError on a malformed escape — `/%` is enough.
  // Uncaught, that propagates out of the request handler and kills the process,
  // so any scanner hitting a stray percent sign restarts the whole marketing
  // site. Seen repeatedly in production logs. A path we cannot decode is simply
  // not a path we serve: treat it as a 404.
  let decoded
  try {
    decoded = decodeURIComponent(pathname)
  } catch {
    return null
  }

  // normalize() collapses ../ before we join, so a crafted path cannot climb
  // out of ROOT.
  const rel = normalize(decoded).replace(/^(\.\.[/\\])+/, '')
  const abs = join(ROOT, rel)
  if (abs !== ROOT && !abs.startsWith(ROOT + sep)) return null

  // index.html is the front door. It was built as the landing page — hero,
  // worked example, the three steps, pricing, parents — and spent weeks
  // unreachable at /home behind CLOSED while / served the dive.
  //
  // A cinematic scroll with no nav and no footer is a good first impression and
  // a bad hub, and the site now has twenty pages that need reaching. So the
  // dive keeps its frame ladder and its own URL at /dive (start.html), and the
  // page with the argument on it gets the address people type.
  //
  // /dive and the /dive/ frame directory coexist: an extensionless request
  // resolves <name>.html first, and the frames are matched by PUBLIC_DIRS.
  if (pathname === '/') {
    return { path: join(ROOT, 'index.html'), ext: '.html' }
  }
  if (pathname === '/dive') {
    return { path: join(ROOT, 'start.html'), ext: '.html' }
  }

  const ext = extname(abs)
  if (ext) {
    if (!isPublic(rel)) return null
    try {
      if ((await stat(abs)).isFile()) return { path: abs, ext }
    } catch {}
    return null
  }

  // Extensionless: try <name>.html, then <name>/index.html.
  for (const [candRel, candAbs] of [
    [`${rel}.html`, `${abs}.html`],
    [`${rel}/index.html`, join(abs, 'index.html')],
  ]) {
    if (!isPublic(candRel)) continue
    try {
      if ((await stat(candAbs)).isFile()) return { path: candAbs, ext: '.html' }
    } catch {}
  }
  return null
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = ''
    let over = false
    req.on('data', c => {
      raw += c
      // An unauthenticated POST should not be able to hand us an unbounded
      // string. The real payload is an email address.
      if (raw.length > 8192 && !over) {
        over = true
        req.destroy()
        reject(new Error('payload_too_large'))
      }
    })
    req.on('end', () => !over && resolve(raw))
    req.on('error', reject)
  })
}

// Gives the Vercel-style handler the res.status().json() it expects.
function shim(res) {
  return {
    setHeader: (k, v) => res.setHeader(k, v),
    status(code) {
      res.statusCode = code
      return this
    },
    json(payload) {
      res.setHeader('Content-Type', 'application/json; charset=utf-8')
      res.end(JSON.stringify(payload))
      return this
    },
  }
}

const server = createServer(async (req, res) => {
  securityHeaders(res)

  let pathname
  try {
    pathname = new URL(req.url, 'http://localhost').pathname
  } catch {
    res.statusCode = 400
    return res.end('Bad Request')
  }

  if (pathname !== '/' && pathname.endsWith('/')) {
    pathname = pathname.replace(/\/+$/, '')
    res.statusCode = 308
    res.setHeader('Location', pathname || '/')
    return res.end()
  }

  const target = REDIRECTS.get(pathname)
  if (target) {
    res.statusCode = 307
    res.setHeader('Location', target)
    return res.end()
  }

  if (pathname === '/api/waitlist') {
    let body = ''
    if (req.method === 'POST') {
      try {
        body = await readBody(req)
      } catch {
        res.statusCode = 413
        res.setHeader('Content-Type', 'application/json; charset=utf-8')
        return res.end(JSON.stringify({ ok: false, error: 'payload_too_large' }))
      }
    }
    // The handler parses a string body itself and answers 400 on bad JSON.
    return waitlist({ method: req.method, headers: req.headers, body }, shim(res))
  }

  // Before the moved-page map and before the .html canonicaliser, so that a
  // closed page reaches / in one hop from whichever of its spellings was asked
  // for rather than bouncing through the pretty URL on the way.
  if (CLOSED.has(pathname)) {
    res.statusCode = 307
    res.setHeader('Location', '/')
    return res.end()
  }

  // Moved pages first, so /start.html reaches / in one hop rather than
  // bouncing through /start on the way.
  const moved = INTERNAL_REDIRECTS.get(pathname)
  if (moved) {
    res.statusCode = 308
    res.setHeader('Location', moved)
    return res.end()
  }

  // Canonicalise /pricing.html → /pricing so the pretty URL is the only one.
  if (pathname.endsWith('.html')) {
    res.statusCode = 308
    res.setHeader('Location', pathname.replace(/\.html$/, '') || '/')
    return res.end()
  }

  const found = await resolveFile(pathname)
  if (!found) {
    res.statusCode = 404
    res.setHeader('Content-Type', 'text/html; charset=utf-8')
    return res.end('<!doctype html><meta charset="utf-8"><title>Not found</title><p>Not found.')
  }

  // Hashless filenames, so HTML must revalidate or a deploy goes unseen.
  // Frames and imagery are content-addressed by directory and never edited in
  // place, which is what earns them the immutable year.
  const longLived = /^\/(img|vid|dive|dive-m|fonts)\//.test(pathname)
  res.setHeader(
    'Cache-Control',
    longLived ? 'public, max-age=31536000, immutable' : 'public, max-age=0, must-revalidate'
  )
  res.setHeader('Content-Type', TYPES[found.ext] || 'application/octet-stream')

  if (req.method === 'HEAD') return res.end()

  try {
    res.end(await readFile(found.path))
  } catch {
    res.statusCode = 500
    res.end('Internal Server Error')
  }
})

// api/waitlist.js accepts a Resend-only configuration: it returns 200, mails the
// notification, and stores nothing. That is a legitimate mode, but it is also a
// silent one — it is how the earliest signups came to exist only as mail in an
// inbox, with no roster to read and nothing to backfill from. It cost real
// signups once. Say it loudly at boot so a deploy cannot make that mistake
// quietly again. api/waitlist.js itself is untouched (docs/BRIEF.md).
function warnOnStorageConfig() {
  const haveStore = Boolean(process.env.WAITLIST_REDIS_URL)
  const haveMail = Boolean(
    process.env.RESEND_API_KEY && process.env.WAITLIST_NOTIFY_TO
  )

  if (haveStore) {
    console.log('waitlist: durable store configured (Render Key Value)')
  } else if (haveMail) {
    console.warn(
      'waitlist: WARNING — no durable store. WAITLIST_REDIS_URL is unset, so ' +
        'signups are emailed and NOT stored. There is no roster, ' +
        '/admin/waitlist has nothing to read, and signups taken in this state ' +
        'cannot be recovered from anywhere but the notification inbox.'
    )
  } else {
    console.error(
      'waitlist: no sink configured at all — /api/waitlist will answer 503'
    )
  }
}

server.listen(PORT, () => {
  console.log(`fuime site listening on :${PORT} (app origin ${APP_ORIGIN})`)
  warnOnStorageConfig()
})
