"""Human card back and the Orc & Troll deck for CowCasino (TGAs, both clients).

Same sizes and conventions as make_tauren_cards.py:
  HumanCardBack.tga          128x128, card in the top-left 92x128
  OrcCardFace / OrcCardBack  128x128, card in the top-left 92x128
  OrcSuits.tga               256x64: spade, heart, diamond, club
  OrcCourt.tga               256x64: jack, queen, king
usage: make_race_cards.py <out folder>
"""
import math, sys
from PIL import Image, ImageDraw, ImageFilter
import make_tauren_cards as T
from make_tauren_cards import K, CW, CH, noise, rounded_mask, save_card_to

OUT = sys.argv[1]

def base(fill, var, outline=(20, 14, 10, 255)):
    w, h = CW * K, CH * K
    img = Image.new("RGBA", (w, h), fill)
    img = noise(img, var, 3 * K)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, w - 2, h - 2], radius=7 * K, outline=outline, width=int(2.2 * K))
    img.putalpha(rounded_mask(w, h, 7 * K))
    return img

# ---------------------------------------------------------------- Human ---
GOLD, GOLD_D = (214, 176, 72, 255), (150, 112, 36, 255)
BLUE, BLUE_D = (34, 60, 132, 255), (16, 28, 70, 255)
SILVER = (214, 220, 230, 255)

def human_back():
    img = base(BLUE, 30, BLUE_D)
    w, h = img.size
    d = ImageDraw.Draw(img)
    # gold lattice inside the frame
    lat = Image.new("RGBA", (w, h), (0, 0, 0, 0)); ld = ImageDraw.Draw(lat)
    step = 12 * K
    for x in range(-h, w + h, step):
        ld.line([(x, 0), (x + h, h)], fill=(214, 176, 72, 70), width=K)
        ld.line([(x, h), (x + h, 0)], fill=(214, 176, 72, 70), width=K)
    for x in range(-h, w + h, step):
        for y in range(0, h, step):
            pass
    inner = Image.new("L", (w, h), 0)
    ImageDraw.Draw(inner).rounded_rectangle([10 * K, 10 * K, w - 10 * K, h - 10 * K], radius=3 * K, fill=255)
    lat.putalpha(Image.composite(lat.split()[3], Image.new("L", (w, h), 0), inner))
    img.alpha_composite(lat)
    d = ImageDraw.Draw(img)
    # double gold frame with corner studs
    d.rounded_rectangle([5 * K, 5 * K, w - 5 * K, h - 5 * K], radius=4 * K, outline=GOLD, width=int(1.6 * K))
    d.rounded_rectangle([9 * K, 9 * K, w - 9 * K, h - 9 * K], radius=3 * K, outline=GOLD_D, width=K)
    for cx, cy in ((9, 9), (CW - 9, 9), (9, CH - 9), (CW - 9, CH - 9)):
        x, y = cx * K, cy * K
        d.polygon([(x, y - 3.5 * K), (x + 3.5 * K, y), (x, y + 3.5 * K), (x - 3.5 * K, y)], fill=GOLD, outline=GOLD_D)
    # crossed swords behind the shield
    cx, cy = w / 2, h / 2 + 4 * K
    for a in (-1, 1):
        x0, y0 = cx - a * 26 * K, cy + 30 * K
        x1, y1 = cx + a * 24 * K, cy - 30 * K
        d.line([(x0, y0), (x1, y1)], fill=(40, 40, 50, 255), width=int(4.4 * K))
        d.line([(x0, y0), (x1, y1)], fill=SILVER, width=int(2.6 * K))
        # crossguard and pommel
        gx, gy = x0 + (x1 - x0) * 0.22, y0 + (y1 - y0) * 0.22
        ang = math.atan2(y1 - y0, x1 - x0) + math.pi / 2
        d.line([(gx - math.cos(ang) * 6 * K, gy - math.sin(ang) * 6 * K), (gx + math.cos(ang) * 6 * K, gy + math.sin(ang) * 6 * K)],
               fill=GOLD, width=int(2.6 * K))
        d.ellipse([x0 - 2.6 * K, y0 - 2.6 * K, x0 + 2.6 * K, y0 + 2.6 * K], fill=GOLD, outline=GOLD_D)
    # heater shield: gold rim, blue field, gold chevron, three bezants
    sw, sh = 34 * K, 40 * K
    top = cy - sh * 0.45
    def shield(inset):
        l, r = cx - sw / 2 + inset, cx + sw / 2 - inset
        t = top + inset
        pts = [(l, t), (r, t), (r, t + sh * 0.45)]
        for i in range(1, 21):
            u = i / 20
            pts.append((r - (r - cx) * u, t + sh * 0.45 + (sh * 0.55 - inset * 1.6) * math.sin(u * math.pi / 2)))
        for i in range(19, 0, -1):
            u = i / 20
            pts.append((l + (cx - l) * u, t + sh * 0.45 + (sh * 0.55 - inset * 1.6) * math.sin(u * math.pi / 2)))
        pts.append((l, t + sh * 0.45))
        return pts
    d.polygon(shield(0), fill=GOLD_D)
    d.polygon(shield(1.6 * K), fill=GOLD)
    d.polygon(shield(3.6 * K), fill=BLUE)
    # chevron
    d.line([(cx - 12 * K, top + 24 * K), (cx, top + 13 * K), (cx + 12 * K, top + 24 * K)], fill=GOLD, width=int(4 * K), joint="curve")
    for bx, by in ((-8, 8), (8, 8), (0, 30)):
        x, y = cx + bx * K, top + by * K
        d.ellipse([x - 2.6 * K, y - 2.6 * K, x + 2.6 * K, y + 2.6 * K], fill=GOLD, outline=GOLD_D)
    # crown above
    ct = top - 13 * K
    d.rectangle([cx - 11 * K, ct + 6 * K, cx + 11 * K, ct + 11 * K], fill=GOLD, outline=GOLD_D)
    for px in (-11, -5.5, 0, 5.5, 11):
        tip = ct - (4 if px in (-11, 0, 11) else 0) * K
        d.polygon([(cx + (px - 3) * K, ct + 6 * K), (cx + px * K, tip), (cx + (px + 3) * K, ct + 6 * K)], fill=GOLD, outline=GOLD_D)
        d.ellipse([cx + px * K - 1.6 * K, tip - 1.6 * K, cx + px * K + 1.6 * K, tip + 1.6 * K], fill=(200, 40, 40, 255))
    for jx, col in ((-6, (200, 40, 40, 255)), (0, (60, 120, 210, 255)), (6, (40, 160, 90, 255))):
        d.ellipse([cx + jx * K - 1.5 * K, ct + 7 * K, cx + jx * K + 1.5 * K, ct + 10 * K], fill=col)
    return img

