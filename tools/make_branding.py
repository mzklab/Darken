# -*- coding: utf-8 -*-
"""
The generator of Darken's branding.

Run from the addon's root:  python tools/make_branding.py
The result is gathered into Media/branding/.

The mark's shape: a shadow overlaps a light disc, leaving a crescent. That is
the very thing the addon does, and a metaphor for its main control — the
passage from a half-shadow into the full shadow.

The palette is taken from the addon's own textures: the white and the final
colour of mzk.tga. Change LIGHT/PASTE below and the whole set is regenerated.
"""

from PIL import Image, ImageDraw, ImageFont
import os

SS = 4          # supersampling for the anti-aliasing
S  = 512        # the mark's final size

LIGHT = (255, 255, 255)     # the light end of mzk.tga's gradient
PASTE = (182, 130, 188)     # the pastel end of mzk.tga
DEEP  = (86, 54, 94)        # the darkened variant for a light background
INK   = (13, 13, 17)        # "the full shadow" - the dark version's background
PAPER = (246, 245, 248)     # the light version's background

OUT = os.path.join('Media', 'branding')
FONT = 'C:/Windows/Fonts/bahnschrift.ttf'


def _disc(size, cx, cy, r):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    return m


def _diag_gradient(size, c_hi, c_lo):
    """A diagonal gradient: bright at the top right into pastel at the bottom
    left."""
    g = Image.new('RGB', (size, size))
    px = g.load()
    for y in range(size):
        ty = 1 - y / size
        for x in range(size):
            t = ((x / size) + ty) / 2
            t **= 0.85
            px[x, y] = tuple(int(c_lo[i] + (c_hi[i] - c_lo[i]) * t) for i in range(3))
    return g


def make_icon(c_hi, c_lo, ring):
    """The crescent: a light disc minus an offset disc of shadow."""
    C = S * SS
    r = int(C * 0.43)
    cx = cy = C // 2

    light = _disc(C, cx, cy, r)
    shade = _disc(C, cx - int(r * 0.42), cy - int(r * 0.20), int(r * 0.985))
    crescent = Image.composite(Image.new('L', (C, C), 0), light, shade)

    icon = Image.new('RGBA', (C, C), (0, 0, 0, 0))
    icon.paste(_diag_gradient(C, c_hi, c_lo), (0, 0), crescent)

    # a thin ring closes the shape and holds the silhouette at small sizes
    ring_img = Image.new('RGBA', (C, C), (0, 0, 0, 0))
    rr = int(r * 1.16)
    ImageDraw.Draw(ring_img).ellipse(
        [cx - rr, cy - rr, cx + rr, cy + rr],
        outline=ring + (105,), width=max(2, int(C * 0.006)))

    return Image.alpha_composite(icon, ring_img).resize((S, S), Image.LANCZOS)


def _track(draw, xy, text, font, spacing, fill):
    """Text with letter spacing — Bahnschrift looks cramped without it."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + spacing


def make_lockup(icon, bg, fg, sub, path, w=1400, h=460):
    im = Image.new('RGBA', (w, h), bg + (255,))
    d = ImageDraw.Draw(im)
    size = 300
    im.alpha_composite(icon.resize((size, size), Image.LANCZOS), (110, (h - size) // 2))
    _track(d, (470, 150), 'DARKEN', ImageFont.truetype(FONT, 132), 16, fg)
    _track(d, (476, 300), 'makes the whole interface dark',
           ImageFont.truetype(FONT, 40), 5, sub)
    im.convert('RGB').save(path)


def make_legibility(icon_dark, icon_light, path):
    sizes = [256, 128, 64, 32, 16]
    pad = 40
    w = pad + sum(s + pad for s in sizes)
    band_h = 256 + pad
    sheet = Image.new('RGBA', (w, 2 * band_h + pad), (0, 0, 0, 0))
    for row, (bg, ico) in enumerate([(INK, icon_dark), (PAPER, icon_light)]):
        band = Image.new('RGBA', (w, band_h), bg + (255,))
        x = pad
        for s in sizes:
            band.alpha_composite(ico.resize((s, s), Image.LANCZOS),
                                 (x, band_h // 2 - s // 2))
            x += s + pad
        sheet.alpha_composite(band, (0, pad // 2 + row * band_h))
    sheet.convert('RGB').save(path)


def make_ingame_title(icon, path, w=256, h=64):
    """The mark and the word for the settings window.

    The sides are powers of two: the game's engine reads a texture whole and
    will stretch it to the size given, while a wrong side turns into blur or
    fails to be read at all.

    The background is transparent: the settings window is dark but somebody
    else's — a backing of our own under the label would look like a patch.
    """
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    size = h - 8
    im.alpha_composite(icon.resize((size, size), Image.LANCZOS), (2, 4))
    _track(d, (size + 14, 12), 'DARKEN',
           ImageFont.truetype(FONT, 34), 4, (240, 238, 245))
    im.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)

    on_dark = make_icon(LIGHT, PASTE, PASTE)
    on_light = make_icon(PASTE, DEEP, DEEP)

    on_dark.save(f'{OUT}/darken-icon-512.png')
    on_dark.resize((64, 64), Image.LANCZOS).save(f'{OUT}/darken-icon-64.png')
    # The icon for the addon list. As a file of its own and a size of its own:
    # the game reads it as an ordinary texture, and a texture is obliged to be
    # an uncompressed TGA with a side that is a power of two.
    on_dark.resize((64, 64), Image.LANCZOS).save(f'{OUT}/darken-icon-64.tga')
    on_light.save(f'{OUT}/darken-icon-512-onlight.png')

    make_lockup(on_dark, INK, (240, 238, 245), PASTE, f'{OUT}/darken-lockup-dark.png')
    make_lockup(on_light, PAPER, (28, 26, 34), DEEP, f'{OUT}/darken-lockup-light.png')
    make_legibility(on_dark, on_light, f'{OUT}/darken-legibility.png')

    # What is visible in the game itself: the icon in the addon list and the
    # mark with the word in the settings window's header.
    make_ingame_title(on_dark, f'{OUT}/darken-title-256.tga')

    print('branding written to', OUT)


if __name__ == '__main__':
    main()
