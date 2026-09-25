"""Widen body along Blender Y only; retain topology, UVs, materials and rig.
Load the current .blend. Repeated runs on the widened mesh are rejected.
"""
import bpy, json, hashlib, shutil, runpy
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'blender/diagnostics'
SOURCE=ROOT/'models/Pelvicachromis_Male_Blockout.blend'

def invariant():
    meshes=[]
    for o in sorted([o for o in bpy.context.scene.objects if o.type=='MESH'],key=lambda o:o.name):
        meshes.append((o.name,[list(p.vertices) for p in o.data.polygons],
            [list(row) for row in o.matrix_world],
            [(u.name,[list(d.uv) for d in u.data]) for u in o.data.uv_layers],
            [g.name for g in o.vertex_groups],
            [[(g.group,g.weight) for g in v.groups] for v in o.data.vertices],
            [m.name for m in o.data.materials],
            [(m.type,m.object.name) for m in o.modifiers if m.type=='ARMATURE']))
    rig=bpy.data.objects['Pelvicachromis_Rig']
    bones=[(b.name,b.parent.name if b.parent else None,[list(r) for r in b.matrix_local],b.length) for b in rig.data.bones]
    actions=[]
    for a in bpy.data.actions:
        curves=[]
        for layer in a.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    curves.extend((c.data_path,c.array_index,[(list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation) for k in c.keyframe_points]) for c in bag.fcurves)
        actions.append((a.name,curves))
    return hashlib.sha256(json.dumps((meshes,bones,actions),sort_keys=True).encode()).hexdigest()

def main():
    scene=bpy.context.scene;scene.frame_set(0)
    body=bpy.data.objects['Fish_Body']
    assert not body.get('width_revision_1_5',False),'Already widened: start from PreWidth backup to reproduce'
    backup=ROOT/'blender/backups/width_before'
    backup.mkdir(exist_ok=True)
    for path in [SOURCE,ROOT/'models/pelvicachromis_taeniatus_male.glb']:
        target=backup/path.name
        if not target.exists():shutil.copy2(path,target)
    helpers=runpy.run_path(str(ROOT/'blender/rig_pelvicachromis.py'),run_name='helpers')
    before_hash=helpers['digest']();protected=invariant()
    textures={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'textures').glob('*.png')}
    objs=[o for o in scene.objects if o.type=='MESH']
    original={o.name:[v.co.copy() for v in o.data.vertices] for o in objs}
    camera=scene.camera;cam_matrix=camera.matrix_world.copy();cam_scale=camera.data.ortho_scale
    scene.render.engine='CYCLES';scene.cycles.samples=24
    scene.render.resolution_x=1400;scene.render.resolution_y=1000
    target=Vector((0,0,.002))
    def render(prefix):
        for suffix,pos,scale in [('side',(0,-.2,.002),.09),('front',(.2,0,.002),.070),('oblique',(.12,-.2,.045),.09)]:
            camera.location=pos;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
            camera.data.type='ORTHO';camera.data.ortho_scale=scale
            scene.render.filepath=str(OUT/f'width_{prefix}_{suffix}.png')
            bpy.ops.render.render(write_still=True)
    render('before')
    adjustments={}
    for obj in objs:
        inv=obj.matrix_world.inverted()
        world=[obj.matrix_world@v.co for v in obj.data.vertices]
        shift=0.0
        if obj.name.startswith('Eye'):
            # Translate the entire eye dome, retaining its thickness and circular iris.
            shift=obj.matrix_world.translation.y*.5
        elif obj.name.startswith('Pectoral'):
            # Every sixth vertex is on the attachment edge of this unchanged grid.
            roots=world[::6];shift=sum(p.y for p in roots)/len(roots)*.5
        elif obj.name.startswith('Pelvic'):
            roots=world[:5];shift=sum(p.y for p in roots)/len(roots)*.5
        for v,p in zip(obj.data.vertices,world):
            if obj.name in ('Fish_Body','Mouth'):p.y*=1.5
            else:p.y+=shift
            v.co=inv@p
        obj.data.update()
        adjustments[obj.name]={'lateral_translation_m':shift,'y_scale':1.5 if obj.name in ('Fish_Body','Mouth') else 1.0}
        assert max(abs(v.co.x-old.x)+abs(v.co.z-old.z) for v,old in zip(obj.data.vertices,original[obj.name]))<1e-8
    assert invariant()==protected,'Rig, weights, UV, topology or transforms changed'
    old=original['Fish_Body'];new=[v.co for v in body.data.vertices]
    old_width=max(p.y for p in old)-min(p.y for p in old)
    new_width=max(p.y for p in new)-min(p.y for p in new)
    assert abs(new_width/old_width-1.5)<1e-6
    assert max(abs(p.y-1.5*q.y) for p,q in zip(new,old))<1e-8
    body['width_revision_1_5']=True
    report={'geometry_sha256_before':before_hash,'geometry_sha256_after':helpers['digest'](),
        'protected_data_before':protected,'protected_data_after':invariant(),
        'body_width_before_m':old_width,'body_width_after_m':new_width,'width_factor':new_width/old_width,
        'x_z_unchanged':True,'adjustments':adjustments,'texture_sha256':textures,
        'axis':'Blender local Y (Godot Z after export)','backup':str(backup.relative_to(ROOT))}
    print('Checking full existing swim loop',flush=True)
    report['animation_validation']=helpers['validate'](bpy.data.objects['Pelvicachromis_Rig'])
    render('after')
    assert invariant()==protected
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in textures.items())
    camera.matrix_world=cam_matrix;camera.data.ortho_scale=cam_scale
    scene.frame_set(0)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    (OUT/'width_validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print('WIDTH CHANGE COMPLETE',new_width/old_width)
if __name__=='__main__':main()
