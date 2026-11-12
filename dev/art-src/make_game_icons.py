# Menu icons for every CowCasino game but Craps (make_craps_icon.py), painted
# in the same style: a scene on a colored backdrop inside a WoW-style icon
# frame. Each is 64x64, 32-bit TGA, so it works on 1.12 and WoW Forever.
#   python3 make_game_icons.py <Art folder> <preview.png>
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import sys, math, os

S = 512
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
OUT, PREVIEW = sys.argv[1], sys.argv[2]

RED = (175, 22, 22, 255)
INK = (25, 22, 20, 255)
IVORY = (246, 240, 222, 255)
GOLD = (222, 178, 64, 255)
DARKGOLD = (120, 86, 24, 255)


def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def backdrop(inner, outer):
    img = Image.new("RGBA", (S, S), outer)
    d = ImageDraw.Draw(img)
    for r in range(int(S * 0.75), 0, -2):
        d.ellipse((S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r), fill=lerp(inner, outer, r / (S * 0.75)))
    return img


def shadow(img, shape_fn, off=(14, 20), blur=14, alpha=150):
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shape_fn(ImageDraw.Draw(sh), off, (0, 0, 0, alpha))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)))


def frame(img):
    fr = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fr)
    for i in range(26):
        t = i / 25
        fd.rectangle((i, i, S - 1 - i, S - 1 - i),
                     outline=lerp((40, 28, 12, 255), (150, 118, 52, 0), t) if i > 3 else (20, 14, 6, 255))
    img.alpha_composite(fr)
    return img


def rotated_card(img, cx, cy, w, h, angle, rank, suit, color):
    card = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle((20, 20, 20 + w, 20 + h), radius=int(w * 0.12), fill=IVORY, outline=(90, 80, 60, 255), width=5)
    f = ImageFont.truetype(SERIF, int(h * 0.26))
    cd.text((20 + w * 0.12, 20 + h * 0.05), rank, font=f, fill=color)
    fs = ImageFont.truetype(SERIF, int(h * 0.20))
    cd.text((20 + w * 0.13, 20 + h * 0.31), suit, font=fs, fill=color)
    fb = ImageFont.truetype(SERIF, int(h * 0.48))
    tw = cd.textlength(suit, font=fb)
    cd.text((20 + w * 0.58 - tw / 2, 20 + h * 0.40), suit, font=fb, fill=color)
    card = card.rotate(angle, resample=Image.BICUBIC, expand=True)
    sh = Image.new("RGBA", card.size, (0, 0, 0, 0))
    sh.putalpha(card.getchannel("A").point(lambda a: int(a * 0.6)))
    sh = sh.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(sh, (int(cx - card.width / 2 + 12), int(cy - card.height / 2 + 16)))
    img.alpha_composite(card, (int(cx - card.width / 2), int(cy - card.height / 2)))


def chip(d, cx, cy, r, color, edge=(240, 235, 225, 255)):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color, outline=(30, 20, 10, 255), width=4)
    for k in range(8):
        a = k * math.pi / 4
        x, y = cx + math.cos(a) * r * 0.82, cy + math.sin(a) * r * 0.82
        d.ellipse((x - r * 0.12, y - r * 0.12, x + r * 0.12, y + r * 0.12), fill=edge)
    d.ellipse((cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55), outline=edge, width=4)


def chip_stack(img, cx, base_y, r, n, color):
    d = ImageDraw.Draw(img)
    shadow(img, lambda sd, o, c: sd.ellipse((cx - r + o[0], base_y - r * 0.45 + o[1], cx + r + o[0], base_y + r * 0.45 + o[1]), fill=c))
    for k in range(n):
        y = base_y - k * r * 0.22
        d.ellipse((cx - r, y - r * 0.42 + r * 0.16, cx + r, y + r * 0.42 + r * 0.16), fill=lerp(color, (0, 0, 0, 255), 0.45))
        d.ellipse((cx - r, y - r * 0.42, cx + r, y + r * 0.42), fill=color, outline=(30, 20, 10, 255), width=3)
        for j in range(6):
            a = j * math.pi / 3
            x = cx + math.cos(a) * r * 0.85
            yy = y + math.sin(a) * r * 0.36
            d.ellipse((x - r * 0.08, yy - r * 0.05, x + r * 0.08, yy + r * 0.05), fill=(240, 235, 225, 255))


# --- Blackjack: an ace and a king fanned, a blackjack --------------------------
def blackjack():
    img = backdrop((40, 140, 70, 255), (10, 50, 25, 255))
    rotated_card(img, 205, 270, 200, 280, 12, "A", "♠", INK)
    rotated_card(img, 305, 265, 200, 280, -10, "K", "♥", RED)
    return frame(img)


