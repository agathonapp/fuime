#!/usr/bin/env python3
"""Swap the screen plate on the SHIPPED dive frames, without the raw take.

composite.py builds frames from raw/, which is gitignored and was gone by
2026-09-25, when the dive came back with a new sign-up panel. The frames in
site/dive/ still had the old one baked in ("Early access", an email field), and
it ghosted under the new DOM panel through the whole cross-fade.

Every shipped frame already has a plate warped onto the screen, and
site/dive/track.json holds the four corners that warp used. So the new plate
goes on the same corners, a few pixels wider to cover the old one's spill onto
the bezel, with composite.py's bloom curve. One extra lossy generation on the
desktop ladder; the mobile ladder and the poster are cut from the same pass.

    python3 replate.py keys/screen-signup.png

Writes site/dive/, site/dive-m/ and site/img/dive-end.webp in place.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# Mirrored from composite.py, which runs its whole pipeline on import and so
# cannot be imported. Change one, change both.
LIFT_MAX, LIFT_END = 0.55, 0.86
LIFT_RGB = (150, 214, 224)
WIDE_PX = 400


def perspective_coeffs(dst, src):
    m = []
    for (x, y), (u, v) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        m.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    return np.linalg.solve(np.array(m, dtype=np.float64), np.array(src, dtype=np.float64).reshape(8))


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def edge(p, q):
    return float(np.hypot(p[0] - q[0], p[1] - q[1]))

SITE = Path(__file__).resolve().parent / "../../site"
UI = Image.open(sys.argv[1]).convert("RGB")
track = json.loads((SITE / "dive/track.json").read_text())
quads = track["quads"]
n = track["frames"]


def plate_for(quad):
    # Same reasoning as composite.plate_at: PERSPECTIVE point-samples, so reduce
    # to ~2x the destination first or the text crawls when scrubbed.
    w_px = max(edge(quad[0], quad[1]), edge(quad[3], quad[2]))
    h_px = max(edge(quad[0], quad[3]), edge(quad[1], quad[2]))
    k = min(1.0, 2.0 * max(w_px / UI.width, h_px / UI.height))
    size = (max(1, round(UI.width * k)), max(1, round(UI.height * k)))
    return (UI if k >= 1.0 else UI.resize(size, Image.LANCZOS)), w_px


def replate(base, i):
    W, H = base.size
    q = quads[i]
    if q is None:
        return base
    dst = [(x * W, y * H) for x, y in q]
    plate, w_px = plate_for(dst)
    pw, ph = plate.size
    coeffs = perspective_coeffs(dst, [(0, 0), (pw, 0), (pw, ph), (0, ph)])
    warped = plate.transform(base.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)

    # The old plate was laid through a keyed mask grown by 5px (3 when small).
    # Grow two more than that so none of it survives at the rim.
    m = Image.new("L", base.size, 0)
    ImageDraw.Draw(m).polygon(dst, fill=255)
    m = m.filter(ImageFilter.MaxFilter(7 if w_px >= WIDE_PX else 5))
    m = m.filter(ImageFilter.GaussianBlur(1.2 if w_px >= WIDE_PX else 0.6))

    t = i / (n - 1)
    lift = LIFT_MAX * (1.0 - smoothstep(t / LIFT_END))
    lit = Image.blend(warped, Image.new("RGB", base.size, LIFT_RGB), lift)
    return Image.composite(lit, base, m)


def webp(img, out, q):
    with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
        img.save(tmp.name)
        subprocess.run(
            ["cwebp", "-quiet", "-q", str(q), "-m", "5", "-sharp_yuv", tmp.name, "-o", str(out)],
            check=True,
        )


for i in range(n):
    name = f"f_{i + 1:04d}.webp"
    frame = replate(Image.open(SITE / "dive" / name).convert("RGB"), i)
    webp(frame, SITE / "dive" / name, 78)
    # build-frames.sh: crop=810:1080:(iw-810)/2:0, native width, q76.
    x = (frame.width - 810) // 2
    webp(frame.crop((x, 0, x + 810, 1080)), SITE / "dive-m" / name, 76)

# The poster is the last frame at q90, and it has its own copy to start from.
poster = SITE / "img/dive-end.webp"
webp(replate(Image.open(poster).convert("RGB"), n - 1), poster, 90)
print(f"replated {n} frames + poster")
