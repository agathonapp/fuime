#!/usr/bin/env node
// fal.ai gen helper — queue API w/ polling (pattern: ai-vfx-reel/scripts/reelgen.cjs).
// Usage: node gen-fal.mjs <jobs.json>   jobs: [{engine, prompt, out, image?, duration?}]
// Engines: still 'nano-banana'|'flux-pro'|'imagen4' · i2v 'veo3-fast-i2v'|'kling25-pro-i2v'|'wan-i2v'
import fs from 'node:fs';
import path from 'node:path';

const ENV = fs.readFileSync(`${process.env.HOME}/.ai.env`, 'utf8');
const KEY = (ENV.match(/^FAL_KEY=([^\s#]+)/m) || [])[1];
if (!KEY) { console.error('no FAL_KEY'); process.exit(1); }

const ENGINES = {
  'nano-banana':     { id: 'fal-ai/nano-banana', video: false, build: (j) => ({ prompt: j.prompt, num_images: 1, output_format: 'png' }) },
  'flux-pro':        { id: 'fal-ai/flux-pro/v1.1-ultra', video: false, build: (j) => ({ prompt: j.prompt, aspect_ratio: '16:9', num_images: 1 }) },
  'imagen4':         { id: 'fal-ai/imagen4/preview', video: false, build: (j) => ({ prompt: j.prompt, aspect_ratio: '16:9', num_images: 1 }) },
  'nano-banana-edit':{ id: 'fal-ai/nano-banana/edit', video: false, build: (j) => ({ prompt: j.prompt, image_urls: [j.image], num_images: 1, output_format: 'png' }) },
  'veo3-fast-i2v':   { id: 'fal-ai/veo3/fast/image-to-video', video: true, build: (j) => ({ prompt: j.prompt, image_url: j.image, aspect_ratio: '16:9', duration: j.duration || '8s', generate_audio: false, resolution: j.resolution || '720p' }) },
  // tail_image_url turns this into a true A→B morph: the shot is forced to land on the
  // end frame, so chained transformations stop drifting.
  'kling25-pro-i2v': { id: 'fal-ai/kling-video/v2.5-turbo/pro/image-to-video', video: true, build: (j) => ({ prompt: j.prompt, image_url: j.image, ...(j.tail ? { tail_image_url: j.tail } : {}), duration: j.duration || '5', negative_prompt: j.negative || 'blur, distort, low quality, text, captions, morphing background, explosion, debris flying at camera', cfg_scale: j.cfg ?? 0.5 }) },
  'kling21-pro-i2v':  { id: 'fal-ai/kling-video/v2.1/pro/image-to-video', video: true, build: (j) => ({ prompt: j.prompt, image_url: j.image, ...(j.tail ? { tail_image_url: j.tail } : {}), duration: j.duration || '5', negative_prompt: j.negative || 'blur, distort, low quality, text, explosion, debris flying at camera', cfg_scale: j.cfg ?? 0.5 }) },
  'wan-i2v':         { id: 'fal-ai/wan-i2v', video: true, build: (j) => ({ prompt: j.prompt, image_url: j.image, resolution: '720p' }) },
};

async function req(method, url, body) {
  const r = await fetch(url, {
    method,
    headers: { Authorization: `Key ${KEY}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`fal ${r.status}: ${text.slice(0, 400)}`);
  try { return JSON.parse(text); } catch { return text; }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function balance() { return req('GET', 'https://rest.alpha.fal.ai/billing/user_balance'); }

async function falRun(engine, job, label) {
  const e = ENGINES[engine];
  if (!e) throw new Error(`unknown engine ${engine}`);
  const submit = await req('POST', `https://queue.fal.run/${e.id}`, e.build(job));
  const started = Date.now();
  for (;;) {
    await sleep(3000);
    const st = await req('GET', submit.status_url);
    if (st.status === 'COMPLETED') break;
    if (st.status === 'FAILED' || st.error) throw new Error(`[${label}] failed: ${JSON.stringify(st).slice(0, 300)}`);
    if (Date.now() - started > 12 * 60 * 1000) throw new Error(`[${label}] timeout 12m`);
  }
  const out = await req('GET', submit.response_url);
  const url = e.video
    ? (out.video && out.video.url) || (out.videos && out.videos[0].url)
    : out.images && out.images[0].url;
  if (!url) throw new Error(`[${label}] no media url: ${JSON.stringify(out).slice(0, 300)}`);
  return { url, secs: Math.round((Date.now() - started) / 1000) };
}

function toDataUri(file) {
  const ext = path.extname(file).slice(1).replace('jpg', 'jpeg');
  return `data:image/${ext};base64,${fs.readFileSync(file).toString('base64')}`;
}

// Inline data URIs blow up the request body once a job carries both image_url and
// tail_image_url (~3MB of base64), which intermittently kills the fetch. Upload to fal
// storage and pass URLs instead.
const uploadCache = new Map();
async function falUpload(file) {
  if (uploadCache.has(file)) return uploadCache.get(file);
  const init = await req('POST', 'https://rest.alpha.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3', {
    content_type: 'image/png', file_name: path.basename(file),
  });
  const put = await fetch(init.upload_url, {
    method: 'PUT', headers: { 'Content-Type': 'image/png' }, body: fs.readFileSync(file),
  });
  if (!put.ok) throw new Error(`upload ${put.status} for ${path.basename(file)}`);
  uploadCache.set(file, init.file_url);
  return init.file_url;
}

const jobs = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const startBal = await balance();
if (typeof startBal === 'number' && startBal <= 0) { console.error(`fal balance $${startBal} — locked`); process.exit(1); }
console.log(`fal balance: $${startBal}`);

const CONC = Number(process.env.CONC || 3);
let idx = 0, fails = 0;
await Promise.all(Array.from({ length: Math.min(CONC, jobs.length) }, async () => {
  while (idx < jobs.length) {
    const job = jobs[idx++];
    const name = path.basename(job.out);
    if (fs.existsSync(job.out) && fs.statSync(job.out).size > 10_000 && process.env.FORCE !== '1') {
      console.log(`skip (exists): ${name}`); continue;
    }
    try {
      const isLocal = (p) => p && !p.startsWith('data:') && !p.startsWith('http');
      // video jobs upload (bigger payloads, often two images); edits keep the inline path
      if (isLocal(job.image)) job.image = job.tail ? await falUpload(job.image) : toDataUri(job.image);
      if (isLocal(job.tail)) job.tail = await falUpload(job.tail);
      const { url, secs } = await falRun(job.engine, job, name);
      const dl = await fetch(url);
      if (!dl.ok) throw new Error(`download ${dl.status}`);
      fs.writeFileSync(job.out, Buffer.from(await dl.arrayBuffer()));
      console.log(`✓ ${name}  ${Math.round(fs.statSync(job.out).size / 1024)}KB  ${secs}s  [${job.engine}]`);
    } catch (e) { fails++; console.error(`✗ ${name}: ${e.message.slice(0, 250)}`); }
  }
}));
const endBal = await balance();
console.log(`fal balance after: $${endBal} (spent ~$${(startBal - endBal).toFixed(2)})`);
console.log(fails ? `DONE with ${fails} failure(s)` : 'DONE clean');
process.exit(fails ? 1 : 0);
