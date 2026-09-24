"""Build an editable 8 cm male Pelvicachromis taeniatus blockout.

Run in Blender's Text Editor or with:
    blender --background --python blender/create_pelvicachromis_male_from_reference.py

Reference: blender/reference/pelvicachromis_taeniatus_male.jpg.
The reference is a visual guide; it is not projected onto the mesh.
Here +X is forward, Y is body width, and Z is height. Dimensions are in
metres (overall length ~0.08 m). No rig, UV maps, or animation are generated.
"""

import math

import bpy
from mathutils import Euler, Vector


# (X, half-width, upper Z, lower Z), ordered from tail stalk to snout.
# The short tail stalk has nearly parallel edges. The dorsal apex is ahead
# of the belly's lowest point; the two contours are deliberately asymmetric.
# Closely spaced head stations describe a convex forehead and blunt muzzle.
BODY_PROFILE = [
    (-0.0275, 0.00165, 0.0030, -0.0032),
    (-0.0240, 0.00190, 0.0033, -0.0035),
    (-0.0205, 0.00270, 0.0049, -0.0046),
    (-0.0160, 0.00350, 0.0071, -0.0067),
    (-0.0100, 0.00450, 0.0102, -0.0100),
    (-0.0030, 0.00520, 0.0128, -0.0125),
    (0.0050, 0.00570, 0.0140, -0.0138),
    (0.0120, 0.00590, 0.0142, -0.0132),
    (0.0190, 0.00550, 0.0133, -0.0100),
    (0.0240, 0.00480, 0.0120, -0.0073),
    (0.0290, 0.00415, 0.0106, -0.0044),
    (0.0330, 0.00340, 0.0089, -0.0023),
    (0.0355, 0.00265, 0.0071, -0.0009),
    (0.0370, 0.00185, 0.0054, 0.0000),
    (0.0378, 0.00120, 0.0042, 0.0007),
    (0.0381, 0.00075, 0.0035, 0.0011),
]


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


def build_body(material):
    # Include every landmark, with denser rings on the rounded head. These
    # transverse quad loops can later carry spine and jaw deformation weights.
    stations = [BODY_PROFILE[0][0]]
    for left, right in zip(BODY_PROFILE, BODY_PROFILE[1:]):
        subdivisions = max(2, math.ceil((right[0] - left[0]) / 0.0018))
        stations.extend(
            left[0] + (right[0] - left[0]) * step / subdivisions
            for step in range(1, subdivisions + 1)
        )
    rings = len(stations)
    sides = 24
    vertices = []
    faces = []

    for x in stations:
        half_width, top, bottom = profile_at(x)
        center_z = (top + bottom) * 0.5
        for side in range(sides):
            angle = 2.0 * math.pi * side / sides
            height = top - center_z if math.sin(angle) >= 0.0 else center_z - bottom
            vertices.append((x, half_width * math.cos(angle), center_z + height * math.sin(angle)))

    for ring in range(rings - 1):
        for side in range(sides):
            next_side = (side + 1) % sides
            a = ring * sides + side
            b = ring * sides + next_side
            c = (ring + 1) * sides + next_side
            d = (ring + 1) * sides + side
            faces.append((a, b, c, d))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((rings - 1) * sides + side for side in range(sides)))
    return make_mesh_object("Fish_Body", vertices, faces, material)


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


def build_membrane(name, base_points, edge_points, material, width_steps=5, normal_side=-1):
    """Regular quad strips leave fins suitable for later bending and UV work."""
    vertices = []
    faces = []
    for base, edge in zip(base_points, edge_points):
        base = Vector(base)
        edge = Vector(edge)
        for step in range(width_steps + 1):
            t = step / width_steps
            point = base.lerp(edge, t)
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
    return make_mesh_object(name, vertices, faces, material)


def build_dorsal_fin(material):
    base = []
    sections = 31
    for index in range(sections):
        t = index / (sections - 1)
        x = 0.023 - 0.0445 * t
        top = profile_at(x)[1]
        base.append((x, 0.0, top - 0.0002))
    # Low anterior crest follows the back; only the posterior soft portion
    # extends beyond its attachment. No tall central sail.
    edge = sample_curve([
        (0.0228, 0.0, 0.0130),
        (0.0160, 0.0, 0.0160),
        (0.0060, 0.0, 0.0170),
        (-0.0040, 0.0, 0.0159),
        (-0.0150, 0.0, 0.0126),
        (-0.0230, 0.0, 0.0107),
        (-0.0305, 0.0, 0.0095),
    ], sections)
    return build_membrane("Dorsal_Fin", base, edge, material)


