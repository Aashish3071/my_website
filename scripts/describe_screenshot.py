# Diagnostic: prints, for each horizontal band of a screenshot, the background
# colour, the colour furthest from it, and the WCAG contrast between the two.
# Usage: python3 scripts/describe_screenshot.py <image> [band height in pixels]
import sys
from collections import Counter
from PIL import Image


def luminance(rgb):
    def channel(v):
        c = v / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


image = Image.open(sys.argv[1]).convert("RGB")
band = int(sys.argv[2]) if len(sys.argv) > 2 else 36
width, height = image.size
print(f"size {width}x{height}")
for top in range(0, int(height * 0.7), band):
    pixels = list(image.crop((0, top, width, top + band)).getdata())
    background = Counter(pixels).most_common(1)[0][0]
    foreground = max(set(pixels), key=lambda p: contrast(p, background))
    print(
        f"y={top:4d} bg=#{'%02X%02X%02X' % background} "
        f"fg=#{'%02X%02X%02X' % foreground} contrast={contrast(foreground, background):.2f}"
    )
