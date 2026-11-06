# og-film

Renders `vid/fuime-coins.mp4` (fuime.com's og:video) and its poster
`img/v2/og-coins.jpg`.

`film.html` draws any frame as a pure function of time on a 1200x630 canvas;
`capture.mjs` steps through it at 30 fps with Playwright and writes PNGs.

    cp ../../img/v2/logo.svg . && mkdir -p frames
    node capture.mjs "$PWD"
    ffmpeg -framerate 30 -i frames/f_%04d.png -c:v libx264 -profile:v high \
      -pix_fmt yuv420p -crf 18 -preset slow -tune animation -movflags +faststart \
      -an fuime-coins.mp4

`/vid` and `/img` are served immutable for a year, so a changed film needs a
new filename, not an overwrite.
