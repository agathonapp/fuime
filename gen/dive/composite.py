#!/usr/bin/env python3
"""Put the real fuime UI on the laptop screen, for every frame of the dive.

The generated take renders the screen as one flat cyan quad, which is the whole
reason this works: the quad is trivially keyable, so its four corners can be
tracked per frame and the app plate warped onto them. No 3D, no rotoscoping.

The plate is on the screen from the very first frame. From across a dark room
you cannot read it, and you are not meant to — what you can see is that the
screen has something on it, and that is what the reader is being asked to fly
toward. A blank rectangle asks nothing.

What changes over the shot is the bloom, not the presence. A bright LCD seen
from ten feet away in a dark room does not read as a dark navy panel; it reads
as a blown-out block of light, and here it is also the key light on the desk,
the chair and the window sill. Paste an unlifted dark UI onto it at frame one
and the room is lit by a lamp that is off. So the plate is lifted hard toward
the screen's own light at the head of the shot and the lift decays to nothing
by LIFT_END, where the screen is big enough to read, the room has left frame,
and the frame has to colour-match the DOM panel the site hands off to.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from track import track_frames

SRC = Path(sys.argv[1])  # dir of extracted frames
UI = Path(sys.argv[2])  # app plate png
OUT = Path(sys.argv[3])
OUT.mkdir(parents=True, exist_ok=True)

# Bloom lift, in normalised shot progress: how far the plate is pushed toward
# the light it replaces. fx/dive.js mirrors both numbers and this curve.
LIFT_MAX, LIFT_END = 0.55, 0.86
LIFT_RGB = (150, 214, 224)

# Above this on-screen width the plate has enough room that the keyer's half-cyan
# edge ring needs the wider dilate; below it, a 5px grow is 3% of the screen and
# paints UI onto the laptop lid.
WIDE_PX = 400


def perspective_coeffs(dst, src):
    """PIL wants the inverse map: output xy -> input xy. Solve the 8 unknowns."""
    m = []
    for (x, y), (u, v) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        m.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(m, dtype=np.float64)
    b = np.array(src, dtype=np.float64).reshape(8)
    return np.linalg.solve(a, b)


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def edge(p, q):
    return float(np.hypot(p[0] - q[0], p[1] - q[1]))


ui = Image.open(UI).convert("RGB")
_mips = {}


def plate_at(quad):
    """The plate, pre-reduced to roughly the size it is about to occupy.

    PIL's PERSPECTIVE transform point-samples. It asks the source for one pixel
    per output pixel and averages nothing in between, so a 3200px plate warped
    into a 148px screen lands on whichever glyph stroke happens to sit under
    each sample. Held still that is mush; scrubbed, it is crawling moire, and it
    is the single ugliest thing in the shot at the head of the dive where the
    reader is looking straight at that screen.

    Reducing with LANCZOS first puts the transform back near 1:1 with every
    source pixel accounted for. Held at 2x the destination so the warp still has
    detail to resample from, never upscaled past the original, and cached by
    rounded scale because the screen grows smoothly and neighbouring frames want
    the same mip.
    """
    w_px = max(edge(quad[0], quad[1]), edge(quad[3], quad[2]))
    h_px = max(edge(quad[0], quad[3]), edge(quad[1], quad[2]))
    scale = min(1.0, 2.0 * max(w_px / ui.width, h_px / ui.height))
    k = round(scale, 2)
    if k not in _mips:
        size = (max(1, round(ui.width * k)), max(1, round(ui.height * k)))
        _mips[k] = ui if k >= 1.0 else ui.resize(size, Image.LANCZOS)
    return _mips[k], w_px


# One definition of where the screen is, shared with the site: track.py writes
# the same corners out as JSON so the DOM handoff lands on the same four points
# this warp does.
frames, masks, tracks, sm, good = track_frames(SRC)
print(f"keyed {len(good)}/{len(frames)} frames (first hit: {good[0]})")

for i, f in enumerate(frames):
    base = Image.open(f).convert("RGB")
    t = i / (len(frames) - 1)
    if tracks[i] is None:
        base.save(OUT / f.name)
        continue

    dst = [tuple(p) for p in sm[i]]
    plate, w_px = plate_at(dst)
    w, h = plate.size
    coeffs = perspective_coeffs(dst, [(0, 0), (w, 0), (w, h), (0, h)])
    warped = plate.transform(base.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)

    # Screen-shaped alpha. Dilate before feathering: the key is a colour
    # distance, so the outermost ring of the screen is half cyan and half bezel
    # and falls outside the mask. Leave it and it rims the pasted UI in glowing
    # teal. Growing the mask spills a hair of UI onto the bezel instead, which
    # at this scale is invisible where the halo very much is not — but the ring
    # is a fixed couple of pixels wide however big the screen is, so the grow
    # has to shrink with it or it becomes a lit fringe around the whole lid.
    m = Image.fromarray((masks[i] * 255).astype(np.uint8))
    m = m.filter(ImageFilter.MaxFilter(5 if w_px >= WIDE_PX else 3))
    m = m.filter(ImageFilter.GaussianBlur(1.2 if w_px >= WIDE_PX else 0.6))

    lift = LIFT_MAX * (1.0 - smoothstep(t / LIFT_END))
    lit = Image.blend(warped, Image.new("RGB", base.size, LIFT_RGB), lift)
    base = Image.composite(lit, base, m)
    base.save(OUT / f.name)

print(f"wrote {len(frames)} frames -> {OUT}")
