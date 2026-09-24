"""Build a deterministic export-friendly FK swim rig on the existing meshes.

Load the existing .blend first. No mesh vertices, topology, UVs or materials
are edited. Vertex weights use linear skinning, at most four influences.
"""
import hashlib
import json
import math
import runpy
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector, Quaternion
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'blender/diagnostics'
BODY = ['Body_01', 'Body_02', 'Body_03', 'Body_04', 'Tail_01', 'Tail_02']
STATIONS = [.040, .020, .009, -.002, -.011, -.017, -.0221, -.040]
CENTERS = [.029, .0145, .0035, -.0065, -.014, -.020]
MODEL = [o for o in bpy.context.scene.objects if o.type == 'MESH']
DEFS = runpy.run_path(str(ROOT / 'blender/create_pelvicachromis_male_from_reference.py'), run_name='definitions')


def digest():
    return hashlib.sha256(json.dumps([(o.name, [list(v.co) for v in o.data.vertices],
        [list(p.vertices) for p in o.data.polygons]) for o in sorted(MODEL, key=lambda o:o.name)]).encode()).hexdigest()


def center(x):
    lo, hi = DEFS['BODY_PROFILE'][0][0], DEFS['BODY_PROFILE'][-1][0]
    _, top, bottom = DEFS['profile_at'](max(lo, min(hi, x)))
    return Vector((x, 0, (top + bottom) * .5))


def body_weights(x):
    if x >= CENTERS[0]:
        return {BODY[0]: 1.0}
    if x <= CENTERS[-1]:
        return {BODY[-1]: 1.0}
    for i in range(len(CENTERS)-1):
        if CENTERS[i] >= x >= CENTERS[i+1]:
            t = (CENTERS[i]-x)/(CENTERS[i]-CENTERS[i+1])
            t = t*t*(3-2*t)
            return {BODY[i]: 1-t, BODY[i+1]: t}


def blend(a, b, t):
    result = {k:v*(1-t) for k,v in a.items()}
    for k,v in b.items():
        result[k] = result.get(k,0)+v*t
    return {k:v for k,v in result.items() if v > 1e-8}


def create_rig():
    assert bpy.data.objects.get('Pelvicachromis_Rig') is None, 'Rig already exists; do not overwrite manual work'
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    data = bpy.data.armatures.new('Pelvicachromis_Skeleton')
    rig = bpy.data.objects.new('Pelvicachromis_Rig', data)
    bpy.context.scene.collection.objects.link(rig)
    rig.show_in_front = True
    data.display_type = 'OCTAHEDRAL'
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')

    def bone(name, head, tail, parent=None, connected=False):
        b = data.edit_bones.new(name)
        b.head, b.tail = head, tail
        b.align_roll(Vector((0,0,1)))
        if parent:
            b.parent = data.edit_bones[parent]
            b.use_connect = connected
        return b

    root = bone('Root', (0,0,-.029), (0,0,-.023))
    root.use_deform = False
    for i,name in enumerate(BODY+['Tail_Fin']):
        bone(name, center(STATIONS[i]), center(STATIONS[i+1]),
             'Root' if i == 0 else (BODY+['Tail_Fin'])[i-1], i>0)
    bone('Dorsal_01', (.013,0,.018), (.003,0,.020), 'Body_02')
    bone('Dorsal_02', (-.007,0,.012), (-.026,0,.014), 'Body_04')
    bone('Anal_Fin', (-.008,0,-.004), (-.024,0,-.019), 'Body_04')
    for name in ('Pectoral_Fin_Left','Pectoral_Fin_Right','Pelvic_Fin_Left','Pelvic_Fin_Right'):
        obj = bpy.data.objects[name]
        head = obj.location.copy()
        points = [obj.matrix_world @ v.co for v in obj.data.vertices]
        tail = min(points, key=lambda p:p.z)
        bone(name, head, head.lerp(tail,.8), 'Body_01')
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    rig['instructions'] = 'Neutral at frame 0. Play 1-60: Swim_Test_Loop, 30 fps. Frame 61 repeats frame 1.'
    rig['rig_test_pose_action'] = 'Rig_Test_Pose (unassigned single pose action)'
    return rig


