"""Read-only extraction of three PhotoUV islands and harmonic interpolation weights."""
from pathlib import Path
from collections import Counter,defaultdict
import bpy,json,hashlib,numpy as np
ROOT=Path(__file__).resolve().parent.parent
bpy.context.scene.frame_set(0)
slots={'Caudal_Fin':[.73,.64,.98,.98],'Dorsal_Fin':[.02,.17,.54,.32],'Anal_Fin':[.73,.31,.98,.61]}
result={'source_glb_sha256':hashlib.sha256((ROOT/'models/pelvicachromis_taeniatus_male.glb').read_bytes()).hexdigest(),'fins':{}}
for name,slot in slots.items():
 o=bpy.data.objects[name];m=o.data;assert m.uv_layers.active.name=='PhotoUV'
 uv={};edges=Counter();adj=defaultdict(set)
 for f in m.polygons:
  ids=list(f.vertices)
  for a,b in zip(ids,ids[1:]+ids[:1]):edges[tuple(sorted((a,b)))]+=1;adj[a].add(b);adj[b].add(a)
  for li in f.loop_indices:
   vi=m.loops[li].vertex_index;p=m.uv_layers.active.data[li].uv
   q=[p.x,1-p.y]
   if vi in uv:assert np.max(np.abs(np.array(uv[vi])-q))<1e-6
   uv[vi]=q
 boundary_adj=defaultdict(list)
 for (a,b),count in edges.items():
  if count==1:boundary_adj[a].append(b);boundary_adj[b].append(a)
 assert boundary_adj and all(len(v)==2 for v in boundary_adj.values())
 start=min(boundary_adj);boundary=[start];previous=-1;current=start
 while True:
  following=next(v for v in boundary_adj[current] if v!=previous)
  if following==start:break
  assert following not in boundary
  boundary.append(following);previous,current=current,following
 assert len(boundary)==len(boundary_adj)
 interior=[i for i in range(len(m.vertices)) if i not in boundary_adj]
 bi={v:i for i,v in enumerate(boundary)};ii={v:i for i,v in enumerate(interior)}
 A=np.zeros((len(interior),len(interior)));B=np.zeros((len(interior),len(boundary)))
 for v,i in ii.items():
  A[i,i]=len(adj[v])
  for n in adj[v]:
   if n in ii:A[i,ii[n]]-=1
   else:B[i,bi[n]]+=1
 H=np.linalg.solve(A,B)
 assert np.min(H)>-1e-9 and np.max(np.abs(H.sum(axis=1)-1))<1e-7
 weights=[]
 for v in range(len(m.vertices)):
  row=H[ii[v]].tolist() if v in ii else [1.0 if j==bi[v] else 0.0 for j in range(len(boundary))]
  weights.append(row)
 m.calc_loop_triangles();world=[o.matrix_world@v.co for v in m.vertices]
 result['fins'][name]={'uv':[uv[i] for i in range(len(m.vertices))],'xy':[[p.x/.08,-p.z/.08] for p in world],
 'boundary':boundary,'harmonic_weights':weights,'triangles':[list(t.vertices) for t in m.loop_triangles],
 'slot_blender_v':slot,'vertices':len(m.vertices),'faces':len(m.polygons)}
 print(name,len(m.vertices),'vertices',len(boundary),'boundary vertices')
(ROOT/'data/fin_projection.json').write_text(json.dumps(result,separators=(',',':')),encoding='utf8')
