# Original-vector artwork

The mark is the first SVG path in the header wordmark on https://aside.com/.
`assets/source-path.json` stores the exact source path, its SHA-256 and viewport.
`assets/original-mark.svg` retains every original Bezier coordinate.

The icon resource was also extracted directly from the installed browser's
`IDR_MAINFRAME` group. Removing the white-shadow contribution and aligning the
official vector rendering yielded an alpha correlation of 0.999819. The residual
comes from the 256-pixel icon's rasterization; this is not a claim of byte-identical
PNG exports. The original official vector, rather than an AI reconstruction,
is the editable master.

Only internal cutout edges are inset, by 0.28 vector units (about nine pixels at
1024px). The exterior path is unchanged. The central star's original boundary
segments form a protection mask. During raster export its fully protected pixels
are copied from the original alpha channel, and alpha is clamped to never add
pixels outside the original. The current alpha area decreases by 10.856 percent;
this area measure is not a universal stroke-width percentage.

Black and white share the same alpha channel. Native ICOs use DIB/BMP frames at
16–256px. The frozen source/star fixtures make central pixel changes, accidental
growth, palette changes and lost transparency fail the asset tests.

Rebuild with `npm ci --ignore-scripts`, `python tools/build-assets.py`, and run
`python -m unittest discover -s tests -v`.