def bind(rig):
    report = {}
    for obj in MODEL:
        assert not obj.vertex_groups and not any(m.type=='ARMATURE' for m in obj.modifiers), obj.name
        world = obj.matrix_world.copy()
        obj.parent = rig
        obj.matrix_world = world
        mod = obj.modifiers.new('Swim_Deformation', 'ARMATURE')
        mod.object = rig
        mod.use_deform_preserve_volume = False  # glTF-compatible linear skinning
        obj.hide_set(False)
        obj.display_type = 'TEXTURED'
        obj.show_in_front = False
        obj.show_wire = False
        obj.show_all_edges = False
        groups = {}
        max_count, max_error = 0,0
        for v in obj.data.vertices:
            p = world @ v.co
            name = obj.name
            if name == 'Fish_Body':
                weights = body_weights(p.x)
            elif name.startswith('Eye') or name == 'Mouth':
                weights = {'Body_01':1.0}
            elif name=='Caudal_Fin':
                # Spatial weights avoid a discontinuity where fan strips converge.
                t=max(0,min(1,(-.0221-p.x)/.007))
                weights=blend(body_weights(p.x),{'Tail_Fin':1.0},t*t*(3-2*t))
            elif name in ('Dorsal_Fin','Anal_Fin'):
                stride = 6 if name=='Caudal_Fin' else 9
                row, col = divmod(v.index,stride)
                root = world @ obj.data.vertices[row*stride].co
                t = col/(stride-1)
                if name=='Anal_Fin':
                    # Distance below the attachment, independent of strip index.
                    _,_,bottom=DEFS['profile_at'](max(DEFS['BODY_PROFILE'][0][0],min(DEFS['BODY_PROFILE'][-1][0],p.x)))
                    t=max(0,min(1,(bottom-p.z)/.007))
                    attached=body_weights(p.x)
                t = t*t*(3-2*t)
                attached = body_weights(p.x if name=='Anal_Fin' else root.x)
                if name == 'Dorsal_Fin':
                    rear = max(0,min(1,(.008-root.x)/.022))
                    own = {'Dorsal_01':1-rear,'Dorsal_02':rear}
                else:
                    own = {'Tail_Fin' if name=='Caudal_Fin' else 'Anal_Fin':1.0}
                weights = blend(attached,own,t)
            elif name.startswith('Pectoral'):
                a=world@obj.data.vertices[0].co
                b=world@obj.data.vertices[26*6].co
                axis=b-a
                closest=a+axis*max(0,min(1,(p-a).dot(axis)/axis.length_squared))
                t=min(1,(p-closest).length/.0035)
                weights = blend({'Body_01':1.0},{name:1.0},t*t*(3-2*t))
            else:  # Pelvic: rows run along the long narrow fin, not its width.
                t = (v.index//5)/34
                t = min(1,t*4)
                weights = blend(body_weights(obj.location.x),{name:1.0},t*t*(3-2*t))
            total = sum(weights.values())
            for key,value in weights.items():
                if key not in groups:
                    groups[key] = obj.vertex_groups.new(name=key)
                groups[key].add([v.index],value/total,'REPLACE')
            max_count = max(max_count,len(weights))
            max_error = max(max_error,abs(total-1))
        report[obj.name] = {'vertices':len(obj.data.vertices),'max_influences':max_count,
                            'max_weight_sum_error':max_error,'groups':list(groups)}
        assert max_count <= 4 and max_error < 1e-6
    bpy.context.view_layer.update()
    return report


def rotate(rig, name, axis, degrees):
    pb = rig.pose.bones[name]
    local_axis = pb.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
    pb.rotation_quaternion = Quaternion(local_axis, math.radians(degrees))


def neutral(rig):
    for pb in rig.pose.bones:
        pb.location = (0,0,0)
        pb.rotation_quaternion = (1,0,0,0)
        pb.scale = (1,1,1)
    bpy.context.view_layer.update()


def pectoral_hinge(name):
    obj=bpy.data.objects[name]
    return (obj.matrix_world.to_3x3() @
            (obj.data.vertices[26*6].co-obj.data.vertices[0].co)).normalized()


def test_pose(rig):
    neutral(rig)
    for name,angle in zip(BODY+['Tail_Fin'],[0,2,4,-6,-8,13,10]):
        rotate(rig,name,(0,0,1),angle)
    for name in ('Pectoral_Fin_Left','Pectoral_Fin_Right'):
        rotate(rig,name,pectoral_hinge(name),8 if name.endswith('Left') else -8)
    bpy.context.view_layer.update()


def key(rig, frame):
    for pb in rig.pose.bones:
        pb.keyframe_insert('rotation_quaternion',frame=frame,group=pb.name)


def actions(rig):
    rig.animation_data_create()
    action = bpy.data.actions.new('Rig_Test_Pose')
    action.use_fake_user = True
    rig.animation_data.action = action
    test_pose(rig)
    key(rig,1)
    rig.animation_data.action = None
    neutral(rig)
    action = bpy.data.actions.new('Swim_Test_Loop')
    action.use_fake_user = True
    rig.animation_data.action = action
    key(rig,0)  # Neutral inspection frame outside the playback/export range.
    for frame in range(1,62):
        phase = 2*math.pi*(frame-1)/60
        for i,name in enumerate(BODY+['Tail_Fin']):
            amplitude = [0,.6,1.3,2.3,3.6,5.0,6.0][i]
            rotate(rig,name,(0,0,1),amplitude*math.sin(phase-i*.62))
        rotate(rig,'Dorsal_01',(1,0,0),1.0*math.sin(phase-.5))
        rotate(rig,'Dorsal_02',(1,0,0),1.7*math.sin(phase-1.5))
        rotate(rig,'Anal_Fin',(1,0,0),1.5*math.sin(phase-1.5))
        for prefix,amplitude in [('Pectoral',4),('Pelvic',2)]:
            for side,sign in [('Left',1),('Right',-1)]:
                name=prefix+'_Fin_'+side
                axis=pectoral_hinge(name) if prefix=='Pectoral' else (1,0,0)
                rotate(rig,name,axis,sign*amplitude*math.sin(phase+.5))
        key(rig,frame)
    action.use_frame_range = True
    action.frame_start, action.frame_end = 1,61
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for point in curve.keyframe_points:
                        point.interpolation = 'LINEAR'
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1,60
    scene.timeline_markers.new('NEUTRAL (outside loop)',frame=0)
    scene.timeline_markers.new('Loop start',frame=1)
    scene.timeline_markers.new('Loop seam = frame 1',frame=61)
    scene.frame_set(0)
    return action


def evaluated(obj):
    dep = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dep)
    return ev, ev.to_mesh()


