# -*- coding: utf-8 -*-
"""CurseForge screenshots: raw captures in, store-ready images out.

Run from the addon root:  python tools/shots.py

Reads  Media/shots/raw/*.png|jpg  (sorted by name)
Writes Media/shots/*.png          (1280x720, same base name)

=== Why a tool and not hand work ===

A store page wants every shot the same size, on the same ground, with the same
caption in the same place. Doing that by hand means one shot drifts from the
next, and the drift is what a visitor notices before the content.

=== Naming raw files ===

The caption is taken from the file name: "1 - The spellbook.png" becomes the
caption "The spellbook" and sorts first. A name with no " - " gets no caption,
which is right for a shot that speaks for itself.

=== Why this ground, for this addon ===

The palette is the addon's own, read off Core/Skin.lua: the ink of the
settings window, its hairline, its lilac accent and its almost-white text.
That matters more here than it would elsewhere. Every capture Darken has to
show is a dark window, and on a light or neutral ground a dark window looks
like a hole. On the addon's own ink it looks like the same piece of work,
and the hairline around each shot is what keeps its edges from dissolving
into that ink.

=== Why 1280x720 ===

CurseForge shows the gallery at 16:9 and crops anything else. A capture of a
settings window is taller than 16:9, so it is never stretched to fill - it is
fitted at full height and the caption takes the room left beside it. A capture
that is wide already (a full-screen window, the map) gets the caption
underneath instead.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

# Core/Skin.lua, the HEX table: ink, line, lilac, text. The gallery and the
# window in the gallery have to read as one thing.
INK = (13, 13, 17)
LINE = (46, 46, 57)
ACCENT = (182, 130, 188)
TEXT = (242, 239, 246)

CANVAS = (1280, 720)
MARGIN = 48          # ground left around the shot
CAPTION = 84         # height of the caption strip at the bottom

RAW = os.path.join("Media", "shots", "raw")
OUT = os.path.join("Media", "shots")
LOGO = os.path.join("Media", "branding", "darken-icon-512.png")

# A face that exists on every Windows install. The game's own fonts live
# inside the client's archives and cannot be opened from here. Bahnschrift
# first: tools/make_branding.py letters the logo with it, so the caption and
# the mark beside it are the same hand.
FACES = (
    r"C:\Windows\Fonts\bahnschrift.ttf",
    r"C:\Windows\Fonts\segoeuisb.ttf",
    r"C:\Windows\Fonts\segoeui.ttf",
    r"C:\Windows\Fonts\arial.ttf",
)


def face(size):
    """The first installed face, or PIL's built-in if none of them is there."""
    for path in FACES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def ground():
    """The backdrop: flat ink with a slow vertical lift.

    Flat ink alone makes the shot's own dark edge invisible against it, and a
    strong gradient competes with the screenshot. The lift is eight levels
    over the whole height - enough to separate, too little to notice.
    """
    plate = Image.new("RGB", CANVAS, INK)
    brush = ImageDraw.Draw(plate)
    for y in range(CANVAS[1]):
        lift = int(8 * y / CANVAS[1])
        brush.line([(0, y), (CANVAS[0], y)],
                   fill=(INK[0] + lift, INK[1] + lift, INK[2] + lift))
    return plate


def fitted(shot, box):
    """The shot scaled to sit inside box, never enlarged.

    Enlarging a capture past its own pixels is the one thing that makes a
    gallery look amateur, so a small capture keeps its size and gets more
    ground around it instead.
    """
    wide, tall = shot.size
    room_w, room_h = box
    scale = min(room_w / wide, room_h / tall, 1.0)
    return shot.resize((max(1, int(wide * scale)), max(1, int(tall * scale))),
                       Image.LANCZOS)


def framed(plate, shot, at):
    """Paste the shot and draw a hairline around it.

    The line is the border colour of the addon's own window: without it a dark
    capture bleeds into the dark ground and loses its edges. For this addon
    that is not a nicety - every capture it has is a dark window.
    """
    plate.paste(shot, at)
    brush = ImageDraw.Draw(plate)
    brush.rectangle([at[0] - 1, at[1] - 1,
                     at[0] + shot.size[0], at[1] + shot.size[1]],
                    outline=LINE, width=1)


