"""Validate the generated fish, save its blend, and render registered views.

Run after the generator in Blender:
  blender --background --factory-startup --python-exit-code 1 \
    --python blender/create_pelvicachromis_male_from_reference.py \
    --python blender/render_reference_comparison.py

The overlay is a presentation image only, not a texture or UV projection.
"""
import json
from pathlib import Path

import bmesh
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'blender' / 'previews'
OUTPUT.mkdir(parents=True, exist_ok=True)
required = {
    'Fish_Body', 'Eye_Left', 'Eye_Right', 'Mouth', 'Dorsal_Fin',
    'Caudal_Fin', 'Anal_Fin', 'Pectoral_Fin_Left', 'Pectoral_Fin_Right',
    'Pelvic_Fin_Left', 'Pelvic_Fin_Right',
}
meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
assert {obj.name for obj in meshes} == required
for obj in meshes:
    assert not obj.data.uv_layers and not obj.animation_data and not obj.modifiers, obj.name
    assert all(poly.area > 1e-13 for poly in obj.data.polygons), obj.name
body = bpy.data.objects['Fish_Body']
bm = bmesh.new()
bm.from_mesh(body.data)
assert all(edge.is_manifold for edge in bm.edges)
assert bm.calc_volume(signed=True) > 0
bm.free()
reference = bpy.data.objects['Reference_Photo']
assert reference.type == 'EMPTY' and reference.data.packed_file
assert bpy.context.scene.camera.data.type == 'ORTHO'
bpy.context.view_layer.update()
points = [obj.matrix_world @ vert.co for obj in meshes for vert in obj.data.vertices]
length = max(p.x for p in points) - min(p.x for p in points)
assert 0.079 <= length <= 0.081
report = {
    'length_m': length, 'mesh_objects': len(meshes),
    'vertices': sum(len(obj.data.vertices) for obj in meshes),
    'faces': sum(len(obj.data.polygons) for obj in meshes),
    'body_closed': True, 'uv_maps': 0, 'rigs': 0,
    'reference_packed': True,
}
print(json.dumps(report))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'models' / 'Pelvicachromis_Male_Blockout.blend'))

scene = bpy.context.scene
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.filepath = str(OUTPUT / 'pelvicachromis_side.png')
bpy.ops.render.render(write_still=True)
render = bpy.data.images.load(scene.render.filepath, check_existing=False)
width, height = render.size
model_pixels = np.array(render.pixels[:], dtype=np.float32).reshape(height, width, 4)
photo = reference.data.copy()
photo.scale(width, height)
photo_pixels = np.array(photo.pixels[:], dtype=np.float32).reshape(height, width, 4)
alpha = model_pixels[:, :, 3:4] * 0.30
comparison = photo_pixels.copy()
comparison[:, :, :3] = photo_pixels[:, :, :3] * (1 - alpha) + model_pixels[:, :, :3] * alpha
comparison[:, :, 3] = 1.0
# Cyan boundary marks the projected model silhouette without hiding the photo.
mask = model_pixels[:, :, 3] > 0.5
interior = mask.copy()
for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2)):
    interior &= np.roll(mask, (dy, dx), axis=(0, 1))
comparison[mask & ~interior, :3] = (0.03, 0.90, 0.90)
image = bpy.data.images.new('ReferenceComparison_Output', width, height, alpha=True, float_buffer=True)
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'


def write_srgb(pixels, path):
    # Loaded byte-image pixels are sRGB samples. save_render expects linear
    # values for a generated float image; avoid brightening the reference twice.
    linear = pixels.copy()
    rgb = linear[:, :, :3]
    linear[:, :, :3] = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055)**2.4)
    image.pixels.foreach_set(linear.ravel())
    image.save_render(str(path), scene=scene)


write_srgb(comparison, OUTPUT / 'pelvicachromis_reference_comparison.png')
side = model_pixels.copy()
coverage = model_pixels[:, :, 3:4]
side[:, :, :3] = model_pixels[:, :, :3] * coverage + np.array((0.12, 0.15, 0.17)) * (1 - coverage)
side[:, :, 3] = 1.0
write_srgb(side, OUTPUT / 'pelvicachromis_side.png')
print('Saved orthographic side view and registered photo/model comparison.')
