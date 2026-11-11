import sys
from PIL import Image, ImageDraw, ImageFont
D = sys.argv[1]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
faceT = Image.open(f"{D}/TaurenCardFace.tga").crop((0, 0, 92, 128))
backT = Image.open(f"{D}/TaurenCardBack.tga").crop((0, 0, 92, 128))
suits = Image.open(f"{D}/TaurenSuits.tga"); court = Image.open(f"{D}/TaurenCourt.tga")
SUIT = {"S": 0, "H": 1, "D": 2, "C": 3}
RED = (178, 56, 34); DARK = (52, 34, 24)
def icon(sheet, i, size):
    return sheet.crop((i * 64, 0, i * 64 + 64, 64)).resize((size, size), Image.LANCZOS)
def card(rank, suit, w, h, up=True):
    s = h / 64.0
    if not up:
        return backT.resize((w, h), Image.LANCZOS)
    c = faceT.resize((w, h), Image.LANCZOS)
    d = ImageDraw.Draw(c)
    col = RED if suit in "HD" else DARK
    f = ImageFont.truetype(FONT, max(6, round(13 * s)))
    d.text((round(4 * s), round(3 * s)), rank, font=f, fill=col)
    si = max(5, round(10 * s))
    c.alpha_composite(icon(suits, SUIT[suit], si), (round(4.5 * s), round(18 * s)))
    if rank in "JQK":
        e = round(31 * s)
        c.alpha_composite(icon(court, "JQK".index(rank), e), ((w - e) // 2 + round(5 * s), (h - e) // 2 + round(5 * s)))
    else:
        b = round(24 * s)
        c.alpha_composite(icon(suits, SUIT[suit], b), ((w - b) // 2 + round(3 * s), (h - b) // 2 + round(5 * s)))
    return c
row = [("A", "S"), ("10", "H"), ("7", "D"), ("3", "C"), ("J", "C"), ("Q", "H"), ("K", "S"), (None, None)]
felt = (20, 76, 40, 255)
def strip(w, h, gap):
    out = Image.new("RGBA", (len(row) * (w + gap) + gap, h + 2 * gap), felt)
    for i, (r, s) in enumerate(row):
        out.alpha_composite(card(r, s, w, h, r is not None), (gap + i * (w + gap), gap))
    return out
big = strip(46, 64, 6).resize(((len(row) * 52 + 6) * 4, 76 * 4), Image.NEAREST)
small = strip(26, 36, 4).resize(((len(row) * 30 + 4) * 4, 44 * 4), Image.NEAREST)
sheet = Image.new("RGBA", (big.width, big.height + small.height + 30), (30, 30, 30, 255))
sheet.alpha_composite(big, (0, 0)); sheet.alpha_composite(small, (0, big.height + 30))
ImageDraw.Draw(sheet).text((8, big.height + 6), "smallest size (26x36), same zoom", fill=(220, 220, 220), font=ImageFont.truetype(FONT, 16))
sheet.save(sys.argv[2])
