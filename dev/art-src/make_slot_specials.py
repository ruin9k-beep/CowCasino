# Slot special symbols, drawn the same in every slot theme:
#   SlotWild     a purple gem badge with WILD in gold
#   SlotScatter  a gold star burst with FREE across it
# 64x64, 32-bit TGA.  python3 make_slot_specials.py <Art folder> <preview.png>
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import sys, os, math
S = 512
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
OUT, PREVIEW = sys.argv[1], sys.argv[2]

def outlined_text(d, cx, cy, text, size, fill, outline, width):
    f = ImageFont.truetype(BOLD, size)
    tw = d.textlength(text, font=f)
    x, y = cx - tw / 2, cy - size * 0.62
    for dx in range(-width, width + 1, 2):
        for dy in range(-width, width + 1, 2):
            d.text((x + dx, y + dy), text, font=f, fill=outline)
    d.text((x, y), text, font=f, fill=fill)

def wild():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # a faceted purple gem
    pts = [(256, 20), (470, 150), (470, 362), (256, 492), (42, 362), (42, 150)]
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(pts, fill=(255, 210, 90, 200))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(12)))
    d.polygon(pts, fill=(110, 40, 170, 255), outline=(255, 215, 90, 255), width=14)
    inner = [(256, 70), (420, 170), (420, 342), (256, 442), (92, 342), (92, 170)]
    d.polygon(inner, fill=(150, 70, 210, 255))
    d.polygon([(256, 70), (420, 170), (256, 256)], fill=(185, 120, 235, 255))
    d.polygon([(92, 170), (256, 70), (256, 256)], fill=(205, 150, 245, 255))
    d.polygon([(92, 342), (256, 442), (256, 256)], fill=(110, 45, 165, 255))
    outlined_text(d, 256, 262, "WILD", 150, (255, 222, 90, 255), (60, 15, 70, 255), 10)
    return img

def scatter():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = 256, 256
    rays = []
    for k in range(32):
        a = k * math.pi / 16 - math.pi / 2
        r = 245 if k % 2 == 0 else 120
        rays.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(rays, fill=(255, 140, 40, 220))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(16)))
    d.polygon(rays, fill=(255, 196, 40, 255), outline=(150, 70, 10, 255), width=8)
    d.ellipse((cx - 150, cy - 150, cx + 150, cy + 150), fill=(220, 40, 40, 255), outline=(120, 10, 10, 255), width=10)
    d.ellipse((cx - 120, cy - 128, cx + 70, cy - 40), fill=(245, 110, 100, 255))
    outlined_text(d, 256, 262, "FREE", 118, (255, 245, 200, 255), (110, 10, 10, 255), 9)
    return img

if __name__ == "__main__":
    imgs = [("SlotWild", wild()), ("SlotScatter", scatter())]
    sheet = Image.new("RGBA", (420, 210), (40, 30, 30, 255))
    for i, (name, img) in enumerate(imgs):
        img.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, name + ".tga"))
        sheet.alpha_composite(img.resize((150, 150), Image.LANCZOS), (20 + i * 200, 10))
        sheet.alpha_composite(img.resize((64, 64), Image.LANCZOS).resize((36, 36), Image.LANCZOS), (75 + i * 200, 168))
    sheet.save(PREVIEW)
