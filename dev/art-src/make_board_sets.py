# Alternate piece sets for Chess and Checkers, one 256x256 atlas each (4 x 4
# cells of 64, 32-bit TGA), laid out like the first 16 cells of BoardPieces:
#   cells 0-5: the side that moves first in chess  K Q R B N P
#   cells 6-11: the other chess side               K Q R B N P
#   cells 12-15: checkers  black man, black king, red man, red king
# Sets:
#   BoardPiecesFaction.tga  Alliance (white / checkers black) vs Horde
#                           (black / checkers red); the checkers men get the
#                           client's own faction emblem on top, in game
#   BoardPiecesGoblin.tga   Gnomes (white / checkers black: steel gears) vs
#                           Goblins (black / checkers red: gold coins)
#   python3 make_board_sets.py <Art folder> <preview.png>
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_board_pieces import soft_shadow, SANS, GLYPHS, CELL, BIG

OUT, PREVIEW = sys.argv[1], sys.argv[2]


def glyph_piece(glyph, fill, top, edge, trim=None, edge_w=10):
    """A chess glyph: a fill shaded from `top` down to `fill`, a thick edge,
    and (optionally) a thin trim line just inside the edge."""
    f = ImageFont.truetype(SANS, 200)
    probe = ImageDraw.Draw(Image.new("RGBA", (BIG, BIG)))
    l, t, r, b = probe.textbbox((0, 0), glyph, font=f)
    x = (BIG - (r - l)) / 2 - l
    y = (BIG - (b - t)) / 2 - t + 4
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((x, y), glyph, font=f, fill=edge, stroke_width=edge_w, stroke_fill=edge)
    if trim:
        d.text((x, y), glyph, font=f, fill=trim, stroke_width=3, stroke_fill=trim)
    # the body: a vertical gradient through the glyph's shape
    mask = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(mask).text((x, y), glyph, font=f, fill=255)
    if trim:
        mask = mask.filter(ImageFilter.MinFilter(3))
    grad = Image.new("RGBA", (BIG, BIG))
    gd = ImageDraw.Draw(grad)
    for i in range(BIG):
        k = min(1, max(0, (i - 40) / 170))
        gd.line((0, i, BIG, i), fill=tuple(int(top[j] + (fill[j] - top[j]) * k) for j in range(3)) + (255,))
    img.paste(grad, (0, 0), mask)
    # a soft shine on the upper left
    hi = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(hi).ellipse((60, 30, 150, 120), fill=(255, 255, 255, 55))
    hi = hi.filter(ImageFilter.GaussianBlur(18))
    shine = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    shine.paste(hi, (0, 0), mask)
    img.alpha_composite(shine)
    return soft_shadow(img)


def crown(d, c, y0, gold=(232, 190, 70, 255), dark=(110, 78, 20, 255)):
    pts = [(c - 52, y0 + 28), (c - 58, y0 - 30), (c - 26, y0), (c, y0 - 46), (c + 26, y0), (c + 58, y0 - 30), (c + 52, y0 + 28)]
    d.polygon(pts, fill=gold, outline=dark, width=5)
    d.rectangle((c - 52, y0 + 24, c + 52, y0 + 40), fill=gold, outline=dark, width=5)
    for px, py in ((c - 58, y0 - 30), (c, y0 - 46), (c + 58, y0 - 30)):
        d.ellipse((px - 9, py - 9, px + 9, py + 9), fill=gold, outline=dark, width=3)


def shine(img, box=(58, 40, 150, 96), alpha=70):
    hi = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(hi).ellipse(box, fill=(255, 255, 255, alpha))
    img.alpha_composite(hi.filter(ImageFilter.GaussianBlur(10)))


def banner_disc(base, rim, inner, king):
    """A checkers man for the faction set: a lacquered disc with a ring of
    trim; the middle is left plain for the faction emblem (drawn in game)."""
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c, R = BIG / 2, 104
    d.ellipse((c - R, c - R + 10, c + R, c + R + 10), fill=rim)
    d.ellipse((c - R, c - R, c + R, c + R), fill=base, outline=rim, width=8)
    d.ellipse((c - 86, c - 86, c + 86, c + 86), outline=inner, width=6)
    d.ellipse((c - 74, c - 74, c + 74, c + 74), fill=tuple(max(0, v - 25) for v in base[:3]) + (255,))
    shine(img)
    if king:
        crown(d, c, c)
    return soft_shadow(img)


