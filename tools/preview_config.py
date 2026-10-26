#!/usr/bin/env python3
"""
Renders the JSON from tools/dump_config.lua into PNG previews of the setup panel.

    lua tools/dump_config.lua preview_config_json
    python tools/preview_config.py preview_config_json preview_config_png

Every page is drawn at its full content height (the real window scrolls). Text is Segoe UI, the font the panel
loads in game. Anything flagged as running past its container gets a red outline. Like the frame previews this
is a replay of what the panel asked for, not a screenshot of the game.
"""
import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

FONT = os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts", "segoeui.ttf")
_fonts = {}


def font(px):
    key = max(6, int(round(px)))
    if key not in _fonts:
        try:
            _fonts[key] = ImageFont.truetype(FONT, key)
        except OSError:
            _fonts[key] = ImageFont.load_default()
    return _fonts[key]


def render(doc):
    w, h = doc["w"], doc["h"]
    img = Image.new("RGBA", (w, h), (24, 26, 32, 255))
    d = ImageDraw.Draw(img, "RGBA")
    for c in doc["cmds"]:
        op = c["op"]
        if op == "rect":
            box = [c["x"], c["y"], c["x"] + c["w"] - 1, c["y"] + max(0, c["h"] - 1)]
            r = max(0, min(c["r"], c["w"] / 2, c["h"] / 2))
            col = tuple(c["c"])
            if r >= 1:
                d.rounded_rectangle(box, radius=r, fill=col, outline=tuple(c["b"]) if "b" in c else None)
            else:
                d.rectangle(box, fill=col, outline=tuple(c["b"]) if "b" in c else None)
        elif op == "text":
            d.text((c["x"], c["y"]), c["s"], font=font(c["px"]), fill=tuple(c["c"]))
        elif op == "line":
            p = c["p"]
            d.line([(p[i], p[i + 1]) for i in range(0, len(p), 2)], fill=tuple(c["c"]), width=max(1, int(round(c["t"]))), joint="curve")
    for f in doc["flags"]:
        d.rectangle([f["x"] - 2, f["y"] - 2, f["x"] + f["w"] + 2, f["y"] + f["h"] + 2], outline=(255, 40, 40, 255), width=3)
    return img


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(src)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(src, name), encoding="utf-8") as fh:
            doc = json.load(fh)
        render(doc).convert("RGB").save(os.path.join(dst, name[:-5] + ".png"))
        print("wrote", name[:-5] + ".png", ("(%d flagged)" % len(doc["flags"])) if doc["flags"] else "")


if __name__ == "__main__":
    main()
