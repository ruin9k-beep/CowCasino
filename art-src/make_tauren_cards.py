"""Tauren card art for CowCasino: face, back, suit and court sheets as TGAs.

Cards show at 46 x 64 at most, so everything is bold and simple. Drawn at 4x
and shrunk for smooth edges. Output (power-of-two TGAs, both clients):
  TaurenCardFace.tga   128x128, card in the top-left 92x128
  TaurenCardBack.tga   128x128, card in the top-left 92x128
  TaurenSuits.tga      256x64: spade, heart, diamond, club (64x64 each)
  TaurenCourt.tga      256x64: jack, queen, king (64x64 each)
usage: make_tauren_cards.py <out folder>
"""
import math, random, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if __name__ == "__main__" else None
K = 4                                  # drawing scale
CW, CH = 92, 128                        # card art size in the files
random.seed(11)

OUTLINE = (34, 20, 12, 255)
HIDE    = (236, 222, 190, 255)
BROWN   = (118, 70, 38, 255)
DARK    = (58, 34, 20, 255)
TURQ    = (40, 150, 142, 255)
OCHRE   = (178, 56, 34, 255)
CREAM   = (240, 226, 190, 255)
IVORY   = (238, 228, 200, 255)
UMBER   = (52, 34, 24, 255)

def noise(img, amount, blur):
    w, h = img.size
    n = Image.effect_noise((w, h), amount).convert("L").filter(ImageFilter.GaussianBlur(blur))
    px, npx = img.load(), n.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0: continue
            d = (npx[x, y] - 128) // 6
            px[x, y] = (max(0, min(255, r + d)), max(0, min(255, g + d)), max(0, min(255, b + d)), a)
    return img

def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return m

def band(d, x0, x1, y, h, flip=False):
    """A row of turquoise/red triangles with cream tips between x0 and x1."""
    step = h * 2
    n = int((x1 - x0) // step)
    start = x0 + ((x1 - x0) - n * step) / 2
    for i in range(n):
        x = start + i * step
        col = TURQ if i % 2 == 0 else OCHRE
        if not flip:
            d.polygon([(x, y + h), (x + step / 2, y), (x + step, y + h)], fill=col)
        else:
            d.polygon([(x, y), (x + step / 2, y + h), (x + step, y)], fill=col)

def card_base(fill, var):
    w, h = CW * K, CH * K
    img = Image.new("RGBA", (w, h), fill)
    img = noise(img, var, 3 * K)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, w - 2, h - 2], radius=7 * K, outline=OUTLINE, width=int(2.2 * K))
    img.putalpha(rounded_mask(w, h, 7 * K))
    return img

def face():
    img = card_base(HIDE, 40)
    d = ImageDraw.Draw(img)
    w, h = img.size
    # thin inner frame line
    d.rounded_rectangle([5 * K, 5 * K, w - 5 * K, h - 5 * K], radius=4 * K, outline=(150, 110, 70, 255), width=K)
    # tribal band along the top and bottom middles (corners stay clear for the rank)
    band(d, 26 * K, w - 26 * K, 7 * K, 5 * K)
    band(d, 26 * K, w - 26 * K, h - 12 * K, 5 * K, flip=True)
    return img

def back():
    img = card_base(BROWN, 60)
    d = ImageDraw.Draw(img)
    w, h = img.size
    # cream frame with a full tribal band
    d.rounded_rectangle([6 * K, 6 * K, w - 6 * K, h - 6 * K], radius=4 * K, outline=CREAM, width=K)
    d.rounded_rectangle([14 * K, 14 * K, w - 14 * K, h - 14 * K], radius=3 * K, outline=CREAM, width=K)
    band(d, 10 * K, w - 10 * K, 8 * K, 5 * K)
    band(d, 10 * K, w - 10 * K, h - 13 * K, 5 * K, flip=True)
    # side bands: draw on a rotated strip
    for side in (0, 1):
        strip = Image.new("RGBA", (h - 28 * K, 6 * K), (0, 0, 0, 0))
        band(ImageDraw.Draw(strip), 0, h - 28 * K, 0, 5 * K, flip=bool(side))
        strip = strip.rotate(90, expand=True)
        img.alpha_composite(strip, (8 * K if side == 0 else w - 14 * K, 14 * K))
    # center: sun disc with horns above and feathers below
    cx, cy = w / 2, h / 2 + 4 * K
    d = ImageDraw.Draw(img)
    for r, col in ((17, OUTLINE), (16, CREAM), (12, TURQ), (8, OCHRE), (4, CREAM)):
        d.ellipse([cx - r * K, cy - r * K, cx + r * K, cy + r * K], fill=col)
    horn(d, cx, cy - 10 * K, -1, 20 * K)
    horn(d, cx, cy - 10 * K, 1, 20 * K)
    for dx in (-8, 0, 8):
        feather(d, cx + dx * K, cy + 14 * K, 16 * K)
    return img

