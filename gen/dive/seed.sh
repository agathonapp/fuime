#!/bin/bash
# k0.png -> k1.png: the edit that made the live seed, plus the resize after it.
#
# The resize is the point of this script. nano-banana/edit returns 1344x768 no
# matter what you feed it, so the edited frame comes back a different shape from
# the 1920x1080 it went in as. Kling is then seeded with that frame and every
# pixel of the dive inherits its resolution. The normalised bbox of the keyed
# screen is identical to four decimal places before and after the edit, which
# says the model resampled the whole frame and cropped nothing, so scaling it
# straight back up is exact rather than a guess about what was lost.
#
# It used to be a line of PIL typed into a shell and thrown away, which meant the
# repo held keys/k1.png with no record of where it came from. Anyone rerunning
# jobs-seed.json would get e2a.png at the wrong size and no way to know it.
#
#   ./seed.sh            # edit + resize
#   ./seed.sh --resize   # skip the $0.24 of fal, just redo the resize
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" != "--resize" ]; then
  # Three variants of one prompt, not two chained edits. The person and the city
  # are separate asks but each pass through the model costs another resample, and
  # the brief was to make the frame better, so they go in together and the roll
  # picks the winner.
  node gen-fal.mjs jobs-seed.json
fi

# e2a is the take that won: SF unmistakable through the glass, screen still 1.8x
# brighter than the brightest city pixel, room luminance unmoved from k0.
python3 - <<'PY'
from PIL import Image
src = Image.open("keys/e2a.png")
out = src.resize((1920, 1080), Image.LANCZOS)
out.save("keys/k1.png")
print(f"keys/k1.png  {src.size} -> {out.size}")
PY
