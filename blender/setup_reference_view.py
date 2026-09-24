"""Configure the existing model's comparison view without changing geometry.

Run with Blender --background models/Pelvicachromis_Male_Blockout.blend
--python blender/setup_reference_view.py. Outputs are projected from actual meshes.
"""
import hashlib
import json
import math
from pathlib import Path

import bpy
import bmesh
import numpy as np
from mathutils import Euler

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'blender' / 'diagnostics'
NAMES = ('Fish_Body', 'Dorsal_Fin', 'Caudal_Fin', 'Anal_Fin',
         'Pectoral_Fin_Left', 'Pelvic_Fin_Left')
SCALE = 0.08 / 670
ALPHA = 0.40
# One shared photo-pixel crop keeps photograph and mesh registration identical.
CROP = (45, 200, 755, 590)
FACTOR = 3


def geometry_digest():
    payload = []
    for obj in sorted((o for o in bpy.context.scene.objects if o.type == 'MESH'), key=lambda o: o.name):
        payload.append((obj.name, [list(v.co) for v in obj.data.vertices],
                        [list(e.vertices) for e in obj.data.edges],
                        [list(p.vertices) for p in obj.data.polygons],
                        [list(row) for row in obj.matrix_world]))
    return hashlib.sha256(json.dumps(payload).encode()).hexdigest()


def configure():
    scene = bpy.context.scene
    ref = bpy.data.objects['Reference_Photo']
    image = bpy.data.images.load(str(ROOT / 'blender/reference/pelvicachromis_taeniatus_male.jpg'), check_existing=True)
    assert tuple(image.size) == (800, 800)
    image.pack()
    image.filepath = '//../blender/reference/pelvicachromis_taeniatus_male.jpg'
    ref.data = image
    ref.location = (0, 0.012, 0)
    ref.rotation_euler = (math.pi / 2, 0, 0)
    ref.scale = (1, 1, 1)
    ref.empty_display_size = 800 * SCALE
    ref.empty_image_offset = (-0.5, -0.5)
    ref.empty_image_depth = 'BACK'
    ref.use_empty_image_alpha = True
    ref.color = (1, 1, 1, ALPHA)
    ref.show_empty_image_orthographic = True
    ref.show_empty_image_perspective = False
    ref.hide_select = True
    for obj in scene.objects:
        obj.select_set(False)
        obj.hide_set(obj.name not in NAMES and obj != ref)
        if obj.name in NAMES:
            obj.display_type = 'WIRE'
            obj.show_wire = True
            obj.show_all_edges = True
            obj.show_in_front = True
            obj.color = (0.08, 0.95, 1.0, 1) if obj.name == 'Fish_Body' else (1, 0.65, 0.08, 1)
    x0, y0, x1, y1 = CROP
    center = (((x0 + x1) / 2 - 400) * SCALE, 0, (400 - (y0 + y1) / 2) * SCALE)
    rotation = Euler((math.pi / 2, 0, 0))
    camera = scene.camera
    camera.location = (center[0], -0.2, center[2])
    camera.rotation_euler = rotation
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = (x1 - x0) * SCALE
    # Use only the world-registered Empty; a fitted camera background would
    # stretch/shift the full square photograph after changing the camera crop.
    camera.data.show_background_images = False
    scene.render.resolution_x = (x1 - x0) * FACTOR
    scene.render.resolution_y = (y1 - y0) * FACTOR
    scene.render.resolution_percentage = 100
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != 'VIEW_3D':
                continue
            space = area.spaces.active
            space.clip_start = 0.0001
            space.clip_end = 10
            space.region_3d.view_rotation = rotation.to_quaternion()
            space.region_3d.view_location = center
            space.region_3d.view_distance = 0.075
            space.camera = camera
            space.region_3d.view_perspective = 'CAMERA'
            space.region_3d.view_camera_zoom = 10
            space.region_3d.view_camera_offset = (0, 0)
            space.shading.type = 'WIREFRAME'
            space.shading.wireframe_color_type = 'OBJECT'
            space.shading.show_xray_wireframe = True
            space.shading.xray_alpha_wireframe = 1.0
            space.shading.background_type = 'VIEWPORT'
            space.shading.background_color = (0.055, 0.065, 0.075)
            space.overlay.show_overlays = True
            space.overlay.show_floor = False
            space.overlay.show_axis_x = False
            space.overlay.show_axis_y = False
            space.overlay.show_axis_z = False
            space.overlay.show_cursor = False
            space.overlay.show_extras = True  # Keep the image Empty visible.
    scene['comparison_reference_opacity'] = ALPHA
    scene['comparison_visible_meshes'] = ', '.join(NAMES)
    bpy.context.view_layer.update()
    return image


