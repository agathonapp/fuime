#!/usr/bin/env node
/* falvid.cjs — submit a fal video job, poll, download the mp4.

   A copy of ~/dev/nox-ad/falvid.cjs with one thing changed that mattered: the
   original hardcodes aspect_ratio '9:16' because it was written for a portrait
   phone ad. Every band on this site is landscape, so the ratio is a flag and
   the default is 16:9.

   usage: node tools/falvid.cjs <model> <out.mp4> "<prompt>" [seconds] [seed.png] [--ar=16:9]
*/
const fs = require('fs')
const path = require('path')

const KEY = (fs
  .readFileSync(process.env.HOME + '/.ai.env', 'utf8')
  .match(/^FAL_KEY=(.+)$/m) || [])[1]
if (!KEY) {
  console.error('no FAL_KEY in ~/.ai.env')
  process.exit(1)
}

const MODELS = {
  'veo3-fast': 'fal-ai/veo3.1/fast',
  'veo3-lite': 'fal-ai/veo3.1/lite',
  veo3: 'fal-ai/veo3.1',
  kling: 'fal-ai/kling-video/v3/standard/text-to-video',
  'kling-pro': 'fal-ai/kling-video/v2.5-turbo/pro/text-to-video',
  seedance: 'bytedance/seedance-2.0/fast/text-to-video',
  wan: 'fal-ai/wan/v2.2-a14b/text-to-video',
  // image-to-video: the seed frame locks the design, the model only adds motion
  'veo3-fast-i2v': 'fal-ai/veo3.1/fast/image-to-video',
  'veo3-i2v': 'fal-ai/veo3.1/image-to-video',
  'kling-i2v': 'fal-ai/kling-video/v2.5-turbo/pro/image-to-video',
  'kling3-i2v': 'fal-ai/kling-video/v3/standard/image-to-video',
}

const argv = process.argv.slice(2)
const flags = argv.filter(a => a.startsWith('--'))
const pos = argv.filter(a => !a.startsWith('--'))
const flag = (n, d) =>
  (flags.find(f => f.startsWith('--' + n + '=')) || '=' + d).split('=')[1]

const [modelKey, out, prompt, dur, image] = pos
const model = MODELS[modelKey] || modelKey
if (!model || !out || !prompt) {
  console.error(
    'usage: falvid.cjs <model> <out.mp4> "<prompt>" [seconds] [seed.png] [--ar=16:9]'
  )
  console.error('models: ' + Object.keys(MODELS).join(', '))
  process.exit(1)
}

const body = { prompt, aspect_ratio: flag('ar', '16:9') }
if (image) {
  const ext = path.extname(image).slice(1).toLowerCase()
  const mime = ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg' : 'image/png'
  body.image_url = `data:${mime};base64,${fs.readFileSync(image).toString('base64')}`
}
if (modelKey.startsWith('veo3')) {
  body.duration = (dur || '8') + 's'
  body.generate_audio = false
  body.resolution = flag('res', '1080p')
} else if (modelKey.startsWith('kling')) {
  body.duration = String(dur || 5)
} else {
  body.num_frames = 121
  body.resolution = flag('res', '720p')
}

const H = { Authorization: 'Key ' + KEY, 'Content-Type': 'application/json' }
const log = (...a) => console.error('[' + path.basename(out) + ']', ...a)

;(async () => {
  const r = await fetch('https://queue.fal.run/' + model, {
    method: 'POST',
    headers: H,
    body: JSON.stringify(body),
  })
  const j = await r.json()
  if (!j.request_id) {
    log('submit failed:', JSON.stringify(j).slice(0, 500))
    process.exit(2)
  }
  log('queued', j.request_id)

  const statusUrl = j.status_url
  const t0 = Date.now()
  let payload = null
  while (Date.now() - t0 < 12 * 60 * 1000) {
    await new Promise(s => setTimeout(s, 6000))
    const sr = await fetch(statusUrl, { headers: H })
    const sj = await sr.json()
    if (sj.status === 'COMPLETED') {
      const rr = await fetch(
        sj.response_url || statusUrl.replace('/status', ''),
        { headers: H }
      )
      payload = await rr.json()
      break
    }
    if (sj.status === 'FAILED' || sj.error) {
      log('FAILED:', JSON.stringify(sj).slice(0, 600))
      process.exit(3)
    }
    log(sj.status, Math.round((Date.now() - t0) / 1000) + 's')
  }
  if (!payload) {
    log('timed out')
    process.exit(4)
  }

  const url =
    payload?.video?.url ||
    payload?.videos?.[0]?.url ||
    JSON.stringify(payload).match(/https:\/\/[^"]+\.mp4/)?.[0]
  if (!url) {
    log('no video url:', JSON.stringify(payload).slice(0, 600))
    process.exit(5)
  }

  const vr = await fetch(url)
  fs.writeFileSync(out, Buffer.from(await vr.arrayBuffer()))
  log('OK ->', out, (fs.statSync(out).size / 1e6).toFixed(1) + 'MB')
  console.log(out)
})()
