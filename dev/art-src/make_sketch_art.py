# The drawing kit's brushes (Games/SketchKit.lua), 32x32 white, tinted in game:
#   SketchLine.tga  a bar from u = 2/32 to 30/32 and v = 0.25 to 0.75, soft
#                   edged, clear all round (so a rotated, clamped copy shows
#                   nothing past the bar)
#   SketchDot.tga   a soft round dot filling the square
#   python3 make_sketch_art.py <Art folder>
from PIL import Image, ImageDraw
import sys, os

OUT = sys.argv[1]
BIG = 256          # drawn at 8x, shrunk to 32

line = Image.new("RGBA", (BIG, BIG), (255, 255, 255, 0))
ImageDraw.Draw(line).rectangle((2 * 8, BIG * 0.25, BIG - 2 * 8 - 1, BIG * 0.75 - 1), fill=(255, 255, 255, 255))
line = line.resize((32, 32), Image.LANCZOS)
px = line.load()
for i in range(32):              # the very edge stays clear
    for (x, y) in ((0, i), (31, i), (i, 0), (i, 31)):
        px[x, y] = (255, 255, 255, 0)
line.save(os.path.join(OUT, "SketchLine.tga"))

dot = Image.new("RGBA", (BIG, BIG), (255, 255, 255, 0))
ImageDraw.Draw(dot).ellipse((10, 10, BIG - 11, BIG - 11), fill=(255, 255, 255, 255))
dot.resize((32, 32), Image.LANCZOS).save(os.path.join(OUT, "SketchDot.tga"))
