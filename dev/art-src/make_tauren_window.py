"""Tauren window art for CowCasino, painted semi-realistic: the frame ring,
the horns and a carved totem pole down each side, as 1.12-ready TGAs.

Everything is modeled as a height map plus colors and lit from the top left
(round poles and horns, carved faces, raised lacing, domed conchos), drawn
at 4x and shrunk for smooth edges.

    python3 make_tauren_window.py <Art folder> [preview.png]

Writes TaurenFrame.tga (the ring: 400 x 460 art in a 512 x 512 file),
TaurenHorn.tga (128 x 128, the left horn; the game mirrors it) and
TaurenTotemL.tga / TaurenTotemR.tga (64 x 512 each, the art in the top 480).
"""
import math, sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

OUT = sys.argv[1]
PREVIEW = sys.argv[2] if len(sys.argv) > 2 else None
SS = 4                                  # supersampling
FW, FH = 380, 440                       # the window
PAD = 10                                # the ring reaches this far outside it
RING = PAD + 14
W, H = FW + 2 * PAD, FH + 2 * PAD
LIGHT = np.array([-0.55, -0.65, 0.55]); LIGHT = LIGHT / np.linalg.norm(LIGHT)
RNG = np.random.default_rng(7)

TURQ = (46, 158, 150); OCHRE = (176, 66, 38); CREAM = (226, 204, 158); INK = (24, 17, 12)
WOOD = (118, 78, 44); WOOD_DARK = (74, 46, 24); HIDE = (44, 30, 20); LEATHER = (98, 60, 32)
RAWHIDE = (206, 176, 128); BONE = (232, 220, 192)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def noise(h, w, sy, sx, seed):
    """Smooth value noise in -1..1 with features about sy x sx pixels."""
    r = np.random.default_rng(seed)
    gh, gw = max(2, int(h / sy) + 2), max(2, int(w / sx) + 2)
    g = Image.fromarray((r.random((gh, gw)) * 255).astype(np.uint8))
    g = g.resize((w, h), Image.BICUBIC)
    return np.asarray(g, dtype=np.float32) / 127.5 - 1.0


def fbm(h, w, sy, sx, seed, octaves=4):
    out = np.zeros((h, w), np.float32); amp = 1.0; total = 0
    for o in range(octaves):
        out += amp * noise(h, w, max(1, sy / 2 ** o), max(1, sx / 2 ** o), seed + o * 31)
        total += amp; amp *= 0.5
    return out / total


def blur(a, r):
    if r <= 0:
        return a
    return gaussian_filter(a.astype(np.float32), r / 2.0, mode="nearest")


