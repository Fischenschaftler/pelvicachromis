"""Build an editable 8 cm male Pelvicachromis taeniatus blockout.

Run in Blender's Text Editor or with:
    blender --background --python blender/create_pelvicachromis_male_from_reference.py

Reference: blender/reference/pelvicachromis_taeniatus_male.jpg.
The reference is a visual guide; it is not projected onto the mesh.
Here +X is forward, Y is body width, and Z is height. Dimensions are in
metres (overall length ~0.08 m). No rig, UV maps, or animation are generated.
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Vector


# All silhouette landmarks are manually read from the sole 800 x 800 photo.
# The photograph's slight head-up posture is intentionally retained so that
# a single orthographic camera registers every vertex against the photograph.
SCRIPT_DIR = Path(__file__).resolve().parent
REFERENCE_PATH = SCRIPT_DIR / "reference" / "pelvicachromis_taeniatus_male.jpg"
PIXEL_SCALE = 0.08 / 670.0
IMAGE_SIZE = 800


def photo_point(u, v, y=0.0):
    return Vector(((u - 400.0) * PIXEL_SCALE, y, (400.0 - v) * PIXEL_SCALE))


def outline_value(points, u):
    if u <= points[0][0]:
        return points[0][1]
    for a, b in zip(points, points[1:]):
        if u <= b[0]:
            t = (u - a[0]) / (b[0] - a[0])
            return a[1] * (1 - t) + b[1] * t
    return points[-1][1]


BODY_TOP_PIXELS = [
    (215, 369), (237, 365), (266, 358), (298, 343), (331, 326),
    (366, 307), (400, 288), (433, 273), (473, 258), (512, 247),
    (548, 240), (583, 238), (620, 240), (651, 245), (678, 251),
    (697, 261), (714, 273), (725, 280), (731, 286), (734, 293),
]
BODY_BOTTOM_PIXELS = [
    (215, 438), (239, 436), (258, 435), (290, 434), (323, 436),
    (355, 438), (389, 436), (423, 432), (457, 426), (491, 419),
    (524, 413), (551, 406), (574, 399), (603, 386), (630, 372),
    (656, 356), (678, 344), (700, 331), (717, 321), (728, 311),
    (732, 304), (734, 297),
]
WIDTH_LANDMARKS = [
    (215, 0.0009), (245, 0.0011), (300, 0.0015), (380, 0.0021),
    (470, 0.0030), (550, 0.0034), (600, 0.0033), (650, 0.0029),
    (680, 0.0026), (710, 0.0020), (728, 0.0010), (734, 0.00035),
]
BODY_PROFILE = [
    ((u - 400) * PIXEL_SCALE, outline_value(WIDTH_LANDMARKS, u),
     (400 - outline_value(BODY_TOP_PIXELS, u)) * PIXEL_SCALE,
     (400 - outline_value(BODY_BOTTOM_PIXELS, u)) * PIXEL_SCALE)
    for u in sorted({p[0] for p in BODY_TOP_PIXELS + BODY_BOTTOM_PIXELS + WIDTH_LANDMARKS})
]
EYE_X, _, EYE_Z = photo_point(669, 276)
EYE_RADIUS = 0.00165


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def make_material(name, color, alpha=1.0, roughness=0.7):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = (*color, alpha)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, alpha)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Alpha"].default_value = alpha
    if alpha < 1.0 and hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    if hasattr(material, "use_backface_culling"):
        material.use_backface_culling = False
    return material


def make_mesh_object(name, vertices, faces, material):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate(clean_customdata=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def set_origin_world(obj, location):
    """Move the pivot without moving any world-space vertex."""
    location = Vector(location)
    delta = location - obj.location
    for vertex in obj.data.vertices:
        vertex.co -= delta
    obj.location = location
    obj.data.update()


def repair_concave_quads(obj):
    """Split only concave quads using their valid diagonal; preserve outlines."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    problem = []
    for face in bm.faces:
        if len(face.verts) == 4:
            a, b, c, d = (v.co for v in face.verts)
            if (b - a).cross(c - a).dot((c - a).cross(d - a)) <= 0:
                problem.append(face)
    if problem:
        bmesh.ops.triangulate(bm, faces=problem, quad_method='BEAUTY')
        bm.to_mesh(obj.data)
        obj.data.update()
    obj['repaired_concave_quads'] = len(problem)
    bm.free()


