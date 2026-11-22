#!/usr/bin/env python3
"""Draws the app icon (assets/icon/icon.png) and the Android TV banner."""
from PIL import Image, ImageDraw, ImageFont

B = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'


def bg(w, h, r):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    grad = Image.new('RGBA', (w, h))
    d = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(46 + 30 * t), int(98 + 20 * t), int(196 - 40 * t), 255))
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], r, fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def glyphs(img, x, y, s):
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([x, y, x + s * 0.62, y + s * 0.5], s * 0.08, fill=(255, 255, 255, 255))
    d.text((x + s * 0.31, y + s * 0.25), 'A', font=ImageFont.truetype(B, int(s * 0.36)), fill=(46, 98, 196, 255), anchor='mm')
    d.rounded_rectangle([x + s * 0.38, y + s * 0.38, x + s, y + s * 0.88], s * 0.08, fill=(255, 196, 61, 255))
    d.text((x + s * 0.69, y + s * 0.63), 'ʃ', font=ImageFont.truetype(B, int(s * 0.36)), fill=(30, 30, 30, 255), anchor='mm')
    # speech waves
    for i, k in enumerate((0.10, 0.17)):
        d.arc([x - s * k, y + s * 0.62 - s * k, x + s * k, y + s * 0.62 + s * k], 110, 250,
              fill=(255, 255, 255, 230), width=max(2, int(s * 0.03)))


icon = bg(1024, 1024, 220)
glyphs(icon, 230, 200, 600)
icon.save('assets/icon/icon.png')
sq = bg(1024, 1024, 0)
glyphs(sq, 230, 200, 600)
sq.convert('RGB').save('assets/icon/icon_square.png')
fg = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
glyphs(fg, 300, 270, 440)
fg.save('assets/icon/icon_foreground.png')
banner = bg(320, 180, 16)
glyphs(banner, 22, 40, 100)
d = ImageDraw.Draw(banner)
d.text((140, 72), 'Universal', font=ImageFont.truetype(B, 26), fill='white', anchor='lm')
d.text((140, 106), 'Translator', font=ImageFont.truetype(B, 26), fill='white', anchor='lm')
import os
os.makedirs('android/app/src/main/res/drawable-xhdpi', exist_ok=True)
banner.save('android/app/src/main/res/drawable-xhdpi/tv_banner.png')
print('ok')
