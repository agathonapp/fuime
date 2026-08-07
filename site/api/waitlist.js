// POST /api/waitlist  { email, source }
//
// Two independent sinks, because a waitlist that silently drops signups is
// worse than one that errors:
//   1. Render Key Value (durable, deduped)  — WAITLIST_REDIS_URL
//   2. Resend notification email            — RESEND_API_KEY + WAITLIST_NOTIFY_TO
//
// If BOTH are unconfigured we return 503 rather than a green checkmark over a
// dropped address. At least one must be wired for the endpoint to accept.
//
// Storage moved from Upstash REST to a Render Key Value instance (2026-08-07),
// so this speaks the Redis protocol over the private network instead of HTTPS.
// The key layout is unchanged and is the contract with Rails' read side
// (Fuime::WaitlistRoster) and the backfill task:
//
//   SADD  fuime:waitlist               <email>
//   HSET  fuime:waitlist:meta:<email>  at / source / ip
//
// Keeping Resend as the second sink is what makes the store swappable at all:
// if the store is down or misconfigured, the address still reaches a human.

import Redis from 'ioredis'

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/
const LIST_KEY = 'fuime:waitlist'

// Unauthenticated POST that can send mail, so it needs a ceiling. Counter per
// IP per window, atomic via INCR, self-expiring via EXPIRE on first hit.
const RATE_MAX = 5
const RATE_WINDOW_S = 600

// In-process fallback for when no store is configured. Without it the
// Redis-backed limiter below never runs and a Resend-only deployment is an
// open mail relay: no counter, and no isNew to suppress duplicates.
//
// Per-process and lost on restart, which is fine at one instance and still
// the right shape at several — a flood large enough to matter hits every
// instance. Both maps are swept on write so they cannot grow without bound.
const memHits = new Map() // ip -> { n, resetAt }
const memSeen = new Map() // email -> firstSeenAt
const MEM_SEEN_MAX = 5000

function sweep(map, now) {
  for (const [k, v] of map) {
    if ((typeof v === 'number' ? v + RATE_WINDOW_S * 1000 : v.resetAt) <= now) {
      map.delete(k)
    }
  }
}

function underRateLimitMemory(ip, now) {
  if (!ip) return true
  if (memHits.size > 1000) sweep(memHits, now)
  const hit = memHits.get(ip)
  if (!hit || hit.resetAt <= now) {
    memHits.set(ip, { n: 1, resetAt: now + RATE_WINDOW_S * 1000 })
    return true
  }
  hit.n += 1
  return hit.n <= RATE_MAX
}

// Mirrors SADD's return: true the first time this address is seen.
function markNewMemory(email, now) {
  if (memSeen.has(email)) return false
  if (memSeen.size >= MEM_SEEN_MAX) {
    sweep(memSeen, now)
    // Still full of live entries: drop the oldest rather than stop deduping.
    if (memSeen.size >= MEM_SEEN_MAX) memSeen.delete(memSeen.keys().next().value)
  }
  memSeen.set(email, now)
  return true
}

// One connection for the process, created on first use rather than at import,
// so a module load never blocks on the network and the tests can inject their
// own client. ioredis reconnects on its own; what it must not do is queue a
// request forever while a visitor waits on the form, hence the timeouts and
// the retry ceiling.
let client = null

export function getRedis() {
  if (client) return client

  const url = process.env.WAITLIST_REDIS_URL
  if (!url) return null

  client = new Redis(url, {
    lazyConnect: false,
    connectTimeout: 3000,
    commandTimeout: 3000,
    maxRetriesPerRequest: 2,
    enableOfflineQueue: false,
    // Render's external Key Value hostname serves a certificate the default
    // store does not chain to. Internal redis:// URLs never reach this.
    ...(url.startsWith('rediss://')
      ? { tls: { rejectUnauthorized: false } }
      : {}),
  })
  // Without a listener an emitted 'error' is an unhandled exception that takes
  // the whole site down — the marketing pages must outlive a store outage.
  client.on('error', e => console.error('waitlist redis:', e?.message ?? e))

  return client
}

// Test seam: swap in a fake client, or reset between cases.
export function setRedis(c) {
  client = c
}

// Fails OPEN: if the limiter itself errors we take the signup rather than
// lose a real one to a store blip. The isNew gate below is the backstop that
// keeps a flood from becoming a mailstorm even when this is unavailable.
async function underRateLimit(redis, ip) {
  if (!ip) return true
  const key = `fuime:waitlist:rl:${ip}`
  try {
    const [[, n]] = await redis
      .multi()
      .incr(key)
      .expire(key, RATE_WINDOW_S, 'NX')
      .exec()
    return Number(n ?? 0) <= RATE_MAX
  } catch {
    return true
  }
}

