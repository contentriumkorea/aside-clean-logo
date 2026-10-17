"""Render the official vector, inset only hole boundaries, and lock the star.

No generative model or curve fitting is used. The source Bezier coordinates are
immutable. A 0.18-unit inset equals about six pixels at 1024px; the outside
silhouette and the central star retain the original vector geometry.
"""
import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets'
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
SOURCE = json.loads((ASSETS / 'source-path.json').read_text(encoding='utf-8'))
PATH = SOURCE['path']
assert hashlib.sha256(PATH.encode()).hexdigest() == SOURCE['path_sha256']
VIEW = ' '.join(str(v) for v in SOURCE['view_box'])
HOLES = ''.join(part + 'Z' for part in PATH.split('Z')[1:] if part.strip())
INSET = 0.18

# Original star boundary segments. The straight connectors lie inside the
# original black intersections, so they do not introduce a new visible edge.
STAR = '''M11.3266 12.9562
C12.2982 13.5645 13.1549 14.1068 13.9214 14.5766 L16.0101 15.7801
C19.0489 17.3545 20.4632 16.9504 23.3332 13.7455
C23.4095 13.6603 23.5396 13.6444 23.6321 13.7117 L24.241 14.154
C24.3335 14.2212 24.3588 14.3496 24.3013 14.4485
C22.2287 18.0151 22.1108 19.6224 24.2013 21.9244 L26.491 24.0873
C27.1113 24.6244 27.8098 25.2109 28.588 25.8635
C28.6774 25.9385 28.6936 26.07 28.625 26.1644 L28.1896 26.7638
C28.121 26.8582 27.9909 26.8835 27.892 26.8216
C27.0297 26.2825 26.2553 25.7989 25.5521 25.3746 L22.7818 23.8631
C19.9518 22.5911 18.4598 23.2017 15.711 26.272
C15.6346 26.3573 15.5048 26.3729 15.4122 26.3057 L14.8034 25.8634
C14.7108 25.7961 14.6857 25.6675 14.7432 25.5686
C16.9026 21.8517 16.8518 20.3811 14.4211 17.9809 L12.6282 16.3632
C11.9438 15.7787 11.1623 15.1307 10.2822 14.3936
C10.1927 14.3186 10.1765 14.1871 10.2451 14.0926 L11.0289 13.0139
C11.0976 12.9195 11.2276 12.8943 11.3266 12.9562Z'''.replace('\n', ' ')


def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{VIEW}" width="1024" height="1024">{body}</svg>'


def render(source, destination):
    subprocess.run(['node', str(ROOT / 'tools/render-svg.cjs'), str(source), str(destination), '1024'], check=True)


original = ASSETS / 'original-mark.svg'
original.write_text(svg(f'<path d="{PATH}" fill="#000" fill-rule="evenodd"/>'), encoding='utf-8')
render(original, BUILD / 'original-mark.png')
lock_svg = BUILD / 'star-lock.svg'
lock_svg.write_text(svg(f'<path d="{STAR}" fill="#000" stroke="#000" stroke-width="0.06" stroke-linejoin="round"/>'), encoding='utf-8')
render(lock_svg, BUILD / 'star-lock.png')

rect = f'x="{SOURCE["view_box"][0]}" y="{SOURCE["view_box"][1]}" width="{SOURCE["view_box"][2]}" height="{SOURCE["view_box"][3]}"'
definitions = f'''<defs>
<mask id="star-lock" maskUnits="userSpaceOnUse" {rect}>
<rect {rect} fill="#000"/><path d="{STAR}" fill="#fff" stroke="#fff" stroke-width="0.06" stroke-linejoin="round"/>
</mask>
<mask id="logo-alpha" maskUnits="userSpaceOnUse" {rect}>
<rect {rect} fill="#000"/>
<path id="original-bezier" d="{PATH}" fill="#fff" fill-rule="evenodd"/>
<path d="{HOLES}" fill="none" stroke="#000" stroke-width="{INSET * 2}" stroke-linejoin="round"/>
<path d="{PATH}" fill="#fff" fill-rule="evenodd" mask="url(#star-lock)"/>
</mask></defs>'''
for name, color in [('black', '#000000'), ('white', '#ffffff')]:
    target = ASSETS / (name + '.svg')
    target.write_text(svg(f'<metadata>Official source: https://aside.com/; original path SHA256: {SOURCE["path_sha256"]}; hole inset: {INSET}; central star locked.</metadata>' + definitions + f'<rect {rect} fill="{color}" mask="url(#logo-alpha)"/>'), encoding='utf-8')
    render(target, ASSETS / (name + '.png'))
    # Keep the same alpha, with unambiguous RGB even in transparent pixels.
    with Image.open(ASSETS / (name + '.png')) as decoded:
        alpha = decoded.convert('RGBA').getchannel('A')
    original_alpha = Image.open(BUILD / 'original-mark.png').convert('RGBA').getchannel('A')
    # Mask rasterization can round a boundary by one alpha level. Clamp to the
    # immutable source, then copy every fully protected star pixel exactly.
    alpha = ImageChops.darker(alpha, original_alpha)
    star_pixels = Image.open(BUILD / 'star-lock.png').convert('RGBA').getchannel('A').point(lambda v: 255 if v == 255 else 0)
    alpha = Image.composite(original_alpha, alpha, star_pixels)
    im = Image.new('RGBA', alpha.size, color)
    im.putalpha(alpha)
    im.save(ASSETS / (name + '.png'))
    ico = ASSETS / (name + '.ico')
    im.save(ico, format='ICO', bitmap_format='bmp', sizes=[(16,16),(20,20),(24,24),(32,32),(40,40),(48,48),(64,64),(96,96),(128,128),(256,256)])
    data = bytearray(ico.read_bytes())
    for i in range(int.from_bytes(data[4:6], 'little')):
        data[10 + 16*i:12 + 16*i] = b'\x01\x00'
    ico.write_bytes(data)

fixtures = ROOT / 'tests/fixtures'
fixtures.mkdir(exist_ok=True)
if not (fixtures / 'original-mark.png').exists():
    Image.open(BUILD / 'original-mark.png').save(fixtures / 'original-mark.png')
if not (fixtures / 'star-lock.png').exists():
    Image.open(BUILD / 'star-lock.png').save(fixtures / 'star-lock.png')
print('Rendered immutable official Bezier paths; central star locked; hole inset =', INSET)
