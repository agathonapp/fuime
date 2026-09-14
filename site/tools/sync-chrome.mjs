#!/usr/bin/env node
// Stamps the canonical nav and footer into every page.
//
// site/docs/BRIEF.md requires the shared chrome to be "byte-identical on all
// pages", with only aria-current differing. That was a copy-paste instruction
// when there were three pages. At twenty it is a promise no one can keep by
// hand: the footer is now a five-column sitemap, so every added link would be
// twenty edits, and the three shipped pages had ALREADY drifted — index.html
// carried a .foot__status row the other two did not.
//
// So the chrome lives once, in chrome/nav.html and chrome/foot.html, and this
// writes it into the pages. It is a dev tool, not a build step: the HTML files
// in git still contain the full markup and still ship exactly as they are.
// Nothing at runtime depends on this having been run — but test/chrome.test.mjs
// fails if it has not been.
//
//   node tools/sync-chrome.mjs         apply
//   node tools/sync-chrome.mjs --check exit 1 if any page is out of date
import { readFileSync, writeFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const CHECK = process.argv.includes('--check')

const NAV = readFileSync(join(ROOT, 'chrome/nav.html'), 'utf8').replace(/\n$/, '')
const FOOT = readFileSync(join(ROOT, 'chrome/foot.html'), 'utf8').replace(/\n$/, '')

// Structural, not marker-based: the pages predate this tool and adding markers
// to twenty files is the same edit this tool exists to avoid.
const NAV_RE = /^[ \t]*<header class="nav[\s\S]*?<\/header>/m
const FOOT_RE = /^[ \t]*<footer class="foot">[\s\S]*?<\/footer>/m

// aria-current belongs to the page, not to the chrome, so it is re-applied
// after the stamp. Key is the page file; value is the href to mark.
const CURRENT = {
  'pricing.html': '/pricing',
  'parents.html': '/parents',
  'compare.html': '/compare',
}

function markCurrent(html, file) {
  const href = CURRENT[file]
  if (!href) return html
  return html.replace(
    new RegExp(`(<a class="nav__link" href="${href}")>`),
    '$1 aria-current="page">'
  )
}

const pages = readdirSync(ROOT)
  .filter(f => f.endsWith('.html'))
  .concat(
    readdirSync(join(ROOT, 'for'), { withFileTypes: true })
      .filter(d => d.isFile() && d.name.endsWith('.html'))
      .map(d => `for/${d.name}`),
    readdirSync(join(ROOT, 'compare'), { withFileTypes: true })
      .filter(d => d.isFile() && d.name.endsWith('.html'))
      .map(d => `compare/${d.name}`)
  )

const stale = []
for (const rel of pages) {
  const abs = join(ROOT, rel)
  const before = readFileSync(abs, 'utf8')
  let after = before

  // Nested pages reference the same absolute URLs, so the chrome is identical
  // at every depth. No rewriting needed.
  if (NAV_RE.test(after)) after = after.replace(NAV_RE, NAV)
  if (FOOT_RE.test(after)) after = after.replace(FOOT_RE, FOOT)
  after = markCurrent(after, rel)

  if (after !== before) {
    stale.push(rel)
    if (!CHECK) writeFileSync(abs, after)
  }
}

if (CHECK) {
  if (stale.length) {
    console.error('chrome out of date in:\n  ' + stale.join('\n  '))
    console.error('\nrun: node tools/sync-chrome.mjs')
    process.exit(1)
  }
  console.log(`chrome: ${pages.length} pages in sync`)
} else {
  console.log(
    stale.length
      ? `chrome: updated ${stale.length} of ${pages.length} pages\n  ${stale.join('\n  ')}`
      : `chrome: ${pages.length} pages already in sync`
  )
}