async function storeRedis(redis, email, meta) {
  const res = await redis
    .multi()
    .sadd(LIST_KEY, email)
    .hset(`fuime:waitlist:meta:${email}`, {
      at: meta.at,
      source: meta.source,
      ip: meta.ip,
    })
    .exec()

  // ioredis returns [[err, reply], ...]; a transaction that failed surfaces
  // here rather than throwing, and must not be reported as a stored signup.
  if (!res) throw new Error('redis transaction aborted')
  for (const [err] of res) if (err) throw err

  // SADD returns 1 for a new member, 0 if it was already there.
  return { isNew: res[0][1] === 1 }
}

async function notifyResend(key, to, email, meta) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: process.env.WAITLIST_NOTIFY_FROM || 'fuime <onboarding@resend.dev>',
      to: [to],
      subject: `fuime waitlist: ${email}`,
      text: [
        `email:  ${email}`,
        `source: ${meta.source}`,
        `at:     ${meta.at}`,
        `ip:     ${meta.ip}`,
      ].join('\n'),
    }),
  })
  if (!res.ok)
    throw new Error(`resend ${res.status}: ${(await res.text()).slice(0, 200)}`)
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST')
    return res.status(405).json({ ok: false, error: 'method_not_allowed' })
  }

  let body = req.body
  if (typeof body === 'string') {
    try {
      body = JSON.parse(body)
    } catch {
      return res.status(400).json({ ok: false, error: 'bad_json' })
    }
  }

  const email = String(body?.email ?? '')
    .trim()
    .toLowerCase()
  const source = String(body?.source ?? 'unknown').slice(0, 40)

  if (!EMAIL_RE.test(email) || email.length > 254) {
    return res.status(400).json({ ok: false, error: 'bad_email' })
  }

  const meta = {
    at: new Date().toISOString(),
    source,
    // Behind Render's proxy the left-most XFF entry is client-supplied and
    // therefore spoofable. It is a breadcrumb, never an access decision.
    ip: String(req.headers['x-forwarded-for'] ?? '')
      .split(',')[0]
      .trim()
      .slice(0, 45),
  }

  const redis = getRedis()
  const resendKey = process.env.RESEND_API_KEY
  const notifyTo = process.env.WAITLIST_NOTIFY_TO

  const haveStore = Boolean(redis)
  const haveMail = Boolean(resendKey && notifyTo)

  if (!haveStore && !haveMail) {
    console.error('waitlist: no sink configured')
    return res.status(503).json({ ok: false, error: 'not_configured' })
  }

  const now = Date.parse(meta.at)
  const withinLimit = haveStore
    ? await underRateLimit(redis, meta.ip)
    : underRateLimitMemory(meta.ip, now)
  if (!withinLimit) {
    return res.status(429).json({ ok: false, error: 'rate_limited' })
  }

  // Store first, so the notification can ask whether this address was new.
  // Re-submitting an address already on the list must not re-send the mail —
  // that is the difference between a waitlist and an open mail relay.
  let stored = null
  let storeErr = null
  if (haveStore) {
    try {
      stored = await storeRedis(redis, email, meta)
    } catch (e) {
      storeErr = e
      console.error('waitlist sink failed:', e?.message ?? e)
    }
  }

  // Without a store the in-process set answers "is this new?" instead, so a
  // resubmitted address still does not re-send. A store that errored is the
  // one case we mail anyway: better a duplicate than a lost signup.
  const isNew = haveStore
    ? storeErr || stored?.isNew
    : markNewMemory(email, now)
  const shouldMail = haveMail && Boolean(isNew)
  let mailErr = null
  if (shouldMail) {
    try {
      await notifyResend(resendKey, notifyTo, email, meta)
    } catch (e) {
      mailErr = e
      console.error('waitlist sink failed:', e?.message ?? e)
    }
  }

  // Succeed if any configured sink accepted it. Only fail when they all did.
  // A skipped duplicate mail is not a failure — the address is already stored.
  const attempted = [haveStore, shouldMail].filter(Boolean).length
  const failed = [storeErr, mailErr].filter(Boolean).length
  if (attempted > 0 && failed === attempted) {
    return res.status(502).json({ ok: false, error: 'all_sinks_failed' })
  }

  return res.status(200).json({ ok: true })
}
