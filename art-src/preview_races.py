import sys
from PIL import Image, ImageDraw, ImageFont
D = sys.argv[1]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def load(name): return Image.open(f"{D}/{name}.tga")
face, back = load("OrcCardFace").crop((0, 0, 92, 128)), load("OrcCardBack").crop((0, 0, 92, 128))
suits, court = load("OrcSuits"), load("OrcCourt")
hback = load("HumanCardBack").crop((0, 0, 92, 128))
SUIT = {"S": 0, "H": 1, "D": 2, "C": 3}
RED, DARK = (150, 26, 20), (38, 30, 26)
def icon(sheet, i, size): return sheet.crop((i * 64, 0, i * 64 + 64, 64)).resize((size, size), Image.LANCZOS)
def orc_card(rank, suit, w, h):
    s = h / 64.0
    if rank is None: return back.resize((w, h), Image.LANCZOS)
    c = face.resize((w, h), Image.LANCZOS); d = ImageDraw.Draw(c)
    col = RED if suit in "HD" else DARK
    d.text((round(4 * s), round(3 * s)), rank, font=ImageFont.truetype(FONT, max(6, round(13 * s))), fill=col)
    c.alpha_composite(icon(suits, SUIT[suit], max(5, round(10 * s))), (round(4.5 * s), round(18 * s)))
    if rank in "JQK":
        e = round(31 * s); c.alpha_composite(icon(court, "JQK".index(rank), e), ((w - e) // 2 + round(5 * s), (h - e) // 2 + round(5 * s)))
    else:
        b = round(24 * s); c.alpha_composite(icon(suits, SUIT[suit], b), ((w - b) // 2 + round(3 * s), (h - b) // 2 + round(5 * s)))
    return c
def plain_card(rank, suit, w, h):
    # approximation of the code-drawn Plain face, for the Human deck
    s = h / 70.0
    if rank is None: return hback.resize((w, h), Image.LANCZOS)
    c = Image.new("RGBA", (w, h), (0, 0, 0, 255)); d = ImageDraw.Draw(c)
    d.rectangle([1, 1, w - 2, h - 2], fill=(247, 247, 240))
    col = (204, 26, 26) if suit in "HD" else (26, 26, 26)
    sym = {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}[suit]
    d.text((round(4 * s), round(4 * s)), rank, font=ImageFont.truetype(SANS, max(6, round(14 * s))), fill=col)
    d.text((round(4 * s), round(20 * s)), sym, font=ImageFont.truetype(SANS, max(6, round(12 * s))), fill=col)
    f = ImageFont.truetype(SANS, round(30 * s)); d.text((w // 2 - round(9 * s), h // 2 - round(14 * s)), sym, font=f, fill=col)
    return c
row = [("A", "S"), ("10", "H"), ("7", "D"), ("3", "C"), ("J", "C"), ("Q", "H"), ("K", "S"), (None, None)]
felt = (20, 76, 40, 255)
def strip(fn, w, h, gap, cards):
    out = Image.new("RGBA", (len(cards) * (w + gap) + gap, h + 2 * gap), felt)
    for i, (r, s) in enumerate(cards): out.alpha_composite(fn(r, s, w, h), (gap + i * (w + gap), gap))
    return out
Z = 4
orc = strip(orc_card, 46, 64, 6, row).resize(((8 * 52 + 6) * Z, 76 * Z), Image.NEAREST)
orc_small = strip(orc_card, 26, 36, 4, row).resize(((8 * 30 + 4) * Z, 44 * Z), Image.NEAREST)
hum = strip(plain_card, 46, 64, 6, [("A", "S"), ("Q", "H"), (None, None), (None, None)]).resize(((4 * 52 + 6) * Z, 76 * Z), Image.NEAREST)
big = Image.new("RGBA", (2 * 184 + 3 * 20, 256 + 40), felt)
big.alpha_composite(hback.resize((184, 256), Image.LANCZOS), (20, 20)); big.alpha_composite(back.resize((184, 256), Image.LANCZOS), (224, 20))
big = big.resize((big.width * 2, big.height * 2), Image.LANCZOS)
font = ImageFont.truetype(SANS, 22)
H = orc.height + orc_small.height + hum.height + big.height + 4 * 40
sheet = Image.new("RGBA", (max(orc.width, big.width), H), (30, 30, 30, 255)); d = ImageDraw.Draw(sheet)
y = 0
for label, img in (("Orc & Troll deck, in-game size (x4)", orc), ("...at the smallest size (26x36)", orc_small),
                   ("Human: Plain faces with the new back (x4)", hum), ("The two backs, larger", big)):
    d.text((10, y + 8), label, fill=(230, 230, 230), font=font); y += 40
    sheet.alpha_composite(img, (0, y)); y += img.height
sheet.save(sys.argv[2])
