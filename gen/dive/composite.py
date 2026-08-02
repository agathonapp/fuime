#!/usr/bin/env python3
"""Put the real fuime UI on the laptop screen, for every frame of the dive.

The generated take renders the screen as one flat cyan quad, which is the whole
reason this works: the quad is trivially keyable, so its four corners can be
tracked per frame and the app plate warped onto them. No 3D, no rotoscoping.

The UI is not pasted at full strength the whole way. From across a dark room a
laptop reads as one block of light, not as legible text, and the screen is also
the key light on the hoodie and the desk — swapping it for a dark UI early would
wreck the lighting the model rendered. So the plate ramps in only over the last
stretch, where the screen is big enough to read and the room has left frame.
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

# Plate opacity ramp, in normalised shot progress. Before FADE_IN the screen is
# untouched light; by FADE_FULL the UI is fully resolved.
FADE_IN, FADE_FULL = 0.55, 0.86


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


ui = Image.open(UI).convert("RGB")

# One definition of where the screen is, shared with the site: track.py writes
# the same corners out as JSON so the DOM handoff lands on the same four points
# this warp does.
frames, masks, tracks, sm, good = track_frames(SRC)
print(f"keyed {len(good)}/{len(frames)} frames (first hit: {good[0]})")

w, h = ui.size
for i, f in enumerate(frames):
    base = Image.open(f).convert("RGB")
    t = i / (len(frames) - 1)
    alpha = smoothstep((t - FADE_IN) / (FADE_FULL - FADE_IN))
    if tracks[i] is None or alpha <= 0.001:
        base.save(OUT / f.name)
        continue

    dst = [tuple(p) for p in sm[i]]
    coeffs = perspective_coeffs(dst, [(0, 0), (w, 0), (w, h), (0, h)])
    warped = ui.transform(base.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)

    # Screen-shaped alpha. Dilate before feathering: the key is a colour
    # distance, so the outermost ring of the screen is half cyan and half bezel
    # and falls outside the mask. Leave it and it rims the pasted UI in glowing
    # teal. Growing the mask spills a hair of UI onto the bezel instead, which
    # at this scale is invisible where the halo very much is not.
    m = Image.fromarray((masks[i] * 255).astype(np.uint8), "L")
    m = m.filter(ImageFilter.MaxFilter(5))
    m = m.filter(ImageFilter.GaussianBlur(1.2))
    m = m.point(lambda v, a=alpha: int(v * a))

    # An LCD at this exposure blooms, so the plate gets lifted toward the light
    # it replaces — but the lift decays to nothing by the last frame, because
    # that frame has to colour-match the DOM panel the site hands off to.
    lift = 0.22 * (1.0 - smoothstep((t - FADE_FULL) / (1.0 - FADE_FULL)))
    lit = Image.blend(warped, Image.new("RGB", base.size, (150, 214, 224)), lift)
    base = Image.composite(lit, base, m)
    base.save(OUT / f.name)

print(f"wrote {len(frames)} frames -> {OUT}")
