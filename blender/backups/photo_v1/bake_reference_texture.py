"""Bake the registered reference to existing PhotoUV without altering the model.
Run: blender -b models/Pelvicachromis_Male_Blockout.blend --python blender/bake_reference_texture.py -- --python-runtime PATH
Requires external Python with NumPy/Pillow for deterministic image rasterization.
"""
import bpy, hashlib, json, runpy, shutil, subprocess, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent
SOURCE=ROOT/'models/Pelvicachromis_Male_Blockout.blend'
OUT=ROOT/'blender/diagnostics'

def fingerprint():
    base=runpy.run_path(str(ROOT/'blender/prepare_uv.py'),run_name='helpers')['fingerprint']()
    uv=[(o.name,[(u.name,[tuple(d.uv) for d in u.data]) for u in o.data.uv_layers],
         [e.use_seam for e in o.data.edges]) for o in sorted(bpy.context.scene.objects,key=lambda o:o.name) if o.type=='MESH']
    return hashlib.sha256((base+json.dumps(uv)).encode()).hexdigest()

def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    runtime=args[args.index('--python-runtime')+1] if '--python-runtime' in args else 'python'
    backup=ROOT/'blender/backups/Pelvicachromis_Male_PrePhoto.blend'
    if not backup.exists():shutil.copy2(SOURCE,backup)
    scene=bpy.context.scene;scene.frame_set(0)
    before=fingerprint()
    work=ROOT/'textures/work';work.mkdir(exist_ok=True);(work/'.gdignore').touch()
    objects=[o for o in scene.objects if o.type=='MESH'];payload=[]
    for obj in objects:
        mesh=obj.data;mesh.calc_loop_triangles();triangles=[]
        assert mesh.uv_layers.active.name=='PhotoUV'
        for tri in mesh.loop_triangles:
            points=[obj.matrix_world@mesh.vertices[i].co for i in tri.vertices]
            triangles.append({'uv':[list(mesh.uv_layers.active.data[i].uv) for i in tri.loops],
                              'photo':[[p.x/(.08/670)+400,400-p.z/(.08/670)] for p in points]})
        payload.append({'name':obj.name,'triangles':triangles})
    (work/'projection_triangles.json').write_text(json.dumps(payload),encoding='utf8')
    subprocess.run([runtime,str(ROOT/'blender/photo_raster.py')],check=True)
    image=bpy.data.images.load(str(ROOT/'textures/pelvicachromis_taeniatus_male_albedo.png'),check_existing=True)
    image.reload();image.name='Pelvicachromis_Photo_Albedo';image.colorspace_settings.name='sRGB';image.pack()
    image.filepath='//../textures/pelvicachromis_taeniatus_male_albedo.png'
    def material(name,alpha):
        mat=bpy.data.materials.get(name) or bpy.data.materials.new(name);mat.use_nodes=True
        nodes=mat.node_tree.nodes;nodes.clear()
        output=nodes.new('ShaderNodeOutputMaterial');shader=nodes.new('ShaderNodeBsdfPrincipled')
        texture=nodes.new('ShaderNodeTexImage');texture.image=image
        shader.inputs['Roughness'].default_value=.72;shader.inputs['Alpha'].default_value=alpha
        mat.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
        mat.node_tree.links.new(shader.outputs['BSDF'],output.inputs['Surface'])
        mat.diffuse_color=(.55,.5,.2,alpha);mat.use_backface_culling=False
        if alpha<1:mat.surface_render_method='DITHERED'
        return mat
    body=material('Pelvicachromis_Photo_Material',1)
    fin=material('Pelvicachromis_Photo_Fins',.88)
    pectoral=material('Pelvicachromis_Photo_Pectoral',.48)
    for obj in objects:
        if obj.name.startswith('Eye'):continue # Keep the existing dark eye and rim.
        mat=pectoral if obj.name.startswith('Pectoral') else fin if 'Fin' in obj.name else body
        for i in range(len(obj.data.materials)):
            if obj.name=='Mouth' and obj.data.materials[i].name=='Eye_Mat':continue
            obj.data.materials[i]=mat
    assert fingerprint()==before,'Protected data changed'
    scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='Standard'
    scene.world.use_nodes=True;bg=scene.world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value=(.42,.42,.42,1);bg.inputs['Strength'].default_value=.8
    camera=scene.camera;camera.data.type='ORTHO';camera.data.ortho_scale=.09
    target=Vector((0,0,.002))
    for name,pos in [('photo_textured_side.png',(0,-.2,.002)),('photo_textured_perspective.png',(.075,-.2,.055))]:
        camera.location=pos;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(OUT/name);bpy.ops.render.render(write_still=True)
    subprocess.run([runtime,str(ROOT/'blender/photo_raster.py'),'--comparison'],check=True)
    camera.location=(0,-.2,.002);camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':area.spaces.active.shading.type='MATERIAL'
    assert fingerprint()==before
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    (OUT/'photo_texture_validation.json').write_text(json.dumps({'protected_data_sha256':before,
        'geometry_uv_rig_weights_animation_unchanged':True,'atlas_size':[4096,4096],
        'photographed_side':'Right (-Y)','fallback_side':'Left (+Y), copied registered projection',
        'padding_pixels':20,'backup':str(backup.relative_to(ROOT))},indent=2),encoding='utf8')
    print('PHOTO BAKE COMPLETE; protected data unchanged')

if __name__=='__main__':main()
