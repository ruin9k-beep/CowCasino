# Craps menu icon: a pair of ivory dice with red pips on green felt, framed
# like a WoW item icon. 64x64, 32-bit TGA (works on 1.12 and WoW Forever).
from PIL import Image, ImageDraw, ImageFilter
import sys, math

S = 512                      # drawn big, then shrunk smoothly
img = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(img)

# felt background: radial green with a dark edge
cx, cy = S / 2, S / 2
for r in range(int(S * 0.75), 0, -2):
    t = r / (S * 0.75)
    g = (int(18 + 40 * (1 - t)), int(70 + 80 * (1 - t)), int(30 + 35 * (1 - t)), 255)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=g)

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def cube(ox, oy, size, angle, top_pips, front_pips, side_pips):
    """A die seen from above-front: top, front and right faces as quads."""
    a = math.radians(angle)
    ux, uy = math.cos(a) * size, math.sin(a) * size            # right edge
    vx, vy = -math.sin(a) * size, math.cos(a) * size           # down edge (front face)
    dx, dy = size * 0.42, -size * 0.55                          # depth (up and right)
    P = lambda x, y: (ox + x, oy + y)
    front = [P(0, 0), P(ux, uy), P(ux + vx, uy + vy), P(vx, vy)]
    top = [P(dx, dy), P(ux + dx, uy + dy), P(ux, uy), P(0, 0)]
    side = [P(ux, uy), P(ux + dx, uy + dy), P(ux + vx + dx, uy + vy + dy), P(ux + vx, uy + vy)]
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.polygon([(x + 14, y + 22) for x, y in front + side], fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    img.alpha_composite(shadow)
    d.polygon(side, fill=(178, 160, 128, 255))
    d.polygon(top, fill=(250, 244, 226, 255))
    d.polygon(front, fill=(226, 214, 186, 255))
    for poly in (front, top, side):
        d.line(poly + [poly[0]], fill=(90, 70, 50, 255), width=5, joint="curve")

    def pips(quad, n, color):
        # pip positions in face coordinates (0..1)
        spots = {1: [(.5, .5)], 2: [(.25, .25), (.75, .75)], 3: [(.25, .25), (.5, .5), (.75, .75)],
                 4: [(.25, .25), (.75, .25), (.25, .75), (.75, .75)],
                 5: [(.25, .25), (.75, .25), (.5, .5), (.25, .75), (.75, .75)],
                 6: [(.25, .22), (.75, .22), (.25, .5), (.75, .5), (.25, .78), (.75, .78)]}[n]
        (x0, y0), (x1, y1), (x2, y2), (x3, y3) = quad
        for u, v in spots:
            top_x, top_y = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
            bot_x, bot_y = x3 + (x2 - x3) * u, y3 + (y2 - y3) * u
            px, py = top_x + (bot_x - top_x) * v, top_y + (bot_y - top_y) * v
            w = math.dist((x0, y0), (x1, y1)) * 0.085
            h = math.dist((x0, y0), (x3, y3)) * 0.085
            d.ellipse((px - w, py - h, px + w, py + h), fill=color)
    pips([top[3], top[2], top[1], top[0]][::-1] if False else [P(dx, dy), P(ux + dx, uy + dy), P(ux, uy), P(0, 0)], top_pips, (170, 20, 20, 255))
    pips(front, front_pips, (150, 15, 15, 255))
    pips([P(ux, uy), P(ux + dx, uy + dy), P(ux + vx + dx, uy + vy + dy), P(ux + vx, uy + vy)], side_pips, (120, 12, 12, 255))

cube(80, 250, 165, -8, 5, 6, 3)       # back-left die
cube(255, 300, 150, 12, 1, 4, 2)      # front-right die

# gold-brown icon frame and a soft vignette, like the game's icons
frame = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fd = ImageDraw.Draw(frame)
for i in range(26):
    t = i / 25
    fd.rectangle((i, i, S - 1 - i, S - 1 - i), outline=lerp((40, 28, 12, 255), (150, 118, 52, 0), t) if i > 3 else (20, 14, 6, 255))
img.alpha_composite(frame)

out = img.resize((64, 64), Image.LANCZOS)
out.save(sys.argv[1])
img.resize((256, 256), Image.LANCZOS).save(sys.argv[2])