# ----------------------------------------------------------- Orc & Troll ---
PARCH = (214, 192, 150, 255)
IRON, IRON_D = (78, 76, 74, 255), (30, 28, 26, 255)
BLOOD, CHAR = (150, 26, 20, 255), (38, 30, 26, 255)
TEAL = (38, 140, 120, 255)
BONE = (232, 222, 196, 255)
WOOD, WOOD_D = (128, 82, 44, 255), (70, 42, 22, 255)

def teeth(d, x0, x1, y, h, down=True):
    """A row of iron spikes on a red band."""
    d.rectangle([x0, y if down else y - 2 * K, x1, (y + 2 * K) if down else y], fill=BLOOD)
    step = h * 1.2
    n = int((x1 - x0) // step)
    start = x0 + ((x1 - x0) - n * step) / 2
    for i in range(n):
        x = start + i * step
        if down:
            d.polygon([(x, y + 2 * K), (x + step / 2, y + 2 * K + h), (x + step, y + 2 * K)], fill=IRON, outline=IRON_D)
        else:
            d.polygon([(x, y - 2 * K), (x + step / 2, y - 2 * K - h), (x + step, y - 2 * K)], fill=IRON, outline=IRON_D)

def orc_face():
    img = base(PARCH, 70)
    w, h = img.size
    # stains
    st = Image.new("RGBA", (w, h), (0, 0, 0, 0)); sd = ImageDraw.Draw(st)
    for (x, y, r) in ((0.75, 0.62, 16), (0.22, 0.80, 11), (0.6, 0.25, 9)):
        sd.ellipse([w * x - r * K, h * y - r * K, w * x + r * K, h * y + r * K], fill=(120, 80, 40, 40))
    st = st.filter(ImageFilter.GaussianBlur(4 * K)); img.alpha_composite(st)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([5 * K, 5 * K, w - 5 * K, h - 5 * K], radius=4 * K, outline=(110, 60, 30, 255), width=K)
    teeth(d, 26 * K, w - 26 * K, 6 * K, 5 * K, down=True)
    teeth(d, 26 * K, w - 26 * K, h - 6 * K, 5 * K, down=False)
    return img

def orc_back():
    img = base((104, 30, 22, 255), 70)
    w, h = img.size
    d = ImageDraw.Draw(img)
    # black iron frame with spikes pointing in
    d.rounded_rectangle([5 * K, 5 * K, w - 5 * K, h - 5 * K], radius=4 * K, outline=IRON_D, width=int(3 * K))
    for x in range(12, CW - 8, 9):
        X = x * K
        d.polygon([(X - 3 * K, 7 * K), (X, 13 * K), (X + 3 * K, 7 * K)], fill=IRON, outline=IRON_D)
        d.polygon([(X - 3 * K, h - 7 * K), (X, h - 13 * K), (X + 3 * K, h - 7 * K)], fill=IRON, outline=IRON_D)
    for y in range(16, CH - 12, 9):
        Y = y * K
        d.polygon([(7 * K, Y - 3 * K), (13 * K, Y), (7 * K, Y + 3 * K)], fill=IRON, outline=IRON_D)
        d.polygon([(w - 7 * K, Y - 3 * K), (w - 13 * K, Y), (w - 7 * K, Y + 3 * K)], fill=IRON, outline=IRON_D)
    for cx, cy in ((8, 8), (CW - 8, 8), (8, CH - 8), (CW - 8, CH - 8)):
        d.ellipse([cx * K - 3 * K, cy * K - 3 * K, cx * K + 3 * K, cy * K + 3 * K], fill=IRON, outline=IRON_D, width=K)
    cx, cy = w / 2, h / 2 + 2 * K
    # crossed tusks: thick at the bottom corners, curving up and outward
    for a in (-1, 1):
        pts_l, pts_r = [], []
        for i in range(25):
            t = i / 24
            x = cx + a * (-22 * K + 40 * K * t + 10 * K * t * t)
            y = cy + 30 * K - 62 * K * t
            th = 5.5 * K * (1 - t) ** 0.7 + 1.2 * K
            # offset across the curve
            pts_l.append((x - th * 0.8, y - th * 0.6 * a)); pts_r.append((x + th * 0.8, y + th * 0.6 * a))
        poly = pts_l + pts_r[::-1]
        d.polygon(poly, fill=BONE)
        d.line(poly + [poly[0]], fill=IRON_D, width=int(1.4 * K))
        # a darker ring where the tusk meets its base
        b0, b1 = pts_l[3], pts_r[3]
        d.line([b0, b1], fill=(170, 150, 120, 255), width=int(1.6 * K))
    # round wooden war shield with claw marks
    R = 20 * K
    d.ellipse([cx - R - K, cy - R - K, cx + R + K, cy + R + K], fill=IRON_D)
    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=WOOD)
    for dy in (-10, 0, 10):
        d.line([(cx - R + 2 * K, cy + dy * K), (cx + R - 2 * K, cy + dy * K)], fill=WOOD_D, width=K)
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=IRON, width=int(2.5 * K))
    for k in (-1, 0, 1):
        d.line([(cx - 9 * K + k * 6 * K, cy - 13 * K), (cx + 3 * K + k * 6 * K, cy + 13 * K)], fill=BLOOD, width=int(3.2 * K))
    d.ellipse([cx - 3 * K, cy - 3 * K, cx + 3 * K, cy + 3 * K], fill=IRON, outline=IRON_D)
    # troll beads
    for bx in (-14, 14):
        d.ellipse([cx + bx * K - 2.4 * K, cy + R + 3 * K, cx + bx * K + 2.4 * K, cy + R + 8 * K], fill=TEAL, outline=IRON_D)
    return img

