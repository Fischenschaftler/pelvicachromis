"""Mesh audit and static diagnostic views; no rig, keys or UVs are created."""
import itertools
import json
import math
import runpy
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
from mathutils.geometry import intersect_ray_tri

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'blender' / 'diagnostics'
OUTPUT.mkdir(parents=True, exist_ok=True)


def triangles(obj):
    obj.data.calc_loop_triangles()
    vertices = [obj.matrix_world @ v.co for v in obj.data.vertices]
    faces = [tuple(tri.vertices) for tri in obj.data.loop_triangles]
    return vertices, faces


def crossing(a, b):
    # Strict interior segment/triangle crossing. Shared boundary contacts and
    # parallel/coplanar sheets are not classified as transversal intersections.
    for source, target in ((a, b), (b, a)):
        for p, q in zip(source, source[1:] + source[:1]):
            direction = q - p
            hit = intersect_ray_tri(*target, direction, p, True)
            if hit is not None and direction.length_squared > 0:
                t = (hit - p).dot(direction) / direction.length_squared
                if 1e-5 < t < 1 - 1e-5:
                    return True
    return False


def intersection_pairs(obj_a, obj_b=None):
    va, fa = triangles(obj_a)
    vb, fb = triangles(obj_b) if obj_b else (va, fa)
    tree_a = BVHTree.FromPolygons(va, fa, all_triangles=True)
    tree_b = BVHTree.FromPolygons(vb, fb, all_triangles=True) if obj_b else tree_a
    hits = []
    for i, j in tree_a.overlap(tree_b):
        if obj_b is None and (i >= j or set(fa[i]) & set(fb[j])):
            continue
        if crossing([va[k] for k in fa[i]], [vb[k] for k in fb[j]]):
            hits.append((i, j))
    return hits


def audit_object(obj):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.normal_update()
    boundary = sum(edge.is_boundary for edge in bm.edges)
    loose = sum(edge.is_wire for edge in bm.edges)
    multi = sum(len(edge.link_faces) > 2 for edge in bm.edges)
    inconsistent = sum(len(edge.link_faces) == 2 and not edge.is_contiguous for edge in bm.edges)
    unvisited = set(bm.verts)
    components = 0
    while unvisited:
        components += 1
        stack = [unvisited.pop()]
        while stack:
            vertex = stack.pop()
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex)
                if other in unvisited:
                    unvisited.remove(other)
                    stack.append(other)
    tree = KDTree(len(mesh.vertices))
    for v in mesh.vertices:
        tree.insert(v.co, v.index)
    tree.balance()
    duplicates = sum(j > v.index for v in mesh.vertices for _, j, _ in tree.find_range(v.co, 1e-8))
    seen = set()
    duplicate_faces = 0
    folded_quads = 0
    for face in mesh.polygons:
        key = tuple(sorted(face.vertices))
        duplicate_faces += key in seen
        seen.add(key)
        if len(face.vertices) == 4:
            a, b, c, d = (mesh.vertices[i].co for i in face.vertices)
            n1 = (b - a).cross(c - a)
            n2 = (c - a).cross(d - a)
            folded_quads += n1.dot(n2) <= 0
    info = {
        'vertices': len(mesh.vertices), 'faces': len(mesh.polygons),
        'connected_components': components,
        'quads': sum(len(p.vertices) == 4 for p in mesh.polygons),
        'boundary_edges': boundary, 'wire_edges': loose,
        'edges_more_than_two_faces': multi, 'inconsistent_winding_edges': inconsistent,
        'duplicate_vertex_pairs_1e_8m': duplicates, 'duplicate_faces': duplicate_faces,
        'zero_area_faces': sum(p.area < 1e-13 for p in mesh.polygons),
        'folded_quads': folded_quads,
        'self_crossing_triangle_pairs': len(intersection_pairs(obj)),
        'signed_volume_m3': bm.calc_volume(signed=True) if not boundary else None,
        'rotation': list(obj.rotation_euler), 'scale': list(obj.scale),
        'origin_world': list(obj.location),
    }
    bm.free()
    return info


