#!/usr/bin/env node
// Measures a page against docs/DENSITY.md. The targets come from paddle.com,
// measured rather than remembered; this exists so "cleaner" is a number a
// writer can hit rather than a matter of taste.
import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
// Calibrated against paddle.com's real distribution, not a flat cap.
//
// The first version capped every section at 45 words TOTAL, which counted the
// contents of a card grid against the same budget as the heading above it. A
// four-card grid then could not fit, and pages lost rows for budget reasons
// rather than redundancy. That is not what Paddle does: their mean section is
// 39 words, but their DENSEST is 130 — ten cards of thirteen words each.
//
// So the budget is split the way the page is actually built:
//   prose    the eyebrow, the h2, the lead — the words framing the object
//   card     each card or ruled row, individually
// A section's TOTAL is deliberately not capped — see the note at the check.
const LIMITS = { prose: 45, perPage: 420, headline: 9, card: 20, para: 40 }

const strip = h => h.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ')

// Remove every <div class="<name>…"> … </div> by walking the tags and counting
// depth, so nesting cannot end the match early.
function cutBalanced(html, name) {
  const open = new RegExp(`<div[^>]*class="${name}[^"]*"[^>]*>`, 'g')
  let out = html, m
  while ((m = open.exec(out))) {
    let i = m.index + m[0].length
    let depth = 1
    const tag = /<\/?div\b[^>]*>/g
    tag.lastIndex = i
    let t
    while (depth > 0 && (t = tag.exec(out))) {
      depth += t[0][1] === '/' ? -1 : 1
      i = t.index + t[0].length
    }
    out = out.slice(0, m.index) + ' ' + out.slice(i)
    open.lastIndex = 0
  }
  return out
}
const count = t => (t.match(/[A-Za-z0-9$%¢][^\s]*/g) || []).length

function sections(html) {
  const main = html.slice(html.indexOf('<main>'), html.indexOf('</main>'))
  const parts = main.split(/(?=<section class="(?:band|hero))/).filter(p => /class="(?:band|hero)/.test(p))
  return parts.map(p => {
    const h = p.match(/class="h2"[^>]*>([\s\S]*?)<\/h2>/) || p.match(/<h1>([\s\S]*?)<\/h1>/)
    // Count CONTAINERS, never their children. `.step` and `.card` were in this
    // list, so a three-step grid scored four objects — the grid plus each step —
    // and could never pass "one object per section" however it was written. A
    // writer worked around it by converting every step grid to cards, which is
    // a component lost to a measurement bug rather than to a design decision.
    const objects = (p.match(/class="(?:grid|rows|matrix-scroll|faq|calc|invoice|strip)[\s"]/g) || []).length
    const cards = [...p.matchAll(/<(?:article|div)[^>]*class="card[^"]*"[^>]*>([\s\S]*?)<\/(?:article|div)>/g)]
      .map(m => count(strip(m[1])))
    // Prose = the section minus everything inside an object. It is the part a
    // reader meets before the thing the section is actually about.
    let prose = p
    for (const re of [/<(?:article|div)[^>]*class="card[^"]*"[^>]*>[\s\S]*?<\/(?:article|div)>/g,
                      /<table[\s\S]*?<\/table>/g, /<details[\s\S]*?<\/details>/g])
      prose = prose.replace(re, ' ')
    // The invoice artifact needs a real matcher, not a regex. A non-greedy
    // /<div class="invoice">[\s\S]*?<\/div>\s*<\/div>/ stops at the first
    // </div></div>, which occurs inside .invoice__head — so the artifact's body
    // and foot were counting as PROSE and pages with a worked example looked
    // 30+ words denser than they are. That mismeasurement pushed a writer into
    // trimming an eight-word lead that was never the problem.
    prose = cutBalanced(prose, 'invoice')
    const paras = [...p.matchAll(/<p[^>]*>([\s\S]*?)<\/p>/g)].map(m => count(strip(m[1])))
    return {
      name: h ? strip(h[1]).trim().replace(/\s+/g, ' ').slice(0, 44) : '(hero)',
      words: count(strip(p)),
      objects,
      worstCard: Math.max(0, ...cards),
      worstPara: Math.max(0, ...paras),
      prose: count(strip(prose)),
      // Collapsed answers are not visible copy, in a section any more than on
      // a page. A band whose one object is a five-question FAQ is not dense;
      // it is a closed drawer.
      visible: count(strip(p)) - [...p.matchAll(/<details[\s\S]*?<\/details>/g)]
        .reduce((a, m) => a + count(strip(m[0])), 0),
    }
  })
}

