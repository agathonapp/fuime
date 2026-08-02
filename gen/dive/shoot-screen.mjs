// Screenshots the app plate at 2x so it survives being blown up to full viewport.
//
//   node shoot-screen.mjs [out.png] [page.html]
//
// The signup plate is served over HTTP rather than file://, because it links
// the site's real stylesheet with an absolute path — see screen-signup.html for
// why that is worth a server.
import pw from '/opt/homebrew/lib/node_modules/playwright/index.js'
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { extname, join, normalize } from 'node:path'

const out = process.argv[2] || 'keys/screen.png'
const doc = process.argv[3] || 'screen.html'
const SITE = new URL('../../site/', import.meta.url).pathname
const TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'text/javascript',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
  '.png': 'image/png',
  '.json': 'application/json',
}

// Two roots, in order: this directory for the plate itself, the built site for
// everything the plate's absolute paths point at.
const server = createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(req.url.split('?')[0]))
  for (const root of [process.cwd(), SITE]) {
    try {
      const body = await readFile(join(root, path))
      res.writeHead(200, {
        'content-type': TYPES[extname(path)] || 'application/octet-stream',
      })
      return res.end(body)
    } catch {}
  }
  res.writeHead(404).end('nope')
})
await new Promise(f => server.listen(0, '127.0.0.1', f))
const port = server.address().port

const browser = await pw.chromium.launch()
const page = await browser.newPage({
  viewport: { width: 1600, height: 1000 },
  deviceScaleFactor: 2,
})
const bad = []
page.on('requestfailed', r => bad.push(r.url()))
page.on(
  'response',
  r => r.status() >= 400 && bad.push(r.status() + ' ' + r.url())
)
await page.goto(`http://127.0.0.1:${port}/${doc}`, { waitUntil: 'load' })
// Fontshare is a network font; wait for it or the plate ships in system sans.
await page.evaluate(() => document.fonts.ready)
await page.waitForTimeout(600)
await page.screenshot({ path: out })
await browser.close()
server.close()

// A plate that silently lost its stylesheet still screenshots — as a stack of
// unstyled text — and the first place anyone notices is 121 baked frames later.
if (bad.length) {
  console.error('FAILED REQUESTS:\n  ' + bad.join('\n  '))
  process.exit(1)
}
console.log(out)
