"""Regenerates every Noor icon from assets/images/noor_mark.png (transparent
copper mark) and noor_logo.png. Run from the repo root: python3 design/logo/tools/make_icons.py
Needs: pip install pillow."""
import json, os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

RES = 'android/app/src/main/res'
CREAM = (244, 240, 228, 255)

mark = Image.open('assets/images/noor_mark.png')
a = np.array(mark)
a[797:, 300:, 3] = 0                      # scrub the leftover of the removed label
mark = Image.fromarray(a, 'RGBA'); mark.save('assets/images/noor_mark.png')
al = mark.getchannel('A')
bb = al.point(lambda v: 255 if v > 25 else 0).getbbox()
bold = al.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.2))  # bolder lines for tiny sizes
m2 = Image.new('RGBA', mark.size, (0xA8, 0x58, 0x2E, 0)); m2.putalpha(bold)
mk = m2.crop((bb[0] - 8, bb[1] - 8, bb[2] + 8, bb[3] + 8))

def fg(size, width_frac):
    k = width_frac * size / mk.width
    m = mk.resize((max(1, round(mk.width * k)), max(1, round(mk.height * k))), Image.LANCZOS)
    c = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    c.paste(m, ((size - m.width) // 2, (size - m.height) // 2), m)
    return c

for dens, s in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
    for d in ('drawable', 'mipmap'):
        p = f'{RES}/{d}-{dens}/ic_launcher_foreground.png'
        if os.path.exists(p):
            fg(s, 0.78).save(p)
for dens, s in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    base = Image.new('RGBA', (s, s), CREAM); base.alpha_composite(fg(s, 0.86))
    mm = Image.new('L', (s * 4, s * 4), 0)
    ImageDraw.Draw(mm).rounded_rectangle([0, 0, s * 4 - 1, s * 4 - 1], radius=int(s * 4 * 0.22), fill=255)
    base.putalpha(mm.resize((s, s), Image.LANCZOS)); base.save(f'{RES}/mipmap-{dens}/launcher_icon.png')

full = Image.new('RGBA', (1024, 1024), CREAM); full.alpha_composite(fg(1024, 0.86)); full = full.convert('RGB')
full.save('assets/images/noor_app_icon.png')
d = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for e in json.load(open(f'{d}/Contents.json'))['images']:
    sz = round(float(e['size'].split('x')[0]) * int(e['scale'].replace('x', '')))
    full.resize((sz, sz), Image.LANCZOS).save(f"{d}/{e['filename']}")
fg(1024, 0.78).save('assets/images/noor_icon_foreground.png')
print('icons written')