def profile_at(x):
    """Piecewise cubic interpolation keeps the body smooth and editable."""
    if x <= BODY_PROFILE[0][0]:
        return BODY_PROFILE[0][1:]
    if x >= BODY_PROFILE[-1][0]:
        return BODY_PROFILE[-1][1:]

    for index in range(len(BODY_PROFILE) - 1):
        left = BODY_PROFILE[index]
        right = BODY_PROFILE[index + 1]
        if left[0] <= x <= right[0]:
            span = right[0] - left[0]
            t = (x - left[0]) / span
            values = []
            for field in range(1, 4):
                previous = BODY_PROFILE[max(index - 1, 0)]
                following = BODY_PROFILE[min(index + 2, len(BODY_PROFILE) - 1)]
                slope_left = (right[field] - previous[field]) / (right[0] - previous[0])
                slope_right = (following[field] - left[field]) / (following[0] - left[0])
                value = (
                    (2 * t**3 - 3 * t**2 + 1) * left[field]
                    + (t**3 - 2 * t**2 + t) * span * slope_left
                    + (-2 * t**3 + 3 * t**2) * right[field]
                    + (t**3 - t**2) * span * slope_right
                )
                values.append(value)
            return tuple(values)
    raise RuntimeError("Body profile interpolation failed")


def flank_width(x, z):
    """Sculpted half-width at an X/Z position, shared by body and attachments.

    The exponent flattens the flanks while retaining rounded dorsal/ventral
    ridges. Head relief is bilateral and part of the continuous body mesh.
    """
    half_width, top, bottom = profile_at(x)
    center_z = bottom + 0.48 * (top - bottom)
    height = top - center_z if z >= center_z else center_z - bottom
    vertical = max(-1.0, min(1.0, (z - center_z) / height))
    side_weight = max(0.0, 1.0 - vertical**2)**0.34
    width = half_width * side_weight * (1.0 - 0.06 * vertical)

    cheek_center = photo_point(620, 316)
    cheek = 0.00032 * math.exp(-((x - cheek_center.x) / 0.0045)**2 - ((z - cheek_center.z) / 0.0060)**2)
    # A curved, shallow posterior opercular margin; not an open cut or seam.
    gill_center = photo_point(591, 329)
    gill_edge_x = gill_center.x + 0.0015 * ((z - gill_center.z) / 0.007)**2
    gill_envelope = math.exp(-((z - gill_center.z) / 0.007)**4)
    operculum = gill_envelope * (
        0.00022 * math.exp(-((x - gill_edge_x - 0.00065) / 0.00065)**2)
        - 0.00016 * math.exp(-((x - gill_edge_x + 0.0002) / 0.00055)**2)
    )
    orbit_radius = math.hypot(x - EYE_X, z - EYE_Z)
    orbital_rim = 0.00022 * math.exp(-((orbit_radius - 0.0021) / 0.00060)**2)
    socket = -0.00020 * math.exp(-(orbit_radius / 0.00155)**4)
    # A small lateral cheek-to-snout depression differentiates the muzzle.
    muzzle_center = photo_point(716, 299)
    muzzle = -0.00012 * math.exp(-((x - muzzle_center.x) / 0.0017)**2 - ((z - muzzle_center.z) / 0.0015)**2)
    return max(0.0, width + side_weight * (cheek + operculum + orbital_rim + socket + muzzle))


def body_surface(x, angle):
    _, top, bottom = profile_at(x)
    center_z = bottom + 0.48 * (top - bottom)
    height = top - center_z if math.sin(angle) >= 0 else center_z - bottom
    z = center_z + height * math.sin(angle)
    side = 1.0 if math.cos(angle) >= 0 else -1.0
    return Vector((x, side * flank_width(x, z), z))


