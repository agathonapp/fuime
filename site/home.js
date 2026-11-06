// fuime front door: the waitlist form, and the week that plays in the phone.
// No dependencies, no build step. docs/WAITLIST_PLAN.md is the brief.
//
// The phone runs a 24-second loop in three phases, the same three the app's
// tabs name. Earn it: four jobs pay out, and a sticker for each kind of work
// pops beside the phone. Track it: the week as a chart. Spend it: some of it
// goes on gear for the work, and what's kept is the last sticker. State is
// computed from the clock every frame, so pausing, holding a frame (?t=) and
// reduced motion are all the same code path.
;(() => {
  'use strict'

  const root = document.documentElement
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches

  /* ── the waitlist form ─────────────────────────────────────────────── */

  const form = document.getElementById('join')
  const input = form.querySelector('input[type="email"]')
  const go = form.querySelector('.join__go')
  const msg = form.querySelector('.join__msg')
  // The server's own check, in api/waitlist.js, so a typo costs no round trip.
  const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

  const say = (text, state) => {
    msg.textContent = text
    if (state) msg.setAttribute('data-state', state)
    else msg.removeAttribute('data-state')
  }
  input.addEventListener('input', () => input.removeAttribute('aria-invalid'))

  form.addEventListener('submit', async ev => {
    ev.preventDefault()
    if (go.disabled) return

    const email = input.value.trim()
    if (!EMAIL_RE.test(email) || email.length > 254) {
      say('That address does not look right.', 'error')
      input.setAttribute('aria-invalid', 'true')
      input.focus()
      return
    }

    // home-<who>-waitlist lets the roster tell a parent from a founder.
    const who = form.querySelector('input[name="who"]:checked')
    const source = who ? `home-${who.value}-waitlist` : 'home-waitlist'

    go.disabled = true
    go.textContent = 'Joining'
    say('')
    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, source }),
      })
      if (!res.ok) throw new Error(`http ${res.status}`)
      form.setAttribute('data-done', 'true')
    } catch {
      say('That did not send. Email rushil@fuime.com and we will add you.', 'error')
    } finally {
      go.disabled = false
      go.textContent = 'Join the waitlist'
    }
  })

  // The app sends a sign-in that found no account here as /?account=none#join
  // (Fuime::Signups in the Rails app). Say why, and put them in the field.
  if (/(?:^|[?&])account=none(?:&|$)/.test(location.search)) {
    document.querySelector('[data-account-none]').hidden = false
    input.focus({ preventScroll: true })
  }

  /* ── the week ──────────────────────────────────────────────────────── */

  const LOOP = 24
  // 445 in, 347 out, 98 kept. The figures the stickers quote come from here.
  const PAY = [
    { at: 0.7, ico: 'L', label: 'Lawn', sub: 'Sat · the Parks', amount: 40 },
    { at: 2.5, ico: 'P', label: 'Senior photos', sub: 'Sun · 3 hr shoot', amount: 250 },
    { at: 4.3, ico: 'D', label: 'DJ set', sub: 'Fri · a birthday', amount: 120 },
    { at: 6.1, ico: 'A', label: 'Algebra', sub: 'Thu · 1 hr', amount: 35 },
  ]
  const BUY = [
    { at: 16.7, ico: 'C', label: 'Camera lens', sub: 'for the shoots', amount: 240 },
    { at: 17.9, ico: 'M', label: 'Mower blade', sub: 'for the lawns', amount: 18 },
    { at: 19.1, ico: 'H', label: 'Headphones', sub: 'for the sets', amount: 89 },
  ]
  const IN = PAY.reduce((n, p) => n + p.amount, 0)

  const clamp = x => (x < 0 ? 0 : x > 1 ? 1 : x)
  const span = (t, a, b) => clamp((t - a) / (b - a))
  const out3 = x => 1 - (1 - x) ** 3
  const money = n =>
    `$${n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

  const total = document.querySelector('.app__total')
  const label = document.querySelector('.app__label')
  const feed = document.querySelector('.app__feed')
  const cash = document.querySelector('.st--cash')
  const cashAmt = cash.querySelector('.st__amt')
  const pauseBtn = document.querySelector('.pause')

  // When each sticker is on. [in, out) in seconds of the loop.
  const CUES = new Map([
    [document.querySelector('.st--age'), [0.25, Infinity]],
    ...PAY.map((p, i) => [document.querySelector(`[data-at="earn-${i}"]`), [p.at, 7.85]]),
    [document.querySelector('[data-at="track"]'), [8.6, 15.8]],
    [document.querySelector('[data-at="track-1"]'), [9.7, 15.8]],
    [document.querySelector('[data-at="spend"]'), [16.85, 23.3]],
    [document.querySelector('[data-at="kept"]'), [20.0, 23.3]],
  ])

  const row = (item, out) => {
    const li = document.createElement('li')
    if (out) li.className = 'out'
    li.innerHTML =
      `<span class="ico">${item.ico}</span>` +
      `<span><b>${item.label}</b><small>${item.sub}</small></span>` +
      `<span class="amt">${out ? '−' : '+'}${money(item.amount)}</span>`
    return li
  }

  let phase = ''
  let shown = 0
  let cashFor = -1
  let first = true

  const render = t => {
    const now = t < 8 ? 'earn' : t < 16 ? 'track' : 'spend'
    if (now !== phase) {
      phase = now
      root.setAttribute('data-phase', now)
      feed.textContent = ''
      shown = 0
      label.textContent = now === 'spend' ? 'Left this week' : 'This week'
    }

    // The feed: newest on top, each row dropping in as its moment passes.
    const list = phase === 'earn' ? PAY : phase === 'spend' ? BUY : []
    const due = list.filter(p => p.at <= t).length
    while (shown < due) {
      const li = row(list[shown], phase === 'spend')
      if (first) li.style.animation = 'none'
      feed.prepend(li)
      shown++
    }

    // The total counts up as money lands, and down as it goes.
    let n = 0
    if (phase === 'earn') for (const p of PAY) n += p.amount * out3(span(t, p.at, p.at + 0.6))
    else n = IN
    if (phase === 'spend') for (const b of BUY) n -= b.amount * out3(span(t, b.at, b.at + 0.6))
    const text = money(Math.round(n * 100) / 100)
    if (total.textContent !== text) total.textContent = text

    // One sticker per kind of work, and a cash sticker for each payment.
    for (const [el, [a, b]] of CUES) el.classList.toggle('is-in', t >= a && t < b)
    const paying = PAY.findIndex(p => t >= p.at + 0.15 && t < p.at + 1.5)
    if (paying !== cashFor) {
      cashFor = paying
      if (paying >= 0) {
        cashAmt.textContent = `+$${PAY[paying].amount}`
        cash.classList.remove('is-in')
        void cash.offsetWidth // restart the pop for each new amount
        cash.classList.add('is-in')
      } else {
        cash.classList.remove('is-in')
      }
    }
    first = false
  }

  let t = 0
  let last = 0
  let raf = 0
  let playing = false
  const frame = now => {
    const dt = last ? Math.min((now - last) / 1000, 0.1) : 0
    last = now
    t = (t + dt) % LOOP
    render(t)
    raf = requestAnimationFrame(frame)
  }
  const play = () => {
    playing = true
    last = 0
    root.removeAttribute('data-paused')
    raf = requestAnimationFrame(frame)
    pauseBtn.setAttribute('aria-pressed', 'false')
    pauseBtn.setAttribute('aria-label', 'Pause the animation')
  }
  const pause = () => {
    playing = false
    cancelAnimationFrame(raf)
    root.setAttribute('data-paused', '')
    pauseBtn.setAttribute('aria-pressed', 'true')
    pauseBtn.setAttribute('aria-label', 'Play the animation')
  }
  pauseBtn.addEventListener('click', () => (playing ? pause() : play()))

  // ?t=12.5 holds the week at that second, for reviewing a frame.
  const held = parseFloat(new URLSearchParams(location.search).get('t'))

  if (reduced) {
    // The week at its fullest moment, still, and no control for motion that
    // is not there.
    pauseBtn.hidden = true
    render(7.5)
  } else if (held >= 0 && held < LOOP) {
    // Walk up to the held second so the feed holds what it would by then.
    for (let s = 0; s <= held; s += 0.25) render(Math.min(s, held))
    render(held)
    pause()
  } else {
    play()
  }
})()
