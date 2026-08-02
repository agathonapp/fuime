#!/usr/bin/env python3
"""Where the laptop screen is, in every frame of the dive.

The generated take renders the screen as one flat cyan quad, which is the whole
reason this pipeline works: the quad is trivially keyable, so its four corners
can be tracked per frame. composite.py uses that to warp the app plate onto the
screen; the site uses it to land a real DOM panel on exactly the same four
corners when the scrub hands over.

Run standalone to write the track the site reads:

    python3 track.py raw ../../site/dive/track.json

Corners come out normalised to frame size, so a ladder can be rebuilt at any
width — or cropped, as the mobile one is — without invalidating the file.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# The cyan plate, sampled off the source render rather than guessed.
KEY_RGB = np.array([98, 233, 243], dtype=np.float32)
TOL = 78.0

# Corner jitter from the keyer is a pixel or two per frame. Unsmoothed it makes
# the pasted UI shimmer against a screen that is visibly rock steady.
SMOOTH = 2  # frames either side


def quad_from_mask(mask):
    """Four corners of the screen, as extremes of the keyed region.

    Valid because the screen is convex and axis-ish: TL minimises x+y, BR
    maximises it, TR maximises x-y, BL minimises it.
    """
    ys, xs = np.nonzero(mask)
    if len(xs) < 400:  # too small to be worth warping into
        return None
    s, d = xs + ys, xs - ys
    return [
        (float(xs[np.argmin(s)]), float(ys[np.argmin(s)])),  # TL
        (float(xs[np.argmax(d)]), float(ys[np.argmax(d)])),  # TR
        (float(xs[np.argmax(s)]), float(ys[np.argmax(s)])),  # BR
        (float(xs[np.argmin(d)]), float(ys[np.argmin(d)])),  # BL
    ]


def track_frames(src):
    """(frames, masks, raw quads, smoothed quads) for a directory of PNGs."""
    frames = sorted(Path(src).glob("*.png"))
    if not frames:
        sys.exit(f"no frames in {src}")

    tracks, masks = [], []
    for f in frames:
        arr = np.asarray(Image.open(f).convert("RGB"), dtype=np.float32)
        mask = np.linalg.norm(arr - KEY_RGB, axis=2) < TOL
        masks.append(mask)
        tracks.append(quad_from_mask(mask))

    good = [i for i, q in enumerate(tracks) if q is not None]
    if not good:
        sys.exit("screen never keyed — check KEY_RGB/TOL")

    arr_t = np.full((len(frames), 4, 2), np.nan)
    for i, q in enumerate(tracks):
        if q is not None:
            arr_t[i] = q
    # Box smoothing over the tracked span only, so the untracked head of the
    # shot cannot drag the first real corner toward nothing.
    sm = arr_t.copy()
    for i in good:
        lo, hi = max(good[0], i - SMOOTH), min(good[-1], i + SMOOTH)
        win = arr_t[lo : hi + 1]
        win = win[~np.isnan(win[:, 0, 0])]
        sm[i] = win.mean(axis=0)

    return frames, masks, tracks, sm, good


if __name__ == "__main__":
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    frames, _masks, tracks, sm, good = track_frames(src)
    w, h = Image.open(frames[0]).size
    print(f"keyed {len(good)}/{len(frames)} frames (first hit: {good[0]})")

    # An untracked frame gets a null rather than a guess. The site holds the
    # last real quad through those, which is correct: they are the head of the
    # shot, where the screen is a handful of pixels and nothing is landing on
    # it anyway.
    quads = []
    for i in range(len(frames)):
        if tracks[i] is None:
            quads.append(None)
            continue
        quads.append(
            [[round(float(x) / w, 5), round(float(y) / h, 5)] for x, y in sm[i]]
        )

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(
            {
                "frames": len(frames),
                "frameW": w,
                "frameH": h,
                "firstTracked": good[0],
                "quads": quads,
            },
            separators=(",", ":"),
        )
        + "\n"
    )
    print(f"wrote {out} ({out.stat().st_size // 1024}K)")
