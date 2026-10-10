# The village lawn: short grass blades that follow the camera (see
# shaders/grass_lawn.gdshader). Two MultiMeshes of single blades:
#   near: a 24 m wrap patch of 4-blade tufts 14 cm apart on High (~215
#         blades per m²), 3 segments, fading out at 8.5-11.5 m;
#   far:  a 48 m patch of wider 2-segment tufts that grows in where the
#         near patch fades and fades out by 23 m.
# The mask (density, dryness, tall grass, trodden path) and the height map
# are painted once from layout.gd: no grass in the paddy, courtyard, house,
# pens, canal, pond or nursery bed, and none on the bund steps, where
# world.gd's taller tufts grow instead. No shadows from grass.
extends Node3D

const L = preload("res://scripts/layout.gd")
const F = preload("res://scripts/flora.gd")
const SHADER = preload("res://shaders/grass_lawn.gdshader")
const MAP_RECT := Rect2(-40.0, -44.0, 80.0, 80.0)
const RES := 256
# [near grid, far grid] per quality level 0..2
const GRIDS := [[120, 72], [148, 88], [176, 104]]

var shade_spots: Array = [] # [Vector3(x, z, radius)] under groves: thinner, drier grass
var _near: MultiMeshInstance3D
var _far: MultiMeshInstance3D
var _level := -1


func _ready() -> void:
	add_to_group("quality")
	var maps := _paint()
	var nz := F.wind_noise()
	_near = _patch(24.0, 3, Vector2(8.5, 11.5), Vector2.ZERO, 0.0068, maps, nz)
	_far = _patch(48.0, 2, Vector2(18.0, 23.0), Vector2(8.0, 11.0), 0.011, maps, nz)
	set_quality(2)


func set_quality(level: int) -> void:
	level = clampi(level, 0, 2)
	if level == _level:
		return
	_level = level
	_set_grid(_near, GRIDS[level][0])
	_set_grid(_far, GRIDS[level][1])


func _set_grid(mmi: MultiMeshInstance3D, grid: int) -> void:
	var mm := mmi.multimesh
	var n := grid * grid
	# The shader ignores instance transforms; fill identities once so no pass
	# reads uninitialised data (doubling append: about 1 ms for 40k).
	var buf := PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0])
	while buf.size() < n * 12:
		buf.append_array(buf.slice(0, mini(buf.size(), n * 12 - buf.size())))
	mm.instance_count = n
	mm.buffer = buf
	(mmi.material_override as ShaderMaterial).set_shader_parameter("grid", grid)


