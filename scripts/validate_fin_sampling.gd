extends SceneTree
const Baker=preload("res://scripts/fin_texture_baker.gd")
func _initialize() -> void:
	var photo:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	photo.fill(Color(1,0,1,1))
	var mask:=Image.create(32,32,false,Image.FORMAT_L8)
	for y in range(8,24):
		for x in range(8,24):
			mask.set_pixel(x,y,Color.WHITE)
			photo.set_pixel(x,y,Color(.1,.4,.2,1) if x>9 else Color(1,1,1,.5))
	var polygon:=PackedVector2Array([Vector2(8,8),Vector2(24,8),Vector2(24,24),Vector2(8,24)])
	var clean:=Baker.edge_mask(photo,mask,polygon)
	assert(clean.rejected==0,"Real pale edge rejected despite exterior contrast")
	var contaminated: Image=photo.duplicate()
	for y in range(22,32):
		for x in range(32):contaminated.set_pixel(x,y,Color.WHITE)
	var corrected:=Baker.edge_mask(contaminated,mask,polygon)
	assert(corrected.rejected>0,"Background strip not detected")
	assert(corrected.mask.get_pixel(16,23).r<.5,"Contaminated edge retained")
	assert(corrected.mask.get_pixel(16,18).r>.5,"Fin interior removed")
	var lookup:=Baker.valid_lookup(photo,mask,polygon)
	var failures: Array=[]
	for y in range(0,32):
		for x in range(0,32):
			var c:=Baker.sample(photo,mask,Vector2(x+.25,y+.25),lookup)
			if c.g<.3 or c.a<.49:failures.append([x,y])
	var light:=Baker.sample(photo,mask,Vector2(8.5,12.5),lookup)
	assert(light.r>.99 and light.g>.99 and absf(light.a-.5)<.01,"Natural light/translucent edge was removed")
	assert(failures.is_empty(),"Outside-mask pixels sampled")
	FileAccess.open("res://godot/diagnostics/fin_sampling_validation.json",FileAccess.WRITE).store_string(JSON.stringify({"outside_mask_poison_samples":1024,"failures":failures,"natural_light_edge_preserved":true,"natural_alpha_preserved":true,"background_strip_rejected":corrected.rejected},"\t"))
	print("Mask sampling: 1024 adversarial samples passed; natural bright/transparent edge preserved")
	quit()
