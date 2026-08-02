#!/bin/bash
# Frame ladders for the dive scrub, straight off the composited PNGs.
#
# No interpolation and no frame padding: 122 frames is thin for a scrub, and the
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

# Measured on a 13-frame sample across the shot rather than guessed, because the
# payload is dominated by the head of the dive, where the whole city is in shot and
# every lit window is a hard edge. 1920 q78 lands 8.0MB against 1600 q70's 3.3MB,
# and it buys a legible sign-up on the screen instead of a suggestion of one. Half
# that jump is the quality bump and half is the San Francisco skyline, which has
# far more high-frequency detail than the suburban sprawl it replaced and which
# WebP charges for. 810 is the native crop width, so the mobile ladder is 1:1 —
# anything wider upscales the crop and pays for it twice.
extract "" 1920 78 "$SITE/dive"
extract "crop=810:1080:(iw-810)/2:0," 810 76 "$SITE/dive-m"

# Reduced-motion and no-JS still: the last frame, where the app is legible. It is
# the only frame some readers ever see, so it gets the quality the ladder cannot.
# Picked by listing rather than named, because the take decides the count — a
# tail_image_url shot lands one frame longer than a free one.
LAST=$(ls comp/f*.png | tail -1)
cwebp -quiet -q 90 -m 5 -sharp_yuv "$LAST" -o "$SITE/img/dive-end.webp"
echo "poster: $(du -h "$SITE/img/dive-end.webp" | cut -f1)"