# --- Texas Hold'em: two aces and a stack of chips ------------------------------
def holdem():
    img = backdrop((40, 90, 150, 255), (12, 24, 60, 255))
    rotated_card(img, 190, 225, 170, 240, 14, "A", "♠", INK)
    rotated_card(img, 280, 215, 170, 240, -8, "A", "♦", RED)
    chip_stack(img, 360, 420, 80, 5, (170, 25, 25, 255))
    chip_stack(img, 165, 435, 70, 3, (30, 30, 30, 255))
    return frame(img)


# --- Five-Card Draw: a full house fanned out, five cards ----------------------
def draw():
    img = backdrop((120, 50, 120, 255), (40, 12, 45, 255))
    fan = [("K", "♠", INK), ("K", "♥", RED), ("K", "♣", INK), ("7", "♦", RED), ("7", "♠", INK)]
    for i, (rank, suit, color) in enumerate(fan):
        k = i - 2
        rotated_card(img, 256 + k * 62, 270 + abs(k) * 14, 150, 212, -k * 13, rank, suit, color)
    return frame(img)


# --- Video Poker: a machine screen, five cards, two of them HELD --------------
def videopoker():
    img = backdrop((30, 50, 140, 255), (8, 10, 45, 255))
    d = ImageDraw.Draw(img)
    # the cabinet and its screen
    shadow(img, lambda sd, o, c: sd.rounded_rectangle((52 + o[0], 110 + o[1], 460 + o[0], 410 + o[1]), radius=30, fill=c))
    d.rounded_rectangle((52, 110, 460, 410), radius=30, fill=(170, 135, 55, 255), outline=(60, 45, 15, 255), width=6)
    d.rounded_rectangle((74, 132, 438, 388), radius=16, fill=(10, 20, 110, 255), outline=(20, 15, 5, 255), width=5)
    fan = [("A", "♠", INK), ("A", "♥", RED), ("7", "♣", INK), ("A", "♦", RED), ("3", "♠", INK)]
    for i, (rank, suit, color) in enumerate(fan):
        rotated_card(img, 120 + i * 68, 238, 62, 96, 0, rank, suit, color)
    d = ImageDraw.Draw(img)
    for i in (0, 1, 3):     # HELD bars under the kept cards
        x = 120 + i * 68
        d.rounded_rectangle((x - 30, 312, x + 30, 334), radius=6, fill=(255, 210, 40, 255))
    return frame(img)


# --- Roulette: the wheel from above, with the ball -----------------------------
def roulette():
    img = backdrop((95, 60, 30, 255), (35, 18, 8, 255))
    d = ImageDraw.Draw(img)
    cx, cy, R = 256, 256, 205
    shadow(img, lambda sd, o, c: sd.ellipse((cx - R + o[0], cy - R + o[1], cx + R + o[0], cy + R + o[1]), fill=c))
    d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=(92, 52, 22, 255), outline=(40, 20, 6, 255), width=6)
    r1, r2 = R * 0.88, R * 0.58
    n = 18
    for k in range(n):
        a0, a1 = 360 / n * k - 90, 360 / n * (k + 1) - 90
        col = (20, 140, 50, 255) if k == 0 else ((185, 25, 25, 255) if k % 2 else (25, 22, 22, 255))
        d.pieslice((cx - r1, cy - r1, cx + r1, cy + r1), a0, a1, fill=col, outline=GOLD, width=3)
    d.ellipse((cx - r2, cy - r2, cx + r2, cy + r2), fill=(130, 78, 32, 255), outline=GOLD, width=5)
    for k in range(4):
        a = k * math.pi / 2 + 0.3
        d.line((cx, cy, cx + math.cos(a) * r2 * 0.85, cy + math.sin(a) * r2 * 0.85), fill=GOLD, width=12)
    d.ellipse((cx - 30, cy - 30, cx + 30, cy + 30), fill=GOLD, outline=DARKGOLD, width=4)
    bx, by = cx + math.cos(-0.9) * R * 0.74, cy + math.sin(-0.9) * R * 0.74
    d.ellipse((bx - 20, by - 20, bx + 20, by + 20), fill=(250, 250, 250, 255), outline=(120, 120, 120, 255), width=3)
    d.ellipse((bx - 10, by - 12, bx - 2, by - 4), fill=(255, 255, 255, 255))
    return frame(img)


