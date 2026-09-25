"""Read-only checks on the saved rig, suitable for Blender background mode."""
import json
import runpy
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parent.parent
helpers=runpy.run_path(str(ROOT/'blender/rig_pelvicachromis.py'),run_name='rig_helpers')
report=json.loads((ROOT/'blender/diagnostics/rig_validation.json').read_text(encoding='utf-8'))
rig=bpy.data.objects['Pelvicachromis_Rig']
assert rig.type=='ARMATURE' and len(rig.data.bones)==15
# The user-approved width revision has its own audited geometry baseline.
if bpy.data.objects['Fish_Body'].get('width_revision_1_5',False):
    width_report=json.loads((ROOT/'blender/diagnostics/width_validation.json').read_text())
    assert width_report['protected_data_before']==width_report['protected_data_after']
    assert width_report['x_z_unchanged'] and abs(width_report['width_factor']-1.5)<1e-6
    expected_geometry=width_report['geometry_sha256_after']
else:
    expected_geometry=report['geometry_sha256_before']
assert helpers['digest']()==expected_geometry
assert bpy.context.scene.frame_current==0
assert bpy.context.scene.render.fps==30
assert rig.animation_data.action.name=='Swim_Test_Loop'
assert tuple(rig.animation_data.action.frame_range)==(1,61)
assert bpy.data.actions.get('Rig_Test_Pose') is not None
assert max(abs(v) for v in rig.rotation_euler)<1e-7
assert tuple(rig.scale)==(1,1,1)
assert not rig.animation_data.drivers
assert all(not b.constraints and b.matrix_basis.is_identity for b in rig.pose.bones)
meshes=helpers['MODEL']
assert len(meshes)==11
largest_sum_error=0
for obj in meshes:
    assert obj.parent==rig and len(obj.data.uv_layers)==1
    assert obj.data.uv_layers.active.name=='PhotoUV'
    assert all(0<=c<=1 for loop in obj.data.uv_layers.active.data for c in loop.uv)
    assert obj.data.shape_keys is None
    modifiers=[m for m in obj.modifiers if m.type=='ARMATURE']
    assert len(modifiers)==1 and modifiers[0].object==rig
    assert not modifiers[0].use_deform_preserve_volume
    for vertex in obj.data.vertices:
        weights=[g for g in vertex.groups if g.weight>0]
        assert 1<=len(weights)<=4
        assert all(obj.vertex_groups[g.group].name in rig.data.bones for g in weights)
        error=abs(sum(g.weight for g in weights)-1)
        largest_sum_error=max(largest_sum_error,error)
        assert error<1e-6
    ev,mesh=helpers['evaluated'](obj)
    assert max((v.co-obj.data.vertices[v.index].co).length for v in mesh.vertices)<1e-7
    ev.to_mesh_clear()
print(json.dumps({'saved_rig_verified':True,'bones':15,'meshes':11,
                  'neutral_frame':0,'maximum_stored_weight_sum_error':largest_sum_error,
                  'geometry_matches_approved_baseline':True,'uv_maps_per_mesh':1,'export_performed':False}))
