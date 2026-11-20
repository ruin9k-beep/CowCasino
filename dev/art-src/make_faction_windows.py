# Horde and Alliance window frames (MainMenu.lua, ns:SkinFrame), in the same
# footprint as TaurenFrame.tga and ModernFrame.tga: the window is 436 x 440,
# painted with 10 px around it, in the top-left of a 512 x 512 32-bit TGA.
# Colors and materials only; no faction emblems.
#   Horde:    dark iron, studs, angled corner plates, a crimson title band
#   Alliance: deep navy, double gold trim with corner ornaments, a royal blue band
#   python3 make_faction_windows.py <Art folder> <preview.png>
from PIL import Image, ImageDraw, ImageFilter
import sys, os, random

OUT, PREVIEW = sys.argv[1], sys.argv[2]
S = 4
W, H, PAD = 436, 440, 10
BAND = 34


def P(v):                      # window units to drawing pixels (0 at the window's corner)
    return (v + PAD) * S


def gradient(draw, x0, y0, x1, y1, top, bottom, alpha=255):
    for y in range(int(P(y0)), int(P(y1))):
        t = (y - P(y0)) / max(1, P(y1) - P(y0))
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (alpha,)
        draw.line([(P(x0), y), (P(x1) - 1, y)], fill=c)


def noise(img, amount, seed):
    random.seed(seed)
    n = Image.new("RGBA", img.size, (0, 0, 0, 0))
    px = n.load()
    for _ in range(img.size[0] * img.size[1] // 9):
        x, y = random.randrange(img.size[0]), random.randrange(img.size[1])
        v = random.randint(0, amount)
        px[x, y] = (255, 255, 255, v) if random.random() < 0.5 else (0, 0, 0, v)
    return n.filter(ImageFilter.GaussianBlur(1.2))


def shadow(img, radius):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([P(0), P(2), P(W) - 1, P(H + 2) - 1], radius=radius * S, fill=(0, 0, 0, 180))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(5 * S)))


def stud(d, cx, cy, r, base, hi, lo):
    d.ellipse([cx - r - S, cy - r + S, cx + r + S, cy + r + 2 * S], fill=(0, 0, 0, 160))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=base, outline=lo, width=S)
    d.ellipse([cx - r * 0.55, cy - r * 0.65, cx + r * 0.1, cy - r * 0.05], fill=hi)


def finish(big, name):
    art = big.resize((W + 2 * PAD, H + 2 * PAD), Image.LANCZOS)
    out = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    out.paste(art, (0, 0))
    out.save(os.path.join(OUT, name))
    return art


def horde():
    big = Image.new("RGBA", (P(W + PAD), P(H + PAD)), (0, 0, 0, 0))
    shadow(big, 4)
    panel = Image.new("RGBA", big.size, (0, 0, 0, 0))
    pd = ImageDraw.Draw(panel)
    gradient(pd, 0, 0, W, H, (40, 30, 25), (17, 13, 11))
    gradient(pd, 0, 0, W, BAND, (138, 24, 18), (84, 13, 10))
    panel.alpha_composite(noise(panel, 26, 7))
    mask = Image.new("L", big.size, 0)
    md = ImageDraw.Draw(mask)
    # angled corners: the window's outline with its corners clipped
    c = 14
    outline = [(P(c), P(0)), (P(W - c), P(0)), (P(W), P(c)), (P(W), P(H - c)), (P(W - c), P(H)), (P(c), P(H)), (P(0), P(H - c)), (P(0), P(c))]
    md.polygon(outline, fill=255)
    big.paste(panel, (0, 0), mask)
    d = ImageDraw.Draw(big)
    iron, ironHi, ironLo = (78, 72, 68, 255), (150, 140, 128, 255), (26, 22, 20, 255)
    # the iron rim: a thick band round the edge, beveled
    d.line(outline + [outline[0]], fill=ironLo, width=9 * S, joint="curve")
    d.line(outline + [outline[0]], fill=iron, width=6 * S, joint="curve")
    inner = [(P(c + 2), P(3)), (P(W - c - 2), P(3)), (P(W - 3), P(c + 2)), (P(W - 3), P(H - c - 2)), (P(W - c - 2), P(H - 3)), (P(c + 2), P(H - 3)), (P(3), P(H - c - 2)), (P(3), P(c + 2))]
    d.line(inner + [inner[0]], fill=(110, 102, 96, 200), width=S)
    # a dark iron bar under the title band
    d.rectangle([P(3), P(BAND - 1), P(W - 3), P(BAND + 3)], fill=ironLo)
    d.rectangle([P(3), P(BAND), P(W - 3), P(BAND + 2)], fill=iron)
    # studs along the rim and the bar
    for x in range(28, W - 20, 34):
        stud(d, P(x), P(1.5), 2.6 * S, iron, ironHi, ironLo)
        stud(d, P(x), P(H - 1.5), 2.6 * S, iron, ironHi, ironLo)
        stud(d, P(x), P(BAND + 1), 2.2 * S, iron, ironHi, ironLo)
    for y in range(BAND + 30, H - 20, 34):
        stud(d, P(1.5), P(y), 2.6 * S, iron, ironHi, ironLo)
        stud(d, P(W - 1.5), P(y), 2.6 * S, iron, ironHi, ironLo)
    # corner plates with a spike pointing out
    for (cx, cy, sx, sy) in ((0, 0, -1, -1), (W, 0, 1, -1), (0, H, -1, 1), (W, H, 1, 1)):
        plate = [(P(cx), P(cy - sy * 22)), (P(cx - sx * 22), P(cy)), (P(cx + sx * 5), P(cy + sy * 5))]
        spike = [(P(cx - sx * 6), P(cy - sy * 0)), (P(cx + sx * 8), P(cy + sy * 8)), (P(cx - sx * 0), P(cy - sy * 6))]
        d.polygon(plate, fill=ironLo)
        d.polygon([(x + (S if sx < 0 else -S), y + (S if sy < 0 else -S)) for x, y in plate], fill=iron)
        d.polygon(spike, fill=(190, 182, 170, 255), outline=ironLo)
        stud(d, P(cx - sx * 9), P(cy - sy * 9), 2.4 * S, iron, ironHi, ironLo)
    return finish(big, "HordeFrame.tga")


