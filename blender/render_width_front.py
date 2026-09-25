"""Re-render front comparison with identical framing; never save Blender inputs."""
import bpy
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent
for label,path in [('before','blender/backups/width_before/Pelvicachromis_Male_Blockout.blend'),('after','models/Pelvicachromis_Male_Blockout.blend')]:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/path))
    s=bpy.context.scene;s.frame_set(0)
    s.render.engine='CYCLES';s.cycles.samples=24
    s.render.resolution_x=1400;s.render.resolution_y=1000;s.render.resolution_percentage=100
    c=s.camera;c.location=(.2,0,.002)
    c.rotation_euler=(Vector((0,0,.002))-c.location).to_track_quat('-Z','Y').to_euler()
    c.data.type='ORTHO';c.data.ortho_scale=.070
    s.render.filepath=str(ROOT/f'blender/diagnostics/width_{label}_front.png')
    bpy.ops.render.render(write_still=True)
