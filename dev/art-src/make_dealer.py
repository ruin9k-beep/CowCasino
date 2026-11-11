# The Dealer's default picture: a card dealer with a green visor and a bow
# tie, framed like the game icons. 64x64, 32-bit TGA.
#   python3 make_dealer.py <Art folder> <preview.png>
from PIL import Image, ImageDraw, ImageFilter
import sys, os
from make_game_icons import backdrop, frame, S

def dealer():
    img = backdrop((150, 40, 40, 255), (40, 10, 10, 255))
    d = ImageDraw.Draw(img)
    # shoulders: black vest over a white shirt
    d.ellipse((70, 330, 442, 640), fill=(25, 25, 30, 255))
    d.polygon([(206, 330), (306, 330), (280, 512), (232, 512)], fill=(240, 236, 228, 255))
    # neck and head
    d.rectangle((222, 270, 290, 340), fill=(226, 180, 140, 255))
    d.ellipse((150, 110, 362, 330), fill=(232, 188, 148, 255), outline=(150, 100, 70, 255), width=5)
    # hair
    d.chord((150, 100, 362, 260), 180, 360, fill=(70, 45, 25, 255))
    # eyes, smile and mustache
    for x in (212, 300):
        d.ellipse((x - 18, 212, x + 18, 242), fill=(255, 255, 255, 255))
        d.ellipse((x - 9, 218, x + 9, 238), fill=(40, 30, 20, 255))
    d.arc((210, 250, 302, 310), 20, 160, fill=(120, 50, 40, 255), width=7)
    d.polygon([(256, 268), (304, 280), (256, 288), (208, 280)], fill=(70, 45, 25, 255))
    # the green visor
    d.chord((128, 110, 384, 230), 180, 360, fill=(30, 150, 70, 230))
    d.rectangle((128, 166, 384, 180), fill=(20, 110, 50, 255))
    # red bow tie
    d.polygon([(256, 350), (196, 322), (196, 378)], fill=(200, 25, 30, 255))
    d.polygon([(256, 350), (316, 322), (316, 378)], fill=(200, 25, 30, 255))
    d.ellipse((242, 336, 270, 364), fill=(150, 15, 20, 255))
    return frame(img)

if __name__ == "__main__":
    img = dealer()
    img.resize((64, 64), Image.LANCZOS).save(os.path.join(sys.argv[1], "DealerPortrait.tga"))
    sheet = Image.new("RGBA", (360, 180), (30, 30, 30, 255))
    sheet.paste(img.resize((160, 160), Image.LANCZOS), (10, 10))
    sheet.paste(img.resize((64, 64), Image.LANCZOS).resize((44, 44), Image.LANCZOS), (220, 68))
    sheet.save(sys.argv[2])
