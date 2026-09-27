"""Pixel invariants and diagnostic assembled from actual masks/textures/Godot renders."""
from pathlib import Path
import json,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageOps,ImageFont
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'godot/diagnostics'
record=json.loads((OUT/'fin_transfer_validation.json').read_text(encoding='utf8'))
base=Image.open(record['body_texture_path']).convert('RGBA')
combined=Image.open(record['texture_path']).convert('RGBA')
photo=Image.open(record['normalized_path']).convert('RGBA')
coverage=Image.open(record['coverage_path']).convert('L')
changed=np.any(np.asarray(base)!=np.asarray(combined),axis=2)
assert not np.any(changed & (np.asarray(coverage)<128))
config=json.loads((ROOT/'data/fin_projection.json').read_text(encoding='utf8'))['fins']
allowed=np.zeros(changed.shape,dtype=bool)
counts={}
for name,fin in config.items():
 x0,y0,x1,y1=fin['slot_blender_v'];w,h=combined.size
 r=(slice(int((1-y1)*h),int((1-y0)*h)+1),slice(int(x0*w),int(x1*w)+1))
 allowed[r]=True;counts[name]=int(changed[r].sum())
 mask=Image.open(record['fins'][name]['mask_path']).convert('L')
 assert mask.size==photo.size
 assert not np.any((np.asarray(mask)>127)&(np.asarray(photo.getchannel('A'))==0))
 mask.save(OUT/f'fin_mask_{name}.png')
assert not np.any(changed & ~allowed),'Body or protected atlas pixels changed'
protected=json.loads((OUT/'photo_import_protected.json').read_text(encoding='utf8'))
modified=[name for name,digest in protected.items() if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
assert not modified,modified
report={'changed_by_fin':counts,'changes_outside_three_fin_slots':0,'changes_outside_coverage':0,'body_unchanged':True,'protected_files_checked':len(protected),'protected_files_changed':modified}
(OUT/'fin_pixel_validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
annotated=photo.copy();d=ImageDraw.Draw(annotated)
colors={'Caudal_Fin':(255,205,50),'Dorsal_Fin':(50,255,205),'Anal_Fin':(255,100,205)}
for name,item in record['fins'].items():
 pts=[tuple(p) for p in item['points_normalized_px']]
 d.line(pts+[pts[0]],fill=colors[name],width=6)
 for x,y in pts:d.ellipse((x-7,y-7,x+7,y+7),fill=colors[name])
annotated.save(OUT/'fin_mask_overlay.png')
uv=combined.copy();uv.putalpha(coverage);uv.thumbnail((1400,1400));uv.save(OUT/'fin_uv_regions.png')
canvas=Image.new('RGB',(2400,1740),(22,29,36));draw=ImageDraw.Draw(canvas)
font=lambda n:ImageFont.truetype('C:/Windows/Fonts/arial.ttf',n)
def tile(image,rect,label,checker=False):
 x,y,w,h=rect;draw.text((x+12,y+8),label,fill='white',font=font(25))
 if checker:
  for yy in range(y+48,y+h,24):
   for xx in range(x,x+w,24):
    color=(60,68,76) if ((xx-x)//24+(yy-y-48)//24)%2 else (48,55,63)
    draw.rectangle((xx,yy,min(xx+23,x+w-1),min(yy+23,y+h-1)),fill=color)
 fitted=ImageOps.contain(image,(w-24,h-64));at=(x+(w-fitted.width)//2,y+48+(h-64-fitted.height)//2)
 canvas.paste(fitted,at,fitted if fitted.mode=='RGBA' else None)
tile(photo,(0,0,800,570),'Normalisierte Referenz',True)
tile(annotated,(800,0,800,570),'Konturen: Schwanz / Rücken / After',True)
tile(uv,(1600,0,800,570),'Drei neue Flossen-UV-Bereiche',True)
for row,angle in enumerate(['side','oblique']):
 images=[Image.open(OUT/f'fin_{mode}_{angle}.png').convert('RGB') for mode in ['original','generated']]
 bounds=[]
 for im in images:
  a=np.asarray(im).astype(int);ys,xs=np.nonzero(np.max(np.abs(a-a[0,0]),axis=2)>8)
  bounds.append((xs.min(),ys.min(),xs.max()+1,ys.max()+1))
 box=(max(0,min(b[0] for b in bounds)-35),max(0,min(b[1] for b in bounds)-35),min(images[0].width,max(b[2] for b in bounds)+35),min(images[0].height,max(b[3] for b in bounds)+35))
 for column,(label,image) in enumerate(zip(['Originalfärbung','Generiert: Körper + drei Flossen'],images)):
  tile(image.crop(box),(column*1200,590+row*565,1200,550),label+(' · Seite' if angle=='side' else ' · schräg'))
canvas.save(OUT/'fin_transfer_comparison.png')
print(json.dumps(report))
