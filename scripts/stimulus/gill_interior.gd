extends RefCounted
## Narrow skinned inner-rim strips. No imported mesh, material or UV is edited.
var nodes: Array[MeshInstance3D]=[]
var triangle_count:=0
func surface_point(arrays: Array,x: float,y: float,side: float) -> Dictionary:
	var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var best: Dictionary={}
	for i in range(0,indices.size(),3):
		var ids: Array=[indices[i],indices[i+1],indices[i+2]]
		var a:=Vector2(positions[ids[0]].x,positions[ids[0]].y);var b:=Vector2(positions[ids[1]].x,positions[ids[1]].y);var c:=Vector2(positions[ids[2]].x,positions[ids[2]].y)
		var denominator: float=(b-a).cross(c-a)
		if absf(denominator)<1e-14:continue
		var v: float=(Vector2(x,y)-a).cross(c-a)/denominator
		var w: float=(b-a).cross(Vector2(x,y)-a)/denominator;var u:=1-v-w
		if minf(u,minf(v,w))<-.00001:continue
		var z: float=positions[ids[0]].z*u+positions[ids[1]].z*v+positions[ids[2]].z*w
		if z*side<=0 or (not best.is_empty() and z*side<=best.position.z*side):continue
		var influence: Dictionary={};var bary: Array=[u,v,w]
		for corner in range(3):
			for slot in range(4):
				var bone: int=bones[ids[corner]*4+slot]
				influence[bone]=float(influence.get(bone,0))+weights[ids[corner]*4+slot]*bary[corner]
		var keys:=influence.keys();keys.sort_custom(func(a_id,b_id):return influence[a_id]>influence[b_id])
		var out_bones:=PackedInt32Array();var out_weights:=PackedFloat32Array();var total:=0.0
		for j in range(4):
			var weight: float=influence[keys[j]] if j<keys.size() else 0
			out_bones.append(keys[j] if j<keys.size() else 0);out_weights.append(weight);total+=weight
		for j in range(4):out_weights[j]/=total
		best={"position":Vector3(x,y,z),"bones":out_bones,"weights":out_weights}
	return best
func bind(body: MeshInstance3D,deformer: RefCounted) -> String:
	var source: Array=deformer.original.surface_get_arrays(0)
	if source[Mesh.ARRAY_BONES].size()!=source[Mesh.ARRAY_VERTEX].size()*4:return "Kiemeninnenfläche erwartet vier bestehende Skin-Gewichte pro Vertex."
	for side in [-1.0,1.0]:
		var vertices:=PackedVector3Array();var opened:=PackedVector3Array();var normals:=PackedVector3Array();var bones:=PackedInt32Array();var weights:=PackedFloat32Array();var indices:=PackedInt32Array()
		for row in range(33):
			var t:=float(row)/32;var y:=lerpf(.0028,.0141,t)
			var rim:=.022806+.0015*pow((y-.008478)/.007,2)
			var closed:=surface_point(source,rim-.00012,y,side)
			if closed.is_empty():detach();return "Kiemenrand liegt außerhalb der vorhandenen Körperfläche."
			for edge in range(2):
				var sample:=surface_point(source,rim-.00012+edge*.0007*sin(PI*t),y,side)
				if sample.is_empty():detach();return "Geöffneter Kiemenrand liegt außerhalb des Körpers."
				var p: Vector3=sample.position
				vertices.append(closed.position+Vector3(0,0,side*.000012))
				opened.append(p+Vector3(0,0,deformer.displacement(p,side)+side*.000012))
				normals.append(Vector3(0,0,side));bones.append_array(sample.bones);weights.append_array(sample.weights)
			if row>0:
				var j:=row*2;indices.append_array(PackedInt32Array([j-2,j,j-1,j-1,j,j+1]))
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices;arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights
		var shape: Array=[];shape.resize(Mesh.ARRAY_MAX);shape[Mesh.ARRAY_VERTEX]=opened;shape[Mesh.ARRAY_NORMAL]=normals
		var mesh:=ArrayMesh.new();mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED;mesh.add_blend_shape("Open");mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[shape])
		var material:=StandardMaterial3D.new();material.albedo_color=Color(.035,.013,.011);material.roughness=1;material.cull_mode=BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0,material)
		var node:=MeshInstance3D.new();node.name="Gill_Interior_Left" if side<0 else "Gill_Interior_Right";node.mesh=mesh;node.skin=body.skin;body.add_child(node);node.skeleton=node.get_path_to(body.get_node(body.skeleton));node.visible=false
		nodes.append(node);triangle_count+=indices.size()/3
	return ""
func update(amount: float) -> void:
	for node in nodes:
		node.visible=amount>.001;node.set_blend_shape_value(0,amount)
func detach() -> void:
	for node in nodes:
		if is_instance_valid(node):node.free()
	nodes.clear();triangle_count=0
