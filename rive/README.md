# fuime motion

Six Rive pieces for fuime, authored as text and built from the command line.
No Rive editor, no binary source: each piece is an `.rml` file you can read,
diff and review like any other source in this repo.

```bash
curl -fsSL https://releases.rive.app/cli/install.sh | sh   # once
export PATH="$HOME/.rive/bin:$PATH"

./tools/build-all.sh          # every piece -> out/
./tools/render.sh paid 200 30 190   # one piece: dir, frames, fps, poster frame
rive paid                     # live preview window, rebuilds on save
```

Look at everything at once: `python3 -m http.server 8777` here, then open
`http://127.0.0.1:8777/gallery.html`. The gallery plays the real `.riv` files
through the web runtime, so it is also the check that they load outside the CLI.

## The pieces

| Piece | What it shows | Where it earns its keep |
|---|---|---|
| `arch-draw` | The mark strokes itself on, then floods with colour from the bottom | Loader, video intro/outro, README, social |
| `flow-of-funds` | $400 crosses from the client through fuime to the venture, −$20 splitting off | The one thing fuime most has to explain |
| `paid` | Badge lands, two rings ping, "Paid." rises | In-app, the moment an invoice is paid |
| `invoice-builds` | An invoice assembling itself row by row | "An invoice with your name on it" |
| `cosign` | Two half-arches, neither standing alone, meeting once both are signed | "Three steps. One of them needs a parent" |
| `arch-pending` | A segment travelling through the arch, looping | Every pending state. 593 bytes |
| `pay-button` | **Interactive.** Hover, press, processing, paid — with a cancel if you drag off | What your buyer actually does |
| `fee-dial` | **Interactive.** Drag to set the sale; amount, fee and payout recompute live | Pricing, and the 50¢ floor made visible |

Each builds to `out/<name>.{riv,mp4,gif,png}`. The two interactive ones are
filmed by `tools/render-interactive.sh`, which drives a gesture and captures the
result, because there is no timeline to advance.

## The one thing that will catch you: unsigned scripts

**A locally built `.riv` carries unsigned Luau, and web runtimes refuse to run
it — silently.** The file loads, the view model is there, every bind resolves,
and the script never executes. Verified rather than assumed: loading
`fee-dial.riv` in a browser and reading back `fillW` gives `300` (the authored
default) where the script would have written `439`.

So:

| Piece | Behaviour lives in | Works unsigned on the web |
|---|---|---|
| `pay-button` | listeners + state machine | **yes** |
| `fee-dial` | a Luau script | **no** — needs `rive login`, then `rive fee-dial --publish` |

Nothing else in the set has a script. `fee-dial` still works fully in the CLI
preview (`rive fee-dial`) and in its exported video, because the CLI runs
unsigned scripts happily; it is only web runtimes that reject them.

This is why `pay-button` is built from listeners and view model booleans rather
than the script that would have been quicker — a checkout button that silently
does nothing on the web is worse than no button.

## Rules these follow

- **Flat colour only.** No gradients, no glow, no blur, no glass. The warm
  palette from `site/style.css` — `#1c1a15` ink, `#f9f8f7` paper, `#ebe7df`
  cream, `#c2401f` accent, used once per piece at the point that matters.
- **Gambetta for display, General Sans for everything else**, the same pairing
  the site uses. `fonts/` holds both as TTF from Fontshare.
- **No invented arithmetic.** Every figure is the worked example from
  `site/pricing.html` ($400.00 → −$20.00 → $380.00). The 5% never appears
  without the 50¢ floor, and card processing never appears as a second charge
  to the seller — Stripe bills fuime, and its cut comes out of the 5%
  (CLAUDE.md L8). If pricing changes, that page changes first and these follow.
- **`cosign`'s caption is the approved disclosure wording** from
  LEGAL_RESEARCH §7 (L5). Do not reword it here.

## The brand mark is generated, not traced

`tools/svg2rml.py` converts an SVG path into RML `PointsPath` vertices. Rive
stores cubic handles as polar (angle + distance from the vertex) where SVG
stores absolute control points, so the conversion is exact rather than an
approximation — the rendered result is pixel-identical to `site/img/favicon.svg`.

```bash
python3 tools/svg2rml.py ../site/img/favicon.svg --fit 380 380 --translate 300 300
```

`arch-draw` and `paid` carry the output inline. Regenerate rather than hand-edit
those vertex blocks. `arch-pending` and `cosign` use the arch's *silhouette*
instead: at 200px the real glyph is mud, and in `cosign` the point is the
structure, not the logo.

## Things that cost time, written down

- **`--viewport` does not scale content.** It enlarges the canvas and leaves the
  art at its authored size, anchored top-left. There is no resolution multiplier
  on the CLI — resolution lives in the artboard. `.riv` is vector, so this only
  affects the PNG/MP4/GIF exports, which render at artboard size.
- **A `ClippingShape` masks the whole shape, stroke included.** `arch-draw`
  needs two copies of the geometry because one shape cannot both trim a stroke
  and clip a fill.
- **Fonts dominate `.riv` size.** `arch-pending` (no text) is 593 bytes;
  the text pieces are ~110KB and `paid` is 235KB because it embeds two faces.
  Subsetting is the lever if that ever matters.
- **GIF is ~10× the MP4 for the same clip.** Prefer `.riv`, then `.mp4`. Reach
  for the GIF only where neither can go.
- **Listeners inside a `StateMachineLayer` build clean and never fire.** They
  belong directly on the `StateMachine`. `--verify` passes, `inspect` reports no
  problems, hit areas look right, and nothing happens. This cost the most time
  of anything here; the tell is a view model boolean that never changes under
  `--data-dump`.
- **A transition cannot be left mid-blend without `enableEarlyExit`.** A quick
  click arrives while `Rest -> Hover` is still fading, so the press lands on a
  machine that has not reached `Hover` yet and the click is simply lost. This
  looks exactly like a broken listener.
- **`exitTimeIsPercetange` is misspelled in the format.** Write the typo.
- **Committing on release means racing the gesture.** `pay-button` enters
  `Press` and commits on exit time instead, so a press cannot be outrun. Leaving
  the button during those 8 frames still cancels.
- **`--data-dump --data-dump-every=1` is the debugger.** It shows exactly which
  view model property changed on which frame, which is how the listener bug
  above was found.
- **`loopValue` defaults to `oneShot`.** A loop that is not explicitly `loop`
  plays once and holds.
- **First sibling declared draws on top** — the reverse of HTML.
- **A clean `--verify` proves names, not appearance.** Run
  `rive <dir> --verify`, then `rive inspect <dir> --summary` for wiring, then
  screenshot and actually look. All three; none is a superset of another.

## Not wired into anything yet

These are assets. Nothing on the marketing site or in the Rails app loads them.
Putting `flow-of-funds` on the homepage or `paid` in the app is a separate
change against the pages' own copy guards.