function report(rel) {
  const html = readFileSync(join(ROOT, rel), 'utf8')
  const main = html.slice(html.indexOf('<main>'), html.indexOf('</main>'))
  const secs = sections(html)
  const total = secs.reduce((a, s) => a + s.words, 0)
  // Paddle's FAQ answers are <details>, collapsed on load, and their own
  // reporting leads with visible words and notes the expanded figure
  // separately — /billing is 819 visible and 1,099 expanded. An answer nobody
  // has clicked is not copy on the page, so the page budget is measured the
  // same way here. It is also why an FAQ page can honestly carry more.
  const collapsed = [...main.matchAll(/<details[\s\S]*?<\/details>/g)]
    .reduce((a, m) => a + count(strip(m[0])), 0)
  const visible = total - collapsed
  const links = (main.match(/<a\s/g) || []).length
  const bad = []
  if (visible > LIMITS.perPage)
    bad.push(`page ${visible}w visible > ${LIMITS.perPage}` + (collapsed ? ` (+${collapsed} collapsed)` : ''))
  if (links > 20) bad.push(`${links} body links > 20`)
  for (const s of secs) {
    if (s.prose > LIMITS.prose) bad.push(`"${s.name}" ${s.prose}w of prose > ${LIMITS.prose}`)
    // No total-per-section cap. 130 was the densest section MEASURED on
    // paddle.com, not a rule they follow — it emerges from one object, short
    // framing prose and short cards. Enforcing it directly punishes a complete
    // list: the roadmap's two halves are twelve and ten rows, every row under
    // fifteen words, and there is nothing wrong with either of them. The three
    // checks below are the actual constraints; the total takes care of itself.
    if (s.objects > 1) bad.push(`"${s.name}" ${s.objects} objects > 1`)
    if (s.worstCard > LIMITS.card) bad.push(`"${s.name}" card ${s.worstCard}w > ${LIMITS.card}`)
    if (s.worstPara > LIMITS.para) bad.push(`"${s.name}" para ${s.worstPara}w > ${LIMITS.para}`)
  }
  return { rel, total, visible, collapsed, links, secs, bad }
}

const arg = process.argv[2]
const pages = arg
  ? [arg.replace(/^site\//, '')]
  : [...readdirSync(ROOT).filter(f => f.endsWith('.html')),
     ...readdirSync(join(ROOT, 'for')).map(f => `for/${f}`),
     ...readdirSync(join(ROOT, 'compare')).map(f => `compare/${f}`)].filter(f => existsSync(join(ROOT, f)))

let fails = 0
for (const p of pages) {
  const r = report(p)
  if (arg) {
    console.log(`\n${r.rel} — ${r.visible} visible words` +
      (r.collapsed ? ` (+${r.collapsed} in collapsed FAQ)` : '') + `, ${r.links} body links\n`)
    for (const s of r.secs)
      console.log(`  ${String(s.visible).padStart(4)}w vis    ${String(s.prose).padStart(3)}w prose  ${s.objects} obj  card:${String(s.worstCard).padStart(3)}  ${s.name}`)
  }
  if (r.bad.length) {
    fails++
    console.log(`\n✗ ${r.rel}`)
    for (const b of r.bad) console.log(`    ${b}`)
  }
}
console.log(fails ? `\ndensity: ${fails} of ${pages.length} pages over budget` : `\ndensity: ${pages.length} pages within budget`)
process.exit(fails && !arg ? 1 : 0)
