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
import io, json, os, re, subprocess, sys, urllib.request
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
# Solid-ground styles ship a .png rather than an animated .gif -- a colour is
# not a picture, and the file exists to wipe the previous style's wallpaper.
ext = 'png' if name in ('gitbash', 'sober', 'phosphor') else 'gif'
url = f'https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/{name}.{ext}'
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
    elif mode == 'none':
        # NOT contain. 'none' means draw it at its own size -- the whole point
        # of the styles that ask for it. Treating it as contain made the
        # preview shrink a 660-wide image to 255 and show a fit no style asks
        # for, which is the same class of lie as hardcoding the prompt was.
        s = 1.0
    else:                                    # uniform -> contain
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
            align = str(theme.get('backgroundImageAlignment', 'center')).lower()
            top = H - n.height if 'bottom' in align else (0 if 'top' in align
                                                          else (H - n.height) // 2)
            placed.paste(n, ((W - n.width) // 2, top))
    im = Image.blend(im, placed, float(theme.get('backgroundImageOpacity', 0.3)))
except Exception as e:
    print(f'no background ({e}); rendering on the solid scheme colour')

F = os.path.expanduser('~/Library/Fonts')
mono = ImageFont.truetype(f'{F}/JetBrainsMono-Regular.ttf', 23)
draw = ImageDraw.Draw(im)

# The prompt, obtained by RUNNING the style's profile.ps1 and calling the
# function it defines -- not by reading a literal out of it, and certainly not
# by hardcoding one. The first version of this file did the last of those while
# its own docstring claimed the first, so every preview rendered koholint's
# prompt regardless of the style it was previewing.
def style_prompt(style_dir):
    ps = os.path.join(style_dir, 'profile.ps1')
    if not os.path.exists(ps):
        return []
    script = (
        f'. "{ps}" *> $null; '
        'Set-Location $HOME; '
        '$p = prompt; '
        '[Console]::Out.Write($p)'
    )
    try:
        out = subprocess.run(['pwsh-preview', '-NoProfile', '-Command', script],
                             capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return []
    # Split the returned string into (text, colour) runs on its SGR escapes.
    rows, cur, colour = [], [], None
    for line in out.split('\n'):
        cur = []
        for part in re.split(r'(\x1b\[[0-9;]*m)', line):
            if not part:
                continue
            m = re.fullmatch(r'\x1b\[38;2;(\d+);(\d+);(\d+)m', part)
            if m:
                colour = '#%02x%02x%02x' % tuple(int(g) for g in m.groups())
                continue
            if re.fullmatch(r'\x1b\[[0-9;]*m', part):
                colour = None
                continue
            cur.append((part, colour or scheme['foreground']))
        rows.append(cur)
    return rows

prompt_rows = style_prompt(d)
if not prompt_rows:
    prompt_rows = [[('$ ', scheme['foreground'])]]

def line(extra):
    return prompt_rows[-1] + extra

rows = []
rows += prompt_rows[:-1]
rows.append(line([('tstyles list', scheme['foreground'])]))
rows.append([('', scheme['foreground'])])
rows.append([(f'    * {name}', scheme['cursorColor']),
             ('   ' + meta['description'][:40], scheme['brightBlack'])])
rows.append([('      umbrella', scheme['foreground']),
             ('   Resident-Evil survival horror.', scheme['brightBlack'])])
rows.append([('', scheme['foreground'])])
rows += prompt_rows[:-1]
rows.append(line([('\u2588', scheme['cursorColor'])]))

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
