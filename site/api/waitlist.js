// POST /api/waitlist  { email, source }
//
// Two independent sinks, because a waitlist that silently drops signups is
// worse than one that errors:
//   1. Upstash Redis (durable, deduped)  — UPSTASH_REDIS_REST_URL + _TOKEN
//   2. Resend notification email          — RESEND_API_KEY + WAITLIST_NOTIFY_TO
//
// If BOTH are unconfigured we return 503 rather than a green checkmark over a
// dropped address. At least one must be wired for the endpoint to accept.

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/
const LIST_KEY = 'fuime:waitlist'

async function storeUpstash(url, token, email, meta) {
  const cmds = [
    ['SADD', LIST_KEY, email],
    [
      'HSET',
      `fuime:waitlist:meta:${email}`,
      'at',
      meta.at,
      'source',
      meta.source,
      'ip',
      meta.ip,
    ],
  ]
  const res = await fetch(`${url}/pipeline`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(cmds),
  })
  if (!res.ok)
    throw new Error(
      `upstash ${res.status}: ${(await res.text()).slice(0, 200)}`
    )
  const out = await res.json()
  // SADD returns 1 for a new member, 0 if it was already there.
  return { isNew: out?.[0]?.result === 1 }
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
    // Behind Vercel's proxy the left-most XFF entry is client-supplied and
    // therefore spoofable. It is a breadcrumb, never an access decision.
    ip: String(req.headers['x-forwarded-for'] ?? '')
      .split(',')[0]
      .trim()
      .slice(0, 45),
  }

  const kvUrl = process.env.UPSTASH_REDIS_REST_URL
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN
  const resendKey = process.env.RESEND_API_KEY
  const notifyTo = process.env.WAITLIST_NOTIFY_TO

  const haveStore = Boolean(kvUrl && kvToken)
  const haveMail = Boolean(resendKey && notifyTo)

  if (!haveStore && !haveMail) {
    console.error('waitlist: no sink configured')
    return res.status(503).json({ ok: false, error: 'not_configured' })
  }

  const results = await Promise.allSettled([
    haveStore
      ? storeUpstash(kvUrl, kvToken, email, meta)
      : Promise.resolve(null),
    haveMail
      ? notifyResend(resendKey, notifyTo, email, meta)
      : Promise.resolve(null),
  ])

  const failures = results.filter(r => r.status === 'rejected')
  for (const f of failures)
    console.error('waitlist sink failed:', f.reason?.message ?? f.reason)

  // Succeed if any configured sink accepted it. Only fail when they all did.
  const configured = [haveStore, haveMail].filter(Boolean).length
  if (failures.length === configured) {
    return res.status(502).json({ ok: false, error: 'all_sinks_failed' })
  }

  return res.status(200).json({ ok: true })
}
