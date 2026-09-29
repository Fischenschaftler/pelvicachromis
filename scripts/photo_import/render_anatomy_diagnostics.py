"""Render measured anatomical suggestions; development-only Pillow dependency."""
from pathlib import Path
import json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'godot/diagnostics'
data=json.loads((OUT/'anatomy_variations.json').read_text(encoding='utf8'));r=data['cases']['right']['result']
t=json.loads((ROOT/'data/anatomical_landmarks_male.json').read_text())
photo=Image.open(ROOT/'blender/reference/pelvicachromis_taeniatus_male.jpg').convert('RGB')
font=lambda n:ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',n)
colors={'HIGH':'#68edab','MEDIUM':'#57def2','LOW':'#ffbe62'}
canvas=Image.new('RGB',(1800,1200),'#101a22');d=ImageDraw.Draw(canvas)
d.text((25,15),'Anatomisches Template → lokale Landmark-Verfeinerung',font=font(33),fill='white')
d.text((25,65),'Kopf rechts · gleiche 12 Punkte · Grün: HIGH   Cyan: MEDIUM   Ring/Orange: LOW, bitte prüfen',font=font(23),fill='#bed0dc')
for x,title,key in [(25,'Gemeinsam platziertes Template','template_landmarks'),(925,'Final: Kontur, Achse, Auge und Konfidenz','suggested_landmarks')]:
 panel=photo.crop((20,190,780,610)).resize((850,470),Image.Resampling.LANCZOS);q=ImageDraw.Draw(panel)
 def xy(p):return ((p[0]-20)*850/760,(p[1]-190)*470/420)
 contour=[xy(p) for p in r['fish_contour']];q.line(contour+[contour[0]],fill='#32d8e3',width=2)
 if key=='suggested_landmarks':
  q.line([xy(r['axis_start']),xy(r['axis_end'])],fill='#ffb74c',width=3)
  roi=[xy(p) for p in r['pectoral_region']];q.line(roi+[roi[0]],fill='#dca967',width=1)
 for i,p in enumerate(r[key]):
  px,py=xy(p);level=r['landmark_confidence'][i]['level'];color=colors[level] if key=='suggested_landmarks' else '#f1f1f1'
  q.ellipse((px-4,py-4,px+4,py+4),fill=color,outline='black')
  if key=='suggested_landmarks' and level=='LOW':q.ellipse((px-8,py-8,px+8,py+8),outline=color,width=2)
  q.text((min(px+7,824),max(0,py-24)),str(i+1),font=font(19),fill=color,stroke_width=2,stroke_fill='#101a22')
 d.text((x,112),title,font=font(25),fill='white');canvas.paste(panel,(x,150))
d.text((25,650),'Normalisiertes Template vor Bildanpassung',font=font(25),fill='white')
poly=t['outline'];xs=[p[0] for p in poly];ys=[p[1] for p in poly];scale=min(780/(max(xs)-min(xs)),320/(max(ys)-min(ys)))
def xy2(p):return (35+(p[0]-min(xs))*scale,710+(p[1]-min(ys))*scale)
ps=[xy2(p) for p in poly];d.line(ps+[ps[0]],fill='#637c8c',width=2)
for i,p in enumerate(t['anchors']):
 x,y=xy2(p);d.ellipse((x-3,y-3,x+3,y+3),fill='#eef5f7');d.text((x+4,y-20),str(i+1),font=font(17),fill='#eef5f7')
labels=['Schnauze','Auge','Schwanzstiel oben','Schwanzstiel unten','Schwanzflosse oben','Schwanzflosse unten','Rückenflosse vorne','Rückenflosse hinten','Afterflosse vorne','Afterflosse hinten','Bauchflossenansatz','Bauchflossenspitze']
for i,label in enumerate(labels):
 x=925+(i%2)*430;y=666+(i//2)*62;c=r['landmark_confidence'][i]
 d.text((x,y),f'{i+1} {label}',font=font(22),fill='white');d.text((x,y+28),c['level'],font=font(18),fill=colors[c['level']])
d.text((25,1090),'Lokale Suche ist begrenzt. Schwanzstiel: geglättete Querbreite + anatomisches Suchfenster.',font=font(24),fill='#c4d5de')
d.text((25,1132),'Transparente Brustflosse: schwache Bildhinweise + anatomischer Bereich; immer LOW.',font=font(24),fill='#ffbe62')
canvas.save(OUT/'anatomy_template_diagnostics.png')
# Contact sheet of every deterministic variation; errors measured against transformed annotations.
sheet=Image.new('RGB',(1600,1100),'#101a22');draw=ImageDraw.Draw(sheet)
for i,(name,case) in enumerate(data['cases'].items()):
 im=Image.open(ROOT/case['path'].replace('res://','')).convert('RGB');size=im.size;im.thumbnail((385,275));painter=ImageDraw.Draw(im);sx=im.width/size[0];sy=im.height/size[1]
 if 'result' in case:
  rr=case['result'];ps=[(p[0]*sx,p[1]*sy) for p in rr['fish_contour']];painter.line(ps+[ps[0]],fill='cyan',width=1)
  for k,(px,py) in enumerate(rr['suggested_landmarks']):
   x,y=px*sx,py*sy;c=colors[rr['landmark_confidence'][k]['level']];painter.ellipse((x-2,y-2,x+2,y+2),fill=c)
 x=(i%4)*400;y=(i//4)*360;sheet.paste(im,(x+(400-im.width)//2,y+42));draw.text((x+10,y+8),name,font=font(20),fill='white');draw.text((x+10,y+320),f"Mittlerer Fehler: {case.get('mean_relative_error',1)*100:.2f}% Körperlänge",font=font(16),fill='#bed0dc')
sheet.save(OUT/'anatomy_variations.png')
print('Anatomy diagnostics rendered')
