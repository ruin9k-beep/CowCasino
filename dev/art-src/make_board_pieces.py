# Pieces for Chess and Checkers, in one 256x256 atlas of 64x64 cells
# (32-bit TGA, so it works on 1.12 and WoW Forever):
#   row 1: white  K Q R B N P     row 2: black  K Q R B N P
#   row 3: checkers  black man, black king, red man, red king
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


if __name__ == "__main__":
    atlas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    for row, items in enumerate(cells()):
        for col, img in enumerate(items):
            small = img.resize((CELL, CELL), Image.LANCZOS)
            # chess rows hold 6 pieces: 4 per atlas row, so they wrap
            idx = row * 6 + col if row < 2 else 12 + col
            atlas.paste(small, ((idx % 4) * CELL, (idx // 4) * CELL))
    atlas.save(os.path.join(OUT, "BoardPieces.tga"))
    # preview: on light and dark squares
    pv = Image.new("RGBA", (16 * 72 + 8, 160), (30, 30, 30, 255))
    for i in range(16):
        piece = atlas.crop(((i % 4) * CELL, (i // 4) * CELL, (i % 4) * CELL + CELL, (i // 4) * CELL + CELL))
        for j, sq in enumerate(((232, 214, 176, 255), (120, 82, 50, 255))):
            tile = Image.new("RGBA", (64, 64), sq)
            tile.alpha_composite(piece)
            pv.paste(tile, (8 + i * 72, 8 + j * 72))
    pv.save(PREVIEW)
