# App icon

The app icon is an original mark called **Ascent**. It replaces the placeholder that
shipped earlier, which was Kubera's own "K" logo lifted from their web app's touch
icon — a trademark this project has no right to use. Nothing in the icon derives from
Kubera's branding.

## The mark

Three ascending treads merged into a single continuous mass, filleted at every corner,
in the app's green on the app's near-black.

- **Why a staircase.** The app's whole reason to exist is a number on the Home Screen
  that goes up. The chart is its signature, so the icon is the chart reduced to its
  bare gesture: value rising left to right. It says "net worth over time" without a
  word or a currency symbol.
- **Why one solid mass rather than separate bars.** Solid silhouettes survive
  downsampling; thin gaps do not. Separated bars were tried and the gaps closed up at
  40×40pt into a green smudge. Merging the treads and filleting the inner corners
  keeps it one confident shape at every size, and reads as drawn rather than as the
  stock `chart.bar.fill` glyph.
- **Why three treads, not four.** Four was tried first. At 40pt its 100px risers
  scale to under 4px and the steps stop reading as steps — the profile turns into a
  serrated diagonal, and the shallow bottom tread reads as a stray bar sitting beside
  the mark rather than as the first stair. Three treads at 220 wide with a uniform
  120 riser keep every step countable at 40pt, and the bottom tread becomes a solid
  260-tall plinth that anchors the form.
- **Colours.** Background is a vertical `#151B2E → #0B0E1A` gradient, matching the
  app's near-black. The mark is a diagonal `#35C773 → #5FE694` gradient running
  bottom-left to top-right, so the light follows the rise; it averages out to the
  app's `#4ADE80` gain green.
- **Composition — balance the ink, not the box.** An ascending form carries most of
  its area at the right and bottom, so centring its *bounding box* leaves the
  upper-left third empty and the icon reads as having slid down and right. The fix is
  to centre the mark's **area centroid** instead. With the box centred the centroid
  sits at `(558, 559)`; the box is therefore offset up and left until the centroid
  reaches `(523, 523)` — three quarters of the way to the canvas centre. Going the
  full distance to `(512, 512)` overshoots: the mark visibly drifts up-left and opens
  a hole at the bottom right. Final bounding box `x 147..807`, `y 226..726`, so the
  margins are deliberately uneven: left 147, right 217, top 226, bottom 298.
  Verified that no part of the mark is clipped by iOS's corner mask at any size.
- No text, no mask, no shadow, no transparency. iOS applies its own corner mask, so the
  artwork is full-bleed square and the PNG has no alpha channel (App Store validation
  rejects alpha).

## Directions that lost

All were rendered at 1024, 80, 60 and 40px, corner-masked, and compared at actual size:

| Direction | Why it lost |
| --- | --- |
| Separated ascending columns | Generic — reads as cellular signal strength. Gaps mushed shut at 40px. |
| Bold zigzag line / trending-up stroke | Generic, and the stroke thinned into a squiggle when small. |
| Area chart with a bright top edge | The dim fill went muddy and the curve's wiggle disappeared at 40px. |
| Double ascending chevron | Reads as a "scroll up" / "collapse" UI control, not a brand. |
| Full-bleed staircase splitting the canvas | Read as abstract wallpaper rather than a mark. |
| Off-white staircase with a green cap block | Two-tone split the mark into two objects; the cap looked stuck on. |
| Treads with a compounding (accelerating) rise | Thematically nice, but it starved the first tread into a sliver that vanished small. |
| Four treads | Risers under 4px at 40pt; the steps blurred into a serration and the shallow first tread read as a stray bar. |
| Fillet radius 58 | The step notches rounded away at 40px and the mark went blobby. |
| Fillet radius 36 | Crisp, but stiffer than the rest of the app's rounded geometry. 40 splits the difference. |

## Regenerating the PNG

`docs/icon-source.svg` is the source of truth. Requires `librsvg` and ImageMagick
(`brew install librsvg imagemagick`). From the repo root:

```sh
rsvg-convert -w 1024 -h 1024 docs/icon-source.svg -o /tmp/icon-rgba.png
magick /tmp/icon-rgba.png -background '#0B0E1A' -alpha remove -alpha off -strip \
  App/Assets.xcassets/AppIcon.appiconset/icon.png
```

The second step is not optional: `rsvg-convert` always writes an alpha channel, and
App Store validation rejects an icon that has one. Verify:

```sh
sips -g pixelWidth -g pixelHeight -g hasAlpha \
  App/Assets.xcassets/AppIcon.appiconset/icon.png
# pixelWidth: 1024 / pixelHeight: 1024 / hasAlpha: no
```

To check it still reads small before committing a change, render it at the real Home
Screen size and look at it magnified:

```sh
for px in 40 60; do
  magick App/Assets.xcassets/AppIcon.appiconset/icon.png -resize ${px}x${px} /tmp/icon-$px.png
  magick /tmp/icon-$px.png -filter point -resize 900% /tmp/icon-$px-zoom.png
done
```

40pt is the Home Screen size on a phone and is where any composition problem shows up
first; 60pt is where balance is easiest to judge. Judging balance is easier with iOS's
corner mask applied, since the mask is what makes uneven margins visible:

```sh
python3 - <<'EOF'
import subprocess
src = "App/Assets.xcassets/AppIcon.appiconset/icon.png"
for size in (40, 60, 80, 120, 180):
    r = round(size * 0.2237)
    open("/tmp/mask.svg", "w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}">'
        f'<rect width="{size}" height="{size}" rx="{r}" ry="{r}" fill="#fff"/></svg>')
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size),
                    "/tmp/mask.svg", "-o", "/tmp/mask.png"], check=True)
    subprocess.run(["magick", src, "-resize", f"{size}x{size}", "/tmp/mask.png",
                    "-alpha", "off", "-compose", "CopyOpacity", "-composite",
                    f"/tmp/masked-{size}.png"], check=True)
EOF
```