def run_audit():
    bpy.context.view_layer.update()
    objects = sorted((o for o in bpy.context.scene.objects if o.type == 'MESH'), key=lambda o: o.name)
    report = {'objects': {o.name: audit_object(o) for o in objects}, 'cross_object_intersections': {}}
    for a, b in itertools.combinations(objects, 2):
        count = len(intersection_pairs(a, b))
        if count:
            report['cross_object_intersections'][a.name + ' / ' + b.name] = count
    body = bpy.data.objects['Fish_Body']
    xs = []
    for x in sorted((body.matrix_world @ v.co).x for v in body.data.vertices):
        if not xs or x - xs[-1] > 1e-7:
            xs.append(x)
    distances = [b - a for a, b in zip(xs, xs[1:])]
    report['body_loops'] = {'count': len(xs), 'min_spacing_mm': min(distances) * 1000,
                            'max_spacing_mm': max(distances) * 1000}
    defs = runpy.run_path(str(ROOT / 'blender' / 'create_pelvicachromis_male_from_reference.py'), run_name='shape_definition')
    top, bottom, widths = [], [], []
    for x in xs:
        points = [body.matrix_world @ v.co for v in body.data.vertices
                  if abs((body.matrix_world @ v.co).x - x) < 1e-7]
        top.append(max(p.z for p in points))
        bottom.append(min(p.z for p in points))
        widths.append(max(p.y for p in points) - min(p.y for p in points))
    sample_x = np.linspace(xs[0], xs[-1], 2000)
    expected = np.array([defs['profile_at'](float(x)) for x in sample_x])
    deviation = max(float(np.max(np.abs(np.interp(sample_x, xs, top) - expected[:, 1]))),
                    float(np.max(np.abs(np.interp(sample_x, xs, bottom) - expected[:, 2]))))
    report['body_loops']['maximum_contour_resampling_error_pixels'] = deviation / defs['PIXEL_SCALE']
    report['cross_sections'] = {
        'max_width_mm': max(widths) * 1000,
        'max_height_mm': max(a - b for a, b in zip(top, bottom)) * 1000,
        'tail_stalk_width_mm': widths[0] * 1000,
    }
    report['intersection_interpretation'] = (
        'Body/median-fin crossings are intentional embedded roots. Eyes and mouth '
        'have hidden closure surfaces inside the body. Open fin rims are intentional. '
        'Numerical crossing test excludes coplanar contact; duplicate faces, folded '
        'quads and visual wire views are checked separately.'
    )
    return report


def static_bend_probe():
    """Two unlinked temporary meshes, no armature, keyframe, or saved pose."""
    body = bpy.data.objects['Fish_Body']
    source = [body.matrix_world @ v.co for v in body.data.vertices]
    anchor = 0.025
    length = anchor - min(p.x for p in source)
    amplitude = length * math.tan(math.radians(30)) / 3
    results = []
    for direction in (-1, 1):
        temp = body.copy()
        temp.data = body.data.copy()
        inverse = body.matrix_world.inverted()
        for vertex, p in zip(temp.data.vertices, source):
            t = max(0, min(1, (anchor - p.x) / length))
            slope = -direction * 3 * amplitude * t**2 / length
            normal = Vector((-slope, 1.0, 0.0)).normalized()
            vertex.co = inverse @ Vector((p.x + normal.x * p.y,
                direction * amplitude * t**3 + normal.y * p.y, p.z))
        temp.data.update()
        bm = bmesh.new()
        bm.from_mesh(temp.data)
        volume = bm.calc_volume(signed=True)
        bm.free()
        intersections = len(intersection_pairs(temp))
        min_area_ratio = min(b.area / a.area for a, b in zip(body.data.polygons, temp.data.polygons))
        results.append({'tail_angle_degrees': direction * 30,
                        'self_crossing_triangle_pairs': intersections,
                        'minimum_face_area_ratio': min_area_ratio,
                        'positive_volume': volume > 0})
        mesh = temp.data
        bpy.data.objects.remove(temp)
        bpy.data.meshes.remove(mesh)
        assert intersections == 0 and volume > 0 and min_area_ratio > 0.5
    return results


