// Exercises the waitlist handler against a fake Redis and a stubbed fetch.
// No network, no Render, no real store.
//
// The store moved from Upstash REST to a Render Key Value instance, so this
// injects a fake ioredis client through setRedis() where it used to stub
// global fetch. fetch is still stubbed, but now only for Resend.
//
// Run: node test/waitlist.test.mjs
import assert from 'node:assert/strict'
import handler, { setRedis } from '../api/waitlist.js'

let calls = []
const realFetch = globalThis.fetch

// Enough of ioredis for this handler: multi() chains, exec() resolves to
// ioredis' [[err, reply], ...] shape. `fail` makes exec reject (connection
// down); `replyErr` makes it resolve with a per-command error, which is the
// subtler shape and the one a naive implementation reports as success.
function fakeRedis({ members = new Set(), counters = {}, fail = false, replyErr = false } = {}) {
  const r = {
    members,
    counters,
    hashes: {},
    multi() {
      const queued = []
      const chain = {
        incr(key) {
          counters[key] = (counters[key] ?? 0) + 1
          queued.push(counters[key])
          return chain
        },
        expire() {
          queued.push(1)
          return chain
        },
        sadd(_key, member) {
          const isNew = !members.has(member)
          members.add(member)
          queued.push(isNew ? 1 : 0)
          return chain
        },
        hset(key, obj) {
          r.hashes[key] = obj
          queued.push(1)
          return chain
        },
        async exec() {
          if (fail) throw new Error('connection refused')
          if (replyErr) return queued.map(() => [new Error('READONLY'), null])
          return queued.map(v => [null, v])
        },
      }
      return chain
    },
  }
  return r
}

function stubResend(plan = {}) {
  globalThis.fetch = async (url, opts) => {
    calls.push({ url: String(url), body: opts?.body })
    if (plan.throw) throw new Error('network down')
    return {
      ok: plan.ok !== false,
      status: plan.status ?? 200,
      text: async () => plan.text ?? '',
      json: async () => plan.json ?? {},
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
  'WAITLIST_REDIS_URL',
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
  setRedis(null)
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
  await run('400s an unparseable body', async () => {
    setEnv({ RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    const res = mockRes()
    await handler({ method: 'POST', headers: {}, body: '{not json' }, res)
    assert.equal(res.statusCode, 400)
    assert.equal(res.payload.error, 'bad_json')
  })
)

results.push(
  await run('400s a malformed address before touching any sink', async () => {
    setEnv({ RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    const res = mockRes()
    globalThis.fetch = async () => {
      throw new Error('must not be called')
    }
    await handler({ method: 'POST', headers: {}, body: { email: 'nope' } }, res)
    assert.equal(res.statusCode, 400)
    assert.equal(res.payload.error, 'bad_email')
  })
)

results.push(
  await run('503s when no sink at all is configured', async () => {
    setEnv({})
    const res = mockRes()
    await handler({ method: 'POST', headers: {}, body: { email: 'a@b.com' } }, res)
    assert.equal(res.statusCode, 503)
    assert.equal(res.payload.error, 'not_configured')
  })
)

results.push(
  await run('stores to redis and lowercases the address', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x' })
    const fake = fakeRedis()
    setRedis(fake)
    const res = mockRes()
    await handler(
      { method: 'POST', headers: {}, body: { email: '  MiXeD@Example.COM ', source: 'home-hero' } },
      res
    )
    assert.equal(res.statusCode, 200)
    assert.equal(fake.members.has('mixed@example.com'), true)
    assert.equal(fake.hashes['fuime:waitlist:meta:mixed@example.com'].source, 'home-hero')
  })
)

results.push(
  await run('records source and caps its length', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x' })
    const fake = fakeRedis()
    setRedis(fake)
    const res = mockRes()
    await handler(
      { method: 'POST', headers: {}, body: { email: 'a@b.com', source: 'x'.repeat(80) } },
      res
    )
    assert.equal(res.statusCode, 200)
    assert.equal(fake.hashes['fuime:waitlist:meta:a@b.com'].source.length, 40)
  })
)

results.push(
  await run('succeeds when one of two sinks fails', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x', RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    setRedis(fakeRedis({ fail: true }))
    stubResend()
    const res = mockRes()
    await handler({ method: 'POST', headers: {}, body: { email: 'a@b.com' } }, res)
    // The store failed, so the mail must go out anyway — better a duplicate
    // notification than a lost signup.
    assert.equal(res.statusCode, 200)
    assert.equal(calls.length, 1)
  })
)

results.push(
  await run('a per-command redis error is a failure, not a silent success', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x' })
    setRedis(fakeRedis({ replyErr: true }))
    const res = mockRes()
    await handler({ method: 'POST', headers: {}, body: { email: 'a@b.com' } }, res)
    assert.equal(res.statusCode, 502)
    assert.equal(res.payload.error, 'all_sinks_failed')
  })
)

results.push(
  await run('502 when every configured sink fails', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x', RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    setRedis(fakeRedis({ fail: true }))
    stubResend({ throw: true })
    const res = mockRes()
    await handler({ method: 'POST', headers: {}, body: { email: 'a@b.com' } }, res)
    assert.equal(res.statusCode, 502)
    assert.equal(res.payload.error, 'all_sinks_failed')
  })
)

results.push(
  await run('parses a raw JSON string body', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x' })
    const fake = fakeRedis()
    setRedis(fake)
    const res = mockRes()
    await handler(
      { method: 'POST', headers: {}, body: JSON.stringify({ email: 'raw@b.com' }) },
      res
    )
    assert.equal(res.statusCode, 200)
    assert.equal(fake.members.has('raw@b.com'), true)
  })
)

