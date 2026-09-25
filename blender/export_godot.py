"""Export only the existing rig, eleven meshes and active two-second swim clip.

Load models/Pelvicachromis_Male_Blockout.blend before running this script.
The source .blend is never saved or modified on disk by this exporter.
"""
import hashlib
import json
import runpy
import shutil
import struct
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'models/pelvicachromis_taeniatus_male.glb'
SOURCE=ROOT/'models/Pelvicachromis_Male_Blockout.blend'
BACKUP=ROOT/'blender/backups/Pelvicachromis_Male_PreGodot.blend'
runpy.run_path(str(ROOT/'blender/verify_rig.py'),run_name='verify')
source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
BACKUP.parent.mkdir(parents=True,exist_ok=True)
(BACKUP.parent/'.gdignore').touch()
# Preserve the first pre-export snapshot on repeat runs.
if not BACKUP.exists():
    shutil.copy2(SOURCE,BACKUP)
rig=bpy.data.objects['Pelvicachromis_Rig']
scene=bpy.context.scene
meshes=[o for o in scene.objects if o.type=='MESH']
for obj in scene.objects:
    obj.select_set(False)
for obj in meshes+[rig]:
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active=rig
rig.animation_data.action=bpy.data.actions['Swim_Test_Loop']
scene.render.fps=30
scene.frame_start,scene.frame_end=1,61
scene.frame_set(0)
settings=dict(filepath=str(OUT),export_format='GLB',use_selection=True,
    export_yup=True,export_apply=False,export_current_frame=False,
    export_skins=True,export_all_influences=False,export_def_bones=False,
    export_leaf_bone=False,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',
    export_nla_strips_merged_animation_name='Swim_Test_Loop',
    export_frame_range=True,export_frame_step=1,export_force_sampling=True,export_anim_slide_to_zero=True,
    export_optimize_animation_size=False,export_reset_pose_bones=True,
    export_cameras=False,export_lights=False,export_extras=False,
    export_texcoords=True,export_morph=False,export_materials='EXPORT')
bpy.ops.export_scene.gltf(**settings)
raw=OUT.read_bytes()
length,kind=struct.unpack_from('<II',raw,12)
assert kind==0x4e4f534a
gltf=json.loads(raw[20:20+length])
animations=gltf.get('animations',[])
assert len(animations)==1 and animations[0]['name']=='Swim_Test_Loop', animations
accessors=gltf['accessors']
time_ranges=[(accessors[s['input']]['min'][0],accessors[s['input']]['max'][0]) for s in animations[0]['samplers']]
assert all(abs(a)<1e-6 and abs(b-2)<1e-6 for a,b in time_ranges),time_ranges
assert len(gltf['meshes'])==11 and len(gltf['skins'])==1
assert len(gltf['skins'][0]['joints'])==15
assert not gltf.get('cameras')
assert gltf.get('images') and gltf.get('textures'), 'Photo atlas missing'
assert all('bufferView' in image for image in gltf['images']), 'Textures must be embedded'
photo_materials=[m for m in gltf['materials'] if m.get('name','').startswith('Pelvicachromis_Photo')]
assert len(photo_materials)==4
assert all('baseColorTexture' in m['pbrMetallicRoughness'] for m in photo_materials)
assert all('JOINTS_0' in p['attributes'] and 'WEIGHTS_0' in p['attributes']
           for m in gltf['meshes'] for p in m['primitives'])
assert all('TEXCOORD_0' in p['attributes'] for m in gltf['meshes'] for p in m['primitives'])
# Independent evaluated Blender bounds to compare against imported Godot skinning.
expected={}
for frame in (1,16,31,46,61):
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    sample={}
    for obj in meshes:
        ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh=ev.to_mesh()
        points=[obj.matrix_world@v.co for v in mesh.vertices]
        points=[(p.x,p.z,-p.y) for p in points]  # Blender Z-up -> glTF/Godot Y-up
        sample[obj.name]={'min':[min(p[i] for p in points) for i in range(3)],
                          'max':[max(p[i] for p in points) for i in range(3)]}
        ev.to_mesh_clear()
    expected[str((frame-1)/30)]=sample
scene.frame_set(0)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash
report={'source_sha256':source_hash,'backup':str(BACKUP.relative_to(ROOT)),
        'glb':str(OUT.relative_to(ROOT)),'mesh_count':11,'joints':15,'embedded_images':len(gltf['images']),
        'photo_materials':[m['name'] for m in photo_materials],
        'animations':[a['name'] for a in animations],'duration_seconds':2,
        'coordinate_conversion':'Blender (x,y,z) -> glTF/Godot (x,z,-y)',
        'blender_skin_bounds':expected}
(ROOT/'blender/diagnostics/glb_export_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('GLB verified: 11 skinned meshes, 15 joints, one 2-second clip; source unchanged')
