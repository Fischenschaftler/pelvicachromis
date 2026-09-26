"""Compose original / actual clicked contour / actual generated mask diagnostic."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageOps
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'godot/diagnostics'
data=json.loads((OUT/'mask_contour.json').read_text(encoding='utf8'))
photo=Image.open(data['photo_path']).convert('RGBA')
mask=Image.open(OUT/'mask_fish_4000x3000.png').convert('L')
assert photo.size==mask.size==(4000,3000)
outline=photo.copy();draw=ImageDraw.Draw(outline)
points=[tuple(p) for p in data['points']]
draw.line(points+[points[0]],fill=(255,205,35,255),width=12)
for x,y in points:draw.ellipse((x-17,y-17,x+17,y+17),fill=(255,205,35,255))
cutout=photo.copy();cutout.putalpha(mask)
checker=Image.new('RGBA',photo.size,(190,190,190,255));draw=ImageDraw.Draw(checker)
for y in range(0,photo.height,100):
 for x in range(0,photo.width,100):
  if (x//100+y//100)%2:draw.rectangle((x,y,x+99,y+99),fill=(215,215,215,255))
checker.alpha_composite(cutout)
canvas=Image.new('RGB',(2400,660),(242,242,242));draw=ImageDraw.Draw(canvas)
for index,(label,image) in enumerate([('Originalfoto - 4000 x 3000',photo),('Geklickte Polygonkontur',outline),('Freistellung aus gespeicherter Maske',checker)]):
 canvas.paste(ImageOps.contain(image.convert('RGB'),(780,585)),(index*800+10,65))
 draw.text((index*800+20,20),label,fill=(20,20,20),font_size=25)
canvas.save(OUT/'photo_mask_comparison.png')
