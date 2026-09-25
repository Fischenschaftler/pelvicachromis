"""Compose existing renders at identical scale; no texture editing."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'blender/diagnostics'
for view in ['front','oblique']:
    canvas=Image.new('RGB',(2800,1080),(235,235,235))
    for x,label,title in [(0,'before','Vorher: 7,37 mm Koerperbreite'),(1400,'after','Nachher: 11,06 mm Koerperbreite (1,5x)')]:
        canvas.paste(Image.open(OUT/f'width_{label}_{view}.png').convert('RGB'),(x,80))
        ImageDraw.Draw(canvas).text((x+35,22),title,fill=(20,20,20),font_size=30)
    canvas.save(OUT/f'width_comparison_{view}.png')
