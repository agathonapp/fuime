#!/usr/bin/env bash
# Every piece, with the frame counts and poster moments each one was authored to.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo "building the fuime rive set"
#              project          frames fps poster
./tools/render.sh arch-draw       170  30  132
./tools/render.sh arch-pending     96  30   30
./tools/render.sh flow-of-funds   330  30  250
./tools/render.sh paid            200  30  190
./tools/render.sh invoice-builds  250  30  240
./tools/render.sh cosign          320  30  310

# These two have no timeline to advance - they move only when touched.
./tools/render-interactive.sh click pay-button 290 30
./tools/render-interactive.sh sweep fee-dial   300 24

echo; echo "out/:"; ls -lh out | tail -n +2 | awk '{printf "  %-26s %s\n", $9, $5}'