def validate(rig):
    report = {'frames_checked':[], 'maximum_rest_displacement_m':0}
    scene = bpy.context.scene
    scene.frame_set(0)
    for obj in MODEL:
        ev,mesh = evaluated(obj)
        delta = max((v.co-obj.data.vertices[v.index].co).length for v in mesh.vertices)
        report['maximum_rest_displacement_m'] = max(report['maximum_rest_displacement_m'],delta)
        ev.to_mesh_clear()
    assert report['maximum_rest_displacement_m'] < 1e-7
    minimum,maximum = 1.0,1.0
    report['area_ratio_by_mesh'] = {o.name:[1.0,1.0] for o in MODEL}
    seam = []
    # All 61 sampled poses: finite geometry and no collapsed/stretched faces.
    for frame in range(1,62):
        scene.frame_set(frame)
        for obj in MODEL:
            ev,mesh = evaluated(obj)
            ratios = [p.area/obj.data.polygons[p.index].area for p in mesh.polygons]
            bounds = report['area_ratio_by_mesh'][obj.name]
            bounds[0],bounds[1] = min(bounds[0],min(ratios)),max(bounds[1],max(ratios))
            minimum,maximum = min(minimum,min(ratios)),max(maximum,max(ratios))
            assert all(math.isfinite(v) and v>.05 for v in ratios), (frame,obj.name)
            if frame in (1,61):
                seam.append(np.array([list(v.co) for v in mesh.vertices]))
            ev.to_mesh_clear()
        report['frames_checked'].append(frame)
    report['minimum_face_area_ratio'] = minimum
    report['maximum_face_area_ratio'] = maximum
    report['all_mesh_loop_seam_error_m'] = max(float(np.max(np.abs(a-b)))
        for a,b in zip(seam[:len(MODEL)],seam[len(MODEL):]))
    assert report['all_mesh_loop_seam_error_m'] < 1e-7
    assert minimum > .7 and maximum < 1.4, 'Excessive local skin stretch'
    # A geometric self-intersection check on actual skinned body extremes.
    audit = runpy.run_path(str(ROOT/'blender/diagnose_model.py'),run_name='audit_helpers')
    report['mesh_self_intersections'] = {}
    for frame in (1,8,16,23,31,38,46,53,61):
        scene.frame_set(frame)
        report['mesh_self_intersections'][frame] = {}
        for obj in MODEL:
            ev,mesh = evaluated(obj)
            temp = bpy.data.objects.new('TemporarySkinAudit',mesh.copy())
            temp.matrix_world = obj.matrix_world
            count = len(audit['intersection_pairs'](temp))
            report['mesh_self_intersections'][frame][obj.name] = count
            copy = temp.data
            bpy.data.objects.remove(temp)
            bpy.data.meshes.remove(copy)
            ev.to_mesh_clear()
            assert count == 0,(frame,obj.name,count)
    scene.frame_set(0)
    return report


