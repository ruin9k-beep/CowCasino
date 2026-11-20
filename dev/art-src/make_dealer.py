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


def whiskers():
    """Whiskers: a gray rat croupier in a green visor and a red bow tie."""
    img = backdrop((70, 110, 80, 255), (14, 30, 20, 255))
    fur, furDark, furLight = (138, 130, 128, 255), (78, 72, 72, 255), (186, 180, 176, 255)
    pink, pinkDark = (236, 158, 170, 255), (180, 100, 112, 255)

    def soft(shape_fn, color, blur):
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        shape_fn(ImageDraw.Draw(layer), color)
        img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))

    d = ImageDraw.Draw(img)
    # shoulders: a black vest over a white shirt
    body(d)
    # neck
    d.ellipse((196, 330, 316, 430), fill=furDark)
    # ears: smaller than a mouse's, set back on the head, pink inside
    for cx in (166, 346):
        d.ellipse((cx - 50, 104, cx + 50, 214), fill=fur, outline=furDark, width=6)
        d.ellipse((cx - 32, 124, cx + 32, 198), fill=pink)
        soft(lambda dd, c, cx=cx: dd.ellipse((cx - 24, 134, cx + 16, 184), fill=c), (255, 210, 220, 120), 8)
    # the head, tapering into a long snout
    d.ellipse((160, 150, 352, 310), fill=fur, outline=furDark, width=6)
    d.polygon([(170, 250), (342, 250), (282, 392), (230, 392)], fill=fur, outline=furDark)
    d.ellipse((168, 190, 344, 300), fill=fur)
    d.ellipse((218, 330, 294, 400), fill=furLight, outline=furDark, width=5)
    # shading: lighter brow and cheeks
    soft(lambda dd, c: dd.ellipse((190, 170, 320, 250), fill=c), (230, 230, 238, 110), 18)
    # the visor
    d.chord((150, 128, 362, 236), 180, 360, fill=(30, 150, 70, 235))
    d.rectangle((150, 176, 362, 190), fill=(20, 110, 50, 255))
    # shiny black eyes
    for x in (214, 298):
        d.ellipse((x - 22, 222, x + 22, 266), fill=(18, 14, 16, 255))
        d.ellipse((x - 11, 228, x + 1, 240), fill=(255, 255, 255, 255))
        d.ellipse((x + 6, 248, x + 12, 254), fill=(200, 200, 210, 255))
    # pink nose at the snout's tip, a small smile with two front teeth
    d.ellipse((238, 362, 274, 388), fill=pink, outline=pinkDark, width=4)
    d.ellipse((245, 366, 256, 373), fill=(255, 220, 228, 255))
    d.line((256, 388, 256, 396), fill=furDark, width=4)
    d.arc((232, 384, 256, 404), 20, 160, fill=furDark, width=4)
    d.arc((256, 384, 280, 404), 20, 160, fill=furDark, width=4)
    d.rectangle((248, 400, 264, 414), fill=(250, 246, 230, 255), outline=furDark, width=3)
    d.line((256, 400, 256, 414), fill=furDark, width=2)
    # the whiskers
    for side in (-1, 1):
        x0 = 256 + side * 20
        for k, dy in enumerate((-12, 0, 12)):
            x1 = 256 + side * (160 - k * 8)
            d.line((x0, 378 + dy * 0.4, x1, 362 + dy * 2.4), fill=(240, 240, 245, 230), width=3)
    bow_tie(d, 440)
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
    imgs = [("DealerGoblin", fizz), ("DealerHuman", human()), ("DealerWhiskers", whiskers())]
    sheet = Image.new("RGBA", (870, 170), (30, 30, 30, 255))
    for i, (name, img) in enumerate(imgs):
        img.resize((128, 128), Image.LANCZOS).save(os.path.join(out, name + ".tga"))
        sheet.paste(img.resize((150, 150), Image.LANCZOS), (10 + i * 290, 10))
        sheet.paste(img.resize((128, 128), Image.LANCZOS).resize((108, 108), Image.LANCZOS), (170 + i * 290, 10))
    sheet.save(preview)
