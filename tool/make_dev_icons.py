# Writes the debug build's app icons: the release ones with a red DEV BUILD
# ribbon across the bottom right corner, so a `flutter run` BaoCode is told from an
# installed one at a glance, on the dock, the taskbar and in the app
# switcher.
#
#   python3 -m venv /tmp/brand && /tmp/brand/bin/pip install pillow
#   /tmp/brand/bin/python tool/make_dev_icons.py
#
# macOS: macos/Runner/Assets.xcassets/AppIcon-Dev.appiconset, from AppIcon's
# (the Debug configuration's ASSETCATALOG_COMPILER_APPICON_NAME). Windows:
# windows/runner/resources/app_icon_dev.ico, from app_icon.ico (Runner.rc
# takes it when BAOCODE_DEV_ICON is defined, as it is for Debug). Run it
# again after the release icons change.
import io
import json
import os
import shutil
import struct

from PIL import Image, ImageChops, ImageDraw

RIBBON, LETTER = (0xE5, 0x19, 0x4B), (0xFF, 0xFF, 0xFF)

# Letters in pixels, like the mark: 7 high, a unit apart, a space 3 wide.
GLYPHS = {
    'D': ['XXXX.', 'X...X', 'X...X', 'X...X', 'X...X', 'X...X', 'XXXX.'],
    'E': ['XXXXX', 'X....', 'X....', 'XXXX.', 'X....', 'X....', 'XXXXX'],
    'V': ['X...X', 'X...X', 'X...X', 'X...X', 'X...X', '.X.X.', '..X..'],
    'B': ['XXXX.', 'X...X', 'X...X', 'XXXX.', 'X...X', 'X...X', 'XXXX.'],
    'U': ['X...X', 'X...X', 'X...X', 'X...X', 'X...X', 'X...X', '.XXX.'],
    'I': ['XXX', '.X.', '.X.', '.X.', '.X.', '.X.', 'XXX'],
    'L': ['X....', 'X....', 'X....', 'X....', 'X....', 'X....', 'XXXXX'],
}
ANGLE = 30
# Drawn this many times larger, then rotated and scaled down.
SS = 4


def text_width(text):
    return sum(3 if c == ' ' else len(GLYPHS[c][0]) for c in text) + len(text) - 1


def draw_text(d, text, x, y, unit):
    for c in text:
        if c == ' ':
            x += 4 * unit
            continue
        for row, line in enumerate(GLYPHS[c]):
            for col, cell in enumerate(line):
                if cell == 'X':
                    # Each cell a fifth of a unit wider all round: bold.
                    d.rectangle((x + (col - 0.2) * unit, y + (row - 0.2) * unit,
                                 x + (col + 1.2) * unit - 1, y + (row + 1.2) * unit - 1),
                                fill=LETTER + (255,))
        x += (len(GLYPHS[c][0]) + 1) * unit


def badge(src):
    # A ribbon across the bottom right corner, cut to the icon's body (its
    # shadow, macOS's, below alpha 64, left out).
    im = src.convert('RGBA')
    n = im.width
    body = im.getchannel('A').point(lambda a: max(0, min(255, (a - 64) * 255 // 191)))
    left, top, right, bottom = body.getbbox()
    w = right - left
    # The text as big as fits: DEV BUILD, DEV, or none where even that would
    # be a blur (16 to 48), the ribbon telling it alone.
    text, thick = 'DEV BUILD', 0.2 * w
    unit = 0.5 * thick / 7
    if unit < 1.4:
        text, thick = 'DEV', 0.26 * w
        unit = 0.6 * thick / 7
        if unit < 0.9:
            text = ''
    k = SS
    length, t = 2 * w * k, round(thick * k)
    band = Image.new('RGBA', (length, t), RIBBON + (255,))
    if text:
        u = unit * k
        tw = text_width(text) * u
        draw_text(ImageDraw.Draw(band), text, length / 2 - tw / 2, t / 2 - 3.5 * u, u)
    band = band.rotate(ANGLE, Image.BICUBIC, expand=True)
    layer = Image.new('RGBA', (n * k, n * k), (0, 0, 0, 0))
    cx, cy = (left + 0.57 * w) * k, (top + 0.75 * w) * k
    layer.alpha_composite(band, (round(cx - band.width / 2), round(cy - band.height / 2)))
    layer = layer.resize((n, n), Image.LANCZOS)
    layer.putalpha(ImageChops.multiply(layer.getchannel('A'), body))
    im.alpha_composite(layer)
    return im


def macos():
    src = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    out = 'macos/Runner/Assets.xcassets/AppIcon-Dev.appiconset'
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    with open(f'{src}/Contents.json') as f:
        contents = json.load(f)
    for name in {image['filename'] for image in contents['images']}:
        badge(Image.open(f'{src}/{name}')).save(f'{out}/{name}', optimize=True)
    shutil.copy(f'{src}/Contents.json', f'{out}/Contents.json')


def windows():
    # Each of the icon's sizes badged as it is (they are drawn apart, not
    # scaled from one), written back as PNG entries.
    with open('windows/runner/resources/app_icon.ico', 'rb') as f:
        data = f.read()
    count = struct.unpack('<HHH', data[:6])[2]
    frames = []
    for i in range(count):
        size, offset = struct.unpack('<II', data[14 + 16 * i:22 + 16 * i])
        png = io.BytesIO()
        badge(Image.open(io.BytesIO(data[offset:offset + size]))).save(png, 'PNG', optimize=True)
        frames.append(png.getvalue())
    head = struct.pack('<HHH', 0, 1, count)
    offset = 6 + 16 * count
    for i, png in enumerate(frames):
        w, h = Image.open(io.BytesIO(png)).size
        head += struct.pack('<BBBBHHII', w % 256, h % 256, 0, 0, 1, 32, len(png), offset)
        offset += len(png)
    with open('windows/runner/resources/app_icon_dev.ico', 'wb') as f:
        f.write(head + b''.join(frames))


if __name__ == '__main__':
    os.chdir(os.path.join(os.path.dirname(__file__), '..'))
    macos()
    windows()