# --- Slots: a machine window showing three red sevens --------------------------
def slots():
    img = backdrop((150, 40, 110, 255), (40, 8, 30, 255))
    d = ImageDraw.Draw(img)
    shadow(img, lambda sd, o, c: sd.rounded_rectangle((70 + o[0], 120 + o[1], 442 + o[0], 392 + o[1]), radius=36, fill=c))
    d.rounded_rectangle((70, 120, 442, 392), radius=36, fill=GOLD, outline=DARKGOLD, width=8)
    d.rounded_rectangle((100, 160, 412, 352), radius=16, fill=(40, 25, 15, 255))
    f = ImageFont.truetype(SANS, 150)
    for k in range(3):
        x0 = 108 + k * 102
        d.rectangle((x0, 168, x0 + 94, 344), fill=IVORY)
        tw = d.textlength("7", font=f)
        d.text((x0 + 47 - tw / 2 + 4, 182 + 4), "7", font=f, fill=(60, 10, 10, 255))
        d.text((x0 + 47 - tw / 2, 182), "7", font=f, fill=RED)
    d.line((100, 256, 412, 256), fill=(255, 210, 60, 200), width=4)
    # lights on top
    for k in range(5):
        x = 120 + k * 68
        d.ellipse((x - 16, 92, x + 16, 124), fill=(255, 230, 120, 255) if k % 2 == 0 else (255, 120, 60, 255),
                  outline=DARKGOLD, width=3)
    return frame(img)


# --- Mines: a lit bomb on the tiles, with a gem --------------------------------
def mines():
    img = backdrop((70, 80, 110, 255), (16, 18, 30, 255))
    d = ImageDraw.Draw(img)
    for row in range(4):
        for col in range(4):
            x0, y0 = 50 + col * 106, 50 + row * 106
            fill = (30, 80, 45, 255) if (row, col) in ((0, 0), (3, 1), (2, 3)) else (42, 46, 62, 255)
            d.rounded_rectangle((x0, y0, x0 + 96, y0 + 96), radius=10, fill=fill, outline=(95, 100, 125, 255), width=4)
    # gem
    gx, gy = 98, 98
    d.polygon([(gx - 30, gy - 8), (gx - 14, gy - 28), (gx + 14, gy - 28), (gx + 30, gy - 8), (gx, gy + 30)], fill=(90, 210, 240, 255),
              outline=(20, 70, 100, 255))
    d.polygon([(gx - 14, gy - 28), (gx + 14, gy - 28), (gx, gy - 8)], fill=(190, 245, 255, 255))
    # bomb
    cx, cy, r = 280, 300, 135
    shadow(img, lambda sd, o, c: sd.ellipse((cx - r + o[0], cy - r + o[1], cx + r + o[0], cy + r + o[1]), fill=c))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(32, 32, 38, 255), outline=(10, 10, 12, 255), width=6)
    d.ellipse((cx - r * 0.6, cy - r * 0.7, cx - r * 0.05, cy - r * 0.25), fill=(95, 95, 110, 255))
    d.rectangle((cx + r * 0.35, cy - r * 1.05, cx + r * 0.8, cy - r * 0.7), fill=(70, 70, 80, 255), outline=(10, 10, 12, 255), width=4)
    d.line([(cx + r * 0.6, cy - r * 1.05), (cx + r * 0.75, cy - r * 1.35), (cx + r * 1.0, cy - r * 1.45)], fill=(160, 120, 70, 255), width=10)
    sx, sy = cx + r * 1.05, cy - r * 1.5
    for k in range(10):
        a = k * math.pi / 5
        d.line((sx, sy, sx + math.cos(a) * 42, sy + math.sin(a) * 42), fill=(255, 220, 80, 255), width=7)
    d.ellipse((sx - 18, sy - 18, sx + 18, sy + 18), fill=(255, 250, 200, 255))
    return frame(img)


# --- Plinko: pegs, a falling ball and the slots --------------------------------
def plinko():
    img = backdrop((60, 50, 140, 255), (14, 10, 40, 255))
    d = ImageDraw.Draw(img)
    rows, dx, dy = 4, 80, 74
    for r in range(1, rows + 1):
        for k in range(r + 2):
            x = 256 + (k - (r + 1) / 2) * dx
            y = 40 + r * dy
            d.ellipse((x - 15, y - 15, x + 15, y + 15), fill=(225, 225, 245, 255))
    colors = [(240, 70, 40), (245, 160, 40), (250, 225, 90), (245, 160, 40), (240, 70, 40)]
    for i, c in enumerate(colors):
        x = 256 + (i - 2) * dx
        d.rounded_rectangle((x - dx / 2 + 5, 395, x + dx / 2 - 5, 470), radius=10, fill=c + (255,), outline=(60, 30, 10, 255), width=4)
    bx, by = 256 + 0.5 * dx, 40 + 2.5 * dy
    for k, a in enumerate((70, 120)):
        tx, ty = bx - (2 - k) * 14, by - (2 - k) * 36
        d.ellipse((tx - 22, ty - 22, tx + 22, ty + 22), fill=(255, 90, 140, a))
    d.ellipse((bx - 40, by - 40, bx + 40, by + 40), fill=(255, 90, 140, 255), outline=(120, 20, 60, 255), width=5)
    d.ellipse((bx - 22, by - 24, bx - 6, by - 8), fill=(255, 220, 235, 255))
    return frame(img)


