# Pieces for Chess, Checkers and Battleship, in one 256x512 atlas of 64x64
# cells, 4 across (32-bit TGA, so it works on 1.12 and WoW Forever):
#   cells 0-5: white  K Q R B N P     cells 6-11: black  K Q R B N P
#   cells 12-15: checkers  black man, black king, red man, red king
#   cells 16-21: ship parts  end left, end right, end top, end bottom,
#                middle (across), middle (down)
#   cells 22-23: a miss (a splash), a hit (a burst of fire)
# The chess shapes are DejaVu Sans's chess glyphs, filled and outlined.
#   python3 make_board_pieces.py <Art folder> <preview.png>
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import sys, os

CELL, BIG = 64, 256           # drawn at 256, shrunk to 64
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
OUT, PREVIEW = sys.argv[1], sys.argv[2]

GLYPHS = "♚♛♜♝♞♟"   # filled K Q R B N P


def soft_shadow(img, alpha=120, blur=6, off=(5, 8)):
    a = img.split()[3]
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh.putalpha(a.point(lambda v: v * alpha // 255))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(sh, off)
    out.alpha_composite(img)
    return out


def chess_piece(glyph, white):
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(SANS, 200)
    l, t, r, b = d.textbbox((0, 0), glyph, font=f)
    x = (BIG - (r - l)) / 2 - l
    y = (BIG - (b - t)) / 2 - t + 4
    if white:
        fill, edge = (246, 240, 222, 255), (35, 28, 22, 255)
    else:
        fill, edge = (38, 34, 32, 255), (205, 196, 178, 255)
    d.text((x, y), glyph, font=f, fill=fill, stroke_width=9, stroke_fill=edge)
    d.text((x, y), glyph, font=f, fill=fill)
    if white:
        # a touch of shading low on the ivory pieces
        shade = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shade)
        for i in range(60):
            sd.line((0, BIG - 70 + i, BIG, BIG - 70 + i), fill=(120, 95, 60, i))
        mask = Image.new("L", (BIG, BIG), 0)
        ImageDraw.Draw(mask).text((x, y), glyph, font=f, fill=255)
        img.paste(Image.alpha_composite(img, shade), (0, 0), mask)
    return soft_shadow(img)


def disc(base, rim, king):
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c, R = BIG / 2, 104
    d.ellipse((c - R, c - R + 10, c + R, c + R + 10), fill=rim)              # the edge, seen low
    d.ellipse((c - R, c - R, c + R, c + R), fill=base, outline=rim, width=6)
    for k, rr in enumerate((80, 56)):                                       # ridges
        d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=rim, width=5)
    hi = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))                        # highlight
    ImageDraw.Draw(hi).ellipse((c - 70, c - 88, c + 20, c - 30), fill=(255, 255, 255, 60))
    img.alpha_composite(hi.filter(ImageFilter.GaussianBlur(10)))
    if king:
        gold, dark = (232, 190, 70, 255), (110, 78, 20, 255)
        pts = [(c - 52, c + 28), (c - 58, c - 30), (c - 26, c), (c, c - 46), (c + 26, c), (c + 58, c - 30), (c + 52, c + 28)]
        d.polygon(pts, fill=gold, outline=dark, width=5)
        d.rectangle((c - 52, c + 24, c + 52, c + 40), fill=gold, outline=dark, width=5)
        for px, py in ((c - 58, c - 30), (c, c - 46), (c + 58, c - 30)):
            d.ellipse((px - 9, py - 9, px + 9, py + 9), fill=gold, outline=dark, width=3)
    return soft_shadow(img)


def cells():
    out = []
    for white in (True, False):
        out.append([chess_piece(g, white) for g in GLYPHS])
    out.append([disc((40, 38, 36, 255), (12, 10, 10, 255), False), disc((40, 38, 36, 255), (12, 10, 10, 255), True),
                disc((190, 30, 28, 255), (90, 10, 10, 255), False), disc((190, 30, 28, 255), (90, 10, 10, 255), True)])
    return out


HULL, DECK, EDGE = (128, 136, 146, 255), (96, 104, 114, 255), (40, 44, 50, 255)


