import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)
const { chromium } = require(process.env.HOME + '/.claude/skills/gstack/node_modules/playwright')
const dir = process.argv[2]
const FPS = 30
const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 })
await page.goto('file://' + dir + '/film.html')
await page.evaluate(() => window.ready)
const dur = await page.evaluate(() => window.DURATION)
const n = Math.round(dur * FPS)
const canvas = await page.$('canvas')
for (let i = 0; i < n; i++) {
  await page.evaluate(t => window.draw(t), i / FPS)
  await canvas.screenshot({ path: `${dir}/frames/f_${String(i).padStart(4, '0')}.png` })
}
// the poster: the end card, fully settled
await page.evaluate(t => window.draw(t), 9.7)
await canvas.screenshot({ path: `${dir}/poster.png` })
await browser.close()
console.log('frames', n)
