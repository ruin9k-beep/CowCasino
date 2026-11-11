"""Tauren window art for CowCasino: frame ring + horns, as 1.12-ready TGAs."""
import math, random, sys
from PIL import Image, ImageDraw, ImageFilter
OUT = sys.argv[1]
S = 2                       # draw at 2x, then shrink for smooth edges
FW, FH = 380, 440           # the window
PAD = 10                    # art reaches this far outside the window
RING = PAD + 14             # ring width: outside pad + the window's own 14px margin
W, H = FW + 2 * PAD, FH + 2 * PAD
random.seed(7)

def C(*c): return tuple(c)
OUTLINE = C(20, 11, 6, 255)
RIM     = C(104, 64, 34, 255)
RIM_HI  = C(140, 92, 52, 255)
BAND_BG = C(58, 33, 18, 255)
TURQ    = C(46, 158, 150, 255)
OCHRE   = C(176, 66, 38, 255)
CREAM   = C(226, 204, 158, 255)
HIDE    = C(36, 24, 16, 255)
LACE    = C(196, 160, 104, 255)

def leather(w, h, base, var=10, blur=1.2):
    img = Image.new("RGBA", (w, h), base)
    px = img.load()
    for y in range(h):
        for x in range(w):
            n = random.randint(-var, var)
            r, g, b, a = base
            px[x, y] = (max(0, min(255, r + n)), int(max(0, min(255, g + n * 0.7))), int(max(0, min(255, b + n * 0.5))), a)
    return img.filter(ImageFilter.GaussianBlur(blur))

