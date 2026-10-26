#!/usr/bin/env python3
"""
Renders the JSON draw-command dumps from tools/dump_draw.lua into PNG previews.

    lua tools/dump_draw.lua preview_json
    python tools/preview.py preview_json preview_png

This is a faithful replay of what ui.lua asked the graphics backend to draw (same rectangles,
same text, same colors). It is NOT a screenshot of the game: real ImGui text uses its own font
and metrics, so expect small differences in text width.
"""
import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES = [
    "C:/Windows/Fonts/consola.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
    "DejaVuSansMono.ttf",
]


SEGOE = os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts", "segoeui.ttf")
_cache = {}


def load_font(px, seg=False):
    key = (int(round(px)), seg)
    if key not in _cache:
        _cache[key] = _load_font(px, seg)
    return _cache[key]


def _load_font(px, seg):
    for path in ([SEGOE] if seg else []) + FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, max(6, int(round(px))))
        except OSError:
            continue
    return ImageFont.load_default()


def unpack(c):
    r = c & 255
    g = (c >> 8) & 255
    b = (c >> 16) & 255
    a = (c >> 24) & 255
    return (r, g, b, a)


ICON_DIR = os.environ.get("CH_ICON_DIR", "media_icons")   # local only: the game's own art, never committed
_icons = {}


def status_icon(sid, px):
    """The game status icon `sid` resized to `px`, or None. Black is the transparent key."""
    key = (sid, px)
    if key not in _icons:
        img = None
        path = os.path.join(ICON_DIR, "%d.bmp" % sid)
        if os.path.exists(path):
            im = Image.open(path).convert("RGBA")
            data = [(r, g, b, 0 if (r, g, b) == (0, 0, 0) else 255) for r, g, b, _ in im.getdata()]
            im.putdata(data)
            img = im.resize((px, px), Image.LANCZOS)
        _icons[key] = img
    return _icons[key]


def render(doc, origin_bg=(34, 38, 46, 255)):
    w, h, fs = doc["w"], doc["h"], doc["fs"]
    img = Image.new("RGBA", (w, h), origin_bg)
    seg = bool(doc.get("seg"))
    base = (15 if seg else 11.6) * fs   # monospace advance ~0.602em -> ~7px per char at fs=1; Segoe is the game's font
    font = load_font(base, seg)
    tooltip = None
    for cmd in doc["cmds"]:
        op = cmd["op"]
        if op == "quad":
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            pts = [(cmd["p"][k], cmd["p"][k + 1]) for k in range(0, 8, 2)]
            col = unpack(int(cmd["c"]))
            if cmd.get("t", 0) > 0:
                d.line(pts + [pts[0]], fill=col, width=max(1, int(round(cmd["t"]))), joint="curve")
            else:
                d.polygon(pts, fill=col)
            img = Image.alpha_composite(img, layer)
            continue
        if op == "rect":
            if cmd["w"] <= 0 or cmd["h"] <= 0:
                continue
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            x0, y0 = int(round(cmd["x"])), int(round(cmd["y"]))
            x1, y1 = int(round(cmd["x"] + cmd["w"])) - 1, int(round(cmd["y"] + cmd["h"])) - 1
            if x1 < x0 or y1 < y0:
                continue
            box = [x0, y0, x1, y1]
            radius = int(min(cmd["r"], (x1 - x0 + 1) // 2, (y1 - y0 + 1) // 2))
            if radius > 0:
                d.rounded_rectangle(box, radius=radius, fill=unpack(cmd["c"]))
            else:
                d.rectangle(box, fill=unpack(cmd["c"]))
            img = Image.alpha_composite(img, layer)
        elif op == "text":
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            k = cmd.get("k", 1) or 1
            f2 = font if abs(k - 1) < 0.01 else load_font(base * k, seg)
            d.text((cmd["x"], cmd["y"] - (0 if seg else 1 * fs)), cmd["s"], font=f2, fill=unpack(cmd["c"]))
            img = Image.alpha_composite(img, layer)
        elif op == "icon":
            ic = status_icon(int(cmd["id"]), max(4, int(round(cmd["w"]))))
            if ic is not None:
                layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
                layer.paste(ic, (int(round(cmd["x"])), int(round(cmd["y"]))))
                img = Image.alpha_composite(img, layer)
        elif op == "tooltip":
            tooltip = cmd["lines"]
    return img, tooltip, fs, seg


def tooltip_image(lines, fs, seg=False):
    font = load_font((15 if seg else 11.6) * fs, seg)
    pad = int(6 * fs)
    line_h = int(16 * fs)
    width = max(int(font.getlength(l)) for l in lines) + 2 * pad
    height = len(lines) * line_h + 2 * pad
    img = Image.new("RGBA", (width, height), (24, 24, 30, 245))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, width - 1, height - 1], outline=(110, 115, 135, 255))
    for i, l in enumerate(lines):
        d.text((pad, pad + i * line_h), l, font=font, fill=(235, 236, 240, 255))
    return img


def compose(src, name):
    """The finished picture for one scenario in `src`: roster, alert bar, tooltip and flyout on one canvas."""
    with open(os.path.join(src, name + ".roster.json")) as fh:
        roster = json.load(fh)
    apath = os.path.join(src, name + ".alerts.json")
    alerts = None
    if os.path.exists(apath):
        with open(apath) as fh:
            alerts = json.load(fh)

    r_img, r_tip, fs, seg = render(roster)
    a_img = render(alerts)[0] if alerts else Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    t_img = tooltip_image(r_tip, fs, seg) if r_tip else None

    gap = int(16 * fs)
    # Layout: roster on the left; alert bar and tooltip stacked to its right.
    right_w = max(a_img.width if alerts else 0, t_img.width if t_img else 0)
    right_h = (a_img.height if alerts else 0) + (gap + t_img.height if t_img and alerts else (t_img.height if t_img else 0))
    W = r_img.width + (gap + right_w if right_w else 0) + 2 * gap
    H = max(r_img.height, right_h) + 2 * gap
    canvas = Image.new("RGBA", (W, H), (20, 22, 28, 255))
    canvas.paste(r_img, (gap, gap))
    if alerts:
        canvas.paste(a_img, (gap + r_img.width + gap, gap))
    if t_img:
        ty = gap + (a_img.height + gap if alerts else 0)
        canvas.paste(t_img, (gap + r_img.width + gap, ty))
    fpath = os.path.join(src, name + ".flyout.json")
    if os.path.exists(fpath):
        with open(fpath) as fh:
            fdoc = json.load(fh)
        with open(os.path.join(src, name + ".flyout.pos")) as fh:
            fx, fy = [int(v) for v in fh.read().split()]
        f_img, _, _, _ = render(fdoc, origin_bg=(12, 13, 17, 255))
        need_w = gap + fx + f_img.width + gap
        need_h = gap + fy + f_img.height + gap
        if need_w > canvas.width or need_h > canvas.height:
            bigger = Image.new("RGBA", (max(canvas.width, need_w), max(canvas.height, need_h)), (20, 22, 28, 255))
            bigger.paste(canvas, (0, 0))
            canvas = bigger
        canvas.paste(f_img, (gap + fx, gap + fy))
    return canvas


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "preview_json"
    dst = sys.argv[2] if len(sys.argv) > 2 else "preview_png"
    os.makedirs(dst, exist_ok=True)
    names = sorted({f.split(".")[0] for f in os.listdir(src) if f.endswith(".roster.json")})
    for name in names:
        canvas = compose(src, name)
        out = os.path.join(dst, name + ".png")
        canvas.convert("RGB").save(out)
        print("wrote", out, canvas.size)


if __name__ == "__main__":
    main()