def orc_suits():
    cell = 64 * K
    sheet = Image.new("RGBA", (4 * cell, cell), (0, 0, 0, 0))
    for i, (kind, col) in enumerate((("spade", CHAR), ("heart", BLOOD), ("diamond", BLOOD), ("club", CHAR))):
        layer = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        T.suit_shape(ImageDraw.Draw(layer), kind, cell, col)
        a = layer.split()[3]
        edge = a.filter(ImageFilter.MaxFilter(2 * K + 1))
        ol = Image.new("RGBA", (cell, cell), (18, 12, 10, 255)); ol.putalpha(edge)
        ol.alpha_composite(layer)
        # war paint: three diagonal claw slashes
        hl = Image.new("RGBA", (cell, cell), (0, 0, 0, 0)); hd = ImageDraw.Draw(hl)
        paint = BONE if kind in ("spade", "club") else (240, 210, 170, 255)
        for k in (-1, 0, 1):
            x = cell * 0.5 + k * cell * 0.13
            hd.line([(x - cell * 0.06, cell * 0.34), (x + cell * 0.04, cell * 0.62)], fill=paint, width=int(3.4 * K))
        hl.putalpha(Image.composite(hl.split()[3], Image.new("L", (cell, cell), 0), a))
        ol.alpha_composite(hl)
        sheet.alpha_composite(ol, (i * cell, 0))
    return sheet.resize((256, 64), Image.LANCZOS)

