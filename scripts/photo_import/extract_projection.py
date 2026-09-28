"""Read existing UVs/geometry without saving the Blender file."""
from pathlib import Path
import bpy,json,numpy as np
ROOT=Path(__file__).resolve().parents[2]
# Reuse the read-only extraction algorithm, changing only output and object list.
s=(ROOT/'scripts/extract_fin_projection.py').read_text(encoding='utf8')
s=s.replace('ROOT=Path(__file__).resolve().parent.parent','ROOT=Path(__file__).resolve().parents[2]')
s=s.replace("for name,slot in slots.items():", "\nfor name in ['Pectoral_Fin_Left','Pectoral_Fin_Right','Pelvic_Fin_Left','Pelvic_Fin_Right']:\n m=bpy.data.objects[name].data;coords=np.array([list(d.uv) for d in m.uv_layers.active.data]);lo=coords.min(0);hi=coords.max(0);slots[name]=[float(lo[0]-.002),float(lo[1]-.002),float(hi[0]+.002),float(hi[1]+.002)]\nfor name,slot in slots.items():")
s=s.replace("ROOT/'data/fin_projection.json'","ROOT/'data/photo_import_projection.json'")
exec(compile(s,__file__,'exec'))
p=ROOT/'data/photo_import_projection.json';data=json.loads(p.read_text())
b=json.loads((ROOT/'data/body_projection.json').read_text())
f=data['fins'];xy=lambda name:np.array(f[name]['xy'])
# Fin extrema in the existing side projection, independent of any photograph.
c=xy('Caudal_Fin');outer=c[c[:,0]<np.quantile(c[:,0],.35)]
d=xy('Dorsal_Fin');a=xy('Anal_Fin');v=xy('Pelvic_Fin_Left')
keys=['snout','eye','tail_upper','tail_lower','caudal_upper','caudal_lower','dorsal_front','dorsal_back','anal_front','anal_back','pelvic_base','pelvic_tip']
points=b['anchors'][:4]+[outer[outer[:,1].argmin()].tolist(),outer[outer[:,1].argmax()].tolist(),d[d[:,0].argmax()].tolist(),d[d[:,0].argmin()].tolist(),a[a[:,0].argmax()].tolist(),a[a[:,0].argmin()].tolist(),v[v[:,0].argmax()].tolist(),v[v[:,0].argmin()].tolist()]
data['anchor_names']=keys;data['anchors']=points
p.write_text(json.dumps(data,separators=(',',':')),encoding='utf8')

# Paired fins curve out of the side plane. Their raw X/Z outline can overlap.
# Fit an affine side-plane guide to the existing non-overlapping UV island;
# this creates sampling metadata only, never new UVs or mesh geometry.
for name,fin in data['fins'].items():
 uv=np.array(fin['uv']);xy=np.array(fin['xy']);A=np.column_stack((uv,np.ones(len(uv))));fit=np.linalg.lstsq(A,xy,rcond=None)[0]
 fin['projection_xy']=(A@fit).tolist()
p.write_text(json.dumps(data,separators=(',',':')),encoding='utf8')
