// Exercises the waitlist handler against a stubbed fetch. No network, no Vercel.
// Run: node test/waitlist.test.mjs
import assert from 'node:assert/strict'
import handler from '../api/waitlist.js'

let calls = []
const realFetch = globalThis.fetch

function stubFetch(plan) {
  globalThis.fetch = async (url, opts) => {
    calls.push({ url: String(url), body: opts?.body })
    const hit = plan.find(p => String(url).includes(p.match))
    if (!hit) throw new Error(`unstubbed fetch: ${url}`)
    if (hit.throw) throw new Error('network down')
    return {
      ok: hit.ok !== false,
      status: hit.status ?? 200,
      text: async () => hit.text ?? '',
      json: async () => hit.json ?? [{ result: 1 }],
    }
  }
}

function mockRes() {
  const r = {
    statusCode: null,
    payload: null,
    headers: {},
    setHeader(k, v) {
      r.headers[k] = v
      return r
    },
    status(c) {
      r.statusCode = c
      return r
    },
    json(p) {
      r.payload = p
      return r
    },
  }
  return r
}

const ENV_KEYS = [
  'UPSTASH_REDIS_REST_URL',
  'UPSTASH_REDIS_REST_TOKEN',
  'RESEND_API_KEY',
  'WAITLIST_NOTIFY_TO',
  'WAITLIST_NOTIFY_FROM',
]
function setEnv(o) {
  for (const k of ENV_KEYS) delete process.env[k]
  Object.assign(process.env, o)
}

async function run(name, fn) {
  calls = []
  const errs = []
  const realErr = console.error
  console.error = (...a) => errs.push(a.join(' '))
  try {
    await fn()
    console.error = realErr
    console.log(`  ok  ${name}`)
    return true
  } catch (e) {
    console.error = realErr
    console.log(`FAIL  ${name}\n      ${e.message}`)
    return false
  }
}

const results = []

results.push(
  await run('rejects non-POST', async () => {
    setEnv({ RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    const res = mockRes()
    await handler({ method: 'GET', headers: {} }, res)
    assert.equal(res.statusCode, 405)
    assert.equal(res.headers.Allow, 'POST')
  })
)

results.push(
  await run('rejects malformed email', async () => {
    setEnv({ RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    const res = mockRes()
    await handler(
      { method: 'POST', headers: {}, body: { email: 'not-an-email' } },
      res
    )
    assert.equal(res.statusCode, 400)
    assert.equal(res.payload.error, 'bad_email')
  })
)

results.push(
  await run('503 when no sink configured', async () => {
    setEnv({})
    const res = mockRes()
    await handler(
      { method: 'POST', headers: {}, body: { email: 'a@b.com' } },
      res
    )
    assert.equal(res.statusCode, 503)
    assert.equal(res.payload.error, 'not_configured')
  })
)

results.push(
  await run('stores to upstash and lowercases the address', async () => {
    setEnv({
      UPSTASH_REDIS_REST_URL: 'https://kv.test',
      UPSTASH_REDIS_REST_TOKEN: 't',
    })
    stubFetch([{ match: 'kv.test', json: [{ result: 1 }] }])
    const res = mockRes()
    await handler(
      {
        method: 'POST',
        headers: {},
        body: { email: '  MAYA@School.EDU ', source: 'top' },
      },
      res
    )
    assert.equal(res.statusCode, 200)
    assert.equal(res.payload.ok, true)
    assert.match(calls[0].body, /maya@school\.edu/)
    assert.doesNotMatch(calls[0].body, /MAYA/)
  })
)

results.push(
  await run('succeeds when one of two sinks fails', async () => {
    setEnv({
      UPSTASH_REDIS_REST_URL: 'https://kv.test',
      UPSTASH_REDIS_REST_TOKEN: 't',
      RESEND_API_KEY: 'k',
      WAITLIST_NOTIFY_TO: 'me@x.com',
    })
    stubFetch([
      { match: 'kv.test', json: [{ result: 1 }] },
      { match: 'resend.com', throw: true },
    ])
    const res = mockRes()
    await handler(
      { method: 'POST', headers: {}, body: { email: 'a@b.com' } },
      res
    )
    assert.equal(res.statusCode, 200, 'one healthy sink should still accept')
  })
)

results.push(
  await run('502 when every configured sink fails', async () => {
    setEnv({
      UPSTASH_REDIS_REST_URL: 'https://kv.test',
      UPSTASH_REDIS_REST_TOKEN: 't',
    })
    stubFetch([{ match: 'kv.test', throw: true }])
    const res = mockRes()
    await handler(
      { method: 'POST', headers: {}, body: { email: 'a@b.com' } },
      res
    )
    assert.equal(res.statusCode, 502)
    assert.equal(res.payload.error, 'all_sinks_failed')
  })
)

results.push(
  await run('parses a raw JSON string body', async () => {
    setEnv({
      UPSTASH_REDIS_REST_URL: 'https://kv.test',
      UPSTASH_REDIS_REST_TOKEN: 't',
    })
    stubFetch([{ match: 'kv.test', json: [{ result: 1 }] }])
    const res = mockRes()
    await handler(
      {
        method: 'POST',
        headers: {},
        body: JSON.stringify({ email: 'a@b.com' }),
      },
      res
    )
    assert.equal(res.statusCode, 200)
  })
)

results.push(
  await run('takes only the first XFF hop and caps its length', async () => {
    setEnv({
      UPSTASH_REDIS_REST_URL: 'https://kv.test',
      UPSTASH_REDIS_REST_TOKEN: 't',
    })
    stubFetch([{ match: 'kv.test', json: [{ result: 1 }] }])
    const res = mockRes()
    await handler(
      {
        method: 'POST',
        headers: { 'x-forwarded-for': '1.2.3.4, 5.6.7.8' },
        body: { email: 'a@b.com' },
      },
      res
    )
    assert.equal(res.statusCode, 200)
    assert.match(calls[0].body, /1\.2\.3\.4/)
    assert.doesNotMatch(calls[0].body, /5\.6\.7\.8/)
  })
)

globalThis.fetch = realFetch
const failed = results.filter(r => !r).length
console.log(`\n${results.length - failed}/${results.length} passed`)
process.exit(failed ? 1 : 0)
