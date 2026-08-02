// Shared behaviour for all three pages. No dependencies, no build step.
;(function () {
  'use strict'

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  var fine = window.matchMedia('(pointer: fine)').matches

  /* ── loader ──────────────────────────────────────────────────────────── */

  // The arch fills against a real manifest. Every weight below is something
  // that genuinely has to arrive before the first screen is worth looking at,
  // which is the only reason the motion is honest.
  ;(function () {
    var el = document.getElementById('boot')
    if (!el) return

    var root = document.documentElement
    var finish = function () {
      root.classList.add('boot-out')
      el.setAttribute('data-done', 'true')
      setTimeout(function () {
        el.setAttribute('hidden', '')
      }, 700)
      try {
        sessionStorage.setItem('fuime.booted', '1')
      } catch (e) {}
    }

    if (root.classList.contains('booted')) {
      el.setAttribute('hidden', '')
      return
    }

    var rect = document.getElementById('boot-rect')
    var GLYPH = 582
    var GATE = reduced ? 0 : 420 // a sub-half-second flash reads as a glitch
    var CAP = 1200 // no asset gets to hold the page hostage
    var started = Date.now()
    var shown = 0
    var sealed = false

    el.setAttribute('data-lit', 'true')

    var steps = [
      { weight: 0.28, done: false }, // webfonts
      { weight: 0.44, done: false }, // the hero photograph
      { weight: 0.28, done: false }, // everything else
    ]

    var target = function () {
      var t = 0
      for (var i = 0; i < steps.length; i++)
        if (steps[i].done) t += steps[i].weight
      return t
    }

    var seal = function () {
      if (sealed) return
      sealed = true
      var wait = Math.max(0, GATE - (Date.now() - started))
      // Hold a beat on the filled arch so the last frame is the logo, whole.
      setTimeout(finish, wait + (reduced ? 0 : 260))
    }

    var paint = function () {
      var t = target()
      if (t > shown) shown = t
      if (rect) {
        rect.style.transform =
          'translateY(' + (GLYPH * (1 - shown)).toFixed(1) + 'px)'
      }
      if (shown >= 0.999) seal()
    }

    var mark = function (i) {
      return function () {
        steps[i].done = true
        paint()
      }
    }

    if (document.fonts && document.fonts.ready)
      document.fonts.ready.then(mark(0))
    else mark(0)()

    var img = document.querySelector('.hero__media img')
    if (!img) mark(1)()
    else if (img.complete && img.naturalWidth > 0) mark(1)()
    else {
      img.addEventListener('load', mark(1))
      img.addEventListener('error', mark(1)) // a missing photo still ends the wait
    }

    if (document.readyState === 'complete') mark(2)()
    else window.addEventListener('load', mark(2))

    // Any deliberate input means the reader is finished waiting. The arch fills
    // to wherever it had got to and the page lands. A loader that keeps holding
    // the door after someone has already reached for the handle is just rude.
    var impatient = function () {
      shown = 1
      paint()
      seal()
    }
    ;['scroll', 'keydown', 'pointerdown', 'touchstart'].forEach(function (t) {
      window.addEventListener(t, impatient, { passive: true, once: true })
    })

    paint()
    setTimeout(impatient, CAP)
  })()

  /* ── living hero ─────────────────────────────────────────────────────── */

  // The photograph is the hero. This only ever adds motion on top of it, and
  // only when the connection and the reader's stated preference can carry it.
  // Nothing is fetched otherwise: the <video> ships preload="none" and we
  // never call load(), so a metered phone pays nothing for a feature it isn't
  // going to see.
  ;(function () {
    var vid = document.querySelector('.hero__live')
    if (!vid) return

    var conn = navigator.connection || {}
    var slow = /(^|-)2g$/.test(conn.effectiveType || '')
    if (reduced || conn.saveData || slow) return

    // A 5s loop is not worth 165KB on a phone that is showing it at 390px.
    if (window.innerWidth < 700) return

    var start = function () {
      vid.addEventListener(
        'playing',
        function () {
          vid.setAttribute('data-playing', 'true')
        },
        { once: true }
      )
      var p = vid.play()
      if (p && p.catch) p.catch(function () {}) // autoplay refused: keep the still
    }

    // Off-screen it should not be decoding frames. Battery, not bandwidth.
    var hero = vid.closest('.hero')
    if ('IntersectionObserver' in window && hero) {
      var seen = false
      new IntersectionObserver(
        function (entries) {
          entries.forEach(function (e) {
            if (e.isIntersecting) {
              if (!seen) {
                seen = true
                vid.load()
              }
              start()
            } else if (seen) {
              vid.pause()
            }
          })
        },
        { rootMargin: '120px' }
      ).observe(hero)
    } else {
      vid.load()
      start()
    }
  })()

  /* ── nav: transparent over a dark hero, solid once past it ───────────── */

  var nav = document.querySelector('.nav')
  if (nav) {
    var overHero = nav.classList.contains('nav--over')

    /* Measured once per layout, not once per scroll event. Reading
       hero.offsetHeight inside the scroll handler forced a reflow on every
       frame of every scroll, which is a real cost on a page carrying this
       many scroll-driven modules. */
    var heroEnd = 40
    var navH = 72
    var darkRanges = []

    var measureNav = function () {
      var hero = document.querySelector('.hero')
      heroEnd = hero ? hero.offsetHeight - 90 : 40
      navH = nav.offsetHeight || 72
      darkRanges = []
      var dark = document.querySelectorAll('.hero, .band--night, .foot')
      for (var i = 0; i < dark.length; i++) {
        var top = dark[i].getBoundingClientRect().top + window.scrollY
        darkRanges.push([top, top + dark[i].offsetHeight])
      }
    }

    var syncNav = function () {
      var y = window.scrollY
      var past = y > heroEnd
      nav.classList.toggle('nav--solid', past || !overHero)
      if (overHero) nav.classList.toggle('nav--over', !past)

      // Which band the bar is sitting on decides its colour. Probe inside the
      // bar rather than at its edge, so a boundary line exactly at the seam
      // cannot flicker the class on and off between frames.
      var probe = y + navH * 0.6
      var dark = false
      for (var i = 0; i < darkRanges.length; i++) {
        if (probe >= darkRanges[i][0] && probe < darkRanges[i][1]) {
          dark = true
          break
        }
      }
      nav.classList.toggle('nav--dark', dark)
    }

    var navQueued = false
    var onNavScroll = function () {
      if (navQueued) return
      navQueued = true
      requestAnimationFrame(function () {
        navQueued = false
        syncNav()
      })
    }

    measureNav()
    syncNav()
    window.addEventListener('scroll', onNavScroll, { passive: true })
    window.addEventListener('resize', function () {
      measureNav()
      syncNav()
    })
    // Images and video settle after load and move every band under the nav.
    window.addEventListener('load', function () {
      measureNav()
      syncNav()
    })

    var burger = nav.querySelector('.nav__burger')
    if (burger) {
      burger.addEventListener('click', function () {
        var open = nav.getAttribute('data-open') === 'true'
        nav.setAttribute('data-open', String(!open))
        burger.setAttribute('aria-expanded', String(!open))
      })
      nav.querySelectorAll('.nav__links a').forEach(function (a) {
        a.addEventListener('click', function () {
          nav.setAttribute('data-open', 'false')
          burger.setAttribute('aria-expanded', 'false')
        })
      })
    }
  }

  /* ── scroll reveal, staggered per child ──────────────────────────────── */

  var risers = document.querySelectorAll('.rise')
  risers.forEach(function (el) {
    var kids = el.children
    for (var i = 0; i < kids.length; i++) {
      kids[i].classList.add('rise-i')
      kids[i].style.setProperty('--i', String(i))
    }
  })

  if (reduced || !('IntersectionObserver' in window)) {
    risers.forEach(function (el) {
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
      { rootMargin: '0px 0px -8% 0px', threshold: 0.06 }
    )
    risers.forEach(function (el) {
      io.observe(el)
    })
  }

  /* ── hero: a second light that follows the pointer ───────────────────── */

  var hero = document.querySelector('.hero')
  if (hero && fine && !reduced) {
    var img = hero.querySelector('.hero__media img')
    var raf = 0
    var pending = null

    var paint = function () {
      raf = 0
      if (!pending) return
      hero.style.setProperty('--mx', pending.mx + '%')
      hero.style.setProperty('--my', pending.my + '%')
      if (img) {
        // A few pixels only. Enough to feel alive, not enough to reveal the
        // edge of the photograph.
        img.style.setProperty('--px', pending.px.toFixed(1) + 'px')
        img.style.setProperty('--py', pending.py.toFixed(1) + 'px')
      }
    }

    hero.addEventListener(
      'pointermove',
      function (ev) {
        var r = hero.getBoundingClientRect()
        var x = (ev.clientX - r.left) / r.width
        var y = (ev.clientY - r.top) / r.height
        pending = {
          mx: (x * 100).toFixed(1),
          my: (y * 100).toFixed(1),
          px: (0.5 - x) * 18,
          py: (0.5 - y) * 12,
        }
        hero.setAttribute('data-pointer', 'true')
        if (!raf) raf = requestAnimationFrame(paint)
      },
      { passive: true }
    )

    hero.addEventListener('pointerleave', function () {
      hero.setAttribute('data-pointer', 'false')
      if (img) {
        img.style.setProperty('--px', '0px')
        img.style.setProperty('--py', '0px')
      }
    })
  }

  /* ── portal: the archway drifts as it scrolls into view ──────────────── */

  var portalImg = document.querySelector('.portal__media img')
  if (portalImg && !reduced && 'IntersectionObserver' in window) {
    var drifting = false
    var driftRaf = 0

    var drift = function () {
      driftRaf = 0
      if (!drifting) return
      var r = portalImg.getBoundingClientRect()
      var mid = (r.top + r.height / 2) / window.innerHeight // 0 top, 1 bottom
      portalImg.style.setProperty('--py', ((mid - 0.5) * -26).toFixed(1) + 'px')
    }
    var onScroll = function () {
      if (!driftRaf) driftRaf = requestAnimationFrame(drift)
    }

    new IntersectionObserver(function (entries) {
      drifting = entries[0].isIntersecting
      if (drifting) onScroll()
    }).observe(portalImg)

    window.addEventListener('scroll', onScroll, { passive: true })
  }

  /* ── running strip: duplicate the row so the loop has no seam ────────── */

  // The seamless loop needs the row's contents twice. Only the second copy is
  // decoration, so aria-hidden goes on the clones — hiding the whole row, as
  // this used to, took the real content out of the accessibility tree with it.
  // Cloning per item rather than wrapping keeps the flex row's children direct.
  document.querySelectorAll('.strip__row').forEach(function (row) {
    Array.prototype.slice.call(row.children).forEach(function (item) {
      var copy = item.cloneNode(true)
      copy.setAttribute('aria-hidden', 'true')
      row.appendChild(copy)
    })
  })

  /* ── live fee calculator ─────────────────────────────────────────────── */

  // The one place on the site where the pricing is not a claim. Drag it and
  // the invoice recomputes with the same arithmetic the product uses.
  var STRIPE_PCT = 0.029
  var STRIPE_FIXED = 0.3
  var FUIME_PCT = 0.07
  var MONTHLY_THRESHOLD = 250

  var money = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  })

  document.querySelectorAll('[data-calc]').forEach(function (root) {
    var range = root.querySelector('.calc__range')
    if (!range) return

    var out = {
      charged: root.querySelectorAll('[data-out="charged"]'),
      stripe: root.querySelectorAll('[data-out="stripe"]'),
      fuime: root.querySelectorAll('[data-out="fuime"]'),
      lands: root.querySelectorAll('[data-out="lands"]'),
      monthly: root.querySelectorAll('[data-out="monthly"]'),
    }
    var invoice = root.querySelector('.invoice')
    var settle = 0

    var set = function (nodes, text) {
      nodes.forEach(function (n) {
        n.textContent = text
      })
    }

    var render = function (live) {
      var amount = Number(range.value)
      var stripe = amount * STRIPE_PCT + STRIPE_FIXED
      var fuime = amount * FUIME_PCT
      var lands = amount - stripe - fuime

      set(out.charged, money.format(amount))
      set(out.stripe, '−' + money.format(stripe))
      set(out.fuime, '−' + money.format(fuime))
      set(out.lands, money.format(lands))
      set(
        out.monthly,
        amount >= MONTHLY_THRESHOLD
          ? '$15/mo once you clear $250 in 30 days'
          : 'No monthly fee at this level'
      )

      var pct = ((amount - range.min) / (range.max - range.min)) * 100
      range.style.setProperty('--fill', pct.toFixed(1) + '%')

      root.querySelectorAll('.num').forEach(function (n) {
        n.setAttribute('data-live', live ? 'true' : 'false')
      })
      if (invoice) invoice.setAttribute('data-live', live ? 'true' : 'false')

      if (live) {
        clearTimeout(settle)
        settle = setTimeout(function () {
          render(false)
        }, 700)
      }
    }

    range.addEventListener('input', function () {
      render(true)
    })
    render(false)
  })

  /* ── waitlist capture ────────────────────────────────────────────────── */

  // Mirrors the server's check in api/waitlist.js, so a typo never costs a
  // round trip.
  var EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

  document.querySelectorAll('form.capture').forEach(function (form) {
    var input = form.querySelector('input[type="email"]')
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

    // The message lands in an aria-live region, so a screen reader hears the
    // rejection. What it does not hear is that the field it is sitting in is
    // the one being rejected — tab away and back and the error is gone.
    // aria-invalid is what survives that, and it is the only form-a11y gap
    // left here. Cleared the moment the address changes, because an error
    // that outlives the thing it describes is worse than none.
    var flag = function (bad) {
      if (!input) return
      if (bad) input.setAttribute('aria-invalid', 'true')
      else input.removeAttribute('aria-invalid')
    }
    if (input)
      input.addEventListener('input', function () {
        flag(false)
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
      // Sending is not a claim about the address, so a network failure below
      // must not re-raise this.
      flag(false)

      busy = true
      if (btn) {
        btn.disabled = true
        btn.textContent = 'Sending'
      }
      say('')

      fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: email,
          source: form.getAttribute('data-source') || 'unknown',
        }),
      })
        .then(function (res) {
          if (!res.ok) throw new Error('http ' + res.status)
          form.setAttribute('data-done', 'true')
          say('')
        })
        .catch(function () {
          say(
            'That did not send. Email rushil@fuime.com and we will add you.',
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
})()