def build_body(material):
    # Shape interpolation is unchanged. Resample it independently from the
    # irregular pixel landmarks, using evenly spaced loops in each region.
    stations = [BODY_PROFILE[0][0]]
    for u_start, u_end, spacing in ((215, 300, 0.0012), (300, 550, 0.00125),
                                  (550, 680, 0.0009), (680, 728, 0.00055),
                                  (728, 734, 0.00012)):
        start, end = photo_point(u_start, 0).x, photo_point(u_end, 0).x
        subdivisions = math.ceil((end - start) / spacing)
        stations.extend(
            start + (end - start) * step / subdivisions
            for step in range(1, subdivisions + 1)
        )
    rings = len(stations)
    sides = 40
    vertices = []
    faces = []

    for x in stations:
        for side in range(sides):
            angle = 2.0 * math.pi * side / sides
            vertices.append(tuple(body_surface(x, angle)))

    for ring in range(rings - 1):
        for side in range(sides):
            next_side = (side + 1) % sides
            a = ring * sides + side
            b = ring * sides + next_side
            c = (ring + 1) * sides + next_side
            d = (ring + 1) * sides + side
            faces.append((a, b, c, d))
    # Small triangle fans close the endpoints without large deforming n-gons.
    for ring, reverse in ((0, True), (rings - 1, False)):
        center = sum((Vector(vertices[ring * sides + j]) for j in range(sides)), Vector()) / sides
        cap = len(vertices)
        vertices.append(tuple(center))
        for j in range(sides):
            face = (cap, ring * sides + j, ring * sides + (j + 1) % sides)
            faces.append(tuple(reversed(face)) if reverse else face)
    obj = make_mesh_object("Fish_Body", vertices, faces, material)
    midpoint = (stations[0] + stations[-1]) * 0.5
    _, top, bottom = profile_at(midpoint)
    set_origin_world(obj, (midpoint, 0.0, (top + bottom) * 0.5))
    obj['longitudinal_rings'] = rings
    obj['vertices_per_ring'] = sides
    obj['origin_role'] = 'Body centreline at longitudinal midpoint'
    return obj


def sample_curve(points, count):
    """Sample a smooth contour through hand-placed anatomical landmarks."""
    points = [Vector(point) for point in points]
    knots = [0.0]
    for left, right in zip(points, points[1:]):
        knots.append(knots[-1] + (right - left).length)
    result = []
    segment = 0
    for index in range(count):
        distance = knots[-1] * index / (count - 1)
        while segment < len(points) - 2 and distance > knots[segment + 1]:
            segment += 1
        before = max(0, segment - 1)
        after = min(len(points) - 1, segment + 2)
        span = knots[segment + 1] - knots[segment]
        t = (distance - knots[segment]) / span
        tangent_left = (points[segment + 1] - points[before]) / (knots[segment + 1] - knots[before])
        tangent_right = (points[after] - points[segment]) / (knots[after] - knots[segment])
        result.append(
            (2 * t**3 - 3 * t**2 + 1) * points[segment]
            + (t**3 - 2 * t**2 + t) * span * tangent_left
            + (-2 * t**3 + 3 * t**2) * points[segment + 1]
            + (t**3 - t**2) * span * tangent_right
        )
    return result