# --- Crash: a climbing curve that ends in a burst ------------------------------
def crash():
    img = backdrop((40, 60, 90, 255), (8, 12, 22, 255))
    d = ImageDraw.Draw(img)
    for k in range(1, 5):
        d.line((60, 60 + k * 90, 452, 60 + k * 90), fill=(70, 90, 120, 255), width=2)
        d.line((60 + k * 90, 60, 60 + k * 90, 452), fill=(70, 90, 120, 255), width=2)
    d.line((60, 452, 452, 452), fill=(150, 160, 190, 255), width=5)
    d.line((60, 60, 60, 452), fill=(150, 160, 190, 255), width=5)
    pts = []
    for i in range(60):
        t = i / 59
        x = 60 + t * 290
        y = 452 - (math.exp(2.6 * t) - 1) / (math.exp(2.6) - 1) * 300
        pts.append((x, y))
    d.line(pts, fill=(255, 200, 60, 255), width=28, joint="curve")
    ex, ey = pts[-1]
    for k in range(14):
        a = k * math.pi / 7
        L = 115 if k % 2 == 0 else 70
        d.line((ex, ey, ex + math.cos(a) * L, ey + math.sin(a) * L), fill=(255, 120, 40, 255), width=18)
    d.ellipse((ex - 58, ey - 58, ex + 58, ey + 58), fill=(255, 80, 40, 255))
    d.ellipse((ex - 32, ey - 32, ex + 32, ey + 32), fill=(255, 235, 150, 255))
    return frame(img)


# --- Hi-Lo: a card between an up arrow and a down arrow -------------------------
def hilo():
    img = backdrop((30, 110, 130, 255), (8, 30, 40, 255))
    rotated_card(img, 256, 256, 190, 270, 0, "7", "\u2663", INK)

    def arrow(cx, cy, up, col):
        w, h, stem = 120, 170, 52
        sgn = -1 if up else 1
        tip, base = cy + sgn * h / 2, cy - sgn * h / 2
        mid = cy + sgn * h * 0.02
        poly = [(cx, tip), (cx + w / 2, mid), (cx + stem / 2, mid), (cx + stem / 2, base),
                (cx - stem / 2, base), (cx - stem / 2, mid), (cx - w / 2, mid)]
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(sh).polygon([(x + 8, y + 12) for x, y in poly], fill=(0, 0, 0, 150))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(8)))
        ImageDraw.Draw(img).polygon(poly, fill=col, outline=(20, 20, 20, 255), width=6)

    arrow(96, 190, True, (70, 220, 90, 255))
    arrow(416, 322, False, (235, 70, 60, 255))
    return frame(img)


ICONS = [("BlackjackIcon", blackjack), ("HiLoIcon", hilo), ("HoldemIcon", holdem), ("DrawIcon", draw), ("RouletteIcon", roulette), ("SlotsIcon", slots),
         ("MinesIcon", mines), ("PlinkoIcon", plinko), ("CrashIcon", crash), ("VideoPokerIcon", videopoker)]

if __name__ == "__main__":
    big = []
    for name, fn in ICONS:
        img = fn()
        img.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, name + ".tga"))
        big.append(img)
    craps = os.path.join(OUT, "CrapsIcon.tga")
    sheet = Image.new("RGBA", ((len(big) + 1) * 150 + 10, 210), (30, 30, 30, 255))
    for i, img in enumerate(big + ([Image.open(craps).convert("RGBA").resize((512, 512), Image.NEAREST)] if os.path.exists(craps) else [])):
        sheet.paste(img.resize((140, 140), Image.LANCZOS), (10 + i * 150, 10))
        small = img.resize((64, 64), Image.LANCZOS).resize((40, 40), Image.LANCZOS)
        sheet.paste(small, (60 + i * 150, 160))
    sheet.save(PREVIEW)