def horn(d, cx, cy, side, size):
    """An ivory horn curving out and up from (cx + side*offset, cy)."""
    pts_o, pts_i = [], []
    steps = 30
    for i in range(steps + 1):
        t = i / steps
        x = cx + side * (size * 0.22 + size * 0.70 * math.sin(t * 1.9))
        y = cy - size * 0.90 * t ** 1.5
        th = size * 0.24 * (1 - t) ** 0.8 + K * 0.8
        pts_o.append((x, y - th)); pts_i.append((x, y + th))
    poly = pts_o + pts_i[::-1]
    d.polygon(poly, fill=IVORY)
    d.line(pts_o + pts_i[::-1] + [pts_o[0]], fill=OUTLINE, width=int(1.5 * K), joint="curve")
    # darker tip
    tip_poly = pts_o[int(steps * 0.72):] + pts_i[int(steps * 0.72):][::-1]
    d.polygon(tip_poly, fill=(150, 128, 98, 255))
    tip = pts_o[-1]
    d.ellipse([tip[0] - 1.6 * K, tip[1] - 1.6 * K, tip[0] + 1.6 * K, tip[1] + 1.6 * K], fill=(110, 90, 70, 255))

def feather(d, x, y, length, col=None):
    col = col or (240, 236, 224, 255)
    d.line([(x, y), (x, y + length)], fill=OUTLINE, width=K)
    d.ellipse([x - 3 * K, y + length * 0.25, x + 3 * K, y + length], fill=col, outline=OUTLINE, width=K)
    d.ellipse([x - 3 * K, y + length * 0.72, x + 3 * K, y + length], fill=DARK)

# ---- suits -------------------------------------------------------------
def suit_shape(d, kind, s, col):
    """Standard suit shapes in a box of size s (origin 0,0), with a cream highlight."""
    o = OUTLINE
    if kind == "heart":
        r = s * 0.24
        d.ellipse([s * 0.10, s * 0.16, s * 0.10 + 2 * r, s * 0.16 + 2 * r], fill=col)
        d.ellipse([s * 0.90 - 2 * r, s * 0.16, s * 0.90, s * 0.16 + 2 * r], fill=col)
        d.polygon([(s * 0.12, s * 0.48), (s * 0.88, s * 0.48), (s * 0.5, s * 0.90)], fill=col)
    elif kind == "diamond":
        d.polygon([(s * 0.5, s * 0.06), (s * 0.86, s * 0.5), (s * 0.5, s * 0.94), (s * 0.14, s * 0.5)], fill=col)
    elif kind == "spade":
        r = s * 0.22
        d.polygon([(s * 0.5, s * 0.06), (s * 0.90, s * 0.55), (s * 0.10, s * 0.55)], fill=col)
        d.ellipse([s * 0.10, s * 0.38, s * 0.10 + 2 * r, s * 0.38 + 2 * r], fill=col)
        d.ellipse([s * 0.90 - 2 * r, s * 0.38, s * 0.90, s * 0.38 + 2 * r], fill=col)
        d.polygon([(s * 0.5, s * 0.60), (s * 0.66, s * 0.94), (s * 0.34, s * 0.94)], fill=col)
    elif kind == "club":
        r = s * 0.19
        for cx, cy in ((0.5, 0.27), (0.27, 0.55), (0.73, 0.55)):
            d.ellipse([s * cx - r, s * cy - r, s * cx + r, s * cy + r], fill=col)
        d.polygon([(s * 0.5, s * 0.45), (s * 0.66, s * 0.94), (s * 0.34, s * 0.94)], fill=col)

def suits():
    cell = 64 * K
    sheet = Image.new("RGBA", (4 * cell, cell), (0, 0, 0, 0))
    for i, (kind, col) in enumerate((("spade", UMBER), ("heart", OCHRE), ("diamond", OCHRE), ("club", UMBER))):
        layer = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        suit_shape(ImageDraw.Draw(layer), kind, cell, col)
        # a dark outline from the shape's own edge
        a = layer.split()[3]
        edge = a.filter(ImageFilter.MaxFilter(2 * K + 1))
        ol = Image.new("RGBA", (cell, cell), OUTLINE); ol.putalpha(edge)
        ol.alpha_composite(layer)
        # a painted cream stripe with a turquoise bead, for the tribal look
        hl = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        hd = ImageDraw.Draw(hl)
        y = cell * {"spade": 0.50, "heart": 0.40, "diamond": 0.50, "club": 0.52}[kind]
        hd.line([(0, y), (cell, y)], fill=CREAM, width=int(2.6 * K))
        hd.ellipse([cell * 0.5 - 3.2 * K, y - 3.2 * K, cell * 0.5 + 3.2 * K, y + 3.2 * K], fill=TURQ, outline=CREAM, width=K)
        mask = Image.new("L", (cell, cell), 0); mask.paste(a, (0, 0))
        hl.putalpha(Image.composite(hl.split()[3], Image.new("L", (cell, cell), 0), mask))
        ol.alpha_composite(hl)
        sheet.alpha_composite(ol, (i * cell, 0))
    return sheet.resize((256, 64), Image.LANCZOS)

