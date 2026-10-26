#!/usr/bin/env python3
"""
Builds the pictures and animated GIFs the README uses, into media/.

    lua tools/dump_draw.lua media_json media
    lua tools/dump_config.lua preview_config_json
    python tools/preview_config.py preview_config_json preview_config_png
    python tools/make_media.py media_json preview_config_png media

They are renders of the addon's real drawing code (the same one the game runs), laid out with the game's font,
not screenshots: in game the status effects use the game's own icons.
"""
import os
import re
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import preview  # noqa: E402

BG = (20, 22, 28)

# animation name -> (file name, milliseconds per frame)
ANIMATIONS = {
    "party": ("demo-party.gif", 250),
    "flyout": ("hover-menu.gif", 250),
    "triage": ("triage.gif", 300),
    "modes": ("layouts.gif", 300),
}

# setup panel pages shown in the README: (page, picture name)
SETUP = [("appearance", "setup-appearance.png"), ("commands", "setup-commands.png")]


def save_still(img, path, max_w=1400):
    img = img.convert("RGB")
    if img.width > max_w:
        img = img.resize((max_w, round(img.height * max_w / img.width)), Image.LANCZOS)
    img.save(path, optimize=True)
    print("wrote", path, img.size, os.path.getsize(path) // 1024, "KB")


def save_gif(frames, path, ms, max_w=720):
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    out = []
    for f in frames:
        canvas = Image.new("RGB", (w, h), BG)
        canvas.paste(f.convert("RGB"), (0, 0))
        if w > max_w:
            canvas = canvas.resize((max_w, round(h * max_w / w)), Image.LANCZOS)
        out.append(canvas.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    out[0].save(path, save_all=True, append_images=out[1:], duration=ms, loop=0, optimize=True, disposal=2)
    print("wrote", path, out[0].size, len(out), "frames", os.path.getsize(path) // 1024, "KB")


def main():
    src, cfg_png, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(dst, exist_ok=True)
    names = sorted({f.split(".")[0] for f in os.listdir(src) if f.endswith(".roster.json")})

    for name in names:
        if name.startswith("media_"):
            save_still(preview.compose(src, name), os.path.join(dst, name[len("media_"):] + ".png"))

    for key, (fname, ms) in ANIMATIONS.items():
        frames = [preview.compose(src, n) for n in names if re.fullmatch(r"anim_%s_\d+" % key, n)]
        if frames:
            save_gif(frames, os.path.join(dst, fname), ms)

    for page, fname in SETUP:
        p = os.path.join(cfg_png, "cfg_%s_4k.png" % page)
        if os.path.exists(p):
            im = Image.open(p)
            im = im.crop((0, 0, im.width, min(im.height, 1360)))   # the first screenful: the window opens at this height
            save_still(im, os.path.join(dst, fname), max_w=1000)


if __name__ == "__main__":
    main()