def axe(d, x0, y0, x1, y1, cell):
    d.line([(x0, y0), (x1, y1)], fill=IRON_D, width=int(5 * K))
    d.line([(x0, y0), (x1, y1)], fill=WOOD, width=int(3 * K))
    ang = math.atan2(y1 - y0, x1 - x0)
    px, py = -math.sin(ang), math.cos(ang)
    hx, hy = x0 + (x1 - x0) * 0.82, y0 + (y1 - y0) * 0.82
    L, W = cell * 0.17, cell * 0.10
    for side in (1, -1):
        bx, by = hx + px * side * L, hy + py * side * L
        d.polygon([(hx + math.cos(ang) * W * 0.4, hy + math.sin(ang) * W * 0.4),
                   (bx + math.cos(ang) * W, by + math.sin(ang) * W),
                   (bx - math.cos(ang) * W, by - math.sin(ang) * W),
                   (hx - math.cos(ang) * W * 0.4, hy - math.sin(ang) * W * 0.4)], fill=(150, 150, 156, 255), outline=IRON_D)
    d.line([(hx - math.cos(ang) * 4 * K, hy - math.sin(ang) * 4 * K), (hx + math.cos(ang) * 4 * K, hy + math.sin(ang) * 4 * K)],
           fill=BLOOD, width=int(3 * K))

