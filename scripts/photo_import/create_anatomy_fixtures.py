"""Deterministic development fixtures; Pillow is not an application dependency."""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'.godot/anatomy_fixtures';OUT.mkdir(parents=True,exist_ok=True)
photo=Image.open(ROOT/'blender/reference/pelvicachromis_taeniatus_male.jpg').convert('RGB')
points=np.array([[736,296],[669,275],[220,369],[243,436],[108,363],[142,529],[550,241],[154,283],[416,437],[195,571],[565,406],[405,510]],float)
t=json.loads((ROOT/'data/anatomical_landmarks_male.json').read_text());origin=np.array([231.5,402.5]);u=(points[0]-origin);length=np.linalg.norm(u);u/=length;v=np.array([-u[1],u[0]])
contour=[tuple(origin+length*(u*p[0]+v*p[1])) for p in t['outline']]
mask=Image.new('L',photo.size);ImageDraw.Draw(mask).polygon(contour,fill=255)
a=np.asarray(photo).astype(float);edge=(a[:,:25].mean(axis=1)+a[:,-25:].mean(axis=1))/2
background=Image.fromarray(np.uint8(np.repeat(edge[:,None,:],800,axis=1))).filter(ImageFilter.GaussianBlur(8))
manifest=[]
def save(name,im,pts=points,direction='right',uncertain=None):
 im.save(OUT/(name+'.png'));manifest.append({'name':name,'path':'res://.godot/anatomy_fixtures/'+name+'.png','points':pts.tolist(),'direction':direction,'uncertain':uncertain or []})
save('right',photo)
p=points.copy();p[:,0]=799-p[:,0];save('left',photo.transpose(Image.Transpose.FLIP_LEFT_RIGHT),p,'left')
for angle in [-12,12]:
 r=math.radians(angle);rotation=np.array([[math.cos(r),math.sin(r)],[-math.sin(r),math.cos(r)]])
 save('tilt_'+str(angle),photo.rotate(angle,Image.Resampling.BICUBIC,fillcolor=(28,49,55)),(points-400)@rotation.T+400)
save('small',photo.resize((200,200),Image.Resampling.LANCZOS),points*.25)
save('large',photo.crop((0,100,800,700)).resize((4000,3000),Image.Resampling.LANCZOS),(points-[0,100])*5)
for scale in [.65,1.03]:
 size=round(800*scale);offset=(800-size)//2;im=background.copy();fish=photo.resize((size,size));alpha=mask.resize((size,size));im.paste(fish,(offset,offset),alpha)
 save('fish_size_'+str(scale),im,points*(size/800)+offset)
def weaken(name,polygon,strength,uncertain):
 m=Image.new('L',photo.size);ImageDraw.Draw(m).polygon(polygon,fill=round(strength*255));m=m.filter(ImageFilter.GaussianBlur(3));save(name,Image.composite(background,photo,m),uncertain=uncertain)
weaken('transparent_fins',[(65,359),(249,360),(245,440),(142,535),(72,470)],.6,[4,5])
weaken('weak_pectoral',[(584,339),(624,410),(600,456),(567,450),(560,402)],.8,[10])
weaken('weak_pelvic_tip',[(397,510),(452,468),(460,483),(427,511)],.9,[11])
m=Image.new('L',photo.size);ImageDraw.Draw(m).ellipse((643,250,694,300),fill=255);m=m.filter(ImageFilter.GaussianBlur(4))
save('low_eye_contrast',Image.composite(Image.new('RGB',photo.size,(145,149,77)),photo,m),uncertain=[1])
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
print('Fixtures:',len(manifest))
