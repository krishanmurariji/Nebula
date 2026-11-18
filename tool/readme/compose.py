"""Builds the README graphics in docs/readme/ from the frames rendered by
tool/readme/screens_test.dart (in build/readme/), plus the animated SVGs.

Run: python3 tool/readme/compose.py   (needs Pillow)
"""
import base64
import glob
import io
import os

from PIL import Image, ImageDraw, ImageFilter

SRC = 'build/readme'
OUT = 'docs/readme'
COPPER = '#8E4A27'
COPPER_RGB = (142, 74, 39)
INK = '#2B1A12'
MUTE = '#A27B66'
os.makedirs(f'{OUT}/screens', exist_ok=True)


# ── Phone frames ─────────────────────────────────────────────────────────────

def phone(img, width=360):
    """A slim dark phone around a screen, with a soft shadow, on transparent."""
    scale = width / img.width
    sw, sh = width, round(img.height * scale)
    screen = img.convert('RGB').resize((sw, sh), Image.LANCZOS)
    bez, rad, pad = 10, 38, 26
    W, H = sw + 2 * bez + 2 * pad, sh + 2 * bez + 2 * pad
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad + 10, W - pad, H - pad + 6), rad + bez, fill=(60, 30, 15, 70))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((pad, pad, W - pad, H - pad), rad + bez, fill=(26, 20, 17, 255))
    d.rounded_rectangle((pad + 1, pad + 1, W - pad - 1, H - pad - 1), rad + bez - 1,
                        outline=(80, 66, 58, 255), width=1)
    mask = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh), rad, fill=255)
    out.paste(screen, (pad + bez, pad + bez), mask)
    # camera dot
    cx = W // 2
    d.ellipse((cx - 5, pad + bez + 9, cx + 5, pad + bez + 19), fill=(20, 16, 14, 255))
    return out


for name in ['home', 'player', 'search', 'actions', 'circle', 'empty']:
    phone(Image.open(f'{SRC}/{name}.png')).save(f'{OUT}/screens/{name}.png', optimize=True)


# ── GIFs ─────────────────────────────────────────────────────────────────────

