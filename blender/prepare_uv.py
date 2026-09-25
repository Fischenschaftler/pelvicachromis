"""Photo-friendly unique UV atlas, temporary checker diagnostics, no remeshing."""
import hashlib
import json
import math
import runpy
import shutil
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'blender/diagnostics'
SOURCE=ROOT/'models/Pelvicachromis_Male_Blockout.blend'
SLOTS={
 'Body_Left':(.02,.67,.70,.98), 'Body_Right':(.02,.34,.70,.65),
 'Dorsal_Fin':(.02,.17,.54,.32), 'Caudal_Fin':(.73,.64,.98,.98),
 'Anal_Fin':(.73,.31,.98,.61),
 'Pelvic_Fin_Left':(.02,.02,.24,.145),'Pelvic_Fin_Right':(.26,.02,.48,.145),
 'Pectoral_Fin_Left':(.56,.17,.63,.31),'Pectoral_Fin_Right':(.65,.17,.72,.31),
 'Eye_Left_Front':(.51,.07,.56,.12),'Eye_Left_Back':(.58,.07,.63,.12),
 'Eye_Right_Front':(.65,.07,.70,.12),'Eye_Right_Back':(.72,.07,.77,.12),
 'Mouth_Left':(.80,.07,.86,.12),'Mouth_Right':(.89,.07,.95,.12),
 'Body_Tail_Cap':(.77,.18,.85,.27),'Body_Mouth_Cap':(.89,.18,.97,.27),
}
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
islands=[]


def fingerprint():
    rig=bpy.data.objects['Pelvicachromis_Rig']
    payload={'meshes':[], 'bones':[], 'actions':[]}
    for o in sorted(objects,key=lambda o:o.name):
        payload['meshes'].append((o.name,[list(v.co) for v in o.data.vertices],
            [list(p.vertices) for p in o.data.polygons],
            [[(o.vertex_groups[g.group].name,g.weight) for g in v.groups] for v in o.data.vertices],
            [list(r) for r in o.matrix_world], o.parent.name,
            [(m.name,m.type,m.object.name,m.use_deform_preserve_volume) for m in o.modifiers if m.type=='ARMATURE']))
    for b in rig.data.bones:
        payload['bones'].append((b.name,b.parent.name if b.parent else None,[list(r) for r in b.matrix_local],b.length))
    for a in bpy.data.actions:
        curves=[]
        for layer in a.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    curves.extend((c.data_path,c.array_index,[(list(k.co),k.interpolation) for k in c.keyframe_points]) for c in bag.fcurves)
        payload['actions'].append((a.name,curves))
    return hashlib.sha256(json.dumps(payload,sort_keys=True).encode()).hexdigest()


def island(obj,name,faces,coordinate):
    points={vi:Vector(coordinate(vi)) for f in faces for vi in f.vertices}
    low=Vector((min(p.x for p in points.values()),min(p.y for p in points.values())))
    high=Vector((max(p.x for p in points.values()),max(p.y for p in points.values())))
    x0,y0,x1,y1=SLOTS[name]
    factor=min((x1-x0)/(high.x-low.x),(y1-y0)/(high.y-low.y))*.96
    offset=Vector(((x0+x1)/2,(y0+y1)/2))-(low+high)*.5*factor
    for face in faces:
        for li in face.loop_indices:
            uv=points[obj.data.loops[li].vertex_index]*factor+offset
            obj.data.uv_layers.active.data[li].uv=uv
    islands.append({'name':name,'object':obj.name,'slot':SLOTS[name],
                    'faces':[f.index for f in faces], 'uv_per_meter':factor})