def ship_part(kind):
    """A slice of a gray warship; neighbors join edge to edge into one hull."""
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = 150                                     # the hull's breadth
    a, b = (BIG - w) / 2, (BIG + w) / 2
    across = kind in ("left", "right", "mid_h")
    if kind == "mid_h":
        d.rectangle((0, a, BIG, b), fill=HULL)
        d.line((0, a, BIG, a), fill=EDGE, width=8); d.line((0, b, BIG, b), fill=EDGE, width=8)
    elif kind == "mid_v":
        d.rectangle((a, 0, b, BIG), fill=HULL)
        d.line((a, 0, a, BIG), fill=EDGE, width=8); d.line((b, 0, b, BIG), fill=EDGE, width=8)
    else:
        # a pointed bow at the open end, flat where it joins the next part
        tip = 24
        if kind == "left":
            pts = [(BIG, a), (110, a), (tip, BIG / 2), (110, b), (BIG, b)]
        elif kind == "right":
            pts = [(0, a), (BIG - 110, a), (BIG - tip, BIG / 2), (BIG - 110, b), (0, b)]
        elif kind == "top":
            pts = [(a, BIG), (a, 110), (BIG / 2, tip), (b, 110), (b, BIG)]
        else:
            pts = [(a, 0), (a, BIG - 110), (BIG / 2, BIG - tip), (b, BIG - 110), (b, 0)]
        d.polygon(pts, fill=HULL)
        d.line(pts, fill=EDGE, width=8)
    # a deck stripe and rivets down the middle
    if across:
        d.rectangle((0 if kind != "left" else 120, BIG / 2 - 14, BIG if kind != "right" else BIG - 120, BIG / 2 + 14), fill=DECK)
        for x in range(32, BIG, 64):
            if (kind == "left" and x < 120) or (kind == "right" and x > BIG - 120):
                continue
            d.ellipse((x - 7, a + 18, x + 7, a + 32), fill=EDGE)
            d.ellipse((x - 7, b - 32, x + 7, b - 18), fill=EDGE)
    else:
        d.rectangle((BIG / 2 - 14, 0 if kind != "top" else 120, BIG / 2 + 14, BIG if kind != "bottom" else BIG - 120), fill=DECK)
        for y in range(32, BIG, 64):
            if (kind == "top" and y < 120) or (kind == "bottom" and y > BIG - 120):
                continue
            d.ellipse((a + 18, y - 7, a + 32, y + 7), fill=EDGE)
            d.ellipse((b - 32, y - 7, b - 18, y + 7), fill=EDGE)
    if kind in ("mid_h", "mid_v"):
        # a gun turret on the middle parts
        d.ellipse((BIG / 2 - 34, BIG / 2 - 34, BIG / 2 + 34, BIG / 2 + 34), fill=(110, 118, 128, 255), outline=EDGE, width=7)
    return img


def miss_marker():
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = BIG / 2
    d.ellipse((c - 70, c - 70, c + 70, c + 70), outline=(235, 245, 255, 230), width=14)
    d.ellipse((c - 26, c - 26, c + 26, c + 26), fill=(235, 245, 255, 240))
    for dx, dy in ((-92, -40), (88, -52), (-60, 86), (70, 80), (0, -100)):
        d.ellipse((c + dx - 11, c + dy - 11, c + dx + 11, c + dy + 11), fill=(200, 225, 255, 210))
    return img


def hit_marker():
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = BIG / 2
    import math as _m
    def star(r1, r2, n, fill, rot=0):
        pts = []
        for i in range(n * 2):
            r = r1 if i % 2 == 0 else r2
            ang = rot + i * _m.pi / n
            pts.append((c + r * _m.cos(ang), c + r * _m.sin(ang)))
        d.polygon(pts, fill=fill)
    star(112, 52, 9, (190, 20, 10, 255))
    star(84, 40, 9, (255, 110, 20, 255), rot=0.3)
    star(52, 24, 7, (255, 220, 70, 255), rot=0.1)
    return soft_shadow(img, alpha=90)


if __name__ == "__main__":
    atlas = Image.new("RGBA", (256, 512), (0, 0, 0, 0))
    for row, items in enumerate(cells()):
        for col, img in enumerate(items):
            small = img.resize((CELL, CELL), Image.LANCZOS)
            # chess rows hold 6 pieces: 4 per atlas row, so they wrap
            idx = row * 6 + col if row < 2 else 12 + col
            atlas.paste(small, ((idx % 4) * CELL, (idx // 4) * CELL))
    extra = [ship_part(k) for k in ("left", "right", "top", "bottom", "mid_h", "mid_v")] + [miss_marker(), hit_marker()]
    for i, img in enumerate(extra):
        idx = 16 + i
        atlas.paste(img.resize((CELL, CELL), Image.LANCZOS), ((idx % 4) * CELL, (idx // 4) * CELL))
    atlas.save(os.path.join(OUT, "BoardPieces.tga"))
    # preview: on light and dark squares
    pv = Image.new("RGBA", (24 * 72 + 8, 160), (30, 30, 30, 255))
    for i in range(24):
        piece = atlas.crop(((i % 4) * CELL, (i // 4) * CELL, (i % 4) * CELL + CELL, (i // 4) * CELL + CELL))
        for j, sq in enumerate(((232, 214, 176, 255), (40, 80, 130, 255))):
            tile = Image.new("RGBA", (64, 64), sq)
            tile.alpha_composite(piece)
            pv.paste(tile, (8 + i * 72, 8 + j * 72))
    pv.save(PREVIEW)
