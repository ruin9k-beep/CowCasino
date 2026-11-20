# The Modern window frame (MainMenu.lua, ns:SkinFrame): a dark slate panel
# with rounded corners, a soft shadow, a title band with a thin gold line
# under it, and a fine edge. Same footprint as TaurenFrame.tga: the window is
# 436 x 440, painted with 10 px around it for the shadow, in the top-left of
# a 512 x 512 32-bit TGA.
#   python3 make_modern_window.py <Art folder> <preview.png>
from PIL import Image, ImageDraw, ImageFilter
import sys, os

OUT, PREVIEW = sys.argv[1], sys.argv[2]
S = 4                         # drawn 4x, shrunk
W, H, PAD = 436, 440, 10
R = 9                         # corner radius
BAND = 34                     # title band height

def box(x0, y0, x1, y1):
    return [(x0 + PAD) * S, (y0 + PAD) * S, (x1 + PAD) * S - 1, (y1 + PAD) * S - 1]

big = Image.new("RGBA", ((W + 2 * PAD) * S, (H + 2 * PAD) * S), (0, 0, 0, 0))

# the soft shadow round the window
sh = Image.new("RGBA", big.size, (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle(box(0, 2, W, H + 2), radius=R * S, fill=(0, 0, 0, 170))
sh = sh.filter(ImageFilter.GaussianBlur(5 * S))
big.alpha_composite(sh)

# the panel: a slate gradient, darker toward the bottom
panel = Image.new("RGBA", big.size, (0, 0, 0, 0))
pd = ImageDraw.Draw(panel)
top, bottom = (30, 32, 38), (17, 18, 22)
for y in range(H * S):
    t = y / (H * S)
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (250,)
    pd.line([(PAD * S, (PAD * S) + y), ((PAD + W) * S, (PAD * S) + y)], fill=c)
# the title band, a touch lighter
for y in range(BAND * S):
    t = y / (BAND * S)
    c = (int(44 - 8 * t), int(47 - 8 * t), int(56 - 9 * t), 252)
    pd.line([(PAD * S, PAD * S + y), ((PAD + W) * S, PAD * S + y)], fill=c)
mask = Image.new("L", big.size, 0)
ImageDraw.Draw(mask).rounded_rectangle(box(0, 0, W, H), radius=R * S, fill=255)
big.paste(panel, (0, 0), mask)

d = ImageDraw.Draw(big)
# a thin gold line under the title band, fading toward the ends
line = Image.new("RGBA", big.size, (0, 0, 0, 0))
ld = ImageDraw.Draw(line)
y = (PAD + BAND) * S
for x in range(W * S):
    t = abs(x / (W * S) - 0.5) * 2          # 0 in the middle, 1 at the ends
    a = int(200 * max(0.0, 1 - t ** 3))
    ld.line([((PAD * S) + x, y), ((PAD * S) + x, y + S - 1)], fill=(214, 172, 62, a))
big.alpha_composite(line)
# the edge: a dark outline and a faint inner highlight
d.rounded_rectangle(box(0, 0, W, H), radius=R * S, outline=(6, 6, 8, 255), width=S)
d.rounded_rectangle(box(1, 1, W - 1, H - 1), radius=(R - 1) * S, outline=(86, 92, 106, 160), width=S)

art = big.resize((W + 2 * PAD, H + 2 * PAD), Image.LANCZOS)
out = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
out.paste(art, (0, 0))
out.save(os.path.join(OUT, "ModernFrame.tga"))
pv = Image.new("RGBA", (W + 2 * PAD + 40, H + 2 * PAD + 40), (70, 90, 70, 255))
pv.alpha_composite(art, (20, 20))
pv.save(PREVIEW)
