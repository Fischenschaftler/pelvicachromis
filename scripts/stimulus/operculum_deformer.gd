extends RefCounted
## Two temporary blend shapes on a private mesh. Imported arrays/skin/UVs remain untouched.
const MAX_OPENING=0.0007
var body: MeshInstance3D
var original: Mesh
var affected_vertices:=0
func displacement(p: Vector3,side: float) -> float:
	if p.z*side<=0:return 0.0
	# Existing anatomical opercular rim: photo (591,329), 0.08m / 670px.
	var rim:=.022806+.0015*pow((p.y-.008478)/.007,2)
	var x: float=(p.x-rim)/.0055
	var y: float=(p.y-.008478)/.0065
	if absf(x)>=1 or absf(y)>=1:return 0.0
	var envelope: float=pow(1-x*x,3)*pow(1-y*y,3)*smoothstep(.001,.003,absf(p.z))
	return side*MAX_OPENING*envelope
func bind(model: Node3D) -> String:
	var bodies:=model.find_children("Fish_Body","MeshInstance3D",true,false)
	if bodies.size()!=1:return "Kiemenbewegung benötigt genau ein Fish_Body Mesh."
	body=bodies[0];original=body.mesh
	if original.get_blend_shape_count()!=0:return "Vorhandene Körper-Blendshapes dürfen nicht überschrieben werden."
	var mesh:=ArrayMesh.new();mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED
	mesh.add_blend_shape("Operculum_Left");mesh.add_blend_shape("Operculum_Right")
	for surface in range(original.get_surface_count()):
		var arrays:=original.surface_get_arrays(surface)
		var shapes: Array[Array]=[]
		for side in [-1.0,1.0]:
			var shape: Array=[];shape.resize(Mesh.ARRAY_MAX)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL].duplicate()
			for i in range(vertices.size()):
				var p:=vertices[i];var d:=displacement(p,side)
				if d==0:continue
				affected_vertices+=1;vertices[i].z+=d
				var e:=.000001
				var dx:=(displacement(p+Vector3(e,0,0),side)-displacement(p-Vector3(e,0,0),side))/(2*e)
				var dy:=(displacement(p+Vector3(0,e,0),side)-displacement(p-Vector3(0,e,0),side))/(2*e)
				var dz:=(displacement(p+Vector3(0,0,e),side)-displacement(p-Vector3(0,0,e),side))/(2*e)
				var n:=normals[i];normals[i]=Vector3(n.x-dx*n.z/(1+dz),n.y-dy*n.z/(1+dz),n.z/(1+dz)).normalized()
			shape[Mesh.ARRAY_VERTEX]=vertices;shape[Mesh.ARRAY_NORMAL]=normals
			if arrays[Mesh.ARRAY_TANGENT]!=null:shape[Mesh.ARRAY_TANGENT]=arrays[Mesh.ARRAY_TANGENT].duplicate()
			shapes.append(shape)
		mesh.add_surface_from_arrays(original.surface_get_primitive_type(surface),arrays,shapes)
		mesh.surface_set_material(surface,original.surface_get_material(surface))
	if affected_vertices==0:return "Kiemenregion enthält keine verformbaren Vertices."
	body.mesh=mesh;return ""
func update(opening: float,amplitude: float) -> void:
	if not is_instance_valid(body):return
	for i in range(2):body.set_blend_shape_value(i,clampf(opening*amplitude/MAX_OPENING,0,1))
func detach() -> void:
	if is_instance_valid(body) and original!=null:body.mesh=original
	body=null;original=null
