// Walks the dive and screenshots it. Scroll-scrubbed sections cannot be judged
// from a fullPage capture — that renders one composite of a page whose stage is
// pinned, and everything reveal-driven comes out at its rest state. So this
// steps the real scroll position and takes a viewport shot at each stop, which
// is what a reader actually sees.
import pw from '/opt/homebrew/lib/node_modules/playwright/index.js'

const URL = process.argv[2] || 'http://127.0.0.1:8099/'
const W = Number(process.argv[3] || 1440)
const H = Number(process.argv[4] || 900)
const TAG = process.argv[5] || 'd'
const OUT = 'shots'

const browser = await pw.chromium.launch()
const page = await browser.newPage({ viewport: { width: W, height: H } })
const errs = []
page.on('console', m => {
  if (m.type() === 'error' || m.type() === 'warning') errs.push(m.text())
})
page.on('pageerror', e => errs.push('PAGEERROR ' + e.message))

await page.goto(URL, { waitUntil: 'load' })
await page.evaluate(() => document.fonts.ready)

// Arming is gated on frames arriving, so scroll into range and wait for it.
const sec = await page.$('.dive')
await sec.scrollIntoViewIfNeeded()
await page
  .waitForFunction(() => document.querySelector('.dive[data-fx-dive-on]'), {
    timeout: 25000,
  })
  .catch(() => console.log('!! never armed'))
// Let the ladder fill in before judging any of the frames.
await page.waitForTimeout(6000)

const geom = await page.evaluate(() => {
  const t = document.querySelector('.dive__track')
  const r = t.getBoundingClientRect()
  return {
    top: r.top + window.scrollY,
    height: t.offsetHeight,
    doc: document.documentElement.scrollHeight,
  }
})
const travel = geom.height - H
console.log('track top', Math.round(geom.top), 'travel', Math.round(travel))

const stops = [0, 0.15, 0.3, 0.45, 0.6, 0.72, 0.8, 0.86, 0.92, 0.97, 1]
for (let i = 0; i < stops.length; i++) {
  const y = geom.top + travel * stops[i]
  await page.evaluate(v => window.scrollTo(0, v), y)
  await page.waitForTimeout(320)
  const name = `${OUT}/${TAG}${String(i).padStart(2, '0')}-p${String(
    Math.round(stops[i] * 100)
  ).padStart(3, '0')}.png`
  await page.screenshot({ path: name })
}

const state = await page.evaluate(() => {
  const i = document.querySelector('.dive').__fxDive
  return {
    started: window.__fx && window.__fx.started.dive,
    loaded: i && i.loaded,
    missing: i && i.missing,
    dead: i && i.dead,
    phone: i && i.phone,
    ladder: i && i.ladder && i.ladder.dir,
    panel: i && [i.panel.offsetWidth, i.panel.offsetHeight],
  }
})
console.log(JSON.stringify(state))
if (errs.length) console.log('CONSOLE:\n' + errs.slice(0, 12).join('\n'))
await browser.close()
