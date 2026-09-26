"""Read-only extraction of current PhotoUV and rest positions. Never saves Blender."""
from pathlib import Path
import bpy, json, hashlib
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent
bpy.context.scene.frame_set(0)
body=bpy.data.objects['Fish_Body']; mesh=body.data
assert mesh.uv_layers.active.name=='PhotoUV'
world=[body.matrix_world@v.co for v in mesh.vertices]
# Dimensionless planar coordinates preserve the actual rest surface/UV relation.
def xy(p):return [p.x/.08, -p.z/.08]
rings=int(body['longitudinal_rings']);sides=int(body['vertices_per_ring'])
upper=[];lower=[]
for r in range(rings):
    pts=world[r*sides:(r+1)*sides]
    upper.append(max(pts,key=lambda p:p.z));lower.append(min(pts,key=lambda p:p.z))
end=world[(rings-1)*sides:rings*sides]
snout=sum(end,Vector())/sides
eye=bpy.data.objects['Eye_Right'].matrix_world.translation
span=snout.x-upper[0].x
interior=[p for p in lower if upper[0].x+.2*span < p.x < snout.x-.2*span]
anchors=[snout,eye,upper[0],lower[0],max(upper,key=lambda p:p.z),min(interior,key=lambda p:p.z)]
mesh.calc_loop_triangles();uv=mesh.uv_layers.active.data
triangles=[]
for tri in mesh.loop_triangles:
    triangles.append({'uv':[[uv[i].uv.x,1-uv[i].uv.y] for i in tri.loops], 'xy':[xy(world[i]) for i in tri.vertices]})
fins={}
for o in bpy.context.scene.objects:
    if o.type=='MESH' and 'Fin' in o.name:
        fins[o.name]=[xy(o.matrix_world@v.co) for v in o.data.vertices]
payload={'schema_version':1,'source_blend_sha256':hashlib.sha256((ROOT/'models/Pelvicachromis_Male_Blockout.blend').read_bytes()).hexdigest(),
 'source_glb_sha256':hashlib.sha256((ROOT/'models/pelvicachromis_taeniatus_male.glb').read_bytes()).hexdigest(),
 'object':'Fish_Body','uv_layer':'PhotoUV','uv_origin':'image_top_left','anchors':[xy(p) for p in anchors],
 'anchor_names':['snout','eye','tail_upper','tail_lower','body_upper','body_lower'],
 'body_outline':[xy(p) for p in upper]+[xy(p) for p in reversed(lower)], 'triangles':triangles,'fin_points':fins,
 'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'uv_slots_blender_v':{'left':[.02,.67,.70,.98],'right':[.02,.34,.70,.65],'tail_cap':[.77,.18,.85,.27],'mouth_cap':[.89,.18,.97,.27]}}
(ROOT/'data/body_projection.json').write_text(json.dumps(payload,separators=(',',':')),encoding='utf8')
print('READ ONLY BODY UV EXTRACTION',len(triangles),'triangles; anchors:',payload['anchors'])