def coin(king):
    """A goblin's gold coin: a milled edge, a raised rim, a stamped star."""
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c, R = BIG / 2, 104
    gold, deep, pale = (222, 172, 52, 255), (130, 88, 18, 255), (250, 222, 120, 255)
    d.ellipse((c - R, c - R + 10, c + R, c + R + 10), fill=deep)
    d.ellipse((c - R, c - R, c + R, c + R), fill=gold, outline=deep, width=6)
    for i in range(48):                                    # the milled edge
        a = i * 2 * math.pi / 48
        d.line((c + (R - 3) * math.cos(a), c + (R - 3) * math.sin(a),
                c + (R - 15) * math.cos(a), c + (R - 15) * math.sin(a)), fill=deep, width=3)
    d.ellipse((c - 80, c - 80, c + 80, c + 80), outline=deep, width=6)
    d.ellipse((c - 74, c - 74, c + 74, c + 74), outline=pale, width=3)
    if king:
        crown(d, c, c, gold=(70, 170, 60, 255), dark=(30, 60, 20, 255))
    else:
        pts = []
        for i in range(10):
            r = 52 if i % 2 == 0 else 22
            a = -math.pi / 2 + i * math.pi / 5
            pts.append((c + r * math.cos(a), c + r * math.sin(a)))
        d.polygon(pts, fill=pale, outline=deep, width=4)
    shine(img, alpha=90)
    return soft_shadow(img)


def gear(king):
    """A gnome's steel cog: teeth all round, a teal hub, a bolt hole."""
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = BIG / 2
    steel, dark, teal = (168, 178, 190, 255), (52, 58, 68, 255), (40, 180, 170, 255)
    teeth, r_out, r_in = 12, 108, 88
    pts = []
    for i in range(teeth * 4):
        a = i * 2 * math.pi / (teeth * 4)
        r = r_out if i % 4 in (1, 2) else r_in
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    shadow = [(x, y + 10) for x, y in pts]
    d.polygon(shadow, fill=dark)
    d.polygon(pts, fill=steel, outline=dark, width=6)
    d.ellipse((c - 70, c - 70, c + 70, c + 70), outline=dark, width=5)
    for i in range(6):                                     # spokes' bolts
        a = i * math.pi / 3 + math.pi / 6
        x, y = c + 56 * math.cos(a), c + 56 * math.sin(a)
        d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=dark)
    if king:
        d.ellipse((c - 40, c - 40, c + 40, c + 40), fill=teal, outline=dark, width=5)
        crown(d, c, c + 4, gold=(236, 120, 200, 255), dark=(100, 30, 80, 255))
    else:
        d.ellipse((c - 40, c - 40, c + 40, c + 40), fill=teal, outline=dark, width=5)
        d.ellipse((c - 15, c - 15, c + 15, c + 15), fill=dark)
    shine(img, alpha=80)
    return soft_shadow(img)


SETS = {
    "BoardPiecesFaction": {
        # Alliance: royal blue with gold trim; Horde: blood red edged in black iron
        "first": dict(fill=(28, 56, 140), top=(78, 118, 210), edge=(232, 190, 70, 255), trim=(30, 36, 70, 255)),
        "second": dict(fill=(110, 16, 12), top=(196, 40, 28), edge=(24, 18, 16, 255), trim=(150, 120, 90, 255)),
        "checkers": [banner_disc((36, 66, 150, 255), (210, 170, 60, 255), (240, 205, 100, 255), False),
                     banner_disc((36, 66, 150, 255), (210, 170, 60, 255), (240, 205, 100, 255), True),
                     banner_disc((168, 28, 22, 255), (28, 20, 18, 255), (90, 70, 60, 255), False),
                     banner_disc((168, 28, 22, 255), (28, 20, 18, 255), (90, 70, 60, 255), True)],
        "squares": ((196, 188, 168), (74, 76, 84)),
    },
    "BoardPiecesGoblin": {
        # Gnomes: polished steel trimmed in pink; Goblins: goblin green edged in rusty bronze
        "first": dict(fill=(140, 150, 164), top=(222, 228, 236), edge=(196, 56, 150, 255), trim=(40, 46, 56, 255)),
        "second": dict(fill=(44, 102, 30), top=(120, 190, 70), edge=(92, 52, 20, 255), trim=(230, 180, 70, 255)),
        "checkers": [gear(False), gear(True), coin(False), coin(True)],
        "squares": ((214, 182, 118), (92, 66, 44)),
    },
}

if __name__ == "__main__":
    pv = Image.new("RGBA", (16 * 56 + 8, 2 * 2 * 56 + 24), (30, 30, 30, 255))
    for si, (name, spec) in enumerate(SETS.items()):
        imgs = [glyph_piece(g, **spec["first"]) for g in GLYPHS] + \
               [glyph_piece(g, **spec["second"]) for g in GLYPHS] + spec["checkers"]
        atlas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        for i, img in enumerate(imgs):
            atlas.paste(img.resize((CELL, CELL), Image.LANCZOS), ((i % 4) * CELL, (i // 4) * CELL))
        atlas.save(os.path.join(OUT, name + ".tga"))
        light, dark = spec["squares"]
        for i in range(16):
            piece = atlas.crop(((i % 4) * CELL, (i // 4) * CELL, (i % 4) * CELL + CELL, (i // 4) * CELL + CELL))
            piece = piece.resize((48, 48), Image.LANCZOS)
            for j, sq in enumerate((light, dark)):
                tile = Image.new("RGBA", (48, 48), sq + (255,))
                tile.alpha_composite(piece)
                pv.paste(tile, (8 + i * 56, 8 + si * 116 + j * 56))
    pv.save(PREVIEW)
