# App icon

The icon is a **derivative of Kubera's own mark**: their geometric "K", drawn as
negative space knocked out of a solid disc. Rendered in the app's off-white
`#F5F7FA` on its near-black `#0B0E1A`, with the disc contained inside the canvas
rather than bleeding past it.

## Why this, and what it costs

Kubera Mobile is an unofficial client, and an icon derived from Kubera's mark is
the fastest way to signal which service the app talks to. The maintainer chose
this deliberately, over an original mark, having been shown the tradeoff.

The tradeoff, recorded here so nobody has to rediscover it:

- **It is a derivative of a trademark the project does not own.** The README
  disclaims affiliation; an icon that borrows their mark works against that
  disclaimer.
- **App Store review is the likely friction point.** Apple's guidelines cover
  using another party's marks without permission, so a submission carrying this
  icon may be rejected. Written permission from Kubera would settle it.
- **The repository is public**, so the derivative is public too.

None of that is a reason it cannot be used on a personal build, which is what it
is used for today. It is a reason to expect a conversation before any public
distribution. If that conversation goes badly, the previous original mark
("Ascent", three ascending treads) is in this file's history at commit `b36a48a`
and can be restored without redesigning anything.

## Known weakness: small sizes

The disc sits inside the canvas with a margin, which makes the K's negative-space
gaps thin. At 40pt — the Home Screen size on a phone — the stem slice and the
wedge cuts narrow considerably and the mark reads more as a disc with cuts in it
than as a letter. Variants that let the K bleed past the canvas edge held up
better small, and were not chosen.

If it ever wants fixing without changing the design: widen the three knockout
shapes in `icon-source.svg` and re-render. Check the result at 40px, not at 1024.

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
