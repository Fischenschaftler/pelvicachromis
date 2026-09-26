"""Inspect saved body transfer pixel invariants and compose real Godot diagnostics."""
from pathlib import Path
import json, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageOps, ImageFont
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'godot/diagnostics'
report=json.loads((OUT/'body_transfer_validation.json').read_text(encoding='utf8'))
base=Image.open(ROOT/'textures/pelvicachromis_taeniatus_male_albedo.png').convert('RGBA')
texture=Image.open(report['texture_path']).convert('RGBA')
coverage=Image.open(report['coverage_path']).convert('L')
mask=Image.open(report['body_mask_path']).convert('L')
normalized=Image.open(report['normalized_path']).convert('RGBA')
a=np.asarray(base);b=np.asarray(texture);covered=np.asarray(coverage)>127
changed=np.any(a!=b,axis=2)
assert np.count_nonzero(changed & ~covered)==0,'Untouched atlas area changed'
slots=json.loads((ROOT/'blender/diagnostics/uv_validation.json').read_text(encoding='utf8'))['islands']
fin_changes={}
for island in slots:
    if 'Fin' not in island['object']:continue
    x0,y0,x1,y1=island['slot'];w,h=texture.size
    patch=changed[int((1-y1)*h):int((1-y0)*h)+1,int(x0*w):int(x1*w)+1]
    fin_changes[island['name']]=int(patch.sum())
assert not any(fin_changes.values()),fin_changes
protected=json.loads((OUT/'photo_import_protected.json').read_text(encoding='utf8'))
modified=[name for name,digest in protected.items() if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
assert not modified,modified
pixel_report={'texture_size':list(texture.size),'changed_texels':int(changed.sum()),'changed_outside_coverage':0,'fin_slot_changes':fin_changes,'protected_files_checked':len(protected),'protected_files_changed':modified}
(OUT/'body_pixel_validation.json').write_text(json.dumps(pixel_report,indent=2),encoding='utf8')
mask.save(OUT/'body_source_mask.png')
normalized.save(OUT/'body_normalized_reference.png')
uv=texture.copy();uv.putalpha(coverage)
uv.thumbnail((1400,1400));uv.save(OUT/'body_uv_texture.png')
canvas=Image.new('RGB',(2400,1740),(22,29,36));draw=ImageDraw.Draw(canvas)
font=lambda n:ImageFont.truetype('C:/Windows/Fonts/arial.ttf',n)
def tile(img,rect,label,checker=False):
    x,y,w,h=rect
    draw.text((x+12,y+8),label,fill='white',font=font(25))
    if checker:
        for yy in range(y+48,y+h,24):
            for xx in range(x,x+w,24):
                c=(60,68,76) if ((xx-x)//24+(yy-y-48)//24)%2 else (48,55,63)
                draw.rectangle((xx,yy,min(xx+23,x+w-1),min(yy+23,y+h-1)),fill=c)
    image=ImageOps.contain(img,(w-24,h-64))
    at=(x+(w-image.width)//2,y+48+(h-64-image.height)//2)
    canvas.paste(image,at,image if image.mode=='RGBA' else None)
tile(normalized,(0,0,800,570),'Normalisierte Referenz',True)
cut=normalized.copy();cut.putalpha(Image.fromarray(np.minimum(np.asarray(normalized.getchannel('A')),np.asarray(mask))))
tile(cut,(800,0,800,570),'Körpermaske · Flossen ausgeschlossen',True)
tile(uv,(1600,0,800,570),'Neu belegte Körper-UV-Flächen',True)
# Same crop and scale for both materials at each camera angle.
for row,angle in enumerate(['side','oblique']):
    images=[Image.open(OUT/f'body_{mode}_{angle}.png').convert('RGB') for mode in ['original','generated']]
    points=[]
    for image in images:
        ar=np.asarray(image).astype(int);diff=np.max(np.abs(ar-ar[0,0]),axis=2)>8
        ys,xs=np.nonzero(diff);points.append((xs.min(),ys.min(),xs.max()+1,ys.max()+1))
    box=(max(0,min(p[0] for p in points)-35),max(0,min(p[1] for p in points)-35),min(images[0].width,max(p[2] for p in points)+35),min(images[0].height,max(p[3] for p in points)+35))
    for column,(mode,image) in enumerate(zip(['Originalfärbung','Generierte Körperfärbung'],images)):
        tile(image.crop(box),(column*1200,590+row*565,1200,550),mode+(' · Seite' if angle=='side' else ' · schräg'))
canvas.save(OUT/'body_transfer_comparison.png')
print(json.dumps(pixel_report))
