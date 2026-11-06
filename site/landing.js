// fuime.com front door behaviour. No dependencies.
;(function () {
  'use strict'

  var root = document.documentElement

  /* ── top bar ───────────────────────────────────────────────────────── */

  var bar = document.querySelector('[data-topbar]')
  var burger = bar && bar.querySelector('.topbar__burger')

  if (bar) {
    var onScroll = function () {
      bar.classList.toggle('is-scrolled', window.scrollY > 8)
    }
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
  }

  if (bar && burger) {
    var setOpen = function (open) {
      bar.classList.toggle('is-open', open)
      burger.setAttribute('aria-expanded', open ? 'true' : 'false')
    }
    burger.addEventListener('click', function () {
      setOpen(burger.getAttribute('aria-expanded') !== 'true')
    })
    bar.querySelectorAll('.topbar__links a').forEach(function (a) {
      a.addEventListener('click', function () {
        setOpen(false)
      })
    })
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') setOpen(false)
    })
  }

  /* ── reveal on scroll ──────────────────────────────────────────────── */

  var rises = document.querySelectorAll('.rise')
  if (!('IntersectionObserver' in window)) {
    rises.forEach(function (el) {
      el.classList.add('is-in')
    })
  } else {
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (e) {
          if (!e.isIntersecting) return
          e.target.classList.add('is-in')
          io.unobserve(e.target)
        })
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.08 }
    )
    rises.forEach(function (el) {
      io.observe(el)
    })
  }

  /* ── agent examples (tabs) ─────────────────────────────────────────── */

  var tabs = Array.prototype.slice.call(document.querySelectorAll('.agent__tab'))
  var select = function (tab, focus) {
    tabs.forEach(function (t) {
      var on = t === tab
      t.setAttribute('aria-selected', on ? 'true' : 'false')
      t.tabIndex = on ? 0 : -1
      var panel = document.getElementById(t.getAttribute('aria-controls'))
      if (panel) panel.hidden = !on
    })
    if (focus) tab.focus()
  }
  tabs.forEach(function (tab, i) {
    tab.addEventListener('click', function () {
      select(tab)
    })
    tab.addEventListener('keydown', function (e) {
      var next = null
      if (e.key === 'ArrowDown' || e.key === 'ArrowRight') next = tabs[(i + 1) % tabs.length]
      if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') next = tabs[(i - 1 + tabs.length) % tabs.length]
      if (e.key === 'Home') next = tabs[0]
      if (e.key === 'End') next = tabs[tabs.length - 1]
      if (next) {
        e.preventDefault()
        select(next, true)
      }
    })
  })

  /* ── waitlist ──────────────────────────────────────────────────────── */

  // The Rails app sends a sign-in that found no account to /?account=none#join
  // (Fuime::Signups), so say why they landed on a waitlist. Hidden in the
  // markup, so with scripts off nothing looks wrong.
  if (/(?:^|[?&])account=none(?:&|$)/.test(location.search)) {
    var none = document.querySelector('[data-account-none]')
    if (none) none.hidden = false
  }

  // Mirrors the server's check in api/waitlist.js, so a typo never costs a
  // round trip.
  var EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

  document.querySelectorAll('form.capture').forEach(function (form) {
    var input = form.querySelector('input[type="email"]')
    var type = form.querySelector('select[data-type]')
    var btn = form.querySelector('button[type="submit"]')
    var msg = form.querySelector('.capture__msg')
    var idle = btn ? btn.textContent : ''
    var busy = false

    var say = function (text, state) {
      if (!msg) return
      msg.textContent = text
      if (state) msg.setAttribute('data-state', state)
      else msg.removeAttribute('data-state')
    }
    var flag = function (bad) {
      if (!input) return
      if (bad) input.setAttribute('aria-invalid', 'true')
      else input.removeAttribute('aria-invalid')
    }

    if (input)
      input.addEventListener('input', function () {
        flag(false)
      })
    if (type)
      type.addEventListener('change', function () {
        type.classList.toggle('has-value', !!type.value)
      })

    form.addEventListener('submit', function (ev) {
      ev.preventDefault()
      if (busy) return

      var email = (input.value || '').trim()
      if (!EMAIL_RE.test(email) || email.length > 254) {
        say('That address does not look right.', 'error')
        flag(true)
        input.focus()
        return
      }
      flag(false)

      // api/waitlist.js stores { email, source } and nothing else, and the
      // admin roster groups by source. Carrying the business type in the
      // source ("home-waitlist:soleprop") gets a breakdown by type without
      // changing the endpoint or its storage contract. The server caps source
      // at 40 characters; the longest value here is 22.
      var source = form.getAttribute('data-source') || 'unknown'
      if (type && type.value) source += ':' + type.value

      busy = true
      if (btn) {
        btn.disabled = true
        btn.textContent = 'Sending'
      }
      say('')

      fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email, source: source }),
      })
        .then(function (res) {
          if (res.status === 429) throw new Error('rate')
          if (!res.ok) throw new Error('http ' + res.status)
          form.setAttribute('data-done', 'true')
          say('')
        })
        .catch(function (err) {
          say(
            err && err.message === 'rate'
              ? 'Too many tries from here. Give it a few minutes.'
              : 'That did not send. Email support@fuime.com and we will add you.',
            'error'
          )
        })
        .finally(function () {
          busy = false
          if (btn) {
            btn.disabled = false
            btn.textContent = idle
          }
        })
    })
  })

  root.classList.add('is-ready')
})()
