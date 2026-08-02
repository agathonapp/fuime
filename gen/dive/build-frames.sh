#!/bin/bash
# Frame ladders for the dive scrub, straight off the composited PNGs.
#
# No interpolation and no frame padding: 121 frames is thin for a scrub, and the
# fix is in the scrubber, which cross-fades adjacent frames on fractional
# progress. That buys the smoothness an interpolated ladder would have cost 3MB
# and a pile of minterpolate artefacts on a fast dolly to get.
set -euo pipefail
cd "$(dirname "$0")"
SITE=../../site

# Desktop keeps the generated 16:9 framing — it is the shot, not a crop of it.
# Mobile takes a 3:4 window around the laptop, because a 16:9 frame cover-fitted
# to a phone throws away the desk and the city and leaves a screen floating in
# black.
extract() { # $1=crop-filter $2=width $3=quality $4=outdir
  local vf=$1 width=$2 q=$3 dir=$4
  mkdir -p "$dir"
  local i=0
  for f in comp/f*.png; do
    i=$((i + 1))
    local png="/tmp/fuime-dive-scratch.png"
    ffmpeg -v error -y -i "$f" -vf "${vf}scale=${width}:-2:flags=lanczos" "$png"
    cwebp -quiet -q "$q" -m 5 -sharp_yuv "$png" -o "$(printf '%s/f_%04d.webp' "$dir" "$i")"
  done
  echo "$dir: $i frames, $(du -sh "$dir" | cut -f1)"
}

extract "" 1600 70 "$SITE/dive"
extract "crop=810:1080:(iw-810)/2:0," 760 70 "$SITE/dive-m"

# Reduced-motion and no-JS still: the last frame, where the app is legible.
cwebp -quiet -q 88 -m 5 -sharp_yuv comp/f0121.png -o "$SITE/img/dive-end.webp"
echo "poster: $(du -h "$SITE/img/dive-end.webp" | cut -f1)"