def contours(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    edges = [tuple(v.index for v in e.verts) for e in bm.edges if e.is_boundary or
             (len(e.link_faces) == 2 and (e.link_faces[0].normal.y >= 0) != (e.link_faces[1].normal.y >= 0))]
    bm.free()
    return edges


def draw(pixels, obj, edges, color, radius=0):
    positions = []
    for vertex in obj.data.vertices:
        p = obj.matrix_world @ vertex.co
        positions.append(((p.x / SCALE + 400 - CROP[0]) * FACTOR,
                          (400 - p.z / SCALE - CROP[1]) * FACTOR))
    h, w = pixels.shape[:2]
    for a, b in edges:
        a, b = np.array(positions[a]), np.array(positions[b])
        line = np.rint(np.linspace(a, b, max(2, int(max(abs(b-a))) + 1))).astype(int)
        for dx in range(-radius, radius+1):
            for dy in range(-radius, radius+1):
                x, y = line[:, 0]+dx, line[:, 1]+dy
                valid = (x >= 0) & (x < w) & (y >= 0) & (y < h)
                pixels[y[valid], x[valid], :3] = color


def save_image(pixels, name):
    h, w = pixels.shape[:2]
    image = bpy.data.images.new('ComparisonDiagnostic', width=w, height=h, alpha=True, float_buffer=True)
    values = pixels[::-1].copy()
    rgb = values[:, :, :3]
    values[:, :, :3] = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055)**2.4)
    image.pixels.foreach_set(values.ravel())
    image.save_render(str(OUT / name), scene=bpy.context.scene)
    bpy.data.images.remove(image)


def diagnostics(image):
    scaled = image.copy()
    scaled.scale(800 * FACTOR, 800 * FACTOR)
    full = np.array(scaled.pixels[:], dtype=np.float32).reshape(800*FACTOR, 800*FACTOR, 4)[::-1]
    x0, y0, x1, y1 = (v * FACTOR for v in CROP)
    base = full[y0:y1, x0:x1].copy()
    base[:, :, :3] = base[:, :, :3] * ALPHA + np.array((0.22, 0.24, 0.26)) * (1-ALPHA)
    base[:, :, 3] = 1
    bpy.data.images.remove(scaled)
    wire, clean = base.copy(), base.copy()
    for name in NAMES:
        obj = bpy.data.objects[name]
        color = (0.08, 0.95, 1.0) if name == 'Fish_Body' else (1.0, 0.72, 0.15)
        draw(wire, obj, [tuple(e.vertices) for e in obj.data.edges], color)
        draw(clean, obj, contours(obj), color, radius=1)
    scene = bpy.context.scene
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    save_image(wire, 'reference_wireframe_overlay.png')
    save_image(clean, 'reference_overlay_clean.png')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    before = geometry_digest()
    diagnostics(configure())
    after = geometry_digest()
    assert before == after, 'Model geometry or transforms changed'
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'reference_view_check.json').write_text(json.dumps({
        'geometry_sha256_before': before, 'geometry_sha256_after': after,
        'reference_opacity': ALPHA, 'visible_meshes': NAMES, 'photo_crop_pixels': CROP,
        'projection': 'Orthographic from negative Y, +X right, +Z up'
    }, indent=2), encoding='utf-8')
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'models/Pelvicachromis_Male_Blockout.blend'))
    print('Comparison saved; geometry and object transforms unchanged:', after)
