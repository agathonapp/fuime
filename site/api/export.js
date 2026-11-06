// GET /api/waitlist/export  ->  CSV of every waitlist signup.
//
// The roster lives in Render Key Value (fuime:waitlist + fuime:waitlist:meta:*),
// which is reachable only from inside Render. Its one reader used to be
// /admin/waitlist in the Rails app; with that app suspended there was no way
// to see who had signed up. This is the smallest door that fixes that without
// opening the store to the internet.
//
// Guarded by WAITLIST_EXPORT_TOKEN, sent as `Authorization: Bearer <token>`.
// With the variable unset the route answers 404, as though it did not exist,
// so a deploy that forgets the secret is closed rather than open.
import { timingSafeEqual } from 'node:crypto'
import { getRedis } from './waitlist.js'

const LIST_KEY = 'fuime:waitlist'

function tokenOk(header, expected) {
  const m = /^Bearer\s+(.+)$/.exec(header || '')
  if (!m) return false
  const a = Buffer.from(m[1].trim())
  const b = Buffer.from(expected)
  return a.length === b.length && timingSafeEqual(a, b)
}

// A cell that starts with = + - @ is a formula to a spreadsheet. Emails and
// sources are attacker-controlled, so neutralise them before they reach Excel.
function cell(v) {
  let s = String(v ?? '')
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s
  return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s
}

export default async function exportHandler(req, res) {
  const expected = process.env.WAITLIST_EXPORT_TOKEN
  if (!expected) {
    res.statusCode = 404
    return res.end('Not found')
  }
  if (req.method !== 'GET') {
    res.statusCode = 405
    res.setHeader('Allow', 'GET')
    return res.end()
  }
  if (!tokenOk(req.headers.authorization, expected)) {
    res.statusCode = 401
    return res.end('Unauthorized')
  }

  const redis = await getRedis()
  if (!redis) {
    res.statusCode = 503
    return res.end('No store configured')
  }

  const emails = await redis.smembers(LIST_KEY)
  const pipe = redis.pipeline()
  for (const e of emails) pipe.hgetall(`${LIST_KEY}:meta:${e}`)
  const metas = emails.length ? await pipe.exec() : []

  const rows = emails.map((email, i) => {
    const meta = (metas[i] && metas[i][1]) || {}
    return { email, at: meta.at || '', source: meta.source || '' }
  })
  rows.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : 0))

  const csv = ['email,signed_up_at,source']
    .concat(rows.map(r => [r.email, r.at, r.source].map(cell).join(',')))
    .join('\n') + '\n'

  res.statusCode = 200
  res.setHeader('Content-Type', 'text/csv; charset=utf-8')
  res.setHeader('Content-Disposition', 'attachment; filename="fuime-waitlist.csv"')
  res.setHeader('Cache-Control', 'no-store')
  res.end(csv)
}
