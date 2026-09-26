"""Diagnostic composed from real Godot-clicked landmarks and saved normalization."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageOps, ImageFont
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT/'godot/diagnostics'
data = json.loads((OUT/'landmark_large_right.json').read_text(encoding='utf8'))
photo = Image.open(data['original_photo_path']).convert('RGBA')
mask = Image.open(data['mask_path']).convert('L')
box = mask.getbbox()
box = (max(0,box[0]-100), max(0,box[1]-100), min(photo.width,box[2]+100), min(photo.height,box[3]+100))
cutout=photo.copy();cutout.putalpha(mask)
normalized=Image.open(OUT/'landmark_large_right_normalized.png').convert('RGBA')
canvas=Image.new('RGB',(2400,840),(24,31,38));draw=ImageDraw.Draw(canvas)
labels=['Originalfoto','Freistellung + gesetzte Referenzpunkte','Normalisiert: Kopf rechts, Achse horizontal']
for index,img in enumerate([photo.crop(box),cutout.crop(box),normalized]):
    fitted=ImageOps.contain(img,(770,570))
    x=index*800+15+(770-fitted.width)//2;y=90+(570-fitted.height)//2
    for yy in range(90,660,20):
        for xx in range(index*800+15,index*800+785,20):
            col=(63,70,77) if ((xx-index*800-15)//20+(yy-90)//20)%2 else (50,57,64)
            draw.rectangle((xx,yy,min(xx+19,index*800+784),min(yy+19,659)),fill=col)
    canvas.paste(fitted,(x,y),fitted)
    draw.text((index*800+20,28),labels[index],fill='white',font=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",26))
    if index==1:
        scale=fitted.width/img.width
        for n,key in enumerate(['snout','eye','tail_upper','tail_lower','body_upper','body_lower'],1):
            p=data['landmarks_original_px'][key]
            px=x+(p[0]-box[0])*scale;py=y+(p[1]-box[1])*scale
            draw.ellipse((px-6,py-6,px+6,py+6),fill=(40,255,210),outline='black',width=2)
            offset={1:(23,0),2:(10,-45),3:(-55,-20),4:(-55,25),5:(-10,-45),6:(-5,40)}[n]
            tx,ty=px+offset[0],py+offset[1]
            draw.line((px,py,tx,ty),fill=(40,255,210),width=2)
            draw.text((tx-9,ty-12),str(n),fill=(40,255,210),font=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",28),stroke_width=3,stroke_fill='black')
    if index==2:
        # The exact snout / tail axis in normalized image pixels.
        coords=data['landmarks_normalized_px']; snout=coords['snout']; top=coords['tail_upper'];bottom=coords['tail_lower']
        scale=fitted.width/img.width
        tail=((top[0]+bottom[0])/2,(top[1]+bottom[1])/2)
        draw.line((x+tail[0]*scale,y+tail[1]*scale,x+snout[0]*scale,y+snout[1]*scale),fill=(40,255,210),width=2)
legend=['1 Schnauzenspitze     2 Augenmitte','3 Schwanzansatz oben     4 Schwanzansatz unten','5 Körper oben (ohne Rückenflosse)     6 Körper unten (ohne Flossen)']
for n,line in enumerate(legend):draw.text((25,690+n*36),line,fill=(225,235,240),font=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",24))
draw.text((1330,710),f"Original: 4000 × 3000 px | Achse: {data['axis_angle_degrees']:.1f}°",fill='white',font=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",25))
draw.text((1330,754),'PNG mit Alpha + JSON; Foto und 3D-Modell unverändert',fill='white',font=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",24))
canvas.save(OUT/'landmark_comparison.png')
