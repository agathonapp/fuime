#!/usr/bin/env bash
# render.sh - build one Rive project and export what the rest of the world needs:
# a .riv for runtimes, a poster PNG, and an MP4/GIF for anywhere that cannot run one.
#
# The CLI renders a single frame per invocation, so a clip is N invocations.
# They are independent, so they go through xargs -P; on this machine that is the
# difference between a minute per piece and ten seconds.
#
# Sizing: everything renders at the artboard's own size. --viewport does NOT
# scale content - it enlarges the canvas and leaves the art at its authored size,
# anchored top left, so asking for 2x gets you the same drawing on a bigger sheet.
# Resolution therefore lives in the artboard, and the .riv is vector regardless.
#
# usage: render.sh <project-dir> <frames> [fps] [poster-frame]
set -euo pipefail
export PATH="$HOME/.rive/bin:$PATH"

DIR="$(cd "$1" && pwd)"; NAME="$(basename "$DIR")"
FRAMES="$2"; FPS="${3:-30}"; POSTER="${4:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/out"; TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

# Artboard size, so the capture is not silently letterboxed to some default.
read -r W H < <(rive inspect "$DIR" --json 2>/dev/null \
  | python3 -c 'import json,sys; a=json.load(sys.stdin)["artboards"][0]; print(int(a.get("width",500)), int(a.get("height",500)))')
VW=$W; VH=$H

echo "  $NAME - ${W}x${H}, ${FRAMES}f -> ${FPS}fps"

rive "$DIR" --once --quiet
cp "$DIR/build/$NAME.riv" "$OUT/$NAME.riv"

# 60fps source sampled down to FPS, so frame n of the clip is advance n*60/FPS.
STEP=$(python3 -c "print(60/$FPS)")
COUNT=$(python3 -c "print(int($FRAMES/$STEP))")

# One frame, as its own script: nesting this in an xargs -I{} command line ran
# past the argument limit once the paths got long.
cat > "$TMP/frame.sh" <<FRAME
#!/usr/bin/env bash
n="\$1"
adv=\$(python3 -c "print(max(1, round(\$n * $STEP)))")
"$HOME/.rive/bin/rive" "$DIR" --screenshot="$TMP/\$(printf %04d \$n).png" \\
    --advance=\$adv --viewport=${VW}x${VH} --quiet >/dev/null 2>&1
FRAME
chmod +x "$TMP/frame.sh"
seq 0 $((COUNT - 1)) | xargs -P 8 -n 1 "$TMP/frame.sh"

ls "$TMP"/*.png >/dev/null 2>&1 || { echo "  !! no frames rendered"; exit 1; }

# yuv420p and the even-dimension pad: without them the mp4 will not play in Safari.
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/%04d.png" \
  -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 18 \
  "$OUT/$NAME.mp4"

ffmpeg -y -loglevel error -i "$OUT/$NAME.mp4" \
  -vf "fps=$FPS,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  "$OUT/$NAME.gif"

POSTER_ADV="${POSTER:-$FRAMES}"
rive "$DIR" --screenshot="$OUT/$NAME.png" --advance="$POSTER_ADV" \
     --viewport="${VW}x${VH}" --quiet >/dev/null

printf "  -> %s.riv %s  %s.mp4 %s  %s.gif %s  %s.png %s\n" \
  "$NAME" "$(du -h "$OUT/$NAME.riv" | cut -f1)" \
  "$NAME" "$(du -h "$OUT/$NAME.mp4" | cut -f1)" \
  "$NAME" "$(du -h "$OUT/$NAME.gif" | cut -f1)" \
  "$NAME" "$(du -h "$OUT/$NAME.png" | cut -f1)"
