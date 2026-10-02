extends SkeletonModifier3D
## Godot restores the animation pose after modifier evaluation. Never accumulate offsets.
const CHAIN=["Body_01","Body_02","Body_03","Body_04","Tail_01","Tail_02","Tail_Fin"]
var motion: Node3D
var indices: Dictionary={}
var local_axes: Dictionary={}
var last_base: Dictionary={}
var last_final: Dictionary={}
func bind(body: Node3D,skeleton: Skeleton3D) -> String:
	motion=body
	if skeleton.get_bone_count()!=15:return "Kurvenpose erwartet das vorhandene Rig mit 15 Bones."
	var previous: int=-1
	for name in CHAIN:
		var index:=skeleton.find_bone(name)
		if index<0 or (previous>=0 and skeleton.get_bone_parent(index)!=previous):return "Körper-Bone oder Hierarchie fehlt: "+name
		indices[name]=index;local_axes[name]=(skeleton.get_bone_global_rest(index).basis.inverse()*Vector3.UP).normalized();previous=index
	for name in ["Pectoral_Fin_Left_2","Pectoral_Fin_Right_2"]:
		var index:=skeleton.find_bone(name)
		if index<0:return "Brustflossen-Bone fehlt: "+name
		indices[name]=index;local_axes[name]=Vector3.UP
	return ""
func _process_modification_with_delta(_delta: float) -> void:
	var skeleton:=get_skeleton()
	if skeleton==null or not is_instance_valid(motion):return
	var offsets: Dictionary=motion.bone_offsets()
	for name in indices:
		var index: int=indices[name];var base:=skeleton.get_bone_pose_rotation(index)
		var result: Quaternion=(base*Quaternion(local_axes[name],float(offsets.get(name,0.0)))).normalized()
		last_base[name]=base;last_final[name]=result;skeleton.set_bone_pose_rotation(index,result)
