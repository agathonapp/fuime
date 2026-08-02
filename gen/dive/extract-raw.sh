#!/bin/bash
# The chosen take -> raw/, as PNG, for track.py and composite.py.
#
# Straight off the shot mp4 and not off a master, because there is no master to
# make: the dive is one continuous 5s take, so concatenating and re-grading it
# only spends a lossy generation. The shot arrives from Kling at ~21 Mbps; the
# re-encode it used to go through was 7 Mbps at the same size and frame count,
# which is a third of the bitrate thrown away before the compositor has even
# looked at it. The plate is warped onto these pixels and the whole city is in
# shot at the head of the dive, so that loss lands exactly where the reader is
# looking.
#
#   ./extract-raw.sh shots/b1.mp4
set -euo pipefail
cd "$(dirname "$0")"
SHOT=${1:?usage: extract-raw.sh shots/<take>.mp4}

# The old frames move aside rather than getting deleted. A shorter take would
# otherwise leave the tail of the previous one behind, and composite.py globs the
# directory — it would happily composite a dive that ends in somebody else's shot.
[ -d raw ] && mv raw "raw.prev.$$"
mkdir -p raw
ffmpeg -v error -y -i "$SHOT" -vsync 0 raw/f%04d.png
echo "raw: $(ls raw | wc -l | tr -d ' ') frames from $SHOT ($(du -sh raw | cut -f1))"
ls -d raw.prev.* 2>/dev/null | sed 's/^/superseded: /'