def frame():
    w, h = W * S, H * S
    img = leather(w, h, RIM, 14)
    d = ImageDraw.Draw(img)
    r = RING * S
    # center hide (behind the menu; game screens cover it with their own felt)
    center = leather(w - 2 * r, h - 2 * r, HIDE, 6, 2)
    img.paste(center, (r, r))
    # outline + rim bevel
    d.rectangle([0, 0, w - 1, h - 1], outline=OUTLINE, width=2 * S)
    d.rectangle([2 * S, 2 * S, w - 1 - 2 * S, h - 1 - 2 * S], outline=RIM_HI, width=1 * S)
    # tribal band, 5..15 px in
    b0, b1 = 5 * S, 15 * S
    band_w = b1 - b0
    for (x0, y0, x1, y1) in [(b0, b0, w - b0, b1), (b0, h - b1, w - b0, h - b0),
                             (b0, b0, b1, h - b0), (w - b1, b0, w - b0, h - b0)]:
        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=BAND_BG)
    d.rectangle([b0, b0, w - b0 - 1, h - b0 - 1], outline=CREAM, width=S)
    d.rectangle([b1 - S, b1 - S, w - b1, h - b1], outline=CREAM, width=S)
    step = band_w * 2
    inner = band_w - 4 * S
    def tri_row(x_from, x_to, y_top, horizontal=True, flip=False):
        k = 0
        x = x_from
        while x + step <= x_to:
            col = TURQ if k % 2 == 0 else OCHRE
            if horizontal:
                y = y_top + 2 * S
                d.polygon([(x, y + inner), (x + step / 2, y), (x + step, y + inner)], fill=col)
                d.polygon([(x + step / 2 - 2 * S, y + inner), (x + step / 2, y + inner - 4 * S), (x + step / 2 + 2 * S, y + inner)], fill=CREAM)
            else:
                xx = y_top + 2 * S
                d.polygon([(xx, x), (xx + inner, x + step / 2), (xx, x + step)], fill=col) if not flip else \
                d.polygon([(xx + inner, x), (xx, x + step / 2), (xx + inner, x + step)], fill=col)
                cx = xx + (inner if not flip else 0)
                dx = -4 * S if not flip else 4 * S
                d.polygon([(cx, x + step / 2 - 2 * S), (cx + dx, x + step / 2), (cx, x + step / 2 + 2 * S)], fill=CREAM)
            x += step; k += 1
    corner = 26 * S
    tri_row(corner, w - corner, b0, True)
    # bottom band points down: draw then flip that strip
    tri_row(corner, w - corner, h - b1, True)
    strip = img.crop((corner, h - b1 + S, w - corner, h - b0 - S)).transpose(Image.FLIP_TOP_BOTTOM)
    img.paste(strip, (corner, h - b1 + S))
    tri_row(corner, h - corner, b0, False, False)
    tri_row(corner, h - corner, w - b1, False, True)
    # laced stitching on the inner rim (16..22 px in)
    s0 = 18 * S
    for x in range(corner, w - corner, 8 * S):
        d.line([(x, s0 - 2 * S), (x + 4 * S, s0 + 2 * S)], fill=LACE, width=S)
        d.line([(x, h - s0 + 2 * S), (x + 4 * S, h - s0 - 2 * S)], fill=LACE, width=S)
    for y in range(corner, h - corner, 8 * S):
        d.line([(s0 - 2 * S, y), (s0 + 2 * S, y + 4 * S)], fill=LACE, width=S)
        d.line([(w - s0 + 2 * S, y), (w - s0 - 2 * S, y + 4 * S)], fill=LACE, width=S)
    # inner edge line
    d.rectangle([r - S, r - S, w - r, h - r], outline=OUTLINE, width=S)
    # corner patches with a bone concho
    for cx, cy in [(0, 0), (w - corner, 0), (0, h - corner), (w - corner, h - corner)]:
        d.rectangle([cx + 2 * S, cy + 2 * S, cx + corner - 2 * S, cy + corner - 2 * S], fill=C(84, 50, 26, 255), outline=OUTLINE, width=S)
        mx, my, rr = cx + corner / 2, cy + corner / 2, 8 * S
        d.ellipse([mx - rr, my - rr, mx + rr, my + rr], fill=CREAM, outline=OUTLINE, width=S)
        d.ellipse([mx - rr / 2, my - rr / 2, mx + rr / 2, my + rr / 2], fill=TURQ, outline=OUTLINE, width=S)
    img = img.resize((W, H), Image.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.paste(img, (0, 0))
    return canvas

def horn():
    # a left horn: rises from the bottom-right of the image, curving out and up
    n = 128 * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = (n * 0.80, n * 0.92)
    pts_out, pts_in = [], []
    steps = 60
    for i in range(steps + 1):
        t = i / steps
        ang = math.radians(200 - 120 * t)        # sweeps left, then up
        rad = n * 0.55
        cx, cy = n * 0.80 - rad * 0.0, n * 0.92 - rad * 0.55
        x = base[0] + (rad * math.cos(ang) + rad) * 0.85 * t * 1.0 - 0
        # parametric curve: out to the left, then curling up at the tip
        x = base[0] - n * 0.62 * math.sin(t * math.pi * 0.62)
        y = base[1] - n * 0.80 * (t ** 1.35)
        thick = n * 0.13 * (1 - t) ** 0.9 + S
        # normal
        t2 = min(1, t + 0.01)
        x2 = base[0] - n * 0.62 * math.sin(t2 * math.pi * 0.62)
        y2 = base[1] - n * 0.80 * (t2 ** 1.35)
        dx, dy = x2 - x, y2 - y
        l = math.hypot(dx, dy) or 1
        nx, ny = -dy / l, dx / l
        pts_out.append((x + nx * thick, y + ny * thick, t))
        pts_in.append((x - nx * thick, y - ny * thick, t))
    # filled in bands so the color runs ivory -> dark tip
    for i in range(steps):
        t = pts_out[i][2]
        if t < 0.55:   col = (232, 218, 186)
        else:
            k = (t - 0.55) / 0.45
            col = (int(232 - 150 * k), int(218 - 160 * k), int(186 - 150 * k))
        poly = [pts_out[i][:2], pts_out[i + 1][:2], pts_in[i + 1][:2], pts_in[i][:2]]
        d.polygon(poly, fill=col + (255,))
    # ridges
    for i in range(4, steps - 8, 6):
        d.line([pts_out[i][:2], pts_in[i][:2]], fill=(150, 128, 96, 255), width=S)
    outline = [p[:2] for p in pts_out] + [p[:2] for p in reversed(pts_in)]
    d.line(outline + [outline[0]], fill=OUTLINE, width=2 * S)
    # leather wrap at the base
    for k in range(3):
        a, b = pts_out[k * 2], pts_in[k * 2]
        d.line([a[:2], b[:2]], fill=(120, 70, 36, 255), width=3 * S)
    return img.resize((128, 128), Image.LANCZOS)

frame().save(OUT + "/TaurenFrame.tga", rle=False)
horn().save(OUT + "/TaurenHorn.tga", rle=False)
print("ok")