# One tuft: `blades` blades of `segs` segments, all at the origin; the
# shader spreads and bends them. UV = (across, along), UV2.x = blade index.
static func blade_mesh(segs: int, blades := 4) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for bl in blades:
		var o := v.size()
		for s in segs:
			var t := float(s) / segs
			v.append(Vector3(-0.01, t * 0.3, 0.0))
			v.append(Vector3(0.01, t * 0.3, 0.0))
			uv.append(Vector2(0.0, t))
			uv.append(Vector2(1.0, t))
			uv2.append(Vector2(bl, 0.0))
			uv2.append(Vector2(bl, 0.0))
		v.append(Vector3(0.0, 0.3, 0.0)) # tip
		uv.append(Vector2(0.5, 1.0))
		uv2.append(Vector2(bl, 0.0))
		for s in segs - 1:
			var a := o + s * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
		var last := o + (segs - 1) * 2
		idx.append_array([last, o + segs * 2, last + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _patch(size: float, segs: int, fade: Vector2, fade_in: Vector2, width: float, maps: Array, nz: Texture2D) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade_mesh(segs)
	# Always around the camera: one big box instead of per-frame AABB updates.
	mm.custom_aabb = AABB(Vector3(MAP_RECT.position.x, -3.0, MAP_RECT.position.y), Vector3(MAP_RECT.size.x, 8.0, MAP_RECT.size.y))
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("patch_size", size)
	mat.set_shader_parameter("fade_start", fade.x)
	mat.set_shader_parameter("fade_end", fade.y)
	mat.set_shader_parameter("fade_in", fade_in)
	mat.set_shader_parameter("map_rect", Vector4(MAP_RECT.position.x, MAP_RECT.position.y, MAP_RECT.size.x, MAP_RECT.size.y))
	mat.set_shader_parameter("grass_mask", maps[0])
	mat.set_shader_parameter("height_map", maps[1])
	mat.set_shader_parameter("noise", nz)
	mat.set_shader_parameter("blade_width", width)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	return mmi


# [mask, height]: mask R density, G dryness, B tall grass, A trodden path.
func _paint() -> Array:
	var hs := PackedFloat32Array()
	hs.resize(RES * RES)
	var px_m := MAP_RECT.size.x / RES
	for py in RES:
		for px in RES:
			var x := MAP_RECT.position.x + (px + 0.5) * px_m
			var z := MAP_RECT.position.y + (py + 0.5) * px_m
			hs[py * RES + px] = L.ground_y(x, z)
	var hmap := Image.create_from_data(RES, RES, false, Image.FORMAT_RF, hs.to_byte_array())
	# shade under the bamboo and banana: thinner, yellowing grass and litter
	var shade := PackedFloat32Array()
	shade.resize(RES * RES)
	for s: Vector3 in shade_spots:
		var c := Vector2i(int((s.x - MAP_RECT.position.x) / px_m), int((s.y - MAP_RECT.position.y) / px_m))
		var r := int(ceil(s.z / px_m))
		for py in range(maxi(c.y - r, 0), mini(c.y + r + 1, RES)):
			for px in range(maxi(c.x - r, 0), mini(c.x + r + 1, RES)):
				var d := Vector2(px - c.x, py - c.y).length() * px_m
				shade[py * RES + px] = maxf(shade[py * RES + px], 1.0 - smoothstep(s.z * 0.4, s.z, d))
	var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	var nursery := Rect2(L.NURSERY.x - 2.3, L.NURSERY.y - 1.8, 4.6, 3.6)
	for py in RES:
		for px in RES:
			var x := MAP_RECT.position.x + (px + 0.5) * px_m
			var z := MAP_RECT.position.y + (py + 0.5) * px_m
			var n := fn.get_noise_2d(x, z) * 0.5 + 0.5
			var h := hs[py * RES + px]
			# no blades on steps (bund sides, canal banks): tufts grow there
			var step := 0.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var qx := clampi(px + d.x, 0, RES - 1)
				var qy := clampi(py + d.y, 0, RES - 1)
				step = maxf(step, absf(hs[qy * RES + qx] - h))
			var dens := 1.0 - smoothstep(0.03, 0.08, step)
			dens *= smoothstep(-0.3, -0.1, h) # sunken canal and paddy floor
			var tall := 0.0
			if L.in_field(x, z):
				dens = 0.0
			elif L.in_field(x, z, L.FIELD.bund):
				tall = 0.35 + 0.4 * n
			# courtyard, house, sheds, pens, nursery bed: none, with a soft rim
			dens *= smoothstep(0.0, 0.5, _rect_sd(x, z, L.COURT.x0, L.COURT.x1, L.COURT.z0, L.COURT.z1))
			dens *= smoothstep(0.0, 0.7, _rect_sd(x, z, -5.6, 5.6, -29.4, -21.6))
			for b in L.BLOCKERS:
				dens *= smoothstep(0.0, 0.4, _rect_sd(x, z, b[0], b[1], b[2], b[3]))
			dens *= smoothstep(0.0, 0.3, _rect_sd(x, z, L.DUCK_PEN.x0, L.DUCK_PEN.x1, L.DUCK_PEN.z0, L.DUCK_PEN.z1))
			dens *= smoothstep(0.0, 0.4, _rect_sd(x, z, nursery.position.x, nursery.end.x, nursery.position.y, nursery.end.y))
			# canal: none in the water, taller along the banks
			var cd := absf(x - (L.CANAL.x0 + L.CANAL.x1) * 0.5) - (L.CANAL.x1 - L.CANAL.x0) * 0.5
			dens *= smoothstep(0.15, 0.45, cd)
			tall = maxf(tall, (1.0 - smoothstep(0.3, 1.4, cd)) * 0.7)
			# pond: none inside the rim, reeds on it
			var pdist := Vector2(x - L.POND.x, z - L.POND.z).length() - L.POND.r
			dens *= smoothstep(0.45, 0.8, pdist)
			tall = maxf(tall, (1.0 - smoothstep(0.6, 1.8, pdist)) * 0.8)
			# trodden paths: yard to the field, yard to the pond and the nursery
			var path := (1.0 - smoothstep(0.3, 0.8, absf(x - 0.5 * sin(z * 0.3)))) * float(z > -14.3 and z < -8.7)
			path = maxf(path, _seg_path(x, z, Vector2(-6.0, -15.5), L.POND_EDGE, 0.6))
			path = maxf(path, _seg_path(x, z, Vector2(6.0, -16.0), L.NURSERY + Vector2(-2.3, 0.0), 0.6))
			dens *= 1.0 - 0.75 * path
			var sh := shade[py * RES + px]
			dens *= 1.0 - 0.6 * sh
			var dryness := clampf(0.05 + 0.32 * (1.0 - n) * (1.0 - tall) + 0.35 * sh, 0.0, 1.0)
			img.set_pixel(px, py, Color(clampf(dens, 0.0, 1.0), dryness, tall, path))
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(hmap)]


static func _seg_path(x: float, z: float, a: Vector2, b: Vector2, w: float) -> float:
	var p := Vector2(x, z)
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var d := p.distance_to(a + ab * t) + 0.25 * sin(t * 9.0)
	return 1.0 - smoothstep(w * 0.5, w, d)


static func _rect_sd(x: float, z: float, x0: float, x1: float, z0: float, z1: float) -> float:
	var dx := maxf(x0 - x, x - x1)
	var dz := maxf(z0 - z, z - z1)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length() + minf(maxf(dx, dz), 0.0)