def unwrap():
    for obj in objects:
        mesh=obj.data
        layer=mesh.uv_layers.get('PhotoUV') or mesh.uv_layers.new(name='PhotoUV')
        mesh.uv_layers.active=layer
        layer.active_render=True
        for e in mesh.edges:
            e.use_seam=False
        world=[obj.matrix_world@v.co for v in mesh.vertices]
        def planar(i):
            return (world[i].x,world[i].z)
        if obj.name=='Fish_Body':
            rings=int(obj['longitudinal_rings']); sides=40
            for side,sequence in [('Left',list(range(30,40))+list(range(0,11))),
                                  ('Right',list(range(30,9,-1)))]:
                coords={}
                for r in range(rings):
                    ids=[r*sides+j for j in sequence]
                    arc=[0.0]
                    for a,b in zip(ids,ids[1:]):
                        arc.append(arc[-1]+(world[b]-world[a]).length)
                    middle=10
                    for i,vi in enumerate(ids):
                        # Preserve X/photo length, unroll the half-section in Z.
                        coords[vi]=(world[vi].x,world[ids[middle]].z+arc[i]-arc[middle])
                faces=[f for f in mesh.polygons if len(f.vertices)==4 and
                       ((sum(world[i].y for i in f.vertices)>0)==(side=='Left'))]
                island(obj,'Body_'+side,faces,lambda i:coords[i])
            for cap,name in [(rings*sides,'Body_Tail_Cap'),(rings*sides+1,'Body_Mouth_Cap')]:
                faces=[f for f in mesh.polygons if cap in f.vertices]
                island(obj,name,faces,lambda i:(world[i].y,world[i].z))
            for e in mesh.edges:
                a,b=e.vertices
                if a<rings*sides and b<rings*sides:
                    e.use_seam=(a%sides==b%sides and a%sides in (10,30)) or (a//sides==b//sides and a//sides in (0,rings-1))
        elif obj.name.startswith('Eye_'):
            back=len(mesh.vertices)-1
            island(obj,obj.name+'_Front',[f for f in mesh.polygons if back not in f.vertices],planar)
            island(obj,obj.name+'_Back',[f for f in mesh.polygons if back in f.vertices],planar)
            for e in mesh.edges:
                e.use_seam=all(back-40<=i<back for i in e.vertices)
        elif obj.name=='Mouth':
            # Two disk charts on the small ellipsoid, avoiding cylindrical poles.
            for e in mesh.edges:
                e.use_seam=all(abs(mesh.vertices[i].co.y)<1e-7 for i in e.vertices)
            bpy.ops.object.select_all(action='DESELECT')
            obj.hide_set(False);obj.select_set(True)
            bpy.context.view_layer.objects.active=obj
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.uv.unwrap(method='ANGLE_BASED',margin=0.001)
            bpy.ops.object.mode_set(mode='OBJECT')
            mesh=obj.data;layer=mesh.uv_layers.active
            for side in ('Left','Right'):
                faces=[f for f in mesh.polygons if ((sum(mesh.vertices[i].co.y for i in f.vertices)>0)==(side=='Left'))]
                coords={mesh.loops[li].vertex_index:tuple(layer.data[li].uv) for f in faces for li in f.loop_indices}
                island(obj,'Mouth_'+side,faces,lambda i:coords[i])
        else:
            # A conformal unwrap handles the small 3D folds at converging tips
            # that a pure X/Z projection would map onto overlapping triangles.
            bpy.ops.object.select_all(action='DESELECT')
            obj.hide_set(False);obj.select_set(True)
            bpy.context.view_layer.objects.active=obj
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.uv.unwrap(method='MINIMUM_STRETCH' if obj.name=='Caudal_Fin' else 'ANGLE_BASED',margin=0.001)
            bpy.ops.object.mode_set(mode='OBJECT')
            mesh=obj.data
            layer=mesh.uv_layers.active
            raw={}
            for loop in mesh.loops:
                raw[loop.vertex_index]=tuple(layer.data[loop.index].uv)
            ids=sorted(raw)
            a=np.array([raw[i] for i in ids]);b=np.array([planar(i) for i in ids])
            a-=a.mean(axis=0);b-=b.mean(axis=0)
            u,_,vt=np.linalg.svd(a.T@b)
            aligned=a@(u@vt)
            coords={i:aligned[j] for j,i in enumerate(ids)}
            island(obj,obj.name,list(mesh.polygons),lambda i:coords[i])
        mesh.update()


def validate_uv():
    # Positive-area intersections of UV triangles, using a spatial grid.
    def cross(a,b): return a[0]*b[1]-a[1]*b[0]
    def sub(a,b): return (a[0]-b[0],a[1]-b[1])
    def area(poly):
        return abs(sum(cross(a,b) for a,b in zip(poly,poly[1:]+poly[:1])))*.5 if len(poly)>2 else 0
    def overlap(a,b):
        poly=a[:]
        sign=1 if cross(sub(b[1],b[0]),sub(b[2],b[0]))>0 else -1
        for q,r in zip(b,b[1:]+b[:1]):
            old=poly;poly=[]
            if not old: break
            for s,t in zip(old,old[1:]+old[:1]):
                ds=sign*cross(sub(r,q),sub(s,q));dt=sign*cross(sub(r,q),sub(t,q))
                if ds>=0: poly.append(s)
                if (ds>=0)!=(dt>=0):
                    f=ds/(ds-dt)
                    poly.append((s[0]+f*(t[0]-s[0]),s[1]+f*(t[1]-s[1])))
        return area(poly)
    triangles=[]; grid={};pairs=set(); degenerate=[]
    for obj in objects:
        obj.data.calc_loop_triangles()
        uv=obj.data.uv_layers.active.data
        for tri in obj.data.loop_triangles:
            points=[tuple(uv[i].uv) for i in tri.loops]
            if area(points)<1e-13: degenerate.append((obj.name,tri.polygon_index))
            assert all(0<=c<=1 for p in points for c in p)
            index=len(triangles);triangles.append((obj.name,tri.polygon_index,points))
            xs=[p[0] for p in points];ys=[p[1] for p in points]
            for x in range(int(min(xs)*64),int(max(xs)*64)+1):
                for y in range(int(min(ys)*64),int(max(ys)*64)+1):
                    cell=grid.setdefault((x,y),[])
                    for other in cell: pairs.add((other,index))
                    cell.append(index)
    collisions=[]
    for a,b in pairs:
        if overlap(triangles[a][2],triangles[b][2])>1e-11:
            collisions.append((triangles[a][:2],triangles[b][:2]))
    result={'triangle_count':len(triangles),'degenerate_uv_triangles':degenerate,
            'overlapping_uv_triangles':collisions,'islands':islands}
    (OUT/'uv_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    assert not degenerate and not collisions,(degenerate[:5],collisions[:5])
    return result


def stretch_report():
    """Area-weighted anisotropy: 1 = locally square/angle preserving."""
    result={}
    for obj in objects:
        groups={'all':[],'visible_flank':[]}
        mesh=obj.data;mesh.calc_loop_triangles()
        uv=mesh.uv_layers.active.data
        for tri in mesh.loop_triangles:
            a,b,c=[mesh.vertices[i].co for i in tri.vertices]
            ab=b-a;ac=c-a
            x=ab.length
            if x<1e-12:continue
            horizontal=ac.dot(ab)/x
            vertical=math.sqrt(max(0,ac.length_squared-horizontal**2))
            if vertical<1e-12:continue
            u,v,w=[np.array(uv[i].uv) for i in tri.loops]
            jac=np.column_stack((v-u,w-u))@np.linalg.inv(np.array(((x,horizontal),(0,vertical))))
            singular=np.linalg.svd(jac,compute_uv=False)
            ratio=float(singular[0]/singular[-1])
            entry=(ratio,float(tri.area))
            groups['all'].append(entry)
            if abs(tri.normal.y)>.7:groups['visible_flank'].append(entry)
        result[obj.name]={}
        for key,values in groups.items():
            if not values:continue
            values.sort();total=sum(w for _,w in values)
            quantiles={}
            for fraction in (.5,.95):
                accumulated=0
                for ratio,weight in values:
                    accumulated+=weight
                    if accumulated>=fraction*total:
                        quantiles[str(fraction)]=ratio;break
            result[obj.name][key]=quantiles
    return result


def layout():
    pixels=np.ones((2048,2048,4),dtype=np.float32)
    pixels[:,:,:3]=.07
    for index,item in enumerate(islands):
        obj=bpy.data.objects[item['object']]
        uv=obj.data.uv_layers.active.data
        color=[(.1,.85,1), (1,.65,.12),(.65,1,.3),(.95,.3,.6)][index%4]
        for fi in item['faces']:
            coords=[np.array(uv[li].uv)*2047 for li in obj.data.polygons[fi].loop_indices]
            for a,b in zip(coords,coords[1:]+coords[:1]):
                points=np.rint(np.linspace(a,b,max(2,int(max(abs(b-a)))+1))).astype(int)
                pixels[2047-points[:,1],points[:,0],:3]=color
    runpy.run_path(str(ROOT/'blender/setup_reference_view.py'),run_name='helpers')['save_image'](pixels,'uv_layout.png')


def checker_diagnostics():
    image=bpy.data.images.get('UV_Checker') or bpy.data.images.new('UV_Checker',width=2048,height=2048)
    image.generated_type='COLOR_GRID'
    image.filepath_raw=str(ROOT/'textures/uv_checker.png')
    image.file_format='PNG';image.save()
    image.pack();image.filepath='//../textures/uv_checker.png'
    mat=bpy.data.materials.get('UV_Checker_Preview') or bpy.data.materials.new('UV_Checker_Preview')
    mat.use_nodes=True
    for existing in list(mat.node_tree.nodes):
        if existing.type=='TEX_IMAGE':mat.node_tree.nodes.remove(existing)
    shader=mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value=.85
    node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
    mat.node_tree.links.new(node.outputs['Color'],shader.inputs['Base Color'])
    originals={o.name:list(o.data.materials) for o in objects}
    for obj in objects:
        for i in range(len(obj.data.materials)): obj.data.materials[i]=mat
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.samples=16
    scene.cycles.use_denoising=True
    scene.render.resolution_x=1600;scene.render.resolution_y=1000
    scene.render.resolution_percentage=100
    scene.view_settings.view_transform='Standard'
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get('Background')
    old_world=(tuple(bg.inputs['Color'].default_value),bg.inputs['Strength'].default_value)
    bg.inputs['Color'].default_value=(.65,.65,.65,1);bg.inputs['Strength'].default_value=.8
    camera=scene.camera;old_cam=camera.matrix_world.copy();old_scale=camera.data.ortho_scale
    camera.data.type='ORTHO';camera.data.ortho_scale=.096
    rig=bpy.data.objects['Pelvicachromis_Rig'];rig.hide_render=True
    for name,pos in [('uv_checker_side.png',(0,-.2,0)),('uv_checker_other_side.png',(0,.2,0)),('uv_checker_top.png',(0,0,.2))]:
        camera.location=pos
        camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(OUT/name)
        bpy.ops.render.render(write_still=True)
    for obj in objects:
        for i,material in enumerate(originals[obj.name]): obj.data.materials[i]=material
    mat.use_fake_user=True
    rig.hide_render=False
    bg.inputs['Color'].default_value=old_world[0];bg.inputs['Strength'].default_value=old_world[1]
    camera.matrix_world=old_cam;camera.data.ortho_scale=old_scale
    scene.render.engine='BLENDER_WORKBENCH'


if __name__=='__main__':
    backup=ROOT/'blender/backups/Pelvicachromis_Male_PreUV.blend'
    if not backup.exists(): shutil.copy2(SOURCE,backup)
    bpy.context.scene.frame_set(0)
    before=fingerprint()
    unwrap()
    report=validate_uv()
    report['area_weighted_stretch']=stretch_report()
    layout()
    checker_diagnostics()
    assert fingerprint()==before,'Geometry, rig, weights or animation changed'
    report['protected_data_sha256_before']=before
    report['protected_data_sha256_after']=fingerprint()
    (OUT/'uv_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    print('UV atlas saved: %d islands, no positive-area overlaps; protected data unchanged'%len(islands))