def build_membrane(name, base_points, edge_points, material, width_steps=5, normal_side=-1, camber=0.00025, trailing_points=None):
    """Regular quad strips leave fins suitable for later bending and UV work."""
    vertices = []
    faces = []
    trailing = sample_curve(trailing_points, width_steps + 1) if trailing_points else None
    for section, (base, edge) in enumerate(zip(base_points, edge_points)):
        along = section / (len(base_points) - 1)
        base = Vector(base)
        edge = Vector(edge)
        for step in range(width_steps + 1):
            t = step / width_steps
            point = base.lerp(edge, t)
            if trailing:
                straight_end = Vector(base_points[-1]).lerp(Vector(edge_points[-1]), t)
                influence = max(0.0, (along - 0.70) / 0.30)**2
                point += (trailing[step] - straight_end) * influence
            # Gentle membrane camber and edge sweep, with exactly fixed roots.
            envelope = math.sin(math.pi * along)
            point.y += normal_side * camber * math.sin(math.pi * t) * envelope
            point.y += normal_side * 0.00012 * math.sin(2 * math.pi * along) * t**2
            point.z += 0.00006 * math.sin(3 * math.pi * along) * envelope * t**2
            vertices.append(tuple(point))

    stride = width_steps + 1
    for section in range(len(base_points) - 1):
        for step in range(width_steps):
            a = section * stride + step
            faces.append((a, a + stride, a + stride + 1, a + 1))
    # Consistent sheet normals: outward for paired fins, toward the reference
    # view (-Y) for median fins. Materials remain double-sided.
    normal = Vector((0.0, 0.0, 0.0))
    for face in faces:
        a, b, c = (Vector(vertices[index]) for index in face[:3])
        normal += (b - a).cross(c - a)
    if normal.y * normal_side < 0.0:
        faces = [tuple(reversed(face)) for face in faces]
    obj = make_mesh_object(name, vertices, faces, material)
    repair_concave_quads(obj)
    if name.startswith('Pelvic_'):
        origin = (Vector(base_points[0]) + Vector(edge_points[0])) * 0.5
    else:
        origin = sum((Vector(point) for point in base_points), Vector()) / len(base_points)
    set_origin_world(obj, origin)
    obj['origin_role'] = 'Fin attachment midpoint'
    return obj


def build_dorsal_fin(material):
    base = []
    sections = 43
    for index in range(sections):
        t = index / (sections - 1)
        x = photo_point(565 - 285 * t, 0).x
        root = body_surface(x, math.pi / 2)
        root.z -= 0.00012
        base.append(root)
    # Low anterior crest follows the back; only the posterior soft portion
    # extends beyond its attachment. No tall central sail.
    edge = sample_curve([photo_point(u, v) for u, v in [
        (566, 237), (524, 232), (487, 225), (453, 222), (426, 225),
        (399, 232), (373, 239), (347, 245), (322, 257), (296, 267),
        (270, 277), (242, 280), (212, 281), (181, 283), (154, 283),
    ]], sections)
    trailing = [base[-1]] + [photo_point(u, v) for u, v in [
        (252, 354), (230, 348), (211, 324), (184, 295), (154, 283),
    ]]
    return build_membrane("Dorsal_Fin", base, edge, material, width_steps=8, trailing_points=trailing)


def build_anal_fin(material):
    base = []
    sections = 35
    for index in range(sections):
        t = index / (sections - 1)
        x = photo_point(423 - 169 * t, 0).x
        root = body_surface(x, -math.pi / 2)
        root.z += 0.00012
        base.append(root)
    # Broad attachment, rounded leading part, and a single posterior point
    # directed toward the lower part of the caudal fan.
    edge = sample_curve([photo_point(u, v) for u, v in [
        (417, 437), (400, 455), (385, 476), (353, 494),
        (318, 516), (280, 535), (240, 550), (195, 571),
    ]], sections)
    trailing = [base[-1]] + [photo_point(u, v) for u, v in [
        (252, 456), (240, 491), (222, 533), (195, 571),
    ]]
    return build_membrane("Anal_Fin", base, edge, material, width_steps=8, trailing_points=trailing)


def build_caudal_fin(material):
    base = []
    sections = 43
    # The broad, asymmetric fan is traced, rather than replaced by an ellipse.
    # Its leading margins emerge from the stalk and the lower lobe is fuller.
    for index in range(sections):
        t = index / (sections - 1)
        base.append(photo_point(216 + 20 * t, 370 + 66 * t))
    edge = sample_curve([photo_point(u, v) for u, v in [
        (200, 369), (174, 367), (144, 363), (116, 361), (92, 366),
        (74, 377), (66, 393), (67, 414), (73, 439), (82, 469),
        (93, 495), (109, 518), (124, 528), (142, 530),
        (162, 520), (184, 498), (204, 473), (230, 439),
    ]], sections)
    return build_membrane("Caudal_Fin", base, edge, material)


def build_pectoral_fin(name, side, material):
    base = []
    sections = 27
    # A short root directly behind the gill region opens into a broad fan.
    for index in range(sections):
        t = index / (sections - 1)
        root = photo_point(583 - 4 * t, 346 + 22 * t)
        root.y = side * flank_width(root.x, root.z) * 0.98
        base.append(root)
    edge = sample_curve([photo_point(u, v, side * 0.0038) for u, v in [
        (598, 365), (611, 389), (622, 412), (620, 434),
        (610, 446), (591, 455), (575, 454), (565, 441), (568, 421),
    ]], sections)
    return build_membrane(name, base, edge, material, width_steps=5, normal_side=side, camber=0.00008)


