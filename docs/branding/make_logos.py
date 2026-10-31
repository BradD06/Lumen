#!/usr/bin/env python3
"""Generates the 15 Lumen logo concepts (SVG, 512x512, app-icon shape) and preview.html."""
from pathlib import Path

OUT = Path(__file__).parent / "logos"
OUT.mkdir(exist_ok=True)

def icon(bg, body, defs=""):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
<defs>{defs}</defs>
<rect width="512" height="512" rx="114" fill="{bg}"/>
{body}
</svg>
'''

GLOW = '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
AMBER = '<linearGradient id="amber" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFE29A"/><stop offset="1" stop-color="#FF9F2E"/></linearGradient>'

LOGOS = [
    ("01-glowing-l", "Светящаяся L", "Буква L из луча света на тёмном фоне — прямое прочтение «люмен».",
     icon("#14182B", '<path d="M176 120v232h160" fill="none" stroke="url(#amber)" stroke-width="56" stroke-linecap="round" stroke-linejoin="round" filter="url(#glow)"/>', AMBER + GLOW)),
    ("02-book-ray", "Книга с лучом", "Раскрытая книга, из корешка которой выходит свет — про чтение и обучение.",
     icon("#F6F1E7", '<path d="M256 330 L256 120" stroke="url(#amber)" stroke-width="22" stroke-linecap="round"/><path d="M196 150 L226 200 M316 150 L286 200" stroke="#FFB648" stroke-width="16" stroke-linecap="round"/>'
          '<path d="M96 250 Q176 220 256 270 Q336 220 416 250 V390 Q336 360 256 410 Q176 360 96 390Z" fill="#2B3A67"/><path d="M256 270 V410" stroke="#F6F1E7" stroke-width="8"/>', AMBER)),
    ("03-page-bulb", "Страница-лампочка", "Лист с загнутым углом, внутри — лампочка-идея. Заметки + озарение.",
     icon("#FFFFFF", '<path d="M136 96h176l64 64v256a24 24 0 0 1-24 24H136a24 24 0 0 1-24-24V120a24 24 0 0 1 24-24z" fill="#F2F4F8" stroke="#1F2433" stroke-width="16"/><path d="M312 96v64h64" fill="none" stroke="#1F2433" stroke-width="16" stroke-linejoin="round"/>'
          '<circle cx="244" cy="262" r="62" fill="url(#amber)"/><rect x="220" y="330" width="48" height="16" rx="6" fill="#1F2433"/><rect x="226" y="352" width="36" height="12" rx="6" fill="#1F2433"/>', AMBER)),
    ("04-sunrise-pages", "Рассвет над страницами", "Солнце встаёт над стопкой листов — «каждый день чуть умнее».",
     icon("#2D2A6E", '<circle cx="256" cy="290" r="96" fill="url(#amber)"/><rect x="96" y="290" width="320" height="130" fill="#2D2A6E"/>'
          '<rect x="112" y="300" width="288" height="24" rx="12" fill="#ECE8FF"/><rect x="132" y="340" width="248" height="24" rx="12" fill="#B9B2F2"/><rect x="152" y="380" width="208" height="24" rx="12" fill="#7E74D9"/>', AMBER)),
    ("05-glowing-block", "Светящийся блок", "Стопка блоков как в редакторе, один горит — блочные страницы.",
     icon("#101418", '<rect x="120" y="120" width="272" height="64" rx="16" fill="#2A323C"/><rect x="120" y="224" width="272" height="64" rx="16" fill="url(#amber)" filter="url(#glow)"/><rect x="120" y="328" width="180" height="64" rx="16" fill="#2A323C"/>', AMBER + GLOW)),
    ("06-quote-flame", "Цитата-пламя", "Кавычка, превращающаяся в огонёк — выписки и цитаты из книг.",
     icon("#1C1E26", '<path d="M210 140 C150 200 130 260 160 320 a56 56 0 1 0 60-60 C200 230 200 190 210 140z" fill="url(#amber)"/><path d="M330 140 C270 200 250 260 280 320 a56 56 0 1 0 60-60 C320 230 320 190 330 140z" fill="#FF7A45"/>', AMBER)),
    ("07-candle", "Свеча", "Минималистичный огонёк на кремовом фоне — тихое вечернее чтение.",
     icon("#FBF4E6", '<path d="M256 110 C300 180 320 220 306 262 a52 52 0 0 1-100 0 C192 220 212 180 256 110z" fill="url(#amber)"/><path d="M256 190 C272 220 278 240 270 258 a16 16 0 0 1-28 0 C236 240 240 220 256 190z" fill="#FFF7DD"/>'
          '<rect x="226" y="300" width="60" height="120" rx="12" fill="#3B3355"/>', AMBER)),
    ("08-prism", "Призма", "Белый луч распадается на спектр — темы, виджеты, кастомизация.",
     icon("#0F1020", '<path d="M70 280 L220 260" stroke="#FFFFFF" stroke-width="14" stroke-linecap="round"/><path d="M256 140 L340 360 H172Z" fill="none" stroke="#E8E8FF" stroke-width="14" stroke-linejoin="round"/>'
          + "".join(f'<path d="M292 270 L450 {200+i*28}" stroke="{c}" stroke-width="16" stroke-linecap="round"/>' for i, c in enumerate(["#FF5A5F", "#FFB648", "#FFE45C", "#4CD38A", "#4AA8FF", "#9B6BFF"])))),
    ("09-lighthouse", "Маяк", "Маяк, освещающий путь — ориентир в задачах и знаниях.",
     icon("#123B5C", '<path d="M256 250 L470 190 V310Z" fill="#FFE29A" opacity=".55"/><path d="M226 190h60l20 230H206z" fill="#F4F6FA"/><path d="M216 290h80v30h-80zM210 360h92v30h-92z" fill="#E4534A"/>'
          '<rect x="220" y="150" width="72" height="44" rx="8" fill="url(#amber)"/><path d="M212 150 L256 112 L300 150Z" fill="#E4534A"/>', AMBER)),
    ("10-widget-star", "Звезда в сетке виджетов", "Сетка 2×2, одна плитка — звезда. Намёк на магазин виджетов.",
     icon("#F0F2FF", '<rect x="112" y="112" width="128" height="128" rx="32" fill="#5B5FEF"/><rect x="272" y="112" width="128" height="128" rx="32" fill="#A6A8FF"/><rect x="112" y="272" width="128" height="128" rx="32" fill="#A6A8FF"/>'
          '<rect x="272" y="272" width="128" height="128" rx="32" fill="url(#amber)"/><path d="M336 298l14 29 32 4-23 22 6 32-29-15-29 15 6-32-23-22 32-4z" fill="#FFFFFF"/>', AMBER)),
    ("11-moon-bookmark", "Луна и закладка", "Полумесяц, ставший закладкой — читать в любое время, место не потеряется.",
     icon("#1A1F3D", '<path d="M300 104 A160 160 0 1 0 410 330 A130 130 0 1 1 300 104z" fill="url(#amber)"/><path d="M200 220 h72 v150 l-36 -28 l-36 28z" fill="#E9ECFF"/>', AMBER)),
    ("12-rings", "Кольца света", "Концентрические круги расходятся от точки — люмен как единица света.",
     icon("#0E1116", '<circle cx="256" cy="256" r="150" fill="none" stroke="#FF9F2E" stroke-width="10" opacity=".35"/><circle cx="256" cy="256" r="108" fill="none" stroke="#FFB648" stroke-width="14" opacity=".6"/>'
          '<circle cx="256" cy="256" r="66" fill="none" stroke="#FFD27A" stroke-width="18"/><circle cx="256" cy="256" r="28" fill="#FFF3D1" filter="url(#glow)"/>', GLOW)),
    ("13-ribbon-spark", "Лента-закладка с искрой", "Закладка с искрой на кончике — «отмеченное важное».",
     icon("#E94F64", '<path d="M176 96h160v320l-80-64-80 64z" fill="#FFFFFF"/><path d="M256 168l14 38 38 14-38 14-14 38-14-38-38-14 38-14z" fill="#E94F64"/>')),
    ("14-l-dot", "Монограмма L·", "Строгая монограмма L с точкой-искрой — для иконки и подписи.",
     icon("#FFFFFF", '<path d="M170 120v260h130" fill="none" stroke="#14182B" stroke-width="60" stroke-linecap="round" stroke-linejoin="round"/><circle cx="350" cy="190" r="36" fill="url(#amber)"/>', AMBER)),
    ("15-firefly", "Светлячок", "Светлячок со светящимся хвостом-траекторией — живой, дружелюбный маскот.",
     icon("#13241F", '<path d="M110 380 C180 380 200 300 260 290" fill="none" stroke="#C9F27A" stroke-width="10" stroke-linecap="round" stroke-dasharray="2 22" opacity=".8"/>'
          '<circle cx="300" cy="270" r="44" fill="#DFFF8F" filter="url(#glow)"/><ellipse cx="330" cy="222" rx="40" ry="22" fill="#FFFFFF" opacity=".7" transform="rotate(-30 330 222)"/><ellipse cx="350" cy="250" rx="34" ry="18" fill="#FFFFFF" opacity=".5" transform="rotate(-10 350 250)"/>'
          '<circle cx="330" cy="200" r="24" fill="#2B4A3F"/>', GLOW)),
]

cards = []
for slug, title, desc, svg in LOGOS:
    (OUT / f"{slug}.svg").write_text(svg)
    n = slug[:2]
    cards.append(f'<figure><img src="logos/{slug}.svg" alt="{title}"><figcaption><b>{n}. {title}</b><span>{desc}</span></figcaption></figure>')

(Path(__file__).parent / "preview.html").write_text(f'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lumen — логотипы</title><style>
body{{margin:0;padding:32px 16px;font:15px/1.4 -apple-system,system-ui,sans-serif;background:#F4F4F6;color:#1F2433}}
h1{{text-align:center;font-weight:700}}main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:24px;max-width:1200px;margin:auto}}
figure{{margin:0;background:#fff;border-radius:20px;padding:16px;box-shadow:0 1px 3px #0001}}img{{width:100%;display:block}}
figcaption{{margin-top:10px;display:grid;gap:4px}}figcaption span{{color:#6B7080;font-size:13px}}
</style></head><body><h1>Lumen — 15 вариантов логотипа</h1><main>{"".join(cards)}</main></body></html>
''')
print(f"wrote {len(LOGOS)} logos")
