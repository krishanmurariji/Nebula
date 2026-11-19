"""Abstract cover art for the README screenshots (fictional songs).

Run: python3 tool/readme/make_art.py   (needs Pillow)
"""
import math, random
from PIL import Image, ImageDraw, ImageFilter

OUT = 'docs/readme/art'
PALETTES = [
    ((46, 64, 87), (204, 120, 92), (242, 204, 143)),   # monsoon dusk
    ((120, 45, 30), (232, 145, 70), (250, 220, 160)),  # saffron
    ((22, 28, 48), (82, 96, 160), (230, 214, 170)),    # moonlit
    ((60, 70, 72), (150, 170, 160), (235, 228, 210)),  # rain
    ((110, 40, 60), (214, 110, 120), (246, 210, 200)), # rose
    ((30, 50, 40), (200, 160, 70), (250, 236, 190)),   # lanterns
    ((35, 20, 45), (120, 70, 140), (225, 190, 220)),   # velvet
    ((90, 50, 20), (220, 170, 80), (255, 240, 200)),   # golden
]
W, H = 640, 360

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

for n, (c1, c2, c3) in enumerate(PALETTES, start=1):
    rnd = random.Random(n * 97)
    img = Image.new('RGB', (W, H))
    px = img.load()
    ang = rnd.uniform(0, math.pi)
    for y in range(H):
        for x in range(W):
            t = ((x * math.cos(ang) + y * math.sin(ang)) / (W + H)) % 1.0
            px[x, y] = lerp(c1, c2, t) if t < .7 else lerp(c2, c1, (t - .7) / .3)
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    for _ in range(5):
        r = rnd.randint(60, 190)
        cx, cy = rnd.randint(0, W), rnd.randint(0, H)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c3 + (rnd.randint(50, 110),))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    img = Image.alpha_composite(img.convert('RGBA'), glow)
    d = ImageDraw.Draw(img)
    # a sun or moon over two soft hills
    sx, sy, sr = rnd.randint(180, 460), rnd.randint(90, 150), rnd.randint(42, 62)
    d.ellipse((sx - sr, sy - sr, sx + sr, sy + sr), fill=c3 + (235,))
    for k, (base, amp, col, alpha) in enumerate([(250, 40, c2, 200), (290, 30, c1, 235)]):
        ph = rnd.uniform(0, 6.28)
        pts = [(x, base + amp * math.sin(x / (90 + 30 * k) + ph)) for x in range(0, W + 8, 8)]
        d.polygon(pts + [(W, H), (0, H)], fill=lerp(col, (0, 0, 0), .15 * k) + (alpha,))
    img.convert('RGB').save(f'{OUT}/{n}.jpg', quality=88)
print('ok')
