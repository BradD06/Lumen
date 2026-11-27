#!/usr/bin/env python3
"""Иконка Lumen для всех платформ из одного описания (рисунок ниже).

Запуск из корня репозитория: python3 tool/make_icons.py  (нужен Pillow).
Пишет готовые файлы для Windows (.ico 16–256), macOS, iOS и Android.
Рисунок: белый лист с тремя строками и сиреневая плашка под ним
на графитовом фоне (как в Lumen_exemple, docs/design/app-icon).
"""
import io
import json
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SS = 4  # сглаживание: рисуем крупнее и уменьшаем

TOP, BOTTOM = (0x23, 0x23, 0x27), (0x12, 0x12, 0x14)
PAPER, LINE, ACCENT = (255, 255, 255), (0xC9, 0xC9, 0xD0), (0x84, 0x82, 0xFF)

# Насколько рисунок крупнее, чем в Lumen_exemple: на панели задач Windows
# и в доке он был мелким. 1.0 = исходный размер.
GLYPH_SCALE = 1.15


def gradient(size):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        g.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return g.resize((size, size))


def draw_glyph(img, box, scale=GLYPH_SCALE, small=False):
    """Рисует лист и плашку в квадрате box=(x, y, side), координаты как в SVG 0–100."""
    bx, by, side = box
    d = ImageDraw.Draw(img)

    def p(x, y):  # 0–100 → пиксели, масштаб вокруг центра рисунка (50, 50.5)
        return (bx + (50 + (x - 50) * scale) * side / 100,
                by + (50.5 + (y - 50.5) * scale) * side / 100)

    def rrect(x, y, w, h, r, fill):
        x0, y0 = p(x, y)
        x1, y1 = p(x + w, y + h)
        d.rounded_rectangle((x0, y0, x1, y1), radius=r * scale * side / 100, fill=fill)

    rrect(29, 18, 42, 50, 6, PAPER)
    # В маленьких размерах (16–32 px) три тонкие строки сливаются в серое
    # пятно: две строки потолще читаются лучше.
    lines = [(31.5, 63), (43, 54)] if small else [(32, 63), (40, 63), (48, 54)]
    stroke = 5.5 if small else 3
    for y, x_end in lines:
        rrect(37 - stroke / 2, y - stroke / 2, x_end - 37 + stroke, stroke, stroke / 2, LINE)
    rrect(35, 74, 30, 9, 4.5, ACCENT)


def finish(big, size):
    return big.resize((size, size), Image.LANCZOS)


def full_square(size):
    """Квадрат без прозрачности: iOS (система сама скругляет углы)."""
    s = size * SS
    img = gradient(s).convert("RGBA")
    draw_glyph(img, (0, 0, s), small=size <= 32)
    return finish(img, size).convert("RGB")


def tile(size, inset, radius, shadow=False, border=False, scale=GLYPH_SCALE):
    """Скруглённая плитка на прозрачном фоне (Windows, macOS, старый Android).

    inset и radius — доли стороны иконки.
    """
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    x0 = round(s * inset)
    side = s - 2 * x0
    r = side * radius
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((x0, x0, x0 + side - 1, x0 + side - 1), radius=r, fill=255)
    if shadow:  # тень как у иконок macOS
        sh = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        sh.putalpha(mask.point(lambda v: v * 0.35))
        sh = sh.transform((s, s), Image.AFFINE, (1, 0, 0, 0, 1, -s * 0.01))
        sh = sh.filter(ImageFilter.GaussianBlur(s * 0.012))
        img.alpha_composite(sh)
    body = gradient(s).convert("RGBA")
    draw_glyph(body, (x0, x0, side), scale=scale, small=size <= 32)
    if border:
        ImageDraw.Draw(body).rounded_rectangle(
            (x0 + SS, x0 + SS, x0 + side - 1 - SS, x0 + side - 1 - SS),
            radius=r - SS, outline=(255, 255, 255, 31), width=max(1, s // 512))
    body.putalpha(mask)
    img.alpha_composite(body)
    return finish(img, size)


def png_bytes(im):
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def write_ico(path, images):
    """ICO из нескольких PNG: каждый размер нарисован отдельно, без растяжения."""
    data = [png_bytes(im) for im in images]
    head = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries = b""
    for im, blob in zip(images, data):
        w = im.width if im.width < 256 else 0
        entries += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    path.write_bytes(head + entries + b"".join(data))


def save(im, rel):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG", optimize=True)


def windows():
    # Плитка почти во весь квадрат, как у других программ на панели задач.
    # Тёмная плитка сливается с тёмной панелью, поэтому лист здесь крупнее:
    # видно в основном его, и он должен занимать иконку почти целиком.
    sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    write_ico(ROOT / "windows/runner/resources/app_icon.ico",
              [tile(n, inset=0.03, radius=0.22, border=n >= 32, scale=1.3) for n in sizes])


def macos():
    # Сетка Apple: плитка 824 из 1024 с тенью, так выглядят все иконки в доке.
    folder = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for n in [16, 32, 64, 128, 256, 512, 1024]:
        save(tile(n, inset=100 / 1024, radius=185 / 824, shadow=n >= 64, border=n >= 128),
             f"{folder}/app_icon_{n}.png")


def ios():
    folder = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for item in json.loads((folder / "Contents.json").read_text())["images"]:
        pt = float(item["size"].split("x")[0])
        px = round(pt * int(item["scale"][0]))
        save(full_square(px), folder.relative_to(ROOT) / item["filename"])


def android():
    res = "android/app/src/main/res"
    # Адаптивная иконка (Android 8+): холст 108 dp, видно круг/квадрат 72 dp
    # в центре. Рисунок в безопасной зоне 66 dp, по размеру как на других
    # платформах относительно видимой части.
    for name, k in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]:
        n = round(108 * k)
        save(gradient(n), f"{res}/drawable-{name}/ic_launcher_background.png")
        fg = Image.new("RGBA", (n * SS, n * SS), (0, 0, 0, 0))
        visible = n * SS * 72 / 108
        off = (n * SS - visible) / 2
        draw_glyph(fg, (off, off, visible))
        save(finish(fg, n), f"{res}/drawable-{name}/ic_launcher_foreground.png")
        # Старые Android (до 8): готовая плитка 48 dp.
        m = round(48 * k)
        save(tile(m, inset=1 / 48, radius=0.2), f"{res}/mipmap-{name}/ic_launcher.png")


def sources():
    """Крупные PNG для дизайна и для экранов приложения."""
    save(full_square(1024), "assets/icon/icon-square.png")
    save(tile(1024, inset=100 / 1024, radius=185 / 824, shadow=True, border=True),
         "assets/icon/icon-rounded.png")


if __name__ == "__main__":
    windows()
    macos()
    ios()
    android()
    sources()
    print("Иконки обновлены.")
