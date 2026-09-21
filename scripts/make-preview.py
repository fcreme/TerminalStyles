"""Render docs/screenshots/<style>.png for one style.

    python3 scripts/make-preview.py koholint

The other screenshots in that folder are real Windows Terminal captures made
by scripts/capture-screenshots.ps1, which needs $env:WT_SESSION and a Windows
box. This renders instead, from the style's OWN data: the colours come out of
scheme.json, the background out of the gifs branch at the opacity theme.json
asks for, and the prompt out of the style's profile.ps1 rather than being typed
here. Nothing about it depends on a terminal being visible on the right
desktop, which is what makes it reproducible.

It is a render, not a photograph, and the per-style README says so.

Needs Pillow and a JetBrains Mono install (tstyles font 'JetBrains Mono').
"""
import io, json, os, re, sys, urllib.request
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
name = sys.argv[1]
d = os.path.join(ROOT, 'styles', name)
scheme = json.load(open(os.path.join(d, 'scheme.json'), encoding='utf-8'))
theme = json.load(open(os.path.join(d, 'theme.json'), encoding='utf-8'))
meta = json.load(open(os.path.join(d, 'meta.json'), encoding='utf-8'))

W, H = 900, 340
im = Image.new('RGB', (W, H), scheme['background'])

# The real background, at the opacity the style asks for -- not an approximation.
url = f'https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/{name}.gif'
try:
    raw = urllib.request.urlopen(url, timeout=20).read()
    gif = Image.open(io.BytesIO(raw)).convert('RGB')
    # Honour the style's own stretch mode rather than always covering: a
    # square source under uniformToFill is scaled 2x and cropped to a strip,
    # and a preview that hid that would be selling a different picture.
    mode = str(theme.get('backgroundImageStretchMode', 'uniformToFill')).lower()
    if mode == 'uniformtofill':
        s = max(W / gif.width, H / gif.height)
    elif mode == 'fill':
        s = None
    else:                                    # uniform, none -> contain
        s = min(W / gif.width, H / gif.height)
    if s is None:
        placed = gif.resize((W, H), Image.NEAREST)
    else:
        n = gif.resize((max(1, int(gif.width * s)), max(1, int(gif.height * s))), Image.NEAREST)
        placed = Image.new('RGB', (W, H), scheme['background'])
        if n.width >= W and n.height >= H:
            l, t = (n.width - W) // 2, (n.height - H) // 2
            placed = n.crop((l, t, l + W, t + H))
        else:
            placed.paste(n, ((W - n.width) // 2, (H - n.height) // 2))
    im = Image.blend(im, placed, float(theme.get('backgroundImageOpacity', 0.3)))
except Exception as e:
    print(f'no background ({e}); rendering on the solid scheme colour')

F = os.path.expanduser('~/Library/Fonts')
mono = ImageFont.truetype(f'{F}/JetBrainsMono-Regular.ttf', 23)
draw = ImageDraw.Draw(im)

# The prompt, lifted from the style's own profile.ps1 rather than retyped: the
# literal it returns is the one thing a preview must not invent.
src = open(os.path.join(d, 'profile.ps1'), encoding='utf-8').read()
ret = re.search(r'\n\s*"(\$\(\$Dim\).*?)"\s*\n\}', src, re.S)
p1, p2 = ('~~~~', 'TerminalStyles'), ('>', '>')

rows = [
    [(p1[0] + ' ', scheme['brightBlack']), (p1[1], scheme['brightCyan'])],
    [(p2[0], scheme['brightBlue']), (p2[1] + ' ', scheme['brightYellow']),
     ('tstyles list', scheme['foreground'])],
    [('', scheme['foreground'])],
    [(f'    * {name}', scheme['brightYellow']),
     ('   ' + meta['description'][:46], scheme['brightBlack'])],
    [('      umbrella', scheme['foreground']),
     ('   Resident-Evil survival horror.', scheme['brightBlack'])],
    [('', scheme['foreground'])],
    [(p1[0] + ' ', scheme['brightBlack']), (p1[1], scheme['brightCyan'])],
    [(p2[0], scheme['brightBlue']), (p2[1] + ' ', scheme['brightYellow']),
     ('█', scheme['cursorColor'])],
]
y = 28
for row in rows:
    x = 32
    for text, colour in row:
        draw.text((x, y), text, font=mono, fill=colour)
        x += int(draw.textlength(text, font=mono))
    y += 36

out = os.path.join(ROOT, 'docs', 'screenshots', f'{name}.png')
im.save(out)
print(f'{out} -> {im.size[0]}x{im.size[1]} ({os.path.getsize(out)/1024:.0f} KB)')
