"""Render recorded Godot results, without performing or replacing photo analysis.
Development only: uses the already available Pillow runtime; Godot needs no library.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'godot/diagnostics'
report = json.loads((OUT / 'auto_photo_analysis.json').read_text(encoding='utf8'))
photo = Image.open(ROOT / 'blender/reference/pelvicachromis_taeniatus_male.jpg').convert('RGB')
font_path = 'C:/Windows/Fonts/segoeui.ttf'
def font(size): return ImageFont.truetype(font_path, size)
canvas = Image.new('RGB', (1800, 1000), '#10191e')
draw = ImageDraw.Draw(canvas)
draw.text((30, 18), 'Lokale Fotoanalyse · automatische Vorschläge', font=font(34), fill='white')
draw.text((30, 64), 'Cyan: Kontur   ·   Orange: Körperachse   ·   Grün: Auge   ·   Zahlen: bestehende Landmark-Reihenfolge', font=font(21), fill='#b8cbd5')
for key, x, title in [('right', 25, 'Referenzfoto · Kopf rechts'), ('left', 925, 'Gespiegeltes Testfoto · Kopf links')]:
    result = report[key]
    panel = photo.copy() if key == 'right' else photo.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    panel = panel.crop((20, 190, 780, 610)).resize((850, 470), Image.Resampling.LANCZOS)
    d = ImageDraw.Draw(panel)
    def xy(p): return ((p[0]-20)*850/760, (p[1]-190)*470/420)
    contour = [xy(p) for p in result['fish_contour']]
    d.line(contour + [contour[0]], fill='#10e7ef', width=3)
    start, end = xy(result['axis_start']), xy(result['axis_end'])
    d.line([start, end], fill='#ffa83a', width=3)
    for i, p in enumerate(result['suggested_landmarks']):
        px, py = xy(p)
        color = '#70ff80' if i == 1 else '#ffffff'
        d.ellipse((px-5, py-5, px+5, py+5), fill=color, outline='#081013', width=2)
        # Keep all labels in the panel; avoid a number on top of the eye.
        d.text((min(px+8, 826), max(py-25, 0)), str(i+1), font=font(20), fill=color, stroke_width=2, stroke_fill='#10191e')
    draw.text((x, 112), title, font=font(25), fill='white')
    canvas.paste(panel, (x, 155))
    error = ((result['eye_position'][0] - (669 if key == 'right' else 130))**2 + (result['eye_position'][1]-275)**2)**.5
    draw.text((x, 637), f'Auge erkannt · Abstand zum Kontrollpunkt: {error:.1f} px · Kontur: {len(contour)} Punkte', font=font(20), fill='#b8cbd5')
labels = [
    ('1 Schnauzenspitze', 'Kontur-Ende'), ('2 Augenmitte', 'Lokaler Pupillen-/Ringkontrast'),
    ('3/4 Schwanzstiel oben/unten', 'Schmaler Körperabschnitt; geschätzt'),
    ('5/6 Schwanzflosse oben/unten', 'Lokale Kontur-Extrema'),
    ('7 Rückenflosse vorne', 'Längenanteil; Ansatz geschätzt'),
    ('8 Rückenflosse hinten', 'Hintere obere Konturspitze'),
    ('9 Afterflosse vorne', 'Unterer Körperabschnitt; geschätzt'),
    ('10 Afterflosse hinten', 'Hintere untere Konturspitze'),
    ('11 Bauchflossenansatz', 'Kontur und Körperlänge; geschätzt'),
    ('12 Bauchflossenspitze', 'Lokales unteres Kontur-Extrem'),
]
for i, (label, method) in enumerate(labels):
    x = 30 + (i % 3)*595
    y = 695 + (i // 3)*61
    draw.text((x, y), label, font=font(21), fill='white')
    draw.text((x, y+26), method, font=font(17), fill='#a9bac5')
draw.text((30, 955), 'Alle Vorschläge bleiben editierbar. Transparente Flossenränder und anatomische Ansätze unbedingt prüfen.', font=font(23), fill='#ffc879')
canvas.save(OUT / 'auto_photo_analysis.png')
print(OUT / 'auto_photo_analysis.png')
