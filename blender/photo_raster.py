"""Raster stage for bake_reference_texture.py. Requires Python, NumPy and Pillow."""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parent.parent
N=4096

def spread(rgb, valid, steps):
    # Synchronous four-neighbour dilation; never samples aquarium pixels.
    for _ in range(steps):
        new=valid.copy()
        for axis,step in ((0,1),(0,-1),(1,1),(1,-1)):
            available=np.roll(valid,step,axis)
            if axis==0: available[0 if step==1 else -1,:]=False
            else: available[:,0 if step==1 else -1]=False
            take=available & ~new
            if take.any():
                shifted=np.roll(rgb,step,axis);rgb[take]=shifted[take];new[take]=True
        valid=new
    return rgb,valid

# Manually traced, reproducible foreground polygons in the sole registered photo.
# Separate component masks prevent nearest-edge padding borrowing aquarium colour.
BODY=[(215,369),(237,365),(266,358),(298,343),(331,326),(366,307),(400,288),(433,273),(473,258),(512,247),(548,240),(583,238),(620,240),(651,245),(678,251),(697,261),(714,273),(725,280),(734,293),(732,304),(717,321),(700,331),(678,344),(656,356),(630,372),(603,386),(574,399),(551,406),(524,413),(491,419),(457,426),(423,432),(389,436),(355,438),(323,436),(290,434),(258,435),(239,436),(215,438)]
POLYGONS={
 'Fish_Body':BODY,
 'Dorsal_Fin':[(566,237),(524,232),(487,225),(453,222),(426,225),(399,232),(373,239),(347,245),(322,257),(296,267),(270,277),(242,280),(212,281),(181,283),(154,283),(184,295),(211,324),(230,348),(252,354),(280,351),(331,326),(400,288),(473,258),(548,240)],
 'Caudal_Fin':[(216,370),(200,369),(174,367),(144,363),(116,361),(92,366),(74,377),(66,393),(67,414),(73,439),(82,469),(93,495),(109,518),(124,528),(142,530),(162,520),(184,498),(204,473),(236,436)],
 'Anal_Fin':[(423,432),(417,437),(400,455),(385,476),(353,494),(318,516),(280,535),(240,550),(195,571),(222,533),(240,491),(252,456),(254,437),(323,436),(389,436)],
 'Pelvic_Fin':[(563,395),(542,428),(508,455),(471,478),(437,496),(405,510),(447,500),(482,487),(517,466),(546,438),(559,399)],
 'Pectoral_Fin':[(583,346),(598,365),(611,389),(622,412),(620,434),(610,446),(591,455),(575,454),(565,441),(568,421),(579,368)]}

