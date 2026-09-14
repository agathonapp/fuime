#!/usr/bin/env node
// Local replica of the two RSpec copy/pricing guards, so a page can be checked
// without booting Rails.
//
// Why this exists: spec/fuime_marketing_copy_spec.rb and
// spec/fuime_marketing_pricing_spec.rb are the only two suites that gate a PR on
// site copy, and both require a Rails boot and a database. On a machine without
// the gem bundle they cannot run at all, which is how a page ships unchecked.
// This file applies the SAME assertions to the SAME files, offline.
//
// It is a replica, not the source of truth. When either spec changes, change
// this too — the lists at the top of each are meant to stay in step.
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'

const ROOT = fileURLToPath(new URL('../..', import.meta.url))
const read = rel => readFileSync(join(ROOT, rel), 'utf8')

// Mirrors spec/fuime_marketing_copy_spec.rb `public_pages`. Every page the
// public can reach belongs here; a page left off escapes every copy check.
export const PUBLIC_PAGES = [
  'site/index.html',
  'site/pricing.html',
  'site/parents.html',
  'site/start.html',
  'site/start-scroll.html',
  'site/payment-links.html',
  'site/subscriptions.html',
  'site/books.html',
  'site/taxes.html',
  'site/api.html',
  'site/merchant-of-record.html',
  'site/why-has-fuime-charged-me.html',
  'site/for/tutoring.html',
  'site/for/photo-video.html',
  'site/for/lawn-care.html',
  'site/for/schools.html',
  'site/compare.html',
  'site/compare/venmo.html',
  'site/compare/paddle.html',
  'site/compare/waiting.html',
  'site/roadmap.html',
  'site/faq.html',
]
// Mirrors spec/fuime_marketing_pricing_spec.rb `public_price_pages`. ONLY pages
// that actually quote a price: membership forces "5%" AND "50¢" AND a sales
// route to be present, which is wrong to demand of a page about receipts.
export const PRICE_PAGES = [
  'site/index.html',
  'site/pricing.html',
  'site/parents.html',
  'site/merchant-of-record.html',
  'site/compare/paddle.html',
  'site/faq.html',
]
// Mirrors its `marketing_files` — price pages plus these.
export const EXTRA_MARKETING_FILES = ['site/site.js', 'site/docs/BRIEF.md']

// spec/fuime_marketing_copy_spec.rb:32-40. Downcased substring over the WHOLE
// file, HTML comments included.
const BANNED_PHRASES = [
  'payments are not live',
  'no real money moves',
  'test mode',
  'early access',
  'your turn',
  'onboarding the first businesses',
  'not something running today',
]

const DISCLOSURE = 'financial technology company, not a bank'

const fails = []
const fail = (file, msg) => fails.push(`${file}: ${msg}`)

function checkPublicPage(rel) {
  if (!existsSync(join(ROOT, rel))) return fail(rel, 'file does not exist')
  const body = read(rel)
  const lower = body.toLowerCase()

  for (const p of BANNED_PHRASES) {
    if (lower.includes(p)) fail(rel, `contains banned phrase "${p}"`)
  }
  // Case-sensitive substring, exactly as the spec asserts it.
  if (!body.includes(DISCLOSURE)) fail(rel, 'lost the standing L5 disclosure')
  if (body.includes('href="/start"')) fail(rel, 'links to /start (cached 308)')
  if (!body.includes('href="/get-started"')) fail(rel, 'has no /get-started CTA')

  // site/test/server.test.mjs:229-238 — anchor TEXT is pinned, not just the href.
  if (!/<a\s[^>]*href="\/get-started"[^>]*>\s*(Start your business|Have your teen start)\s*</.test(body))
    fail(rel, 'primary CTA anchor text is not exactly "Start your business" / "Have your teen start"')
  if (!/<a\s[^>]*href="\/login"[^>]*>\s*Log in\s*</.test(body))
    fail(rel, 'lost its <a href="/login">Log in</a>')

  // :254-256 — every capture form must be tagged as a cohort form.
  for (const m of body.matchAll(/<form\s[^>]*class="capture[^"]*"[^>]*data-source="([^"]+)"/g)) {
    if (!/-cohort$/.test(m[1])) fail(rel, `capture form "${m[1]}" is not tagged *-cohort`)
  }
  // :203-208 — a confirmation block, and one plane per block. Conditional on
  // the page having a form at all: the app is open, so the primary action is
  // /get-started and most pages correctly carry no capture form. Demanding one
  // everywhere would put a waitlist back on pages with no business showing one.
  const forms = (body.match(/<form\s[^>]*class="capture/g) || []).length
  const dones = (body.match(/class="capture__done"/g) || []).length
  const planes = (body.match(/class="capture__plane"/g) || []).length
  if (forms > 0 && dones === 0) fail(rel, 'has a capture form and no confirmation block')
  if (planes !== dones) fail(rel, `${planes} paper planes for ${dones} confirmation blocks`)
}

function checkPricePage(rel) {
  if (!existsSync(join(ROOT, rel))) return // reported once by checkPublicPage
  const body = read(rel)
  if (!/5%/.test(body)) fail(rel, 'missing the 5% rate')
  // The literal cent sign or $0.50 — an &cent; entity does not satisfy the spec.
  if (!/50¢|\$0\.50/.test(body)) fail(rel, 'states 5% without the 50¢ floor')
  if (!/custom pricing|talk to us|contact us/i.test(body))
    fail(rel, 'has no sales route for anyone outside the standard rate')
}

function checkMarketingFile(rel) {
  if (!existsSync(join(ROOT, rel))) return
  const body = read(rel)
  if (body.includes('$19.99')) fail(rel, 'still sells the retired family plan')
  if (body.includes('$15/mo')) fail(rel, 'still sells a retired monthly price')
  // NB: /\b7%/ also matches 2.7% and 0.7% — the boundary sits between . and 7.
  if (/\b7%/.test(body)) fail(rel, 'advertises a 7% rate (note: 2.7%/0.7% also trip this)')
  if (/one venture\b/i.test(body)) fail(rel, 'advertises a one-venture limit')
  if (/drops? to|plus 4%|\$15\/mo \+ 4%/.test(body)) fail(rel, 'implies a rate cut / second tier')
}

export function run({ publicPages = PUBLIC_PAGES, pricePages = PRICE_PAGES } = {}) {
  fails.length = 0
  publicPages.forEach(checkPublicPage)
  pricePages.forEach(checkPricePage)
  ;[...pricePages, ...EXTRA_MARKETING_FILES].forEach(checkMarketingFile)
  return fails
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const problems = run()
  if (problems.length) {
    console.error(`copy-guard: ${problems.length} problem(s)\n`)
    for (const p of problems) console.error('  ✗ ' + p)
    process.exit(1)
  }
  console.log(`copy-guard: ${PUBLIC_PAGES.length} pages clean`)
}
