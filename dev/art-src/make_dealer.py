# Dealer pictures (Dealer.lua), framed like the game icons. 128x128, 32-bit TGA.
#   DealerGoblin  Fizzlecog, the default dealer: from fizzlecog.png (the
#                 picture ruin9k supplied), cropped square; the painted goblin
#                 below is only used if that file is missing
#   DealerHuman   a human croupier with a green visor and bow tie
#   python3 make_dealer.py <Art folder> <preview.png>
from PIL import Image, ImageDraw, ImageFilter
import sys, os
from make_game_icons import backdrop, frame, S

SKIN, SKIN_DARK, SKIN_LIGHT = (110, 168, 70, 255), (62, 108, 40, 255), (150, 200, 100, 255)


def body(d):
    # black vest over a white shirt, red bow tie
    d.ellipse((60, 350, 452, 660), fill=(25, 25, 30, 255))
    d.polygon([(206, 350), (306, 350), (280, 512), (232, 512)], fill=(240, 236, 228, 255))


def bow_tie(d, y):
    d.polygon([(256, y), (196, y - 28), (196, y + 28)], fill=(200, 25, 30, 255))
    d.polygon([(256, y), (316, y - 28), (316, y + 28)], fill=(200, 25, 30, 255))
    d.ellipse((242, y - 14, 270, y + 14), fill=(150, 15, 20, 255))


def goblin():
    img = backdrop((150, 110, 40, 255), (40, 25, 8, 255))
    d = ImageDraw.Draw(img)
    body(d)
    d.rectangle((222, 300, 290, 360), fill=SKIN_DARK)
    # long pointed ears, sweeping out and up
    for side in (-1, 1):
        base = 256 + side * 92
        tip = (256 + side * 250, 120)
        ear = [(base, 190), tip, (base + side * 10, 280)]
        d.polygon(ear, fill=SKIN, outline=SKIN_DARK)
        inner = [(base + side * 12, 205), (256 + side * 215, 145), (base + side * 14, 258)]
        d.polygon(inner, fill=(190, 120, 110, 255))
    # head: wide at the cheeks, narrow chin
    d.ellipse((150, 140, 362, 350), fill=SKIN, outline=SKIN_DARK, width=5)
    # the visor
    d.chord((128, 112, 384, 236), 180, 360, fill=(30, 150, 70, 235))
    d.rectangle((128, 168, 384, 182), fill=(20, 110, 50, 255))
    # yellow eyes with slit pupils and heavy brows
    for x in (208, 304):
        d.ellipse((x - 22, 200, x + 22, 236), fill=(250, 220, 60, 255), outline=(60, 40, 10, 255), width=3)
        d.ellipse((x - 5, 204, x + 5, 232), fill=(30, 20, 10, 255))
    d.line((184, 194, 232, 202), fill=SKIN_DARK, width=8)
    d.line((280, 202, 328, 194), fill=SKIN_DARK, width=8)
    # the big hooked nose
    d.polygon([(250, 214), (292, 280), (272, 300), (238, 292)], fill=SKIN_LIGHT, outline=SKIN_DARK)
    d.ellipse((240, 278, 280, 304), fill=SKIN, outline=SKIN_DARK, width=3)
    # a wide grin with pointed teeth and one gold tooth
    d.chord((186, 286, 326, 350), 0, 180, fill=(70, 20, 20, 255))
    for k in range(6):
        x = 200 + k * 20
        col = (240, 200, 60, 255) if k == 3 else (245, 240, 220, 255)
        d.polygon([(x, 318), (x + 16, 318), (x + 8, 334)], fill=col)
    bow_tie(d, 372)
    return frame(img)


def human():
    img = backdrop((150, 40, 40, 255), (40, 10, 10, 255))
    d = ImageDraw.Draw(img)
    body(d)
    d.rectangle((222, 270, 290, 360), fill=(226, 180, 140, 255))
    d.ellipse((150, 110, 362, 330), fill=(232, 188, 148, 255), outline=(150, 100, 70, 255), width=5)
    d.chord((150, 100, 362, 260), 180, 360, fill=(70, 45, 25, 255))
    for x in (212, 300):
        d.ellipse((x - 18, 212, x + 18, 242), fill=(255, 255, 255, 255))
        d.ellipse((x - 9, 218, x + 9, 238), fill=(40, 30, 20, 255))
    d.arc((210, 250, 302, 310), 20, 160, fill=(120, 50, 40, 255), width=7)
    d.polygon([(256, 268), (304, 280), (256, 288), (208, 280)], fill=(70, 45, 25, 255))
    d.chord((128, 110, 384, 230), 180, 360, fill=(30, 150, 70, 230))
    d.rectangle((128, 166, 384, 180), fill=(20, 110, 50, 255))
    bow_tie(d, 372)
    return frame(img)


if __name__ == "__main__":
    out, preview = sys.argv[1], sys.argv[2]
    here = os.path.dirname(os.path.abspath(__file__))
    src = os.path.join(here, "fizzlecog.png")
    if os.path.exists(src):
        pic = Image.open(src).convert("RGBA")
        side = min(pic.size)
        left, top = (pic.size[0] - side) // 2, (pic.size[1] - side) // 2
        fizz = pic.crop((left, top, left + side, top + side)).resize((S, S), Image.LANCZOS)
    else:
        fizz = goblin()
    imgs = [("DealerGoblin", fizz), ("DealerHuman", human())]
    sheet = Image.new("RGBA", (580, 170), (30, 30, 30, 255))
    for i, (name, img) in enumerate(imgs):
        img.resize((128, 128), Image.LANCZOS).save(os.path.join(out, name + ".tga"))
        sheet.paste(img.resize((150, 150), Image.LANCZOS), (10 + i * 290, 10))
        sheet.paste(img.resize((128, 128), Image.LANCZOS).resize((108, 108), Image.LANCZOS), (170 + i * 290, 10))
    sheet.save(preview)