def validate_test_pose():
    audit=runpy.run_path(str(ROOT/'blender/diagnose_model.py'),run_name='audit_helpers')
    report={}
    for obj in MODEL:
        ev,mesh=evaluated(obj)
        ratios=[p.area/obj.data.polygons[p.index].area for p in mesh.polygons]
        temp=bpy.data.objects.new('TemporaryPoseAudit',mesh.copy())
        temp.matrix_world=obj.matrix_world
        count=len(audit['intersection_pairs'](temp))
        copy=temp.data
        bpy.data.objects.remove(temp)
        bpy.data.meshes.remove(copy)
        ev.to_mesh_clear()
        report[obj.name]={'minimum_area_ratio':min(ratios),'maximum_area_ratio':max(ratios),
                          'self_intersections':count}
        assert count==0 and min(ratios)>.4 and max(ratios)<2,(obj.name,report[obj.name])
    return report


def render_diagnostic(rig,name,oblique=False):
    scene = bpy.context.scene
    camera = scene.camera
    target = Vector((0,0,-.001))
    camera.location = (0,-.06,.20) if oblique else (0,-.2,-.001)
    camera.rotation_euler = (target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale = .101
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x,scene.render.resolution_y = 2200,1300
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.background_type = 'WORLD'
    scene.world.color = (.055,.065,.075)
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.render.filepath = str(OUT/name)
    bpy.context.view_layer.update()
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(str(OUT/name),check_existing=False)
    w,h = image.size
    pixels = np.array(image.pixels[:],dtype=np.float32).reshape(h,w,4)[::-1].copy()
    bpy.data.images.remove(image)
    def project(p):
        v = world_to_camera_view(scene,camera,p)
        return np.array((v.x*w,(1-v.y)*h))
    def line(a,b,color,radius):
        points = np.rint(np.linspace(a,b,max(2,int(max(abs(b-a)))+1))).astype(int)
        for dx in range(-radius,radius+1):
            for dy in range(-radius,radius+1):
                x,y=points[:,0]+dx,points[:,1]+dy
                valid=(x>=0)&(x<w)&(y>=0)&(y<h)
                pixels[y[valid],x[valid],:3]=color
    for pb in rig.pose.bones:
        a,b=project(rig.matrix_world@pb.head),project(rig.matrix_world@pb.tail)
        color=(.08,.95,1) if pb.name in BODY+['Tail_Fin'] else (1,.68,.1)
        line(a,b,(.02,.025,.03),4)
        line(a,b,color,2)
        line(a-3,a+3,color,2)
    helper=runpy.run_path(str(ROOT/'blender/setup_reference_view.py'),run_name='image_helpers')
    helper['save_image'](pixels,name)


if __name__ == '__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    if '--audit-only' in sys.argv:
        print(json.dumps(validate(bpy.data.objects['Pelvicachromis_Rig'])))
        raise SystemExit(0)
    if '--rebuild' in sys.argv:
        existing = bpy.data.objects.get('Pelvicachromis_Rig')
        if existing:
            bpy.context.scene.frame_set(0)
            for obj in MODEL:
                world = obj.matrix_world.copy()
                obj.parent = None
                obj.matrix_world = world
                obj.vertex_groups.clear()
                for mod in list(obj.modifiers):
                    if mod.type=='ARMATURE' and mod.object==existing:
                        obj.modifiers.remove(mod)
            data = existing.data
            bpy.data.objects.remove(existing,do_unlink=True)
            bpy.data.armatures.remove(data)
            for name in ('Rig_Test_Pose','Swim_Test_Loop'):
                action=bpy.data.actions.get(name)
                if action:
                    bpy.data.actions.remove(action)
    before=digest()
    rig=create_rig()
    weights=bind(rig)
    loop=actions(rig)
    print('Rig and weights created; checking all loop frames',flush=True)
    checks=validate(rig)
    render_diagnostic(rig,'rig_side.png')
    rig.animation_data.action=None
    test_pose(rig)
    checks['test_pose']=validate_test_pose()
    render_diagnostic(rig,'rig_pose_test.png',True)
    rig.animation_data.action=loop
    bpy.context.scene.frame_set(0)
    neutral(rig)
    # Restore side camera without duplicating the already saved neutral render.
    camera=bpy.context.scene.camera
    camera.location=(0,-.2,-.001)
    camera.rotation_euler=(Vector((0,0,-.001))-camera.location).to_track_quat('-Z','Y').to_euler()
    assert digest()==before
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    bpy.data.objects['Reference_Photo'].hide_set(True)
    rig.hide_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active=rig
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active
                space.shading.type='SOLID'
                space.shading.color_type='MATERIAL'
                space.shading.show_xray=False
                space.overlay.show_extras=True
                space.region_3d.view_perspective='CAMERA'
    result={'bones':[b.name for b in rig.data.bones], 'weights':weights,'validation':checks,
            'geometry_sha256_before':before,'geometry_sha256_after':digest(),
            'neutral_frame':0,'loop_frames':[1,61],'playback_frames':[1,60],'fps':30}
    (OUT/'rig_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'models/Pelvicachromis_Male_Blockout.blend'))
    print(json.dumps(result),flush=True)
