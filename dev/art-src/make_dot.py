# A white anti-aliased disc (32x32, 32-bit TGA): dice pips, Plinko pegs and
# balls, the Crash curve. Tinted in game with SetVertexColor.
from PIL import Image, ImageDraw
import sys
S, K = 32, 8
big = Image.new("L", (S * K, S * K), 0)
ImageDraw.Draw(big).ellipse((K, K, (S - 1) * K, (S - 1) * K), fill=255)
alpha = big.resize((S, S), Image.LANCZOS)
img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
img.putalpha(alpha)
img.save(sys.argv[1])