def alliance():
    big = Image.new("RGBA", (P(W + PAD), P(H + PAD)), (0, 0, 0, 0))
    shadow(big, 8)
    panel = Image.new("RGBA", big.size, (0, 0, 0, 0))
    pd = ImageDraw.Draw(panel)
    gradient(pd, 0, 0, W, H, (26, 36, 62), (11, 15, 29))
    gradient(pd, 0, 0, W, BAND, (44, 78, 156), (27, 48, 104))
    panel.alpha_composite(noise(panel, 12, 11))
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([P(0), P(0), P(W) - 1, P(H) - 1], radius=8 * S, fill=255)
    big.paste(panel, (0, 0), mask)
    d = ImageDraw.Draw(big)
    gold, goldHi, goldLo = (214, 172, 62, 255), (255, 228, 140, 255), (120, 86, 24, 255)
    # double gold trim
    d.rounded_rectangle([P(0), P(0), P(W) - 1, P(H) - 1], radius=8 * S, outline=goldLo, width=4 * S)
    d.rounded_rectangle([P(0.5), P(0.5), P(W - 0.5) - 1, P(H - 0.5) - 1], radius=8 * S, outline=gold, width=2 * S)
    d.rounded_rectangle([P(4), P(4), P(W - 4) - 1, P(H - 4) - 1], radius=5 * S, outline=(214, 172, 62, 150), width=S)
    # a gold rule under the title band, with a small diamond in the middle
    d.rectangle([P(4), P(BAND), P(W - 4), P(BAND + 1.4)], fill=gold)
    m = W / 2
    d.polygon([(P(m), P(BAND - 4)), (P(m + 6), P(BAND + 0.7)), (P(m), P(BAND + 5.4)), (P(m - 6), P(BAND + 0.7))], fill=gold, outline=goldLo)
    d.polygon([(P(m), P(BAND - 2)), (P(m + 3), P(BAND + 0.7)), (P(m), P(BAND + 3.4)), (P(m - 3), P(BAND + 0.7))], fill=(44, 78, 156, 255))
    # corner ornaments: a gold quarter-ring and a diamond in each corner
    for (cx, cy, sx, sy) in ((0, 0, 1, 1), (W, 0, -1, 1), (0, H, 1, -1), (W, H, -1, -1)):
        x0, y0 = P(cx + sx * 2), P(cy + sy * 2)
        r = 18 * S
        box = [min(x0, x0 + sx * 2 * r), min(y0, y0 + sy * 2 * r), max(x0, x0 + sx * 2 * r), max(y0, y0 + sy * 2 * r)]
        start = { (1, 1): 180, (-1, 1): 270, (1, -1): 90, (-1, -1): 0 }[(sx, sy)]
        d.arc(box, start, start + 90, fill=goldLo, width=3 * S)
        d.arc(box, start, start + 90, fill=gold, width=2 * S)
        dx, dy = P(cx + sx * 9), P(cy + sy * 9)
        dd = 5 * S
        d.polygon([(dx, dy - dd), (dx + dd, dy), (dx, dy + dd), (dx - dd, dy)], fill=gold, outline=goldLo)
        d.ellipse([dx - 1.5 * S, dy - 1.5 * S, dx + 1.5 * S, dy + 1.5 * S], fill=goldHi)
    return finish(big, "AllianceFrame.tga")


if __name__ == "__main__":
    h, a = horde(), alliance()
    pv = Image.new("RGBA", (2 * (W + 2 * PAD) + 60, H + 2 * PAD + 40), (70, 90, 70, 255))
    pv.alpha_composite(h, (20, 20))
    pv.alpha_composite(a, (W + 2 * PAD + 40, 20))
    pv.save(PREVIEW)
