# Draws the placeholder app icon. Usage: python3 scripts/generate_app_icon.py <output.png>  (needs Pillow)
import sys, math, json
from PIL import Image, ImageDraw
out = sys.argv[1]
S = 2048  # draw at 2x, then downscale for smooth edges
img = Image.new("RGB", (S, S))
px = img.load()
top, bottom = (0x12, 0x9A, 0x8F), (0x06, 0x4E, 0x4A)
for y in range(S):
    t = y / (S - 1)
    c = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    for x in range(S):
        px[x, y] = c
d = ImageDraw.Draw(img)
white = (255, 255, 255)
# Fragrance drop: a circle with a pointed top
cx, cy, r = 1024, 1210, 330
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=white)
tip = (cx, 520)
ang = math.acos(r / (cy - tip[1]))
p1 = (cx - r * math.sin(ang), cy - r * math.cos(ang))
p2 = (cx + r * math.sin(ang), cy - r * math.cos(ang))
d.polygon([tip, p1, p2], fill=white)
# Highlight inside the drop
d.arc([cx - 215, cy - 215, cx + 215, cy + 215], start=100, end=170, fill=(0x0B, 0x6E, 0x69), width=56)
# Scent waves either side
for sign in (-1, 1):
    for i, (dist, half) in enumerate([(520, 34), (700, 28)]):
        box = [cx - dist, cy - dist, cx + dist, cy + dist]
        centre = 180 if sign < 0 else 0
        d.arc(box, start=centre - half, end=centre + half, fill=white, width=64 - i * 10)
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(out, "PNG")
print(img.mode, img.size)