def build_pelvic_fin(name, side, material):
    sections = 35
    upper = sample_curve([photo_point(u, v, side * 0.0024) for u, v in [
        (563, 395), (542, 428), (508, 455), (471, 478), (437, 496), (405, 510),
    ]], sections)
    lower = sample_curve([photo_point(u, v, side * 0.0025) for u, v in [
        (559, 399), (546, 438), (517, 466), (482, 487), (447, 500), (405, 511),
    ]], sections)
    # Root lies inside the lower flank; the long pointed membranes remain
    # distinct left/right objects. Only the visible side is constrained by photo.
    for path in (upper, lower):
        path[0].y = side * flank_width(path[0].x, path[0].z) * 0.96
    return build_membrane(name, upper, lower, material, width_steps=4, normal_side=side, camber=0.00010)


def build_ellipsoid(name, location, scale, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, calc_uvs=False, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def build_eye(name, side, eye_material, body_material):
    """A shallow dark dome with a skin rim fitted to the actual cheek surface.

    The rim and dome share vertices; their outer margin enters the body very
    slightly. This avoids the irregular intersections of a buried sphere.
    """
    segments = 40
    rings = [(0.00045, 0.00052), (0.0008, 0.00047), (0.00115, 0.00036),
             (0.00143, 0.00022), (EYE_RADIUS, 0.00018),
             (0.00205, 0.00010), (0.00240, -0.00008)]
    center = Vector((EYE_X, side * flank_width(EYE_X, EYE_Z), EYE_Z))
    vertices = [tuple(center + Vector((0.0, side * 0.00054, 0.0)))]
    faces = []
    skin_faces = []
    for radius, lift in rings:
        for segment in range(segments):
            angle = 2 * math.pi * segment / segments
            x = EYE_X + radius * math.cos(angle)
            z = EYE_Z + radius * math.sin(angle)
            vertices.append((x, side * (flank_width(x, z) + lift), z))
    for j in range(segments):
        faces.append((0, 1 + j, 1 + (j + 1) % segments))
    for ring in range(len(rings) - 1):
        for j in range(segments):
            a = 1 + ring * segments + j
            b = 1 + ring * segments + (j + 1) % segments
            faces.append((a, a + segments, b + segments, b))
            if ring >= 3:
                skin_faces.append(len(faces) - 1)
    back = len(vertices)
    vertices.append(tuple(center - Vector((0.0, side * 0.0008, 0.0))))
    last = 1 + (len(rings) - 1) * segments
    for j in range(segments):
        faces.append((back, last + (j + 1) % segments, last + j))
        skin_faces.append(len(faces) - 1)
    if side > 0:
        faces = [tuple(reversed(face)) for face in faces]
    eye = make_mesh_object(name, vertices, faces, eye_material)
    eye.data.materials.append(body_material)
    for index in skin_faces:
        eye.data.polygons[index].material_index = 1
    for vertex in eye.data.vertices:
        vertex.co -= center
    eye.location = center
    eye.data.update()
    return eye


def frame_model_in_viewports():
    # Make the small real-world-scale model visible after running in the GUI.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                space = area.spaces.active
                space.clip_start = 0.0001
                space.region_3d.view_location = (0.0, 0.0, 0.0)
                space.region_3d.view_distance = 0.14
                space.region_3d.view_perspective = "ORTHO"
                space.region_3d.view_rotation = Euler((math.pi / 2, 0.0, 0.0)).to_quaternion()
                space.shading.color_type = 'MATERIAL'
                space.shading.show_xray = True
                space.shading.xray_alpha = 0.35


def add_reference_and_camera():
    """The sole photograph is packed and placed behind the fish, without UVs."""
    image = bpy.data.images.load(str(REFERENCE_PATH), check_existing=True)
    if tuple(image.size) != (800, 800):
        raise ValueError('Landmarks require the supplied 800 x 800 reference.')
    image.pack()
    image.filepath = '//../blender/reference/pelvicachromis_taeniatus_male.jpg'
    collection = bpy.data.collections.get('Reference_Comparison')
    if collection is None:
        collection = bpy.data.collections.new('Reference_Comparison')
        bpy.context.scene.collection.children.link(collection)
    reference = bpy.data.objects.new('Reference_Photo', None)
    collection.objects.link(reference)
    reference.empty_display_type = 'IMAGE'
    reference.data = image
    reference.empty_display_size = IMAGE_SIZE * PIXEL_SCALE
    reference.empty_image_offset = (-0.5, -0.5)
    reference.rotation_euler = (math.pi / 2, 0.0, 0.0)
    reference.location = (0.0, 0.012, 0.0)
    reference.empty_image_depth = 'BACK'
    reference.show_empty_image_orthographic = True
    reference.show_empty_image_perspective = False
    reference.hide_select = True
    reference['source'] = 'blender/reference/pelvicachromis_taeniatus_male.jpg'
    reference['registration'] = 'Pixel (400,400) = X/Z origin; no independent feature scaling'

    data = bpy.data.cameras.new('Side_Orthographic')
    camera = bpy.data.objects.new('Side_Orthographic', data)
    collection.objects.link(camera)
    camera.location = (0.0, -0.20, 0.0)
    camera.rotation_euler = (math.pi / 2, 0.0, 0.0)
    data.type = 'ORTHO'
    data.ortho_scale = IMAGE_SIZE * PIXEL_SCALE
    data.clip_start = 0.001
    data.clip_end = 2.0
    data.show_background_images = True
    background = data.background_images.new()
    background.image = image
    background.alpha = 1.0
    background.display_depth = 'BACK'
    background.frame_method = 'FIT'
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1600
    scene.render.resolution_percentage = 100
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.show_shadows = False
    scene.display.shading.background_type = 'WORLD'
    scene.world.color = (0.13, 0.15, 0.17)
    scene['reference_pixel_scale_m'] = PIXEL_SCALE


def main():
    if not REFERENCE_PATH.is_file():
        raise FileNotFoundError(f'Required sole reference missing: {REFERENCE_PATH}')
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    body_mat = make_material("Body_Mat", (0.54, 0.53, 0.24))
    fin_mat = make_material("Fin_Mat", (0.52, 0.49, 0.27), alpha=0.82)
    translucent_mat = make_material("Fin_Translucent_Mat", (0.68, 0.70, 0.53), alpha=0.42)
    eye_mat = make_material("Eye_Mat", (0.012, 0.018, 0.018), roughness=0.18)

    build_body(body_mat)
    build_dorsal_fin(fin_mat)
    build_caudal_fin(fin_mat)
    build_anal_fin(fin_mat)
    build_pectoral_fin("Pectoral_Fin_Left", +1, translucent_mat)
    build_pectoral_fin("Pectoral_Fin_Right", -1, translucent_mat)
    build_pelvic_fin("Pelvic_Fin_Left", +1, fin_mat)
    build_pelvic_fin("Pelvic_Fin_Right", -1, fin_mat)

    for name, side in (("Eye_Left", 1), ("Eye_Right", -1)):
        build_eye(name, side, eye_mat, body_mat)
    # A small olive lip overlaps the blunt muzzle. Only its narrow forward
    # opening is dark, so the mouth reads as a slight protrusion, not a spike.
    mouth = build_ellipsoid("Mouth", photo_point(731, 298), (0.00065, 0.00085, 0.00040), body_mat)
    mouth.data.materials.append(eye_mat)
    for polygon in mouth.data.polygons:
        if polygon.center.x > 0.00045 and abs(polygon.center.z) < 0.00012:
            polygon.material_index = 1

    # Later: add an armature for tail and fin motion, then skin the body mesh.
    # Later: unwrap body and fin meshes for UVs and project individual photo textures.
    add_reference_and_camera()
    frame_model_in_viewports()
    print("Created simplified male Pelvicachromis taeniatus (~8 cm, head toward +X).")


if __name__ == "__main__":
    main()
