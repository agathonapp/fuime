#!/usr/bin/env bash
# render-interactive.sh - film a piece that only moves when something touches it.
#
# The plain renderer advances a timeline. These two have no timeline to advance:
# pay-button sits in Rest until it is clicked, and fee-dial does nothing until it
# is dragged. Each invocation of the CLI starts the scene from zero and replays
# deterministically, so frame N is simply "do the gesture, then advance N" - and
# for the dial, "press at the x that frame N wants".
#
# usage: render-interactive.sh <click|sweep> <project-dir> <frames> [fps]
set -euo pipefail
export PATH="$HOME/.rive/bin:$PATH"

MODE="$1"; DIR="$(cd "$2" && pwd)"; NAME="$(basename "$DIR")"
FRAMES="$3"; FPS="${4:-30}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/out"; TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

read -r W H < <(rive inspect "$DIR" --json 2>/dev/null \
  | python3 -c 'import json,sys; a=json.load(sys.stdin)["artboards"][0]; print(int(a.get("width",500)), int(a.get("height",500)))')
echo "  $NAME ($MODE) - ${W}x${H}, ${FRAMES}f -> ${FPS}fps"

rive "$DIR" --once --quiet
cp "$DIR/build/$NAME.riv" "$OUT/$NAME.riv"

STEP=$(python3 -c "print(60/$FPS)")
COUNT=$(python3 -c "print(int($FRAMES/$STEP))")

cat > "$TMP/frame.sh" <<FRAME
#!/usr/bin/env bash
n="\$1"
png="$TMP/\$(printf %04d \$n).png"
if [ "$MODE" = click ]; then
    adv=\$(python3 -c "print(max(1, round(\$n * $STEP)))")
    "\$HOME/.rive/bin/rive" "$DIR" --screenshot="\$png" \\
        --pointer=click@$((W/2)),210 --advance=\$adv --quiet >/dev/null 2>&1
else
    # A there-and-back sweep across the track, eased at the turns so the ends
    # do not look like the handle slamming into a wall.
    x=\$(python3 -c "
import math
t = \$n / max($COUNT - 1, 1)
u = 0.5 - 0.5 * math.cos(2 * math.pi * t)
print(int(160 + u * 580))")
    "\$HOME/.rive/bin/rive" "$DIR" --screenshot="\$png" \\
        --pointer=down@\$x,222 --advance=45 --quiet >/dev/null 2>&1
fi
FRAME
chmod +x "$TMP/frame.sh"
seq 0 $((COUNT - 1)) | xargs -P 8 -n 1 "$TMP/frame.sh"

ls "$TMP"/*.png >/dev/null 2>&1 || { echo "  !! no frames"; exit 1; }
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/%04d.png" \
  -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 18 "$OUT/$NAME.mp4"
ffmpeg -y -loglevel error -i "$OUT/$NAME.mp4" \
  -vf "fps=$FPS,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  "$OUT/$NAME.gif"
cp "$TMP/$(printf %04d $((COUNT * 2 / 3))).png" "$OUT/$NAME.png"
printf "  -> %s.riv %s  %s.mp4 %s  %s.gif %s\n" "$NAME" "$(du -h "$OUT/$NAME.riv"|cut -f1)" \
  "$NAME" "$(du -h "$OUT/$NAME.mp4"|cut -f1)" "$NAME" "$(du -h "$OUT/$NAME.gif"|cut -f1)"