results.push(
  await run('takes only the first XFF hop and caps its length', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x' })
    const fake = fakeRedis()
    setRedis(fake)
    const res = mockRes()
    await handler(
      {
        method: 'POST',
        headers: { 'x-forwarded-for': ` 9.9.9.9 , 10.0.0.1, ${'z'.repeat(80)}` },
        body: { email: 'a@b.com' },
      },
      res
    )
    assert.equal(fake.hashes['fuime:waitlist:meta:a@b.com'].ip, '9.9.9.9')
  })
)

results.push(
  await run('429 once the per-IP window is exceeded', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x' })
    // Sixth request in the window: INCR returns 6, the ceiling is 5.
    setRedis(fakeRedis({ counters: { 'fuime:waitlist:rl:5.5.5.5': 5 } }))
    const res = mockRes()
    await handler(
      { method: 'POST', headers: { 'x-forwarded-for': '5.5.5.5' }, body: { email: 'a@b.com' } },
      res
    )
    assert.equal(res.statusCode, 429)
    assert.equal(res.payload.error, 'rate_limited')
  })
)

results.push(
  await run('allows the last request inside the window', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x' })
    setRedis(fakeRedis({ counters: { 'fuime:waitlist:rl:6.6.6.6': 4 } }))
    const res = mockRes()
    await handler(
      { method: 'POST', headers: { 'x-forwarded-for': '6.6.6.6' }, body: { email: 'a@b.com' } },
      res
    )
    assert.equal(res.statusCode, 200)
  })
)

results.push(
  await run('a duplicate address does not re-send the mail', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x', RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    setRedis(fakeRedis({ members: new Set(['dup@b.com']) }))
    stubResend()
    const res = mockRes()
    await handler({ method: 'POST', headers: {}, body: { email: 'dup@b.com' } }, res)
    assert.equal(res.statusCode, 200)
    assert.equal(calls.length, 0, 'a waitlist that re-mails on every resubmit is a mail relay')
  })
)

results.push(
  await run('a new address does send the mail', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x', RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    setRedis(fakeRedis())
    stubResend()
    const res = mockRes()
    await handler({ method: 'POST', headers: {}, body: { email: 'new@b.com' } }, res)
    assert.equal(res.statusCode, 200)
    assert.equal(calls.length, 1)
    assert.match(calls[0].body, /new@b\.com/)
  })
)

results.push(
  await run('rate limiter failing open still accepts the signup', async () => {
    setEnv({ WAITLIST_REDIS_URL: 'redis://x' })
    // The limiter throws but the store works: a limiter blip must not cost a
    // real signup.
    const fake = fakeRedis()
    let first = true
    const originalMulti = fake.multi.bind(fake)
    fake.multi = () => {
      if (first) {
        first = false
        return { incr: () => ({ expire: () => ({ exec: async () => { throw new Error('down') } }) }) }
      }
      return originalMulti()
    }
    setRedis(fake)
    const res = mockRes()
    await handler(
      { method: 'POST', headers: { 'x-forwarded-for': '7.7.7.7' }, body: { email: 'ok@b.com' } },
      res
    )
    assert.equal(res.statusCode, 200)
    assert.equal(fake.members.has('ok@b.com'), true)
  })
)

results.push(
  await run('mail-only mode still dedupes in process', async () => {
    setEnv({ RESEND_API_KEY: 'k', WAITLIST_NOTIFY_TO: 'a@b.com' })
    stubResend()
    const body = { email: 'memo@b.com' }
    await handler({ method: 'POST', headers: {}, body }, mockRes())
    await handler({ method: 'POST', headers: {}, body }, mockRes())
    assert.equal(calls.length, 1, 'no store means the in-process set is the only dedupe there is')
  })
)

globalThis.fetch = realFetch

const failed = results.filter(r => !r).length
console.log(failed ? `\n${failed}/${results.length} failed` : `\n${results.length}/${results.length} passed`)
process.exit(failed ? 1 : 0)