def wrapped(brush, text, font, room):
    """The caption broken into lines that fit room pixels wide."""
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = (line + " " + word).strip()
        if brush.textlength(trial, font=font) <= room or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def mark(plate, at, size):
    """The logo, quiet on purpose.

    Quiet because the gallery is about the addon on screen, and a badge that
    competes with the content is a badge in the wrong place.
    """
    if not os.path.exists(LOGO):
        return
    art = Image.open(LOGO).convert("RGBA").resize((size, size), Image.LANCZOS)
    art.putalpha(art.getchannel("A").point(lambda a: int(a * 0.8)))
    plate.paste(art, at, art)


def beside(plate, shot, text):
    """Tall capture: full height on the right, caption in the column left.

    This is the layout for the settings window. Centring such a capture would
    leave two empty strips of ground, and a caption underneath would shrink
    the capture further to make room for it.
    """
    at = (CANVAS[0] - MARGIN - shot.size[0], (CANVAS[1] - shot.size[1]) // 2)
    framed(plate, shot, at)

    room = at[0] - MARGIN * 2
    brush = ImageDraw.Draw(plate)
    font = face(30)
    lines = wrapped(brush, text, font, room)

    # The block sits on the optical centre, a little above the true one:
    # text centred by its box reads as hanging low.
    tall = len(lines) * 40
    top = (CANVAS[1] - tall) // 2 - 20

    mark(plate, (MARGIN, top - 72), 52)
    brush.line([(MARGIN, top - 14), (MARGIN + 40, top - 14)],
               fill=ACCENT, width=3)
    for i, line in enumerate(lines):
        brush.text((MARGIN, top + i * 40), line, font=font, fill=TEXT)


def under(plate, shot, text):
    """Wide capture: centred, caption on a strip beneath it."""
    at = ((CANVAS[0] - shot.size[0]) // 2,
          (CANVAS[1] - (CAPTION if text else 0) - shot.size[1]) // 2)
    framed(plate, shot, at)

    if not text:
        return

    base = CANVAS[1] - CAPTION
    brush = ImageDraw.Draw(plate)
    brush.line([(MARGIN, base + 18), (MARGIN + 40, base + 18)],
               fill=ACCENT, width=3)
    brush.text((MARGIN, base + 34), text, font=face(26), fill=TEXT)
    mark(plate, (CANVAS[0] - MARGIN - 44, base + 16), 44)


def split(name):
    """The caption out of the file name; the leading number only sorts."""
    stem = os.path.splitext(name)[0]
    if " - " in stem:
        return stem.split(" - ", 1)[1].strip()
    return ""


def main():
    if not os.path.isdir(RAW):
        os.makedirs(RAW)
        print("put raw captures into " + RAW)
        return 1

    names = sorted(n for n in os.listdir(RAW)
                   if n.lower().endswith((".png", ".jpg", ".jpeg", ".tga")))
    if not names:
        print("no captures in " + RAW)
        return 1

    for name in names:
        shot = Image.open(os.path.join(RAW, name)).convert("RGB")
        text = split(name)
        plate = ground()

        # Which layout: a capture taller than the canvas allows, once fitted
        # to full height, leaves a column wide enough to hold the caption.
        # Below that width the column would hold two words a line.
        tall_fit = fitted(shot, (int(CANVAS[0] * 0.72),
                                 CANVAS[1] - MARGIN * 2))
        if text and CANVAS[0] - tall_fit.size[0] - MARGIN * 3 >= 260:
            beside(plate, tall_fit, text)
        else:
            room = (CANVAS[0] - MARGIN * 2,
                    CANVAS[1] - MARGIN - (CAPTION if text else MARGIN))
            under(plate, fitted(shot, room), text)

        out = os.path.join(OUT, os.path.splitext(name)[0] + ".png")
        plate.save(out)
        print("%s  <- %s" % (out, name))

    return 0


if __name__ == "__main__":
    sys.exit(main())