def orc_court():
    cell = 64 * K
    sheet = Image.new("RGBA", (4 * cell, cell), (0, 0, 0, 0))
    # Jack: crossed axes
    j = Image.new("RGBA", (cell, cell), (0, 0, 0, 0)); d = ImageDraw.Draw(j)
    axe(d, cell * 0.18, cell * 0.92, cell * 0.78, cell * 0.14, cell)
    axe(d, cell * 0.82, cell * 0.92, cell * 0.22, cell * 0.14, cell)
    # Queen: troll voodoo mask
    q = Image.new("RGBA", (cell, cell), (0, 0, 0, 0)); d = ImageDraw.Draw(q)
    cx = cell * 0.5
    for fx, fy in ((-0.20, 0.10), (0.0, 0.04), (0.20, 0.10)):
        d.polygon([(cx + fx * cell - 4 * K, cell * 0.30), (cx + fx * cell, cell * fy), (cx + fx * cell + 4 * K, cell * 0.30)],
                  fill=(BLOOD if fx else TEAL), outline=IRON_D)
    d.ellipse([cx - cell * 0.26, cell * 0.20, cx + cell * 0.26, cell * 0.92], fill=WOOD, outline=IRON_D, width=int(1.5 * K))
    d.ellipse([cx - cell * 0.22, cell * 0.24, cx + cell * 0.22, cell * 0.86], outline=TEAL, width=int(2 * K))
    for ex in (-0.10, 0.10):
        d.ellipse([cx + ex * cell - 5.5 * K, cell * 0.42 - 4 * K, cx + ex * cell + 5.5 * K, cell * 0.42 + 4 * K], fill=BONE, outline=IRON_D)
        d.ellipse([cx + ex * cell - 2 * K, cell * 0.42 - 2 * K, cx + ex * cell + 2 * K, cell * 0.42 + 2 * K], fill=IRON_D)
    d.rectangle([cx - cell * 0.12, cell * 0.64, cx + cell * 0.12, cell * 0.74], fill=IRON_D)
    for tx in (-0.09, 0.09):
        d.polygon([(cx + tx * cell - 2.5 * K, cell * 0.70), (cx + tx * cell, cell * 0.55), (cx + tx * cell + 2.5 * K, cell * 0.70)], fill=BONE, outline=IRON_D)
    for sx in (-0.17, 0.17):
        d.line([(cx + sx * cell, cell * 0.52), (cx + sx * cell, cell * 0.62)], fill=BLOOD, width=int(2 * K))
    # King: tusked warlord's helm
    k = Image.new("RGBA", (cell, cell), (0, 0, 0, 0)); d = ImageDraw.Draw(k)
    for sx in (-0.18, 0.0, 0.18):
        d.polygon([(cx + sx * cell - 4 * K, cell * 0.30), (cx + sx * cell, cell * (0.06 if sx == 0 else 0.12)), (cx + sx * cell + 4 * K, cell * 0.30)],
                  fill=IRON, outline=IRON_D)
    d.pieslice([cx - cell * 0.30, cell * 0.20, cx + cell * 0.30, cell * 0.80], 180, 360, fill=IRON, outline=IRON_D, width=int(1.5 * K))
    d.rectangle([cx - cell * 0.32, cell * 0.48, cx + cell * 0.32, cell * 0.56], fill=IRON_D)
    for rx in (-0.24, -0.12, 0.0, 0.12, 0.24):
        d.ellipse([cx + rx * cell - 1.6 * K, cell * 0.52 - 1.6 * K, cx + rx * cell + 1.6 * K, cell * 0.52 + 1.6 * K], fill=(170, 170, 176, 255))
    d.rectangle([cx - cell * 0.22, cell * 0.56, cx + cell * 0.22, cell * 0.66], fill=(30, 26, 24, 255))
    for ex in (-0.10, 0.10):
        d.ellipse([cx + ex * cell - 3 * K, cell * 0.59, cx + ex * cell + 3 * K, cell * 0.63], fill=(220, 40, 30, 255))
    for a in (-1, 1):
        pts_o, pts_i = [], []
        for i in range(16):
            t = i / 15
            x = cx + a * (cell * 0.16 + cell * 0.10 * math.sin(t * 1.4))
            y = cell * 0.66 + cell * 0.04 - cell * 0.30 * t ** 1.3 + cell * 0.24
            th = 3.2 * K * (1 - t) + 0.6 * K
            pts_o.append((x - th, y)); pts_i.append((x + th, y))
        d.polygon(pts_o + pts_i[::-1], fill=BONE, outline=IRON_D)
    for i, img in enumerate((j, q, k)):
        sheet.alpha_composite(img, (i * cell, 0))
    return sheet.resize((256, 64), Image.LANCZOS)

save_card_to(human_back(), f"{OUT}/HumanCardBack.tga")
save_card_to(orc_face(), f"{OUT}/OrcCardFace.tga")
save_card_to(orc_back(), f"{OUT}/OrcCardBack.tga")
orc_suits().save(f"{OUT}/OrcSuits.tga", rle=False)
orc_court().save(f"{OUT}/OrcCourt.tga", rle=False)
print("ok")