def gif(name, ms, width=300, hold_last=1200):
    files = sorted(glob.glob(f'{SRC}/{name}_*.png'))
    frames = []
    for f in files:
        framed = phone(Image.open(f), width)
        bg = Image.new('RGBA', framed.size, (255, 255, 255, 255))
        bg.alpha_composite(framed)
        frames.append(bg.convert('RGB'))
    # One shared palette keeps the colours steady between frames.
    pal = frames[len(frames) // 2].quantize(colors=200, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    durations = [ms] * (len(q) - 1) + [hold_last]
    q[0].save(f'{OUT}/{name}.gif', save_all=True, append_images=q[1:],
              duration=durations, loop=0, optimize=True, disposal=1)


gif('swap', 60)
gif('circle', 50)
gif('slider', 50)


# ── SVGs ─────────────────────────────────────────────────────────────────────

def b64(path, size=None):
    im = Image.open(path).convert('RGBA')
    if size:
        im.thumbnail(size, Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode()


SANS = "'Segoe UI','Helvetica Neue',Arial,sans-serif"
SERIF = "'Cormorant Garamond',Georgia,'Times New Roman',serif"

label = b64('assets/images/noor_record_label.png', (160, 160))
word = b64('assets/images/noor_wordmark.png', (380, 150))
girl = b64('assets/images/noor_girl.png', (240, 300))

# Record grooves
grooves = ''.join(
    f'<circle cx="0" cy="0" r="{r}" fill="none" stroke="#ffffff" stroke-opacity=".07" stroke-width="1"/>'
    for r in range(78, 170, 6))
gaps = ''.join(
    f'<circle cx="0" cy="0" r="{r}" fill="none" stroke="#000" stroke-opacity=".85" stroke-width="1.6"/>'
    for r in (150, 128, 104))

# Waveform bars (uneven above and below the line), breathing
import random
rnd = random.Random(7)
bars = []
for i in range(34):
    up, down = 8 + rnd.random() * 30, 8 + rnd.random() * 30
    x = 660 + i * 16
    col = COPPER if i < 15 else '#E7D3C6'
    dur = 1.4 + rnd.random() * 1.2
    bars.append(
        f'<rect x="{x}" y="{360 - up:.1f}" width="9" height="{up + down:.1f}" rx="4.5" fill="{col}">'
        f'<animate attributeName="height" values="{up + down:.1f};{(up + down) * .6:.1f};{up + down:.1f}" dur="{dur:.2f}s" repeatCount="indefinite"/>'
        f'<animate attributeName="y" values="{360 - up:.1f};{360 - up * .6:.1f};{360 - up:.1f}" dur="{dur:.2f}s" repeatCount="indefinite"/>'
        f'</rect>')

hero = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1280" height="460" viewBox="0 0 1280 460" role="img" aria-label="Noor, a royal, minimal music player">
<title>Noor, a royal, minimal music player</title>
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FBF5EE"/></linearGradient>
<radialGradient id="glow" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#E9C9A8" stop-opacity=".55"/><stop offset="1" stop-color="#E9C9A8" stop-opacity="0"/></radialGradient>
<linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1"><stop offset=".25" stop-color="#fff" stop-opacity="0"/><stop offset=".45" stop-color="#fff" stop-opacity=".14"/><stop offset=".6" stop-color="#fff" stop-opacity="0"/></linearGradient>
<clipPath id="round"><rect width="1280" height="460" rx="28"/></clipPath>
<clipPath id="lab"><circle cx="0" cy="0" r="66"/></clipPath>
</defs>
<g clip-path="url(#round)">
<rect width="1280" height="460" fill="url(#bg)"/>
<rect x=".5" y=".5" width="1279" height="459" rx="28" fill="none" stroke="{COPPER}" stroke-opacity=".35"/>
<circle cx="300" cy="230" r="260" fill="url(#glow)"><animate attributeName="r" values="240;280;240" dur="8s" repeatCount="indefinite"/></circle>
<image x="980" y="40" width="300" height="373" opacity=".10" xlink:href="{girl}"/>
<!-- turntable record -->
<g transform="translate(300 230)">
  <circle r="182" fill="#000" opacity=".12" transform="translate(0 10)"/>
  <g><animateTransform attributeName="transform" type="rotate" from="0" to="360" dur="6s" repeatCount="indefinite"/>
    <circle r="176" fill="#141416"/>
    {grooves}{gaps}
    <circle r="72" fill="#0B0B0C"/>
    <g clip-path="url(#lab)"><image x="-66" y="-66" width="132" height="132" xlink:href="{label}"/></g>
  </g>
  <circle r="176" fill="url(#sheen)"/>
  <circle r="5" fill="#C9C9C9"/>
</g>
<!-- tone arm -->
<g transform="translate(470 70)">
  <circle r="26" fill="#8D9097"/><circle r="17" fill="#C9CBD0"/>
  <g><animateTransform attributeName="transform" type="rotate" values="-14;0;0;-14" keyTimes="0;.12;.88;1" dur="8s" repeatCount="indefinite"/>
    <path d="M0 0 L-4 40 Q-10 160 -70 214" fill="none" stroke="#8F949C" stroke-width="6" stroke-linecap="round"/>
    <rect x="-86" y="206" width="26" height="32" rx="4" fill="#F1F1F1" transform="rotate(40 -73 222)"/>
    <circle r="11" fill="#F3F3F3"/>
  </g>
</g>
<!-- words -->
<image x="640" y="70" width="300" height="115" xlink:href="{word}"/>
<text x="648" y="236" font-family="{SERIF}" font-size="34" font-style="italic" fill="{INK}">A royal, minimal music player.</text>
<text x="648" y="276" font-family="{SANS}" font-size="18" fill="{MUTE}">Swipe-first · YouTube streaming · offline cache · no account, no API key</text>
{''.join(bars)}
<text x="648" y="420" font-family="{SANS}" font-size="13" fill="{MUTE}">01:24</text>
<text x="1196" y="420" font-family="{SANS}" font-size="13" fill="{MUTE}" text-anchor="end">03:52</text>
</g>
</svg>'''
open(f'{OUT}/hero.svg', 'w').write(hero)

divider = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="24" viewBox="0 0 1280 24" role="img" aria-label="divider"><title>divider</title><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{COPPER}" stop-opacity="0"/><stop offset=".5" stop-color="{COPPER}"/><stop offset="1" stop-color="{COPPER}" stop-opacity="0"/></linearGradient><linearGradient id="line" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{COPPER}" stop-opacity="0"/><stop offset=".5" stop-color="{COPPER}" stop-opacity=".35"/><stop offset="1" stop-color="{COPPER}" stop-opacity="0"/></linearGradient></defs><rect y="11.5" width="1280" height="1" fill="url(#line)"/><rect y="10.5" width="240" height="3" rx="1.5" fill="url(#g)"><animate attributeName="x" values="-240;1280" dur="5s" repeatCount="indefinite"/></rect><g transform="translate(640 12)"><circle r="7" fill="#fff" stroke="{COPPER}" stroke-width="1.2"/><circle r="2.4" fill="{COPPER}"/><animateTransform attributeName="transform" type="rotate" from="0 640 12" to="360 640 12" dur="6s" repeatCount="indefinite" additive="sum"/></g></svg>'''
open(f'{OUT}/divider.svg', 'w').write(divider)

STATS = [('0', 'API keys or accounts'), ('1 swipe', 'to like, file or delete'),
         ('10', 'playlists in a circle'), ('3', 'lists ready on Home')]
cells = []
for i, (num, lab) in enumerate(STATS):
    x = 160 + i * 320
    start = i * 0.05
    cells.append(
        f'<g opacity="0"><animate attributeName="opacity" values="0;0;1;1;0" keyTimes="0;{start:.3f};{start + .06:.3f};.92;1" dur="9s" repeatCount="indefinite"/>'
        f'<animateTransform attributeName="transform" type="translate" values="0 16;0 16;0 0;0 0;0 0" keyTimes="0;{start:.3f};{start + .06:.3f};.92;1" dur="9s" repeatCount="indefinite"/>'
        f'<text x="{x}" y="88" text-anchor="middle" font-family="{SERIF}" font-style="italic" font-size="50" fill="{COPPER}">{num}</text>'
        f'<text x="{x}" y="122" text-anchor="middle" font-family="{SANS}" font-size="16" fill="{MUTE}">{lab}</text></g>')
    if i:
        cells.append(f'<rect x="{x - 160}" y="52" width="1" height="72" fill="{COPPER}" opacity=".2"/>')
stats = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="170" viewBox="0 0 1280 170" role="img" aria-label="Noor in numbers: no API key or account, one swipe to like, file or delete a song, up to 10 playlists, 3 lists ready on Home"><title>Noor in numbers</title><rect x=".5" y=".5" width="1279" height="169" rx="24" fill="#FFFFFF" stroke="{COPPER}" stroke-opacity=".35"/>{''.join(cells)}</svg>'''
open(f'{OUT}/stats.svg', 'w').write(stats)

print('done:', sorted(os.listdir(OUT)))