# ---- court emblems -------------------------------------------------------
def court():
    cell = 64 * K
    sheet = Image.new("RGBA", (4 * cell, cell), (0, 0, 0, 0))
    # Jack: crossed spears with a feathered band
    j = Image.new("RGBA", (cell, cell), (0, 0, 0, 0)); d = ImageDraw.Draw(j)
    for a in (-1, 1):
        x0, y0 = cell * (0.5 - a * 0.36), cell * 0.92
        x1, y1 = cell * (0.5 + a * 0.30), cell * 0.16
        d.line([(x0, y0), (x1, y1)], fill=OUTLINE, width=int(5 * K))
        d.line([(x0, y0), (x1, y1)], fill=(150, 98, 52, 255), width=int(3 * K))
        ang = math.atan2(y1 - y0, x1 - x0); L = cell * 0.17; W = cell * 0.07
        tip = (x1 + math.cos(ang) * L, y1 + math.sin(ang) * L)
        l = (x1 + math.cos(ang + math.pi / 2) * W, y1 + math.sin(ang + math.pi / 2) * W)
        r = (x1 + math.cos(ang - math.pi / 2) * W, y1 + math.sin(ang - math.pi / 2) * W)
        d.polygon([tip, l, r], fill=(120, 120, 128, 255), outline=OUTLINE)
    d.rectangle([cell * 0.30, cell * 0.50, cell * 0.70, cell * 0.60], fill=TURQ, outline=OUTLINE, width=K)
    for x in (0.38, 0.50, 0.62):
        d.ellipse([cell * x - 2.5 * K, cell * 0.53 - 2.5 * K, cell * x + 2.5 * K, cell * 0.53 + 2.5 * K], fill=OCHRE)
    feather(d, cell * 0.36, cell * 0.60, cell * 0.24)
    feather(d, cell * 0.64, cell * 0.60, cell * 0.24)
    # Queen: dreamcatcher
    q = Image.new("RGBA", (cell, cell), (0, 0, 0, 0)); d = ImageDraw.Draw(q)
    cx, cy, R = cell * 0.5, cell * 0.38, cell * 0.30
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=OUTLINE, width=int(5 * K))
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=(150, 98, 52, 255), width=int(3 * K))
    pts = [(cx + R * 0.86 * math.cos(a), cy + R * 0.86 * math.sin(a)) for a in [i * math.pi / 4 for i in range(8)]]
    for i in range(8):
        d.line([pts[i], pts[(i + 3) % 8]], fill=(90, 60, 40, 255), width=K)
    d.ellipse([cx - 3 * K, cy - 3 * K, cx + 3 * K, cy + 3 * K], fill=TURQ, outline=OUTLINE)
    for dx, ln in ((-0.22, 0.30), (0.0, 0.36), (0.22, 0.30)):
        x = cx + dx * cell
        y = cy + R * (0.70 if dx else 0.96)
        d.ellipse([x - 2 * K, y - 2 * K, x + 2 * K, y + 2 * K], fill=OCHRE)
        feather(d, x, y + 2 * K, cell * (ln - 0.12))
    # King: horned shield with feathers
    k = Image.new("RGBA", (cell, cell), (0, 0, 0, 0)); d = ImageDraw.Draw(k)
    cx, cy, R = cell * 0.5, cell * 0.50, cell * 0.22
    horn(d, cx, cy - R * 0.35, -1, cell * 0.42)
    horn(d, cx, cy - R * 0.35, 1, cell * 0.42)
    for r, col in ((R + K, OUTLINE), (R, TURQ), (R * 0.72, OCHRE), (R * 0.38, CREAM)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    for dx in (-0.14, 0.0, 0.14):
        feather(d, cx + dx * cell, cy + R * 0.9, cell * 0.24)
    for i, img in enumerate((j, q, k)):
        sheet.alpha_composite(img, (i * cell, 0))
    return sheet.resize((256, 64), Image.LANCZOS)

def save_card(img, name):
    small = img.resize((CW, CH), Image.LANCZOS)
    canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    canvas.paste(small, (0, 0))
    canvas.save(f"{OUT}/{name}.tga", rle=False)

def save_card_to(img, path):
    small = img.resize((CW, CH), Image.LANCZOS)
    canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    canvas.paste(small, (0, 0))
    canvas.save(path, rle=False)

if __name__ == "__main__":
    save_card(face(), "TaurenCardFace")
    save_card(back(), "TaurenCardBack")
    suits().save(f"{OUT}/TaurenSuits.tga", rle=False)
    court().save(f"{OUT}/TaurenCourt.tga", rle=False)
    print("ok")