def main():
    photo=np.asarray(Image.open(ROOT/'blender/reference/pelvicachromis_taeniatus_male.jpg').convert('RGB'))
    # Reuse the existing mask verbatim; never replace the segmentation in this pass.
    existing_mask=np.asarray(Image.open(ROOT/'textures/reference_fish_mask.png'))>0
    sources={}
    # Modest low-frequency luminance correction, preserving chroma and fine markings.
    bodymask=Image.new('L',(800,800));ImageDraw.Draw(bodymask).polygon(BODY,fill=255)
    bm=np.asarray(bodymask,dtype=np.float32)/255
    lum=photo.astype(np.float32)@np.array([.2126,.7152,.0722])
    num=np.asarray(Image.fromarray((lum*bm).astype('uint8')).filter(ImageFilter.GaussianBlur(42)),dtype=float)
    den=np.asarray(bodymask.filter(ImageFilter.GaussianBlur(42)),dtype=float)/255
    low=num/np.maximum(den,.01)
    attachment=np.asarray(bodymask.filter(ImageFilter.GaussianBlur(4)),dtype=float)/255
    target=np.median(low[bm>.5])
    gain=np.clip((target/np.maximum(low,1))**.24,.90,1.13)
    corrected=np.clip(photo.astype(float)*gain[...,None],0,255).astype('uint8')
    for name,poly in POLYGONS.items():
        mask=Image.new('L',(800,800));ImageDraw.Draw(mask).polygon(poly,fill=255)
        safe=(np.asarray(mask.filter(ImageFilter.MinFilter(3)))>0)&existing_mask
        colors=np.zeros_like(photo);colors[safe]=(corrected if name=='Fish_Body' else photo)[safe]
        # Conservative inverse compositing against nearby photographed aquarium colour.
        # Retain the recorded rays rather than replacing them with a uniform tint.
        if name=='Pectoral_Fin':
            yy,xx=np.mgrid[:800,:800]
            base=np.asarray(photo[:,640:655],float).mean(axis=1)[:,None,:]
            alpha=np.clip(.72-(yy-365)*.003,.46,.78)
            recovered=(photo.astype(float)-base*(1-alpha[...,None]))/alpha[...,None]
            recovered=np.clip(recovered,0,255)
            colors[safe]=(.70*recovered+.30*photo)[safe].astype('uint8')
        colors,filled=spread(colors,safe,48)
        colors[~filled]=np.median(photo[safe],axis=0).astype('uint8')
        sources[name]=colors
    sources['Eye']=photo # preserve gold iris, blue/dark rims and black pupil exactly
    data=json.loads((ROOT/'textures/work/projection_triangles.json').read_text())
    atlas=np.zeros((N,N,4),np.uint8);coverage=np.zeros((N,N),bool)
    for obj in data:
        key=obj['name']
        if key.startswith('Eye'):key='Eye'
        if key=='Mouth':key='Fish_Body'
        if key.startswith('Pelvic'):key='Pelvic_Fin'
        if key.startswith('Pectoral'):key='Pectoral_Fin'
        source=sources[key]
        for item in obj['triangles']:
            uv=np.asarray(item['uv'])*N;uv[:,1]=N-uv[:,1]
            xy=np.asarray(item['photo'])
            lo=np.maximum(np.floor(uv.min(axis=0)).astype(int),0);hi=np.minimum(np.ceil(uv.max(axis=0)).astype(int),N-1)
            if np.any(hi<lo):continue
            xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5)
            a,b,c=uv;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(den)<1e-9:continue
            w0=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
            w1=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den;w2=1-w0-w1
            inside=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6)
            coord=w0[...,None]*xy[0]+w1[...,None]*xy[1]+w2[...,None]*xy[2]
            coord=np.clip(coord,0,798.999);ij=np.floor(coord).astype(int);f=coord-ij
            x,y=ij[...,0],ij[...,1];fx,fy=f[...,0,None],f[...,1,None]
            col=(source[y,x]*(1-fx)+source[y,x+1]*fx)*(1-fy)+(source[y+1,x]*(1-fx)+source[y+1,x+1]*fx)*fy
            tile=atlas[lo[1]:hi[1]+1,lo[0]:hi[0]+1];tile[inside,:3]=col[inside].astype('uint8')
            opacity=np.ones(xx.shape)
            if key=='Pectoral_Fin':opacity=np.clip(.74-(coord[...,1]-365)*.004,.35,.8)
            elif key.endswith('_Fin'):
                # Fade embedded roots into the body instead of double-printing scales.
                opacity=.90*(1-.82*attachment[y,x])
            tile[inside,3]=(opacity[inside]*255).astype('uint8')
            coverage[lo[1]:hi[1]+1,lo[0]:hi[0]+1]|=inside
    atlas,padded=spread(atlas,coverage,20)
    Image.fromarray(atlas).save(ROOT/'textures/pelvicachromis_taeniatus_male_albedo.png')
    Image.fromarray(atlas).resize((1600,1600),Image.Resampling.LANCZOS).save(ROOT/'blender/diagnostics/photo_texture_atlas.png')
    print('4096 atlas baked, 20 px padding; coverage',int(coverage.sum()),flush=True)

def comparison():
    photo=Image.open(ROOT/'blender/reference/pelvicachromis_taeniatus_male.jpg').convert('RGB').crop((45,200,755,590))
    model=Image.open(ROOT/'blender/diagnostics/photo_textured_side.png').convert('RGB').crop((70,130,1530,925))
    canvas=Image.new('RGB',(2400,850),(235,235,235))
    from PIL import ImageOps
    canvas.paste(ImageOps.contain(photo,(1160,720)),(20,80))
    canvas.paste(ImageOps.contain(model,(1160,720)),(1220,80))
    draw=ImageDraw.Draw(canvas)
    draw.text((25,25),'REGISTERED REFERENCE / photographed right side',fill=(20,20,20),font_size=24)
    draw.text((1225,25),'PHOTO UV ATLAS / Blender orthographic render',fill=(20,20,20),font_size=24)
    canvas.save(ROOT/'blender/diagnostics/photo_reference_comparison.png')
    # All views at similar fish length, reference repeated for direct comparison.
    sheet=Image.new('RGB',(2400,4*760),(235,235,235))
    for row,(filename,label) in enumerate([
        ('photo_textured_side.png','RIGHT / photographed side'),
        ('photo_textured_left.png','LEFT / provisional mirrored colour'),
        ('photo_textured_perspective.png','FRONT OBLIQUE'),
        ('photo_textured_rear.png','REAR OBLIQUE')]):
        view=Image.open(ROOT/'blender/diagnostics'/filename).convert('RGB')
        arr=np.asarray(view).astype(float)
        # Neutral diagnostic background; foreground colour chroma locates the fish.
        foreground=arr.max(axis=2)-arr.min(axis=2)>12
        yy,xx=np.where(foreground)
        view=view.crop((max(0,xx.min()-15),max(0,yy.min()-15),min(view.width,xx.max()+16),min(view.height,yy.max()+16)))
        sheet.paste(ImageOps.contain(photo,(1160,670)),(20,row*760+65))
        sheet.paste(ImageOps.contain(view,(1160,670)),(1220,row*760+65))
        ImageDraw.Draw(sheet).text((1220,row*760+20),label,fill=(20,20,20),font_size=24)
        ImageDraw.Draw(sheet).text((20,row*760+20),'REFERENCE (right side)',fill=(20,20,20),font_size=24)
    sheet.save(ROOT/'blender/diagnostics/photo_reference_four_views.png')

if __name__=='__main__':
    if '--comparison' in sys.argv:comparison()
    else:main()