def diagnostic_views():
    scene = bpy.context.scene
    camera = scene.camera
    model = [o for o in scene.objects if o.type == 'MESH']
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.display.shading.show_shadows = False
    scene.display.shading.color_type = 'MATERIAL'

    def render(name, resolution, position, target, scale):
        camera.location = position
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        camera.data.ortho_scale = scale
        scene.render.resolution_x, scene.render.resolution_y = resolution
        scene.render.filepath = str(OUTPUT / name)
        bpy.context.view_layer.update()
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(scene.render.filepath, check_existing=False)
        width, height = img.size
        pixels = np.array(img.pixels[:], dtype=np.float32).reshape(height, width, 4)
        bpy.data.images.remove(img)
        return pixels

    def write(pixels, name):
        height, width, _ = pixels.shape
        img = bpy.data.images.new('DiagnosticOutput', width, height, alpha=True, float_buffer=True)
        linear = pixels.copy()
        rgb = linear[:, :, :3]
        linear[:, :, :3] = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055)**2.4)
        img.pixels.foreach_set(linear.ravel())
        img.save_render(str(OUTPUT / name), scene=scene)
        bpy.data.images.remove(img)

    def opaque(pixels, dim=1.0):
        result = pixels.copy()
        alpha = result[:, :, 3:4] * dim
        result[:, :, :3] = result[:, :, :3] * alpha + np.array((0.12, 0.15, 0.17)) * (1 - alpha)
        result[:, :, 3] = 1
        return result

    def draw_edges(pixels, obj, edges, color, radius=1):
        height, width, _ = pixels.shape
        positions = []
        for vertex in obj.data.vertices:
            p = world_to_camera_view(scene, camera, obj.matrix_world @ vertex.co)
            positions.append((p.x * width, p.y * height))
        for a, b in edges:
            a, b = np.array(positions[a]), np.array(positions[b])
            steps = max(2, int(np.max(np.abs(b - a))) + 1)
            line = np.rint(np.linspace(a, b, steps)).astype(int)
            for dx in range(-radius, radius + 1):
                for dy in range(-radius, radius + 1):
                    x, y = line[:, 0] + dx, line[:, 1] + dy
                    valid = (x >= 0) & (x < width) & (y >= 0) & (y < height)
                    pixels[y[valid], x[valid], :3] = color

    def contour_edges(obj):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        view = Vector((0, -1, 0))
        edges = []
        for edge in bm.edges:
            if edge.is_boundary or (len(edge.link_faces) == 2 and
                (edge.link_faces[0].normal.dot(view) >= 0) != (edge.link_faces[1].normal.dot(view) >= 0)):
                edges.append(tuple(v.index for v in edge.verts))
        bm.free()
        return edges

    side = render('01_side_model.png', (2400, 2400), (0, -0.2, 0), (0, 0, 0), 800 * 0.08 / 670)
    write(opaque(side), '01_side_model.png')
    reference = bpy.data.objects['Reference_Photo'].data.copy()
    reference.scale(2400, 2400)
    photo = np.array(reference.pixels[:], dtype=np.float32).reshape(2400, 2400, 4)
    bpy.data.images.remove(reference)
    overlay = photo.copy()
    alpha = side[:, :, 3:4] * 0.16
    overlay[:, :, :3] = photo[:, :, :3] * (1 - alpha) + side[:, :, :3] * alpha
    overlay[:, :, 3] = 1
    for obj in model:
        if obj.name.endswith('_Left'):
            continue
        color = (1.0, 0.72, 0.12) if '_Fin' in obj.name else (0.04, 0.95, 1.0)
        draw_edges(overlay, obj, contour_edges(obj), color, radius=1)
    write(overlay, '02_reference_contours.png')
    wire = opaque(side, dim=0.3)
    for obj in model:
        draw_edges(wire, obj, [tuple(e.vertices) for e in obj.data.edges],
                   (0.32, 0.85, 0.90) if obj.name == 'Fish_Body' else (0.87, 0.73, 0.40), radius=0)
    write(wire, '03_wire_side.png')
    top = render('04_wire_top.png', (2400, 1100), (0, 0, 0.2), (0, 0, 0), 0.094)
    wire = opaque(top, dim=0.3)
    for obj in model:
        draw_edges(wire, obj, [tuple(e.vertices) for e in obj.data.edges],
                   (0.32, 0.85, 0.90) if obj.name == 'Fish_Body' else (0.87, 0.73, 0.40), radius=0)
    write(wire, '04_wire_top.png')
    front = render('05_front.png', (1600, 1600), (0.2, 0, 0.001), (0, 0, 0.001), 0.052)
    write(opaque(front), '05_front.png')


if __name__ == '__main__':
    report = run_audit()
    if '--baseline' not in sys.argv:
        report['static_bend_probe'] = static_bend_probe()
    filename = 'baseline_audit.json' if '--baseline' in sys.argv else 'mesh_audit.json'
    (OUTPUT / filename).write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'body': report['objects']['Fish_Body'], 'loops': report['body_loops'],
                      'sections': report.get('cross_sections'), 'bend': report.get('static_bend_probe')}))
    if '--render' in sys.argv:
        for name, entry in report['objects'].items():
            for key in ('wire_edges', 'edges_more_than_two_faces', 'inconsistent_winding_edges',
                        'duplicate_vertex_pairs_1e_8m', 'duplicate_faces', 'zero_area_faces',
                        'folded_quads', 'self_crossing_triangle_pairs'):
                assert entry[key] == 0, (name, key, entry[key])
            assert entry['connected_components'] == 1
            assert max(abs(x) for x in entry['rotation']) < 1e-7
            assert max(abs(x - 1) for x in entry['scale']) < 1e-7
        assert report['objects']['Fish_Body']['boundary_edges'] == 0
        assert report['body_loops']['maximum_contour_resampling_error_pixels'] < 1.0
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'models' / 'Pelvicachromis_Male_Blockout.blend'))
        diagnostic_views()
