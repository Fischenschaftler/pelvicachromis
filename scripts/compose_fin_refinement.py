"""Reproducible comparison of actual Godot renders and photo sampling triangles."""
from pathlib import Path
import json
import numpy as np
from PIL import Image,ImageDraw,ImageOps,ImageFont
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'godot/diagnostics'
record=json.loads((OUT/'fin_transfer_validation.json').read_text(encoding='utf8'))
old=json.loads((OUT/'fin_before/fin_transfer_validation.json').read_text(encoding='utf8'))
fins=json.loads((ROOT/'data/fin_projection.json').read_text())['fins']
coords=json.loads((OUT/'fin_projection_coordinates.json').read_text())
photo=Image.open(record['normalized_path']).convert('RGBA')
atlas=Image.open(record['texture_path']).convert('RGBA')
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',23)
names={'Caudal_Fin':'Schwanzflosse','Dorsal_Fin':'Rückenflosse','Anal_Fin':'Afterflosse'}
def tile(canvas,im,rect,label):
 x,y,w,h=rect;d=ImageDraw.Draw(canvas);d.text((x+12,y+10),label,font=font,fill='white')
 for yy in range(y+48,y+h,20):
  for xx in range(x,x+w,20):d.rectangle((xx,yy,min(xx+19,x+w-1),min(yy+19,y+h-1)),fill=(37,44,50) if ((xx-x)//20+(yy-y)//20)%2 else (47,54,60))
 im=ImageOps.contain(im,(w-24,h-64));canvas.paste(im,(x+(w-im.width)//2,y+48+(h-64-im.height)//2),im if im.mode=='RGBA' else None)
canvas=Image.new('RGB',(2400,1700),(20,26,32));metrics={}
for row,(name,fin) in enumerate(fins.items()):
 mask=Image.open(record['fins'][name]['mask_path']).convert('L');box=mask.getbbox();box=(max(0,box[0]-8),max(0,box[1]-8),min(photo.width,box[2]+8),min(photo.height,box[3]+8))
 tri=photo.copy();d=ImageDraw.Draw(tri);p=np.array(coords[name]['after']);ids=np.array(fin['triangles'],int)
 for t in ids:d.line([tuple(v) for v in p[t]]+[tuple(p[t[0]])],fill=(0,240,220,255),width=1)
 u0,v0,u1,v1=fin['slot_blender_v'];uvbox=(int(u0*atlas.width),int((1-v1)*atlas.height),int(u1*atlas.width),int((1-v0)*atlas.height))
 for col,(im,label) in enumerate([(photo.crop(box),'Referenz'),((Image.open(OUT/'fin_anal_sampling_mask.png').crop(box) if name=='Anal_Fin' else mask.crop(box)), 'Samplingmaske'),(tri.crop(box),'Abtastdreiecke'),(atlas.crop(uvbox),'UV-Insel')]):tile(canvas,im,(col*600,row*380,600,370),names[name]+' · '+label)
 rest=np.array(fin['xy'])[ids];R=np.stack((rest[:,1]-rest[:,0],rest[:,2]-rest[:,0]),axis=2);valid=np.abs(np.linalg.det(R))>1e-7;weight=np.abs(np.linalg.det(R[valid]));weight/=weight.sum();metrics[name]={}
 for mode in ['before','after']:
  q=np.array(coords[name][mode])[ids];Q=np.stack((q[:,1]-q[:,0],q[:,2]-q[:,0]),axis=2);J=Q[valid]@np.linalg.inv(R[valid]);sv=np.linalg.svd(J,compute_uv=False);area=np.abs(np.linalg.det(J));mean=np.sum(area*weight)
  metrics[name][mode]={'area_variation_coefficient':float(np.sqrt(np.sum((area-mean)**2*weight))/mean),'area_weighted_log_anisotropy':float(np.sum(np.log(sv[:,0]/np.maximum(sv[:,1],1e-9))*weight))}
for col,angle in enumerate(['side','oblique']):
 im=Image.open(OUT/f'fin_generated_{angle}.png').convert('RGB');a=np.array(im).astype(int);ys,xs=np.where(np.max(np.abs(a-a[0,0]),axis=2)>8);im=im.crop((xs.min()-10,ys.min()-10,xs.max()+10,ys.max()+10));tile(canvas,im,(col*1200,1150,1200,540),'Godot · '+('Seite' if angle=='side' else 'schräg'))
canvas.save(OUT/'fin_projection_diagnostic.png')
# Identical crops, camera, pose and display scale for direct before/after.
canvas=Image.new('RGB',(2100,1260),(20,26,32))
boxes={'Caudal_Fin':(75,415,275,605),'Dorsal_Fin':(150,298,580,440),'Anal_Fin':(190,474,445,640)}
before=Image.open(OUT/'fin_before/fin_generated_side.png');after=Image.open(OUT/'fin_generated_side.png')
for row,name in enumerate(names):
 mask=Image.open(record['fins'][name]['mask_path']);box=mask.getbbox()
 for col,(im,label) in enumerate([(photo.crop(box),'Referenz'),(before.crop(boxes[name]),'Vorher'),(after.crop(boxes[name]),'Nachher')]):tile(canvas,im,(col*700,row*420,700,410),names[name]+' · '+label)
canvas.save(OUT/'fin_before_after.png')
(OUT/'fin_distortion_metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf8')
print(json.dumps(metrics))
