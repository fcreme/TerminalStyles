"""Render the README banner, and record what it claims.

The banner is not decoration: it states a theme count and paints one swatch per
bundled style, both read from styles/ at render time. That makes it a claim
like any other, and claims in this project drift -- the README said "16 themes"
for as long as it took someone to notice.

A PNG cannot be inspected by a test, so this also writes docs/banner.json with
the count and the accents it drew. tests/README-Banner.Tests.ps1 compares that
file against styles/ and fails if the banner is stale, which is the only way a
picture can be held to what it says.

    python3 scripts/make-banner.py out.png

Needs Pillow and a JetBrains Mono install (tstyles font 'JetBrains Mono').
"""
import json, os, glob, sys
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCALE = 2                      # render at 2x so it stays crisp on a retina screen
# Sized to the content: the wordmark is about 525px wide at this size and
# the swatch strip about 670, so anything wider is dead space.
W, H = 772 * SCALE, 368 * SCALE
BG, ACCENT, FG, MUTED = '#0a0808', '#e04848', '#e8dcc8', '#8a7d6a'   # umbrella's own palette

WORD = [
    '   _       _         _',
    '  | |_ ___| |_ _   _| | ___  ___',
    '  | __/ __| __| | | | |/ _ \\/ __|',
    '  | |_\\__ \\ |_| |_| | |  __/\\__ \\',
    '   \\__|___/\\__|\\__, |_|\\___||___/',
    '                |___/',
]

FONTS = os.path.expanduser('~/Library/Fonts')
mono  = ImageFont.truetype(f'{FONTS}/JetBrainsMono-Bold.ttf', 34 * SCALE)
small = ImageFont.truetype(f'{FONTS}/JetBrainsMono-Regular.ttf', 17 * SCALE)

im = Image.new('RGB', (W, H), BG)
d  = ImageDraw.Draw(im)

x0, y0, lh = 58 * SCALE, 34 * SCALE, 40 * SCALE
for i, line in enumerate(WORD):
    d.text((x0, y0 + i * lh), line, font=mono, fill=ACCENT)

ty = y0 + len(WORD) * lh + 22 * SCALE
d.text((x0 + 26 * SCALE, ty), 'switch terminal themes live', font=small, fill=FG)

# Every bundled style's real accent, in the order tstyles lists them. Read from
# each scheme.json rather than picked, so the strip cannot drift from the set.
accents = []
for sd in sorted(glob.glob(os.path.join(REPO, 'styles', '*'))):
    p = os.path.join(sd, 'scheme.json')
    if os.path.exists(p):
        s = json.load(open(p))
        accents.append(s.get('brightRed') or s.get('red'))

sw, gap = 28 * SCALE, 7 * SCALE
sx = x0 + 26 * SCALE
sy = ty + 42 * SCALE
for c in accents:
    d.rectangle([sx, sy, sx + sw, sy + 9 * SCALE], fill=c)
    sx += sw + gap

d.text((sx + 14 * SCALE, sy - 4 * SCALE), f'{len(accents)} themes',
       font=ImageFont.truetype(f'{FONTS}/JetBrainsMono-Regular.ttf', 13 * SCALE), fill=MUTED)

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'docs', 'banner.png')
im.save(out)

# What the picture asserts, in a form a test can read.
names = [os.path.basename(d) for d in sorted(glob.glob(os.path.join(REPO, 'styles', '*')))
         if os.path.exists(os.path.join(d, 'scheme.json'))]
with open(os.path.join(REPO, 'docs', 'banner.json'), 'w') as f:
    json.dump({'themes': len(accents), 'styles': names, 'accents': accents}, f, indent=2)
    f.write('\n')
print(f'{out} -> {im.size[0]}x{im.size[1]} ({os.path.getsize(out)/1024:.0f} KB), {len(accents)} swatches')
print('docs/banner.json updated')