def smooth_step(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def ellipse(X, Y, cx, cy, rx, ry, soft=1.0):
    """1 inside the ellipse, 0 outside, with a soft edge (in pixels)."""
    d = np.sqrt(((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2)
    edge = soft / max(1e-3, min(rx, ry))
    return 1 - smooth_step(1 - edge, 1 + edge, d)


def dome(X, Y, cx, cy, rx, ry):
    """A rounded bump: 1 at the center, 0 at the rim (and outside)."""
    d2 = ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2
    return np.sqrt(np.clip(1 - d2, 0, 1))


def paint(col, layer_color, mask):
    m = mask[..., None]
    return col * (1 - m) + np.array(layer_color, np.float32) * m


def shade(height, color, alpha, gloss=None, ao_r=6, ao_k=0.05, amb=0.42, dif=0.78):
    gy, gx = np.gradient(height)
    n = np.stack([-gx, -gy, np.ones_like(height)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    lam = np.clip((n * LIGHT).sum(-1), 0, 1)
    # a little specular (Blinn, viewer straight on)
    hv = LIGHT + np.array([0, 0, 1.0]); hv /= np.linalg.norm(hv)
    spec = np.clip((n * hv).sum(-1), 0, 1) ** 24
    g = gloss if gloss is not None else 0.15
    ao = np.clip(1 + (height - blur(height, ao_r * SS)) * ao_k, 0.45, 1.12)
    rgb = color * (amb + dif * lam)[..., None] * ao[..., None] + (255 * 0.35 * g * spec)[..., None]
    rgb = np.clip(rgb, 0, 255)
    return np.concatenate([rgb, (np.clip(alpha, 0, 1) * 255)[..., None]], -1).astype(np.uint8)


def finish(rgba, w, h):
    img = Image.fromarray(rgba, "RGBA")
    # shrink with premultiplied alpha so edges don't go dark or light
    a = np.asarray(img, np.float32)
    a[..., :3] *= a[..., 3:4] / 255
    img = Image.fromarray(a.astype(np.uint8), "RGBA").resize((w, h), Image.LANCZOS)
    b = np.asarray(img, np.float32)
    al = b[..., 3:4]
    b[..., :3] = np.where(al > 0, b[..., :3] * 255 / np.maximum(al, 1), 0)
    return Image.fromarray(np.clip(b, 0, 255).astype(np.uint8), "RGBA")


def wood(h, w, seed, along="y"):
    """Wood: grain running along y (or x), with growth rings and pores."""
    if along == "y":
        grain = fbm(h, w, 160 * SS, 3 * SS, seed) * 0.7 + fbm(h, w, 40 * SS, 1.2 * SS, seed + 5) * 0.3
    else:
        grain = fbm(h, w, 3 * SS, 160 * SS, seed) * 0.7 + fbm(h, w, 1.2 * SS, 40 * SS, seed + 5) * 0.3
    rings = np.sin(grain * 18) * 0.5 + 0.5
    pores = fbm(h, w, 0.6 * SS, 0.6 * SS, seed + 9, 2)
    t = np.clip(0.55 + 0.35 * (rings - 0.5) + 0.12 * pores, 0, 1)[..., None]
    col = np.array(WOOD_DARK, np.float32) * (1 - t) + np.array(WOOD, np.float32) * t
    return col, grain


def leather_tex(h, w, base, seed, var=0.16):
    n = fbm(h, w, 6 * SS, 6 * SS, seed) * 0.6 + fbm(h, w, 1.2 * SS, 1.2 * SS, seed + 3, 2) * 0.4
    return np.array(base, np.float32) * (1 + var * n)[..., None], n


def worn(mask, seed, amount=0.35):
    """Paint worn away in patches."""
    n = fbm(mask.shape[0], mask.shape[1], 3 * SS, 3 * SS, seed, 3)
    return mask * smooth_step(-amount - 0.1, -amount + 0.1, n)


# --------------------------------------------------------------------------
# The frame ring
# --------------------------------------------------------------------------
def frame():
    w, h = W * SS, H * SS
    Y, X = np.mgrid[0:h, 0:w].astype(np.float32) / SS          # in 1x pixels
    d = np.minimum(np.minimum(X, Y), np.minimum(W - X, H - Y))  # depth into the ring
    horiz = np.minimum(Y, H - Y) <= np.minimum(X, W - X)        # top/bottom sides
    u = np.where(horiz, X, Y)                                   # along the side
    alpha = np.ones((h, w), np.float32)

    # wooden rim (0..5), grain along each side
    woodH, _ = wood(h, w, 11, "x")
    woodV, _ = wood(h, w, 12, "y")
    col = np.where(horiz[..., None], woodH, woodV)
    height = np.zeros((h, w), np.float32)
    rim = d < 5
    height += np.where(rim, 3.2 * np.sin(np.clip(d / 5, 0, 1) * math.pi) + 1.2, 0)

    # the painted leather band (5..15)
    band = (d >= 5) & (d < 15)
    lcol, ln = leather_tex(h, w, LEATHER, 21)
    col = np.where(band[..., None], lcol, col)
    height += np.where(band, 0.6 + 0.15 * ln, 0)
    step = 20.0
    k = np.floor(u / step)
    f = (u / step - k) - 0.5                       # -0.5..0.5 across one triangle
    tdepth = (d - 6.0) / 7.0                       # 0 at the outer tip, 1 at the base
    tri = band & (tdepth >= 0) & (tdepth <= 1) & (np.abs(f) * 2 < tdepth)
    tri = blur(tri.astype(np.float32), 0.6 * SS)
    notch = band & (tdepth >= 0.55) & (tdepth <= 1) & (np.abs(f) * 2 < (tdepth - 0.55) * 0.9)
    notch = blur(notch.astype(np.float32), 0.5 * SS)
    turq = worn(tri * (k % 2 == 0), 31, 0.45)
    ochre = worn(tri * (k % 2 == 1), 32, 0.45)
    col = paint(col, TURQ, turq * 0.92)
    col = paint(col, OCHRE, ochre * 0.92)
    col = paint(col, CREAM, worn(notch, 33, 0.5) * 0.9)
    height += (turq + ochre) * 0.25
    # cream border lines on both edges of the band
    for edge in (5.4, 14.4):
        line = np.exp(-((d - edge) / 0.45) ** 2) * band
        col = paint(col, CREAM, worn(line, 34, 0.55) * 0.85)
        height += line * 0.3

    # rawhide lacing (15..24): diagonal strands over a dark leather welt
    lace_zone = (d >= 15) & (d < RING)
    dcol, dn = leather_tex(h, w, (70, 42, 22), 41)
    col = np.where(lace_zone[..., None], dcol, col)
    height += np.where(lace_zone, 0.4 + 0.1 * dn, 0)
    phase = np.mod(u - (d - 15) * 1.0, 8.0)
    strand = lace_zone & (d >= 16.5) & (d <= 22.5)
    across = np.abs(phase - 4.0)                    # 0 at the strand's middle
    lace = strand * np.clip(1 - across / 1.6, 0, 1)
    lace_h = np.sqrt(np.clip(1 - (across / 1.6) ** 2, 0, 1)) * strand
    rcol, _ = leather_tex(h, w, RAWHIDE, 43, 0.1)
    col = paint(col, (0, 0, 0), np.zeros_like(lace))  # (keeps shapes)
    col = col * (1 - lace[..., None]) + rcol * lace[..., None]
    height += lace_h * 1.3
    # the inner edge drops to the hide
    height += np.where(lace_zone, -0.8 * smooth_step(22.5, 24, d), 0)

    # center hide (behind the menu; the games cover it with their own felt)
    center = d >= RING
    hcol, hn = leather_tex(h, w, HIDE, 51, 0.22)
    col = np.where(center[..., None], hcol, col)
    height += np.where(center, -1.0 + 0.2 * hn, 0)

    # corner patches with a domed bone concho and a turquoise stone
    corner = 26.0
    for cx0, cy0 in [(0, 0), (W - corner, 0), (0, H - corner), (W - corner, H - corner)]:
        inside = (X >= cx0 + 1.5) & (X <= cx0 + corner - 1.5) & (Y >= cy0 + 1.5) & (Y <= cy0 + corner - 1.5)
        pcol, pn = leather_tex(h, w, (92, 56, 28), 61 + int(cx0 + cy0))
        col = np.where(inside[..., None], pcol, col)
        bevel = np.minimum(np.minimum(X - cx0, cx0 + corner - X), np.minimum(Y - cy0, cy0 + corner - Y))
        height = np.where(inside, 1.6 + 0.8 * smooth_step(1.5, 4, bevel) + 0.1 * pn, height)
        # stitching round the patch
        ring_d = np.abs(bevel - 3.2)
        stitch = inside & (ring_d < 0.5) & (np.mod((X + Y) - cx0 - cy0, 3.0) < 1.6)
        col = paint(col, RAWHIDE, blur(stitch.astype(np.float32), 0.3 * SS))
        mx, my = cx0 + corner / 2, cy0 + corner / 2
        con = ellipse(X, Y, mx, my, 8.6, 8.6, 0.6)
        col = paint(col, BONE, con)
        height += dome(X, Y, mx, my, 8.6, 8.6) * 4.5
        groove = np.exp(-((np.hypot(X - mx, Y - my) - 6.2) / 0.5) ** 2) * con
        col = paint(col, (150, 130, 100), groove * 0.7)
        height -= groove * 0.8
        stone = ellipse(X, Y, mx, my, 4.2, 4.2, 0.5)
        scol = np.array(TURQ, np.float32) * (1 + 0.25 * fbm(h, w, 1.5 * SS, 1.5 * SS, 71, 2))[..., None]
        col = col * (1 - stone[..., None]) + scol * stone[..., None]
        height += dome(X, Y, mx, my, 4.2, 4.2) * 1.8
        col = paint(col, INK, np.exp(-((np.hypot(X - mx, Y - my) - 4.3) / 0.35) ** 2) * 0.8)

    # dark outline round the outside
    out_line = np.exp(-(d / 0.7) ** 2)
    col = paint(col, (16, 10, 6), out_line * 0.9)

    rgba = shade(height * SS, col, alpha, gloss=np.where(lace > 0.2, 0.25, 0.12), ao_r=3, ao_k=0.035)
    img = finish(rgba, W, H)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.paste(img, (0, 0))
    return canvas


# --------------------------------------------------------------------------
# The horn (left; the game mirrors it for the right)
# --------------------------------------------------------------------------
def horn():
    n = 128 * SS
    Hm = np.full((n, n), -1.0, np.float32)     # height (sphere sweep)
    T = np.zeros((n, n), np.float32)           # where along the horn
    A = np.zeros((n, n), np.float32)           # across (-1..1)
    steps = 320
    def curve(t):
        x = n * 0.80 - n * 0.62 * math.sin(t * math.pi * 0.62)
        y = n * 0.92 - n * 0.80 * (t ** 1.35)
        return x, y
    for i in range(steps + 1):
        t = i / steps
        x, y = curve(t)
        r = n * 0.13 * (1 - t) ** 0.9 + SS * 1.2
        x0, x1 = int(max(0, x - r - 2)), int(min(n, x + r + 2))
        y0, y1 = int(max(0, y - r - 2)), int(min(n, y + r + 2))
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        d2 = (xx - x) ** 2 + (yy - y) ** 2
        z = np.sqrt(np.clip(r * r - d2, 0, None))
        z = np.where(d2 <= r * r, z, -1)
        win = z > Hm[y0:y1, x0:x1]
        Hm[y0:y1, x0:x1] = np.where(win, z, Hm[y0:y1, x0:x1])
        T[y0:y1, x0:x1] = np.where(win, t, T[y0:y1, x0:x1])
        # across: which side of the center line
        t2 = min(1, t + 0.004); x2, y2 = curve(t2)
        dx, dy = x2 - x, y2 - y; l = math.hypot(dx, dy) or 1
        side = ((xx - x) * (-dy / l) + (yy - y) * (dx / l)) / r
        A[y0:y1, x0:x1] = np.where(win, side, A[y0:y1, x0:x1])
    alpha = blur((Hm >= 0).astype(np.float32), 0.6 * SS)
    height = np.where(Hm >= 0, Hm, 0)
    # color: ivory at the base, darkening to a black tip, with growth ridges
    k = smooth_step(0.35, 0.98, T)[..., None]
    base = np.array((214, 194, 150), np.float32) * (1 - k) + np.array((46, 36, 28), np.float32) * k
    streak = fbm(n, n, 2 * SS, 2 * SS, 81, 3)
    col = base * (1 + 0.08 * streak)[..., None]
    ridges = (np.sin(T * 70) * 0.5 + 0.5) * (1 - smooth_step(0.7, 0.95, T))
    col *= (1 - 0.12 * ridges)[..., None]
    height -= ridges * 0.8 * SS
    # leather wrap and a bead band at the base
    wrap = (T < 0.09).astype(np.float32)
    wcol, wn = leather_tex(n, n, (112, 64, 32), 83)
    col = col * (1 - wrap[..., None]) + wcol * wrap[..., None]
    wraps = (np.sin(T * 260) * 0.5 + 0.5) * wrap
    height += wraps * 1.0 * SS
    col *= (1 - 0.25 * (1 - wraps) * wrap)[..., None]
    bead = ((T > 0.095) & (T < 0.115)).astype(np.float32)
    beadcol = np.where((np.sin(A * 9) > 0)[..., None], np.array(TURQ, np.float32), np.array(OCHRE, np.float32))
    col = col * (1 - bead[..., None]) + beadcol * bead[..., None]
    height += bead * 1.2 * SS
    rgba = shade(height, col, alpha, gloss=np.full_like(height, 0.55) * (1 - wrap), ao_r=2, ao_k=0.02, amb=0.3, dif=0.9)
    # a thin dark outline for the small size
    a = rgba[..., 3].astype(np.float32) / 255
    edge = np.clip(a - blur(a, 0.8 * SS) * 0.0, 0, 1)
    rim = np.clip(blur(a, 1.2 * SS) - 0.0, 0, 1)
    dark = (1 - smooth_step(0.55, 0.95, rim)) * (a > 0.05)
    rgba[..., :3] = (rgba[..., :3] * (1 - 0.7 * dark[..., None])).astype(np.uint8)
    return finish(rgba, 128, 128)


# --------------------------------------------------------------------------
# A carved totem pole (left; the right one is the same carving lit the same)
# --------------------------------------------------------------------------
TOTEM_W, TOTEM_H, TEX_H = 64, 480, 512
BODY = 22.0                                     # half width of the pole


def totem_layers():
    w, h = TOTEM_W * SS, TOTEM_H * SS
    Y, X = np.mgrid[0:h, 0:w].astype(np.float32) / SS
    cx = TOTEM_W / 2
    x = X - cx
    col, grain = wood(h, w, 101, "y")
    half = np.full((h, w), BODY, np.float32)     # half width at each height
    relief = np.zeros((h, w), np.float32)
    paints = []                                  # (color, mask)

    def P(color, mask, wear=0.4, seed=0):
        paints.append((color, worn(mask, 200 + seed + len(paints), wear)))

    def band(y0, y1, color=TURQ):
        """A carved ring round the pole between y0 and y1."""
        m = ((Y >= y0) & (Y < y1)).astype(np.float32)
        t = (Y - y0) / (y1 - y0)
        relief[:] += m * (np.sin(np.clip(t, 0, 1) * math.pi) * 2.2 + 0.6)
        half[:] = np.where(m > 0, BODY + 1.5, half)
        groove = np.exp(-((Y - y0) / 0.6) ** 2) + np.exp(-((Y - y1) / 0.6) ** 2)
        relief[:] -= groove * 1.4
        P(color, m * (np.abs(t - 0.5) < 0.28) * 1.0, 0.5)
        # little cream dashes
        P(CREAM, m * (np.abs(t - 0.5) < 0.12) * (np.mod(X, 6) < 2.2), 0.6)

    def eyes(cy, spread, rx, ry, cream_ring=True, seed=0):
        for s in (-1, 1):
            ex = cx + s * spread
            socket = ellipse(X, Y, ex, cy, rx + 1.6, ry + 1.4, 0.7)
            relief[:] -= socket * 1.6
            ball = dome(X, Y, ex, cy, rx, ry)
            relief[:] += ball * 2.4
            if cream_ring:
                P(CREAM, ellipse(X, Y, ex, cy, rx, ry, 0.5) - ellipse(X, Y, ex, cy, rx * 0.62, ry * 0.62, 0.5), 0.3, seed)
            P(INK, ellipse(X, Y, ex + s * 0.3, cy + 0.3, rx * 0.55, ry * 0.6, 0.4), 0.15, seed + 1)

    # 1. the kodo / bull head at the top (0..70), wider, with ears and a snout
    top = 0.0
    head = (Y >= top) & (Y < top + 70)
    hy = Y - top
    widen = 26 + 3 * np.sin(np.clip(hy / 70, 0, 1) * math.pi)
    half[:] = np.where(head, np.minimum(widen, 31.5), half)
    # rounded top
    capr = ellipse(X, Y, cx, top + 14, 27, 14, 1.0)
    half[:] = np.where((hy < 14), np.where(capr > 0.5, 31.5, 0), half)
    relief[:] += ellipse(X, Y, cx, top + 20, 22, 9, 3) * 2.0              # brow ridge
    P(OCHRE, ellipse(X, Y, cx, top + 12, 5, 7, 0.6), 0.35)               # forehead diamond
    P(CREAM, ellipse(X, Y, cx, top + 12, 2.2, 3.2, 0.5), 0.35)
    eyes(top + 27, 10, 3.8, 2.8)
    snout = dome(X, Y, cx, top + 50, 14, 15)
    relief[:] += snout * 6
    P((150, 104, 70), ellipse(X, Y, cx, top + 52, 13, 13, 2) * 0.6, 0.6)
    for s in (-1, 1):
        nos = ellipse(X, Y, cx + s * 5.5, top + 55, 2.6, 3.4, 0.5)
        relief[:] -= nos * 4
        P(INK, nos, 0.1)
        # painted cheek stripes
        for k in range(3):
            P(TURQ if k % 2 == 0 else OCHRE,
              ((np.abs(Y - (top + 36 + k * 5)) < 1.3) & (np.abs(x - s * 20) < 4.5)).astype(np.float32), 0.4)
    relief[:] += ellipse(X, Y, cx, top + 64, 9, 2.5, 1) * 1.2             # mouth line (lip)
    relief[:] -= np.exp(-((Y - (top + 66.5)) / 0.6) ** 2) * (np.abs(x) < 9) * 1.5
    band(70, 78, TURQ)

    # 2. the thunderbird (78..158): round eyes and a big hooked beak
    t0 = 78.0
    eyes(t0 + 20, 9, 5, 4.2)
    for s in (-1, 1):
        brow = ((np.abs(Y - (t0 + 12 - np.abs(x) * 0.15)) < 1.6) & (np.abs(x - s * 9) < 7)).astype(np.float32)
        relief[:] += blur(brow, 0.5 * SS) * 1.5
        P(INK, brow, 0.2)
    beak_top = dome(X, Y, cx, t0 + 40, 7, 16)
    relief[:] += beak_top * 7
    hook = dome(X, Y, cx, t0 + 58, 5, 6)
    relief[:] += hook * 5
    P((214, 160, 60), ellipse(X, Y, cx, t0 + 42, 6.5, 16, 1.2), 0.75)    # yellow beak
    P(INK, ellipse(X, Y, cx, t0 + 60, 4.2, 4, 0.8) * (Y > t0 + 58), 0.2)
    # feathers carved down both sides
    for s in (-1, 1):
        for k in range(4):
            fy = t0 + 34 + k * 10
            fm = ellipse(X, Y, cx + s * 17, fy, 4, 6, 0.8)
            relief[:] += dome(X, Y, cx + s * 17, fy, 4, 6) * 1.8
            P(TURQ if k % 2 == 0 else OCHRE, fm * 0.85, 0.45, k)
            P(INK, (np.abs(x - s * 17) < 0.5) * fm, 0.3)
    band(158, 166, OCHRE)

    # 3. the bear (166..246): heavy brows, round ears, a toothy mouth
    b0 = 166.0
    for s in (-1, 1):
        relief[:] += dome(X, Y, cx + s * 17, b0 + 9, 6, 6) * 2.5          # ears
        P(INK, ellipse(X, Y, cx + s * 17, b0 + 9, 3, 3, 0.6), 0.2)
    relief[:] += ellipse(X, Y, cx, b0 + 25, 19, 4, 2) * 2.2              # brow
    P(INK, ellipse(X, Y, cx, b0 + 25, 18, 2, 0.8), 0.25)
    eyes(b0 + 33, 9, 4, 3)
    relief[:] += dome(X, Y, cx, b0 + 46, 6, 7) * 4                        # nose
    P(INK, ellipse(X, Y, cx, b0 + 49, 4, 2.6, 0.6), 0.15)
    mouth = ellipse(X, Y, cx, b0 + 63, 14, 7, 0.8)
    relief[:] -= mouth * 3.5
    P((120, 26, 22), mouth, 0.25)
    teeth = mouth * ((np.mod(x + 30, 4.4) < 2.6) & ((np.abs(Y - (b0 + 58.5)) < 2.2) | (np.abs(Y - (b0 + 67.5)) < 2.2)))
    relief[:] += teeth * 2.5
    P(CREAM, teeth, 0.15)
    for s in (-1, 1):
        P(TURQ, ((np.abs(x - s * 17) < 2.2) & (Y > b0 + 36) & (Y < b0 + 74)).astype(np.float32), 0.45)
    band(246, 254, TURQ)

    # 4. the tauren face (254..334): long face, painted stripes, nose ring
    f0 = 254.0
    relief[:] += ellipse(X, Y, cx, f0 + 16, 18, 4, 2) * 1.8
    eyes(f0 + 22, 9, 3.6, 2.6)
    relief[:] += dome(X, Y, cx, f0 + 44, 9, 18) * 5                       # long muzzle
    P((168, 120, 80), ellipse(X, Y, cx, f0 + 48, 8, 14, 2) * 0.6, 0.6)
    for s in (-1, 1):
        nos = ellipse(X, Y, cx + s * 3.6, f0 + 55, 1.8, 2.6, 0.5)
        relief[:] -= nos * 3
        P(INK, nos, 0.1)
        for k in range(2):
            P(OCHRE, ((np.abs(Y - (f0 + 30 + k * 6)) < 1.4) & (np.abs(x - s * 15) < 5)).astype(np.float32), 0.4)
    ring = np.exp(-((np.hypot(x, Y - (f0 + 62)) - 3.2) / 0.6) ** 2) * (Y > f0 + 60)
    relief[:] += ring * 2.5
    P((212, 176, 74), ring, 0.0)                                          # brass nose ring
    P(CREAM, ((np.abs(x) < 1.6) & (Y > f0 + 4) & (Y < f0 + 14)).astype(np.float32), 0.4)
    band(334, 342, OCHRE)

    # 5. a plain stretch with carved chevrons (342..432)
    c0 = 342.0
    for k in range(5):
        cy = c0 + 10 + k * 16
        chev = np.abs(Y - (cy + np.abs(x) * 0.45)) < 2.0
        chev = chev & (np.abs(x) < BODY - 2)
        cm = blur(chev.astype(np.float32), 0.5 * SS)
        relief[:] -= cm * 1.6
        P(TURQ if k % 2 == 0 else OCHRE, cm, 0.4, k)

    # 6. the base (432..480): wider, wrapped in leather
    base = Y >= 432
    half[:] = np.where(base, BODY + 3, half)
    wrap = base & (Y < 470)
    wcol, wn = leather_tex(h, w, (108, 62, 30), 131)
    wraps = (np.sin((Y - 432) * 1.4 + x * 0.25) * 0.5 + 0.5)
    relief[:] += np.where(wrap, 1.5 + wraps * 1.2, 0)
    P((40, 26, 16), (wrap & (wraps < 0.2)).astype(np.float32) * 0.6, 0.0)
    feet = Y >= 470
    relief[:] += np.where(feet, 0.5, 0)

    # the pole's shape: round, its outline
    inside = np.abs(x) <= half
    alpha = blur(inside.astype(np.float32), 0.5 * SS)
    xr = np.clip(np.abs(x) / np.maximum(half, 1), 0, 1)
    cyl = np.sqrt(np.clip(1 - xr ** 2, 0, 1)) * half * 0.9
    height = (cyl + relief * (1 - xr ** 4)) * SS
    # colors: wood, the leather wrap, then the paint
    col = np.where(wrap[..., None], wcol, col)
    for color, mask in paints:
        col = paint(col, color, np.clip(mask, 0, 1) * inside * 0.95)
    # dark in the cracks of the grain
    col *= (1 - 0.18 * np.clip(-grain, 0, 1))[..., None]
    return height, col, alpha


def totem(flip):
    height, col, alpha = totem_layers()
    if flip:
        height, col, alpha = height[:, ::-1], col[:, ::-1], alpha[:, ::-1]
    rgba = shade(height, col, alpha, gloss=np.full_like(height, 0.18), ao_r=2.5, ao_k=0.03, amb=0.45)
    # a soft shadow cast down and to the right
    sh = np.zeros_like(alpha)
    sh[4 * SS:, 3 * SS:] = alpha[:-4 * SS, :-3 * SS]
    sh = blur(sh, 3 * SS) * 0.5
    a = rgba[..., 3:4].astype(np.float32) / 255
    out_a = a + sh[..., None] * (1 - a)
    rgb = rgba[..., :3].astype(np.float32) * a / np.maximum(out_a, 1e-4)
    rgba = np.concatenate([rgb, out_a * 255], -1).astype(np.uint8)
    # darken toward the outline so the pole reads at its small size
    a = rgba[..., 3].astype(np.float32) / 255
    rim = blur(a, 1.4 * SS)
    dark = (1 - smooth_step(0.55, 0.98, rim)) * (a > 0.05)
    rgba[..., :3] = (rgba[..., :3] * (1 - 0.55 * dark[..., None])).astype(np.uint8)
    img = finish(rgba, TOTEM_W, TOTEM_H)
    canvas = Image.new("RGBA", (TOTEM_W, TEX_H), (0, 0, 0, 0))
    canvas.paste(img, (0, 0))
    return canvas


if __name__ == "__main__":
    f, hn, tl, tr = frame(), horn(), totem(False), totem(True)
    f.save(OUT + "/TaurenFrame.tga", rle=False)
    hn.save(OUT + "/TaurenHorn.tga", rle=False)
    tl.save(OUT + "/TaurenTotemL.tga", rle=False)
    tr.save(OUT + "/TaurenTotemR.tga", rle=False)
    if PREVIEW:
        # the window as the game puts it together (see MainMenu.lua SkinFrame)
        M = 140
        sheet = Image.new("RGBA", (FW + 2 * M, FH + 2 * M), (24, 28, 34, 255))
        ox, oy = M, M
        hornR = hn.transpose(Image.FLIP_LEFT_RIGHT)
        hs = hn.resize((96, 96), Image.LANCZOS); hrs = hornR.resize((96, 96), Image.LANCZOS)
        sheet.alpha_composite(hs, (ox - 74, oy - 85))
        sheet.alpha_composite(hrs, (ox + FW + 74 - 96, oy - 85))
        sheet.alpha_composite(f.crop((0, 0, W, H)), (ox - PAD, oy - PAD))
        from_top = 18
        sheet.alpha_composite(tl, (ox - 8 - TOTEM_W // 2, oy - from_top))
        sheet.alpha_composite(tr, (ox + FW + 8 - TOTEM_W // 2, oy - from_top))
        sheet.save(PREVIEW)
    print("ok")