def build_anal_fin(material):
    base = []
    sections = 27
    for index in range(sections):
        t = index / (sections - 1)
        x = 0.001 - 0.0205 * t
        bottom = profile_at(x)[2]
        base.append((x, 0.0, bottom + 0.0002))
    # Broad attachment, rounded leading part, and a single posterior point
    # directed toward the lower part of the caudal fan.
    edge = sample_curve([
        (0.0004, 0.0, -0.0136),
        (-0.0040, 0.0, -0.0166),
        (-0.0130, 0.0, -0.0174),
        (-0.0230, 0.0, -0.0181),
        (-0.0320, 0.0, -0.0215),
    ], sections)
    return build_membrane("Anal_Fin", base, edge, material)


def build_caudal_fin(material):
    base = []
    edge = []
    # An arc greater than 180 degrees makes broad rounded shoulders as well
    # as a rounded trailing rim. It replaces the previous triangular wedge.
    for index in range(33):
        t = index / 32
        angle = math.radians(100.0 - 200.0 * t)
        radius_z = 0.0105 if angle >= 0.0 else 0.0120
        base.append((-0.0272, 0.0, 0.0028 - 0.0056 * t))
        edge.append((
            -0.0325 - 0.0085 * math.cos(angle),
            0.0,
            -0.0005 + radius_z * math.sin(angle),
        ))
    return build_membrane("Caudal_Fin", base, edge, material)


def build_pectoral_fin(name, side, material):
    base = []
    sections = 21
    # A short root directly behind the gill region opens into a broad fan.
    for index in range(sections):
        t = index / (sections - 1)
        base.append((0.021 - 0.002 * t, side * 0.0047, 0.0008 - 0.0038 * t))
    edge = sample_curve([
        (0.016, side * 0.0077, 0.0000),
        (0.010, side * 0.0090, -0.0030),
        (0.009, side * 0.0098, -0.0080),
        (0.013, side * 0.0086, -0.0120),
        (0.017, side * 0.0075, -0.0110),
    ], sections)
    return build_membrane(name, base, edge, material, width_steps=4, normal_side=side)


def build_pelvic_fin(name, side, material):
    upper = []
    lower = []
    for index in range(23):
        t = index / 22
        x = 0.014 - 0.030 * t
        y = side * (0.0026 + 0.0027 * t)
        z = -0.0113 - 0.010 * t + 0.001 * math.sin(math.pi * t)
        half_width = 0.000035 + 0.0009 * (1 - t)**0.75 + 0.0004 * math.sin(math.pi * t)
        upper.append((x, y, z + half_width))
        lower.append((x, y, z - half_width))
    return build_membrane(name, upper, lower, material, width_steps=3, normal_side=side)


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


def main():
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

    build_ellipsoid("Eye_Left", (0.0291, 0.0039, 0.0066), (0.0023, 0.00085, 0.0023), eye_mat)
    build_ellipsoid("Eye_Right", (0.0291, -0.0039, 0.0066), (0.0023, 0.00085, 0.0023), eye_mat)
    # A small olive lip overlaps the blunt muzzle. Only its narrow forward
    # opening is dark, so the mouth reads as a slight protrusion, not a spike.
    mouth = build_ellipsoid("Mouth", (0.0383, 0.0, 0.00235), (0.0007, 0.0012, 0.00045), body_mat)
    mouth.data.materials.append(eye_mat)
    for polygon in mouth.data.polygons:
        if polygon.center.x > 0.00045 and abs(polygon.center.z) < 0.00012:
            polygon.material_index = 1

    # Later: add an armature for tail and fin motion, then skin the body mesh.
    # Later: unwrap body and fin meshes for UVs and project individual photo textures.
    frame_model_in_viewports()
    print("Created simplified male Pelvicachromis taeniatus (~8 cm, head toward +X).")


if __name__ == "__main__":
    main()
