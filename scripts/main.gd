# Ruộng Lúa Nước — first-person wet-rice farming prototype.
# Game loop, time & weather, interactions and the four-stage rice cycle.
extends Node3D

const L = preload("res://scripts/layout.gd")
const World = preload("res://scripts/world.gd")
const FieldScript = preload("res://scripts/field.gd")
const CourtScript = preload("res://scripts/courtyard.gd")
const DucksScript = preload("res://scripts/ducks.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ToolsScript = preload("res://scripts/tools.gd")
const HudScript = preload("res://scripts/hud.gd")
const TransplantScript = preload("res://scripts/transplant.gd")
const AudioScript = preload("res://scripts/audio.gd")

const MIN_PER_SEC := 4.0 # game minutes per real second
const CARRY := 48 # clumps per đòn gánh load (8 lượm × 6 khóm)
const LUOM := 6
const BUNDLES := 8

var audio
var world: Dictionary
var field
var court
var ducks
var player
var tools
var hud
var transplant
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var moon: DirectionalLight3D
var rain: CPUParticles3D
var smoke: CPUParticles3D
var hoe_mark: MeshInstance3D

# ---------------------------------------------------------------- state
var minutes := 6.0 * 60.0
var stage := "prep" # prep -> care -> harvest -> drying -> done
var mode := "walk" # walk | transplant | summary
var playing := false
var paused := false
var real_t := 0.0
var inv := {"ash": 3, "cam": 4, "beo": 0, "beo_bam": 0, "chao": 0, "fert": 0, "eggs": 0, "bricks": 0, "sheaves": 0}
var nursery := {"state": "none", "water_days": 0, "last_water": -1, "bundles": 0}
var canal_full := true
var pig_fed := false
var slurry := 0
var smoke_t := 0.0
var duck_pen_open := false
var duck_eggs := 2
var duck_field_min := 0.0
var duck_forage_min := 0.0
var eggs_collected := 0
var barrel_sheaves := 0
var barrel_paddy := 0.0
var tarp_on := false
var tarp_placed := [false, false, false, false]
var tarp_blow_t := 0.0
var tarp_fly_t := 0.0
var storm := {"phase": "none", "t": 0.0, "level": 0.0, "lightning": 0.0, "next_bolt": 3.0}
var rain_at := INF
var raining := false
var e_held := false
var e_timer := 0.0
var mouse_left := false
var mouse_right := false
var target = null # {label, act, repeat}
var interactables: Array = []
var amb_t := 0.0
var autotest := false
var touring := false
var mouse_sens := 1.0 # multiplier on the base look speed
var invert_y := false
var _skip_motion := 0
const SETTINGS_PATH := "user://settings.cfg"
const KEY_LOOK_YAW := 1.8 # rad/s with the arrow keys (touchpad / accessibility fallback)
const KEY_LOOK_PITCH := 1.2
const TRANSPLANT_LOOK := 0.9 # rad either side of the row while transplanting


func day() -> int:
	return int(minutes / 1440.0) + 1


func hour() -> float:
	return fmod(minutes, 1440.0) / 60.0


func _ready() -> void:
	randomize()
	autotest = "--autotest" in OS.get_cmdline_user_args()
	touring = "--tour" in OS.get_cmdline_user_args()
	audio = AudioScript.new()
	add_child(audio)
	_setup_environment()
	world = World.build(self)

	field = FieldScript.new()
	add_child(field)
	court = CourtScript.new()
	add_child(court)
	ducks = DucksScript.new()
	add_child(ducks)
	ducks.setup(audio, 10)

	camera = Camera3D.new()
	camera.fov = 72
	camera.near = 0.05
	camera.far = 400
	add_child(camera)
	camera.make_current()
	player = PlayerScript.new(camera, audio)
	player.pos = Vector3(L.START.x, 0, L.START.y)
	tools = ToolsScript.new()
	camera.add_child(tools)

	hud = HudScript.new()
	add_child(hud)
	hud.play_pressed.connect(_on_play)
	hud.new_season_pressed.connect(func(): get_tree().reload_current_scene())
	hud.resume_pressed.connect(_set_paused.bind(false))
	hud.sens_changed.connect(_on_sens_changed)
	hud.invert_changed.connect(_on_invert_changed)
	_load_settings()
	transplant = TransplantScript.new()
	add_child(transplant)
	transplant.setup(field, player, tools, hud, audio)
	transplant.finished.connect(_on_transplant_finished)

	var hm := PlaneMesh.new()
	hm.size = Vector2(1.96, 1.96)
	hoe_mark = MeshInstance3D.new()
	hoe_mark.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1, 1, 0.85, 0.1)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hoe_mark.material_override = hmat
	hoe_mark.visible = false
	add_child(hoe_mark)

	_setup_particles()
	_setup_interactables()
	_refresh_nursery()
	hud.tool("tay")
	player.update(0.0, Vector2.ZERO, false, field, 0.0)
	_update_sky()
	if autotest:
		_run_autotest()
	elif "--tour" in OS.get_cmdline_user_args():
		_run_tour()


func _setup_environment() -> void:
	# Sky: four CC0 HDRI panoramas blended by time of day and storm.
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("day_tex", load("res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_2k.hdr"))
	sky_mat.set_shader_parameter("dusk_tex", load("res://assets/hdri/qwantani_sunset_puresky_1k.hdr"))
	sky_mat.set_shader_parameter("night_tex", load("res://assets/hdri/qwantani_night_puresky_1k.hdr"))
	sky_mat.set_shader_parameter("storm_tex", load("res://assets/hdri/kloofendal_overcast_puresky_1k.hdr"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.3
	env.fog_enabled = true
	env.fog_density = 0.0018
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.light_angular_distance = 0.6
	sun.shadow_blur = 1.2
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.rotation = Vector3(-1.0, 0.8, 0)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


func _setup_particles() -> void:
	rain = CPUParticles3D.new()
	var drop := BoxMesh.new()
	drop.size = Vector3(0.015, 0.45, 0.015)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.78, 0.83, 0.88, 0.55)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = dm
	rain.mesh = drop
	rain.amount = 2500
	rain.lifetime = 1.2
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(25, 0.5, 25)
	rain.direction = Vector3(0.15, -1, 0)
	rain.spread = 2.0
	rain.gravity = Vector3.ZERO
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 20.0
	rain.local_coords = false
	rain.emitting = false
	add_child(rain)

	smoke = CPUParticles3D.new()
	var puff := SphereMesh.new()
	puff.radius = 0.25
	puff.height = 0.5
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.85, 0.85, 0.85, 0.35)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = pm
	smoke.mesh = puff
	smoke.amount = 18
	smoke.lifetime = 4.0
	smoke.direction = Vector3(0.1, 1, 0.1)
	smoke.spread = 15.0
	smoke.gravity = Vector3(0.2, 0.3, 0.1)
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.0
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 2.0
	smoke.position = Vector3(L.STOVE.x, 0.9, L.STOVE.y)
	smoke.emitting = false
	add_child(smoke)


# ---------------------------------------------------------------- interactions
func _it(p: Vector2, r: float, label: Callable, act: Callable, repeat := false) -> Dictionary:
	return {"pos": p, "r": r, "label": label, "act": act, "repeat": repeat}


func _setup_interactables() -> void:
	interactables = [
		_it(L.GATE, 2.2, func(): return "Đóng cửa cống (xẻng)" if field.gate_open else "Mở cửa cống dẫn nước từ mương (xẻng)", _toggle_gate),
		_it(L.DRAIN, 2.2, func(): return "Đắp lại rãnh xả (xẻng)" if field.drain_open else "Khoét rãnh bờ để xả bớt nước (xẻng)", _toggle_drain),
		_it(L.HAMMOCK, 2.4, func(): return "" if storm.phase in ["warning", "rain"] else "Nằm võng nghỉ đến sáng mai", sleep),
		_it(L.BASKET, 2.0, _basket_label, _basket_act),
		_it(L.NURSERY, 2.8, _nursery_label, _nursery_act, true),
		_it(L.BARREL, 2.4, _barrel_label, _barrel_act, true),
		_it(L.TARP_ROLL, 2.2, func(): return "" if stage != "drying" else ("Gỡ bạt, cuộn lại" if tarp_on else "Kéo bạt ni-lông phủ khung giữa sân"), _tarp_act),
		_it(L.BRICK_PILE, 2.2, _bricks_label, _take_bricks),
		_it(L.DUCK_GATE, 2.2, func(): return "Đóng cổng chuồng vịt" if duck_pen_open else "Mở cổng chuồng vịt", _toggle_duck_gate),
		_it(Vector2(L.DUCK_PEN.x1 - 1.1, L.DUCK_PEN.z0 + 0.7), 2.6, func(): return ("Nhặt %d quả trứng vịt vào rổ" % duck_eggs) if duck_eggs > 0 else "", _collect_eggs),
		_it(L.POND_EDGE, 2.6, func(): return ("Vớt bèo tây (%d/5)" % inv.beo) if inv.beo < 5 else "", _scoop_hyacinth, true),
		_it(L.BOARD, 2.0, func(): return "Băm nhỏ bèo tây bằng dao chuối" if inv.beo > 0 else "", _chop, true),
		_it(L.STOVE, 2.2, _stove_label, _cook),
		_it(L.TROUGH, 2.2, func(): return "Đổ cháo vào máng cho lợn ăn" if inv.chao > 0 and not pig_fed else "", _feed_pig),
		_it(L.BIOGAS, 3.6, func(): return ("Múc %d gánh bùn vi sinh từ hầm biogas" % slurry) if slurry > 0 else "", _take_slurry),
		_it(L.BUFFALO, 3.0, func(): return "Trâu cày (bản sau: dắt trâu bừa nhanh gấp 4)", _buffalo),
	]
	for i in 4:
		interactables.append(_it(L.CORNERS[i], 1.6, _corner_label.bind(i), _place_brick.bind(i)))
	for i in L.STAKES.size():
		interactables.append(_it(L.STAKES[i], 1.6, _stake_label.bind(i), _remove_eggs.bind(i)))


func _take_bricks() -> void:
	inv.bricks = 4 - tarp_placed.count(true)
	audio.play("pickup")


func _collect_eggs() -> void:
	inv.eggs += duck_eggs
	eggs_collected += duck_eggs
	duck_eggs = 0
	audio.play("pickup")


func _scoop_hyacinth() -> void:
	if _spend(3):
		inv.beo += 1
		audio.play("splash")


func _feed_pig() -> void:
	inv.chao -= 1
	pig_fed = true
	audio.play("oink")
	hud.log_msg("Lợn ăn no. Phân lợn sẽ xuống hầm biogas qua đêm.")


func _take_slurry() -> void:
	inv.fert += slurry
	slurry = 0
	audio.play("splash")
	hud.log_msg("Có bùn vi sinh! Mang ra ruộng bấm E để bón.", "good")


func _buffalo() -> void:
	audio.play("oink", 0.0, 0.6)
	hud.log_msg("\"Tắc! Rì! Họ!\" — điều khiển trâu bằng khẩu lệnh sẽ có ở bản sau.")


func _corner_label(i: int) -> String:
	return "Đặt gạch chặn góc bạt" if tarp_on and not tarp_placed[i] and inv.bricks > 0 else ""


func _place_brick(i: int) -> void:
	tarp_placed[i] = true
	inv.bricks -= 1
	audio.play("thud_hard")


func _stake_label(i: int) -> String:
	return "Bóc ổ trứng ốc bươu vàng" if field.eggs[i] else ""


func _remove_eggs(i: int) -> void:
	field.eggs[i] = false
	audio.play("pickup")


func _toggle_gate() -> void:
	field.gate_open = not field.gate_open
	audio.play("thud_soft")
	if field.gate_open:
		audio.play("splash")
		if not canal_full:
			hud.log_msg("Mương đang cạn, nước không chảy vào. Đứng ở bờ tây, cầm gàu sòng (phím 4) để tát.", "warn")


func _toggle_drain() -> void:
	field.drain_open = not field.drain_open
	audio.play("thud_soft")
	if field.drain_open:
		audio.play("splash")


func _toggle_duck_gate() -> void:
	duck_pen_open = not duck_pen_open
	audio.play("pickup")
	if duck_pen_open:
		hud.log_msg("Cầm sào vịt (phím 7) giữ chuột trái để lùa, Q để huýt sáo gọi đàn.")


func _basket_label() -> String:
	match nursery.state:
		"none":
			return "Ngâm thóc giống vào thúng nước ấm, ủ rơm"
		"soaked":
			return "Thóc đang ủ — chờ qua đêm cho nứt nanh"
	return ""


func _basket_act() -> void:
	if nursery.state != "none":
		return
	nursery.state = "soaked"
	audio.play("splash")
	hud.log_msg("Đã ngâm thóc giống. Ủ qua đêm (nằm võng) để thóc nứt nanh.", "good")
	_refresh_nursery()


func _nursery_label() -> String:
	match nursery.state:
		"sprouted":
			return "Gieo đều tay thóc nứt nanh lên vạt mạ"
		"sown":
			if nursery.last_water == day():
				return "Mạ đã tưới hôm nay (%d/3 ngày)" % nursery.water_days
			return "Tưới nước xăm xắp cho mạ (%d/3 ngày)" % nursery.water_days
		"ready":
			return "Nhổ mạ, gõ rễ vào mu bàn chân, buộc lạt (%d/%d bó)" % [nursery.bundles, BUNDLES]
	return ""


func _nursery_act() -> void:
	match nursery.state:
		"sprouted":
			nursery.state = "sown"
			audio.play("pickup")
			hud.log_msg("Đã gieo mạ. Tưới mỗi ngày, 3 ngày là mạ lên xanh.", "good")
		"sown":
			if nursery.last_water != day():
				nursery.last_water = day()
				nursery.water_days += 1
				audio.play("splash")
		"ready":
			if nursery.bundles < BUNDLES and _spend(4):
				nursery.bundles += 1
				tools.swing(0.35, 0.5, "beat", func(): audio.play("thud_soft"))
				if nursery.bundles >= BUNDLES:
					nursery.state = "pulled"
					hud.log_msg("Đủ 8 bó mạ! Gánh ra ruộng, đứng trong ruộng bấm E để cấy.", "good")
	_refresh_nursery()


func _barrel_label() -> String:
	if inv.sheaves > 0:
		return "Đặt %.1f lượm lúa xuống cạnh thùng" % (inv.sheaves / float(LUOM))
	if barrel_sheaves > 0:
		return "Đập lúa vào thùng (còn %d lượm)" % ceili(barrel_sheaves / float(LUOM))
	if barrel_paddy > 0.0 and stage == "harvest":
		if field.cut_count() < field.planted_count():
			return "Thùng có %d kg thóc — gặt hết lúa ngoài đồng rồi đổ ra sân" % int(barrel_paddy)
		return "Đổ %d kg thóc ra sân gạch phơi" % int(barrel_paddy)
	return ""


func _barrel_act() -> void:
	if inv.sheaves > 0:
		barrel_sheaves += inv.sheaves
		inv.sheaves = 0
		audio.play("pickup")
		return
	if barrel_sheaves > 0:
		if tools.busy() or not _spend(3):
			return
		tools.swing(0.4, 0.45, "beat", func():
			var n := mini(barrel_sheaves, LUOM * 2)
			barrel_sheaves -= n
			barrel_paddy += n * field.kg_per_clump()
			audio.play("thresh")
			player.shake = 0.05)
		return
	if barrel_paddy > 0.0 and stage == "harvest" and field.cut_count() >= field.planted_count():
		court.pour(barrel_paddy)
		barrel_paddy = 0.0
		stage = "drying"
		rain_at = real_t + 35.0
		_select_tool("cao")
		hud.log_msg("Đã đổ thóc ra sân. Cầm cào (phím 6), chuột trái để rải mỏng thóc đón nắng.", "good")


func _tarp_act() -> void:
	audio.play("tarp")
	if tarp_on:
		tarp_on = false
		tarp_placed = [false, false, false, false]
	else:
		tarp_on = true
		tarp_blow_t = 0.0
		hud.log_msg("Đã kéo bạt! Lấy gạch chặn đủ 4 góc kẻo gió lật bạt.")


func _bricks_label() -> String:
	if stage != "drying":
		return ""
	var need: int = 4 - tarp_placed.count(true) - inv.bricks
	return "Ôm %d viên gạch" % need if need > 0 else ""


func _chop() -> void:
	if tools.busy() or not _spend(2):
		return
	tools.swing(0.3, 0.5, "chop", func():
		inv.beo -= 1
		inv.beo_bam += 1
		audio.play("chop"))


func _stove_label() -> String:
	if inv.beo_bam > 0 and inv.cam > 0:
		return "Trộn bèo + cám, nấu cháo heo trên bếp củi"
	if inv.beo_bam > 0:
		return "Hết cám gạo để nấu cháo heo"
	return ""


func _cook() -> void:
	if not (inv.beo_bam > 0 and inv.cam > 0):
		return
	inv.beo_bam -= 1
	inv.cam -= 1
	inv.chao += 1
	inv.ash += 1
	smoke_t = 25.0
	audio.play("splash")
	hud.log_msg("Nồi cháo heo thơm nức khói lam chiều. Bếp củi còn cho thêm tro bếp.", "good")


func _field_interaction():
	if not L.in_field(player.pos.x, player.pos.z, 0.9):
		return null
	if stage == "prep" and nursery.state == "pulled":
		if not field.prep_done():
			return {"label": "Mạ đã sẵn, nhưng ruộng chưa bừa xong", "act": _noop, "repeat": false}
		if field.water < 1.0 or field.water > 6.0:
			return {"label": "Cần nước xăm xắp 1–6 cm để cấy (đang %.1f cm)" % field.water, "act": _noop, "repeat": false}
		return {"label": "Bắt đầu cấy lúa (mini-game nhịp điệu)", "act": _start_transplant, "repeat": false}
	if stage == "care":
		if inv.fert > 0:
			return {"label": "Bón bùn vi sinh cho ruộng (%d)" % inv.fert, "act": _fertilize, "repeat": false}
		if inv.ash > 0:
			var dew := hour() >= 5.0 and hour() < 8.0
			return {"label": "Rắc tro bếp lên lá lúa (%d)%s" % [inv.ash, " — sương còn đọng" if dew else ""], "act": _spread_ash.bind(dew), "repeat": false}
	return null


func _fertilize() -> void:
	inv.fert -= 1
	field.fertilize()
	audio.play("splash")
	hud.log_msg("Ruộng thêm dinh dưỡng.", "good")


func _spread_ash(dew: bool) -> void:
	inv.ash -= 1
	field.apply_ash(dew)
	audio.play("rake")
	if dew:
		hud.log_msg("Tro bám sương trên lá, sâu cuốn lá giảm hẳn.", "good")
	else:
		hud.log_msg("Nắng đã lên, sương tan — tro không bám lá, hiệu quả thấp.", "warn")


func _noop() -> void:
	pass


# What the crosshair points at: the thing whose middle is closest to the
# view ray, within about half a metre of it (more forgiving up close).
func _find_interaction():
	var eye: Vector3 = camera.global_position
	var look: Vector3 = -camera.global_transform.basis.z
	var best = null
	var best_score := INF
	for it in interactables:
		var dist := Vector2(it.pos.x - player.pos.x, it.pos.y - player.pos.z).length()
		if dist > it.r:
			continue
		var aim_at := Vector3(it.pos.x, L.ground_y(it.pos.x, it.pos.y) + 0.6, it.pos.y)
		var ang := look.angle_to(aim_at - eye)
		if dist > 0.9 and ang > atan2(0.5, dist) + 0.08:
			continue
		var label: String = it.label.call()
		if label == "":
			continue
		var score := ang + dist * 0.05
		if score < best_score:
			best_score = score
			best = {"label": label, "act": it.act, "repeat": it.repeat}
	if best == null:
		best = _field_interaction()
	return best


func _spend(cost: float) -> bool:
	if player.stamina < cost:
		hud.set_hint("Mệt quá! Đứng nghỉ một chút cho lại sức…")
		audio.play("miss")
		return false
	player.stamina -= cost
	return true


func _select_tool(id: String) -> void:
	tools.select(id)
	hud.tool(tools.current)


func _start_transplant() -> void:
	mode = "transplant"
	mouse_left = false
	mouse_right = false
	e_held = false
	_select_tool("tay")
	hud.set_prompt("")
	transplant.start()


func _on_transplant_finished(aesthetic: float, planted: int, neighbours: bool) -> void:
	mode = "walk"
	stage = "care"
	nursery.state = "done"
	field.growth_day = 0
	field.rice_dirty = true
	_refresh_nursery()
	hud.log_msg("Cấy xong %d khóm lúa%s. Thẩm mỹ đồng ruộng: %d%% → +%d%% sản lượng." % [planted, " (có hàng xóm đổi công)" if neighbours else "", int(aesthetic * 100), int(aesthetic * 15)], "good")
	hud.log_msg("Giai đoạn 3: giữ nước 3–5 cm, trị sâu, bóc trứng ốc. Nằm võng để qua ngày.")


func sleep() -> void:
	hud.flash.color.a = 1.0
	var target_min := float(day()) * 1440.0 + 6.0 * 60.0
	var hours := (target_min - minutes) / 60.0
	field.water = maxf(0.0, field.water - hours * 0.08)
	if field.gate_open and canal_full:
		field.water = maxf(field.water, minf(6.0, field.water + hours * 2.0))
	if field.drain_open:
		field.water = maxf(0.0, field.water - hours * 2.0)
	_advance(target_min - minutes)
	player.stamina = 100.0
	hud.log_msg("Một đêm yên giấc. Ngày %d bắt đầu, gà gáy, sương còn đọng trên lá." % day())


func _advance(mins: float) -> void:
	var d0 := int(minutes / 1440.0)
	minutes += mins
	var d1 := int(minutes / 1440.0)
	for d in range(d0 + 1, d1 + 1):
		_daily_tick()


func _daily_tick() -> void:
	canal_full = randf() > 0.3
	if not canal_full:
		hud.log_msg("Hôm nay nắng gắt, mương cạn — muốn có nước phải tát bằng gàu sòng.", "warn")
	if stage != "drying" and randf() < 0.22:
		field.water += 2.5
		hud.log_msg("Đêm qua có mưa rào, ruộng thêm ~2.5 cm nước.")
	if nursery.state == "soaked":
		nursery.state = "sprouted"
		hud.log_msg("Thóc giống đã nứt nanh! Ra vạt mạ cạnh nhà để gieo.", "good")
	if nursery.state == "sown" and nursery.water_days >= 3:
		nursery.state = "ready"
		hud.log_msg("Mạ đã lên xanh non, nhổ được rồi!", "good")
	_refresh_nursery()
	if stage == "care":
		for m in field.daily_care(duck_field_min > 90.0):
			hud.log_msg(m[1], m[0])
		if field.is_ripe():
			stage = "harvest"
			_select_tool("liem")
	duck_eggs = mini(8, duck_eggs + (5 if duck_forage_min > 90.0 else 2))
	duck_field_min = 0.0
	duck_forage_min = 0.0
	if pig_fed:
		slurry += 1
		pig_fed = false


func _refresh_nursery() -> void:
	world.basket_water.visible = nursery.state == "soaked"
	var h := 0.01
	if nursery.state == "sown":
		h = 0.15 + nursery.water_days * 0.25
	elif nursery.state == "ready":
		h = 1.0
	world.seedlings.scale = Vector3(1, h, 1)
	var mm: MultiMesh = world.seedlings.multimesh
	match nursery.state:
		"ready":
			mm.visible_instance_count = int(300 * (1.0 - float(nursery.bundles) / BUNDLES))
		"pulled", "done":
			mm.visible_instance_count = 0
		_:
			mm.visible_instance_count = -1


# ---------------------------------------------------------------- tools
# Where the crosshair meets the ground, kept within arm's reach `dist`
# (plus a little slack), so tools hit what the player is looking at.
func _aim(dist: float) -> Vector2:
	var fw: Vector3 = player.forward()
	var fallback := Vector2(player.pos.x + fw.x * dist, player.pos.z + fw.z * dist)
	var o: Vector3 = camera.global_position
	var d: Vector3 = -camera.global_transform.basis.z
	if d.y > -0.05:
		return fallback
	var gy: float = L.ground_y(fallback.x, fallback.y)
	var p := o + d * ((gy - o.y) / d.y)
	var off := Vector2(p.x - player.pos.x, p.z - player.pos.z)
	var reach := dist + 0.6
	if off.length() > reach:
		off = off.normalized() * reach
	elif off.length() < 0.4:
		return fallback
	return Vector2(player.pos.x, player.pos.z) + off


func _use_tool(button: int) -> void:
	if tools.busy():
		return
	match tools.current:
		"cuoc":
			if stage != "prep":
				hud.set_hint("Ruộng đã cấy, không cần cuốc nữa.")
				return
			var a := _aim(1.3)
			if field.cell_at(a.x, a.y) < 0:
				hud.set_hint("Hướng cuốc vào ruộng.")
				return
			var hard := 0.25 if field.is_wet() else 1.0
			if not _spend(5.0 + 9.0 * hard):
				return
			tools.swing(0.6, 0.4, "chop", func():
				field.hoe(a.x, a.y)
				audio.play("thud_hard" if hard > 0.5 else "thud_soft")
				player.shake = 0.12 if hard > 0.5 else 0.05)
		"gau":
			var p: Vector3 = player.pos
			if not (p.x < -8.1 and p.x > -12.5 and absf(p.z) < 9.0):
				hud.set_hint("Đứng ở bờ tây giáp mương để tát nước vào ruộng.")
				return
			if not _spend(7):
				return
			tools.swing(0.8, 0.45, "scoop", func():
				field.water = minf(12.0, field.water + 0.35)
				audio.play("splash"))
		"liem":
			if stage != "harvest":
				hud.set_hint("Lúa chưa chín." if stage == "care" else "Chưa có lúa để gặt.")
				return
			var room: int = CARRY - inv.sheaves
			if room <= 0:
				hud.set_hint("Đòn gánh đã đầy — gánh về thùng đập lúa ở sân.")
				return
			var a := _aim(0.9)
			if not _spend(3):
				return
			tools.swing(0.42, 0.5, "slash", func():
				var n: int = field.cut_near(a.x, a.y, 0.95, mini(6, room))
				if n > 0:
					audio.play("swish")
					inv.sheaves += n
				else:
					audio.play("step"))
		"cao":
			var a := _aim(1.5)
			var idx: int = court.cell_at(a.x, a.y)
			if idx < 0:
				hud.set_hint("Cào dùng để rải/vun thóc trên sân gạch.")
				return
			if not _spend(2):
				return
			tools.swing(0.32, 0.5, "pull", func():
				var ok: bool = court.gather(idx) if button == MOUSE_BUTTON_RIGHT else court.spread(idx)
				if ok:
					audio.play("rake"))


# ---------------------------------------------------------------- input
func _on_play() -> void:
	hud.start_screen.visible = false
	playing = true
	_capture_mouse()
	hud.log_msg("Sáng sớm ngày đầu vụ. Ruộng khô nứt nẻ đang chờ bạn.")
	hud.log_msg("Cầm cuốc (phím 2), xuống ruộng, chuột trái để cuốc. Mẹo: dẫn nước vào trước thì đất mềm hơn.")


func _capture_mouse() -> void:
	if autotest or touring:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The first motion event after capturing can carry the jump from where
	# the cursor was to the window centre.
	_skip_motion = 1


func _set_paused(p: bool) -> void:
	paused = p
	hud.pause_screen.visible = p
	mouse_left = false
	mouse_right = false
	e_held = false
	if p:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_save_settings()
		_capture_mouse()


func _notification(what: int) -> void:
	# Alt-Tab or clicking another window: pause and give the cursor back.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and playing and not paused and mode != "summary" and not autotest and not touring:
		_set_paused(true)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		mouse_sens = clampf(float(cfg.get_value("mouse", "sensitivity", mouse_sens)), 0.2, 3.0)
		invert_y = bool(cfg.get_value("mouse", "invert_y", invert_y))
	hud.set_mouse_settings(mouse_sens, invert_y)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("mouse", "sensitivity", mouse_sens)
	cfg.set_value("mouse", "invert_y", invert_y)
	cfg.save(SETTINGS_PATH)


func _on_sens_changed(v: float) -> void:
	mouse_sens = v # saved when the pause menu closes


func _on_invert_changed(v: bool) -> void:
	invert_y = v
	_save_settings()


# Mouse look and mouse buttons are read in _input, before the GUI, so no
# HUD control can swallow them while the cursor is captured.
func _input(event: InputEvent) -> void:
	if not playing or paused or mode == "summary":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# Lost capture (e.g. after Alt-Tab): the click only takes it back.
			if mb.pressed and not autotest and not touring:
				_capture_mouse()
				get_viewport().set_input_as_handled()
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				mouse_left = mb.pressed
				# Bare hands: the left button uses whatever is in the crosshair.
				if mode == "walk" and tools.current == "tay":
					if mb.pressed:
						_interact_pressed()
					else:
						e_held = false
			MOUSE_BUTTON_RIGHT:
				mouse_right = mb.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and mode == "walk":
					_cycle_tool(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		if _skip_motion > 0:
			_skip_motion -= 1
			return
		# screen_relative is in screen pixels, unaffected by the canvas
		# stretch, so the feel does not change with window size.
		var rel: Vector2 = (event as InputEventMouseMotion).screen_relative
		player.look(rel * mouse_sens, invert_y)
		if mode == "transplant":
			_clamp_transplant_view()
		get_viewport().set_input_as_handled()


# Pressing "use" (E, or the left button with bare hands).
func _interact_pressed() -> void:
	e_held = true
	e_timer = 0.45
	if target != null:
		target.act.call()


# While transplanting the farmer faces the row but may glance around.
func _clamp_transplant_view() -> void:
	var off: float = angle_difference(PI, player.yaw)
	player.yaw = wrapf(PI + clampf(off, -TRANSPLANT_LOOK, TRANSPLANT_LOOK), -PI, PI)
	player.pitch = clampf(player.pitch, -1.3, 0.1)


# Arrow keys look around too: many laptop touchpads ignore the pointer
# while a key such as W is held.
func _keyboard_look(dt: float) -> void:
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
	if v == Vector2.ZERO:
		return
	player.look(Vector2(v.x * KEY_LOOK_YAW, v.y * KEY_LOOK_PITCH) * dt / player.LOOK_SPEED, invert_y)
	if mode == "transplant":
		_clamp_transplant_view()


func _cycle_tool(step: int) -> void:
	var ids := []
	for t in ToolsScript.TOOLS:
		ids.append(t.id)
	var i := ids.find(tools.current)
	_select_tool(ids[posmod(i + step, ids.size())])


func _unhandled_input(event: InputEvent) -> void:
	if not playing or mode == "summary":
		return
	if not (event is InputEventKey):
		return
	var ek := event as InputEventKey
	# Physical keys, like WASD movement: the same place on every layout,
	# and not rewritten by Vietnamese typing tools such as Unikey (Telex).
	var k: int = ek.physical_keycode if ek.physical_keycode != KEY_NONE else ek.keycode
	if paused:
		if ek.pressed and not ek.echo and k == KEY_ESCAPE:
			_set_paused(false)
		return
	if not ek.pressed:
		if k == KEY_E:
			e_held = false
		return
	if ek.echo:
		return
	if k == KEY_ESCAPE:
		_set_paused(true)
		return
	if mode == "transplant":
		transplant.key(k)
		return
	for t in ToolsScript.TOOLS:
		if k == t.key:
			_select_tool(t.id)
	if k == KEY_E:
		_interact_pressed()
	elif k == KEY_Q:
		ducks.whistle()
	elif OS.is_debug_build() and k >= KEY_F6 and k <= KEY_F9:
		debug_skip(k)


func _move_input() -> Vector2:
	if mode != "walk":
		return Vector2.ZERO
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_S):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1
	return v


# ---------------------------------------------------------------- weather & sky
func _update_sky() -> float:
	var h := hour()
	var ang := (h - 6.0) / 12.0 * PI
	var elev := sin(ang)
	var daylight := clampf(elev * 3.0 + 0.35, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elev - 0.08) / 0.27, 0.0, 1.0) if (elev > -0.15 and elev < 0.35) else 0.0
	var s: float = storm.level
	var horizon := Color("1a2236").lerp(Color("b8dcf0"), daylight).lerp(Color("f4b88a"), dusk * 0.6).lerp(Color("4a525a"), s * 0.85)
	var flash: float = storm.lightning
	if flash > 0.0:
		horizon = horizon.lerp(Color("dde6ff"), flash)
	sky_mat.set_shader_parameter("daylight", daylight)
	sky_mat.set_shader_parameter("dusk", dusk)
	sky_mat.set_shader_parameter("storm", s)
	sky_mat.set_shader_parameter("flash", flash)
	sky_mat.set_shader_parameter("drift", fmod(real_t * 0.0005, 1.0))
	env.fog_light_color = horizon.darkened(0.15)
	env.fog_density = lerpf(0.0018, 0.02, s)
	env.ambient_light_energy = (0.25 + 0.75 * daylight) * (1.0 - 0.4 * s) + flash * 1.5
	# Eyes adapt: lift exposure at night so the farm stays playable by moonlight.
	env.tonemap_exposure = lerpf(2.4, 1.0, smoothstep(0.0, 0.5, daylight))
	var dir := Vector3(cos(ang) * 60.0, maxf(elev, 0.08) * 70.0, -25.0)
	sun.look_at_from_position(dir, Vector3.ZERO, Vector3.UP)
	sun.light_energy = 1.6 * clampf(elev * 2.5, 0.0, 1.0) * (1.0 - 0.8 * s)
	sun.light_color = Color("fff1dc").lerp(Color("ffb070"), dusk * 0.7)
	sun.shadow_enabled = sun.light_energy > 0.02
	moon.light_energy = 0.12 * (1.0 - daylight) * (1.0 - s)
	RenderingServer.global_shader_parameter_set("wind_gust", 1.0 + s * 2.5)
	RenderingServer.global_shader_parameter_set("rain_amount", 1.0 if raining else 0.0)
	return maxf(0.0, elev) * (1.0 - s) * (0.0 if raining else 1.0)


func _update_storm(dt: float) -> void:
	var s := storm
	if s.phase == "none" and real_t >= rain_at:
		s.phase = "warning"
		s.t = 90.0
		rain_at = INF
		audio.play("thunder_far")
		hud.log_msg("Trời bỗng sầm tối, gió nổi mạnh… Mưa rào sắp ập tới!", "bad")
	match s.phase:
		"warning":
			s.t -= dt
			s.level = minf(0.85, s.level + dt / 30.0)
			s.next_bolt -= dt
			if s.next_bolt <= 0.0:
				s.next_bolt = randf_range(5, 11)
				s.lightning = 0.6
				get_tree().create_timer(1.5).timeout.connect(func(): audio.play("thunder_far"))
			if s.t <= 0.0:
				s.phase = "rain"
				s.t = 40.0
				raining = true
				hud.log_msg("Mưa trút xuống ào ào!", "bad")
		"rain":
			s.t -= dt
			s.level = minf(1.0, s.level + dt / 5.0)
			s.next_bolt -= dt
			if s.next_bolt <= 0.0:
				s.next_bolt = randf_range(3, 8)
				s.lightning = 1.0
				get_tree().create_timer(0.3).timeout.connect(func(): audio.play("thunder"))
			if tarp_on and tarp_placed.count(true) < 4:
				tarp_blow_t += dt
				if tarp_blow_t > 12.0:
					tarp_on = false
					tarp_placed = [false, false, false, false]
					tarp_fly_t = 3.0
					audio.play("tarp")
					hud.log_msg("Gió giật lật tung tấm bạt vì chưa chặn đủ gạch 4 góc!", "bad")
			if s.t <= 0.0:
				s.phase = "after"
				s.t = 20.0
				raining = false
				hud.log_msg("Tạnh mưa. Gỡ bạt và rải thóc ra phơi tiếp.")
		"after":
			s.t -= dt
			s.level = maxf(0.0, s.level - dt / 10.0)
			if s.t <= 0.0 and s.level <= 0.0:
				s.phase = "done"
	s.lightning = maxf(0.0, s.lightning - dt * 3.0)
	hud.flash.color.a = maxf(hud.flash.color.a - dt * 2.0, s.lightning * 0.5)
	audio.set_wind(s.level * (1.0 if s.phase in ["warning", "rain"] else 0.3))
	audio.set_rain(1.0 if raining else 0.0)
	rain.emitting = raining
	rain.position = Vector3(player.pos.x, player.y + 18.0, player.pos.z)

	if s.phase == "warning":
		hud.set_banner("[b]Mưa rào sau %d giây![/b]\n[font_size=13]Vun thóc vào khung bạt (chuột phải): %d%% · Bạt: %s · Gạch: %d/4[/font_size]" % [ceili(s.t), int(court.share_inside() * 100), "đã kéo" if tarp_on else "chưa", tarp_placed.count(true)])
	elif s.phase == "rain":
		hud.set_banner("[b]Đang mưa![/b] Thóc ngoài bạt bị ướt: %d%%" % int(court.soaked_fraction() * 100))
	else:
		hud.set_banner("")


# ---------------------------------------------------------------- HUD text
func _check(ok: bool, text: String) -> String:
	return ("[color=#8a8a7a][s]✓ %s[/s][/color]\n" % text) if ok else ("○ %s\n" % text)


func _pct(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))


func _objectives() -> String:
	if stage == "prep":
		var ni: int = ["none", "soaked", "sprouted", "sown", "ready", "pulled"].find(nursery.state)
		return "[color=#ffe08a][b]Giai đoạn 1–2 · Làm đất & Ươm mạ[/b][/color]\n" + \
			_check(field.avg_till() >= 0.9, "Cuốc xới đất khô (%s) — phím 2" % _pct(field.avg_till())) + \
			_check(field.water >= 1.0 or field.avg_smooth() >= 0.85, "Mở cửa cống dẫn nước vào ruộng (bờ tây)") + \
			_check(field.avg_smooth() >= 0.85, "Bừa bùn nhuyễn (%s) — phím 3, giữ chuột trái và đi" % _pct(field.avg_smooth())) + \
			_check(ni >= 1, "Ngâm thóc giống (thúng cạnh sân)") + \
			_check(ni >= 3, "Ủ qua đêm, rồi gieo thóc nứt nanh lên vạt mạ") + \
			_check(ni >= 4, "Tưới mạ 3 ngày (%d/3)" % nursery.water_days) + \
			_check(ni >= 5, "Nhổ & bó mạ (%d/%d)" % [nursery.bundles, BUNDLES]) + \
			_check(false, "Vào ruộng, bấm E để cấy") + \
			"[color=#aaaaaa]Nằm võng ở hiên nhà để qua ngày.[/color]"
	if stage == "care":
		var eggs: int = field.eggs.count(true)
		return "[color=#ffe08a][b]Giai đoạn 3 · Chăm sóc (lúa %d/8 ngày)[/b][/color]\n" % field.growth_day + \
			_check(field.water >= 3.0 and field.water <= 5.0, "Giữ nước 3–5 cm: cống / rãnh xả / gàu sòng") + \
			_check(field.pest < 0.3, "Rắc tro bếp lúc sáng sớm (5h–8h) khi sâu tăng") + \
			_check(eggs == 0, "Bóc trứng ốc trên cọc tre (%d ổ)" % eggs) + \
			_check(false, "Thả vịt vào ruộng: dọn ốc, cỏ, sục bùn" if field.growth_day < 5 else "Lúa trổ bông: lùa vịt RA khỏi ruộng!") + \
			"[color=#aaaaaa]Nằm võng để lúa lớn thêm một ngày.[/color]"
	if stage == "harvest":
		return "[color=#ffe08a][b]Giai đoạn 4 · Gặt & Tuốt lúa[/b][/color]\n" + \
			_check(field.cut_count() >= field.planted_count(), "Gặt bằng liềm — phím 5 (%d/%d khóm)" % [field.cut_count(), field.planted_count()]) + \
			_check(inv.sheaves == 0, "Gánh lúa về thùng đập ở sân (đang gánh %.1f lượm)" % (inv.sheaves / float(LUOM))) + \
			_check(barrel_sheaves == 0 and barrel_paddy > 0.0, "Đập lúa vào thùng (%d kg thóc)" % int(barrel_paddy)) + \
			_check(false, "Đổ thóc ra sân gạch")
	if stage == "drying":
		return "[color=#ffe08a][b]Chạy thóc · Phơi trên sân gạch đỏ[/b][/color]\n" + \
			_check(court.dry_fraction() > 0.98, "Rải mỏng thóc đón nắng — chuột trái (khô %s)" % _pct(court.dry_fraction())) + \
			_check(storm.phase in ["after", "done"], "Khi giông tới: vun thóc vào khung bạt (chuột phải), kéo bạt, chặn 4 góc gạch")
	return ""


func _stats() -> String:
	var w: float = field.water
	var wc := "#9ff07a" if (w >= 3.0 and w <= 5.0) else ("#ff6b6b" if (w > 7.0 or (w < 1.0 and stage == "care")) else "#ffb347")
	var s := "[b]Thửa ruộng[/b]\nMực nước: [color=%s]%.1f cm[/color]\nĐộ tơi đất: %s\nĐộ nhuyễn bùn: %s\n" % [wc, w, _pct(field.avg_till()), _pct(field.avg_smooth())]
	if stage != "prep":
		s += "Sâu hại: %s%s[/color]\nDinh dưỡng: %s\nSức khỏe lúa: %s\nCỏ dại: %s\nThẩm mỹ đồng ruộng: %s\n" % [
			"[color=#ff6b6b]" if field.pest > 0.4 else "[color=#ffffff]", _pct(field.pest), _pct(field.nutrient), _pct(field.health), _pct(field.weeds), _pct(field.aesthetic)]
	s += "Cống: %s · Rãnh xả: %s\nMương: %s · Vịt trong ruộng: %d/10" % [
		"mở" if field.gate_open else "đóng", "mở" if field.drain_open else "đắp",
		"[color=#9ff07a]đầy nước[/color]" if canal_full else "[color=#ffb347]cạn[/color]", int(round(ducks.fraction_in_field() * 10))]
	return s


func _inventory() -> String:
	var parts := ["Tro bếp %d" % inv.ash, "Cám %d" % inv.cam]
	for pair in [["beo", "Bèo"], ["beo_bam", "Bèo băm"], ["chao", "Cháo heo"], ["fert", "Bùn vi sinh"], ["eggs", "Trứng vịt"], ["bricks", "Gạch"]]:
		if inv[pair[0]] > 0:
			parts.append("%s %d" % [pair[1], inv[pair[0]]])
	if inv.sheaves > 0:
		parts.append("Gánh %.1f/8 lượm" % (inv.sheaves / float(LUOM)))
	return " · ".join(parts)


func _clock_text() -> String:
	var h := hour()
	var tod := "Đêm" if (h < 5.0 or h >= 19.0) else ("Sương sớm" if h < 8.0 else ("Ban ngày" if h < 17.0 else "Chiều tà"))
	var m := int(fmod(minutes, 1440.0))
	return "Ngày %d · %02d:%02d · %s%s" % [day(), m / 60, m % 60, tod, " · Mưa" if raining else ""]


func _show_summary() -> void:
	mode = "summary"
	mouse_left = false
	mouse_right = false
	e_held = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var soaked: float = court.soaked_fraction()
	var grade := "Gạo loại 1 — hạt trong, thơm"
	if soaked >= 0.25:
		grade = "Gạo nát / thức ăn chăn nuôi — thóc ướt mưa lên mầm nhiều"
	elif soaked >= 0.05:
		grade = "Gạo loại 2 — một phần thóc lên mầm"
	hud.summary_text.text = """[font_size=26][color=#ffe08a]Kết thúc vụ lúa[/color][/font_size]
[font_size=20][color=#ffe08a]%s[/color][/font_size]

Thóc phơi khô: [b]%d kg[/b]
Thóc bị ướt mưa: [b]%s[/b]
Thẩm mỹ đồng ruộng: [b]%s[/b] (+%d%% sản lượng)
Sức khỏe lúa cuối vụ: [b]%s[/b]
Thưởng vịt chạy đồng: [b]+%s[/b]
Trứng vịt đã nhặt: [b]%d[/b]
Số ngày: [b]%d[/b]

Cảm ơn bạn đã xuống đồng!""" % [grade, int(court.total), _pct(soaked), _pct(field.aesthetic), int(field.aesthetic * 15), _pct(field.health), _pct(field.duck_bonus), eggs_collected, day()]
	hud.summary_screen.visible = true
	print("SUMMARY kg=%d soaked=%.2f grade=%s" % [int(court.total), soaked, grade])


# ---------------------------------------------------------------- loop
func _process(raw_dt: float) -> void:
	var dt := minf(raw_dt, 0.1)
	if playing and not paused and mode != "summary":
		_step(dt)
	field.refresh()


func _step(dt: float) -> void:
	real_t += dt
	var dt_min := dt * MIN_PER_SEC
	_advance(dt_min)
	var sun_f := _update_sky()
	_update_storm(dt)

	_keyboard_look(dt)
	var load_frac: float = inv.sheaves / float(CARRY)
	var moved: float = player.update(dt, _move_input(), Input.is_physical_key_pressed(KEY_SHIFT), field, load_frac)
	var pole_active: bool = tools.current == "sao" and mouse_left and mode == "walk"
	tools.animate(dt, player.moving, player.bob_phase, real_t, pole_active, load_frac)

	if mode == "transplant":
		transplant.step(dt)

	if mode == "walk":
		hud.set_hint("")
		if mouse_left or mouse_right:
			if tools.current == "bua" and mouse_left:
				var res: String = field.harrow(player.pos.x, player.pos.z, moved)
				if res == "dry":
					hud.set_hint("Phải dẫn nước vào ruộng (≥ 1 cm) mới bừa được bùn.")
				elif res == "untilled":
					hud.set_hint("Chỗ này chưa cuốc kỹ.")
				elif res == "ok" and moved > 0.0:
					player.stamina -= moved * 3.0
			elif tools.current != "sao":
				_use_tool(MOUSE_BUTTON_RIGHT if mouse_right else MOUSE_BUTTON_LEFT)
		target = _find_interaction()
		hud.set_crosshair("use" if target != null else "aim")
		if target != null:
			hud.set_prompt(target.label)
		if e_held and target != null and target.repeat:
			e_timer -= dt
			if e_timer <= 0.0:
				e_timer = 0.3
				target.act.call()

	# simulation
	field.step(dt_min, canal_full, raining, sun_f)
	if stage == "drying":
		court.step(dt_min, sun_f, raining, tarp_on)
		if court.dry_fraction() > 0.98 and storm.phase in ["after", "done"] and not tarp_on:
			_show_summary()
	ducks.step(dt, player.pos, player.forward(), pole_active, duck_pen_open, real_t)
	if ducks.fraction_in_field() > 0.5:
		duck_field_min += dt_min
	if ducks.count_outside_pen() > 5:
		duck_forage_min += dt_min

	# ambience: frogs and crickets at night, birds by day
	amb_t -= dt
	if amb_t <= 0.0:
		amb_t = 0.12
		var h := hour()
		var night := h < 5.0 or h >= 18.5
		var near_water := Vector2(player.pos.x, player.pos.z).length() < 25.0
		if (night or raining) and near_water and randf() < 0.6:
			audio.play("frog", -8.0, randf_range(0.9, 1.1))
		if night and randf() < 0.3:
			audio.play("cricket", -10.0)
		if not night and not raining and randf() < 0.04:
			audio.play("bird", -10.0, randf_range(0.9, 1.2))

	_update_visuals(dt)
	hud.vignette.color.a = 0.35 if player.stamina < 20.0 else 0.0
	hud.stamina_bar.value = player.stamina
	hud.set_text(hud.clock, "clock", _clock_text())
	hud.set_text(hud.objective, "obj", _objectives())
	hud.set_text(hud.stats, "stats", _stats())
	hud.set_text(hud.inv, "inv", _inventory())


func _update_visuals(dt: float) -> void:
	world.gate.position.y = 0.55 if field.gate_open else -0.05
	world.drain_plug.visible = not field.drain_open
	for i in world.eggs.size():
		world.eggs[i].visible = field.eggs[i]
	for i in world.duck_eggs.size():
		world.duck_eggs[i].visible = i < duck_eggs
	world.duck_gate.rotation.y = -PI / 2 if duck_pen_open else 0.0
	world.barrel_grain.scale.y = 1.0 + barrel_paddy / 6.0
	world.barrel_grain.position.y = 0.05 + barrel_paddy / 240.0
	world.canal_water.position.y = -0.3 if canal_full else -0.7
	smoke_t = maxf(0.0, smoke_t - dt)
	smoke.emitting = smoke_t > 0.0
	world.pig.rotation.y = sin(real_t * 0.5) * 0.4

	# tarp: sits on the heap, flaps in the wind, flies off if not weighted
	var tp: MeshInstance3D = world.tarp
	if tarp_fly_t > 0.0:
		tarp_fly_t -= dt
		tp.visible = true
		tp.position += Vector3(8, 4, 0) * dt
		tp.rotation.z += dt * 2.0
		if tarp_fly_t <= 0.0:
			tp.visible = false
			tp.position = Vector3(0, 0.6, -17)
			tp.rotation = Vector3.ZERO
	else:
		tp.visible = tarp_on
		if tarp_on:
			var anchored: bool = tarp_placed.count(true) == 4
			var amp: float = storm.level * (0.03 if anchored else 0.2)
			tp.position.y = court.max_height() + 0.12 + sin(real_t * 9.0) * amp
			tp.rotation.x = sin(real_t * 7.0) * amp * 0.5
			tp.rotation.z = sin(real_t * 5.3) * amp * 0.5
	for i in 4:
		world.corner_bricks[i].visible = tarp_placed[i]
		world.corner_marks[i].visible = tarp_on and not tarp_placed[i]

	# aim markers
	hoe_mark.visible = false
	court.set_highlight(-1)
	if mode == "walk" and tools.current == "cuoc" and stage == "prep":
		var a := _aim(1.3)
		var idx: int = field.cell_at(a.x, a.y)
		if idx >= 0:
			var c: Vector2 = field.cell_center(idx)
			hoe_mark.position = Vector3(c.x, L.FIELD.y + 0.12, c.y)
			hoe_mark.visible = true
	if mode == "walk" and tools.current == "cao":
		var a := _aim(1.5)
		if L.in_court(a.x, a.y):
			court.set_highlight(court.cell_at(a.x, a.y))


# ---------------------------------------------------------------- debug helpers (F6–F9 in debug builds)
func _debug_skip_prep() -> void:
	field.till.fill(1.0)
	field.smooth.fill(1.0)
	field.water = 3.0
	field.soil_dirty = true
	nursery.state = "pulled"
	nursery.bundles = BUNDLES
	_refresh_nursery()


func _debug_plant_all() -> void:
	for l in 8:
		for r in 26:
			for s in [-0.6, 0.0, 0.6]:
				field.plant(L.FIELD.x0 + 2 * l + 1 + s + randf_range(-0.04, 0.04), L.FIELD.z1 - 0.5 - r * 0.6)
	field.aesthetic = 0.85
	stage = "care"
	nursery.state = "done"
	_refresh_nursery()


func debug_skip(k: int) -> void:
	if stage == "prep":
		_debug_skip_prep()
		if k == KEY_F6:
			hud.log_msg("[debug] làm đất + mạ xong")
			return
		_debug_plant_all()
	if k >= KEY_F8:
		field.growth_day = 8
		field.rice_dirty = true
		stage = "harvest"
		_select_tool("liem")
	if k == KEY_F9:
		for c in field.clumps:
			c.cut = true
		barrel_paddy = 150.0


# ---------------------------------------------------------------- autotest
# godot --path . -- --autotest [--shots=DIR]
# Plays through every stage by driving the same functions the input uses,
# prints progress and exits non-zero if a stage does not advance.
func _shot(name: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.substr(8) + "/" + name + ".png")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _look(x: float, z: float, yaw: float, pitch: float) -> void:
	player.pos = Vector3(x, 0, z)
	player.yaw = yaw
	player.pitch = pitch
	await _wait(0.3)


func _press(label_part: String) -> bool:
	target = _find_interaction()
	var ok: bool = target != null and label_part in target.label
	print("  [%s] -> %s" % [label_part, target.label if target != null else "nothing"])
	if ok:
		target.act.call()
	await _wait(0.5)
	return ok


func _expect(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		get_tree().quit(1)


# godot --path . -- --tour --shots=DIR
# Screenshots of the farm at different stages and times of day, for
# checking the look without playing a whole season.
func _set_time(h: float) -> void:
	minutes = float(day() - 1) * 1440.0 + h * 60.0
	await _wait(0.6)


func _hide_hud(hidden: bool) -> void:
	hud.visible = not hidden


func _look_at(x: float, z: float, tx: float, tz: float, pitch: float) -> void:
	await _look(x, z, atan2(-(tx - x), -(tz - z)), pitch)


func _run_tour() -> void:
	_on_play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hide_hud(true)
	await _look_at(-3, -10.5, 2, 2, -0.15)
	await _set_time(7.0)
	await _shot("tour-1-dry-field")
	await _look_at(6, -11, 0, -24, -0.05)
	await _set_time(9.0)
	await _shot("tour-2-house")
	_debug_skip_prep()
	_debug_plant_all()
	field.water = 4.0
	field.growth_day = 2
	field.rice_dirty = true
	await _look_at(-7.5, 9.0, 2, -4, -0.18)
	await _set_time(10.0)
	await _shot("tour-3-young-rice")
	await _look_at(-14.5, -4, -21, -11, -0.15)
	await _set_time(11.0)
	await _shot("tour-4-pond")
	field.growth_day = 8
	field.rice_dirty = true
	await _look_at(7.5, 3, -4, -1, -0.12)
	await _set_time(16.8)
	await _shot("tour-5-ripe-golden-hour")
	await _look_at(0, -6, 0, 0, -0.35)
	await _set_time(12.0)
	_select_tool("liem")
	await _shot("tour-6-sickle")
	stage = "drying"
	court.pour(140.0)
	for k in 4:
		for i in court.mass.size():
			court.spread(i)
	await _look_at(0.5, -11.5, 0, -19, -0.3)
	await _set_time(12.5)
	await _shot("tour-7-courtyard")
	storm.phase = "warning"
	storm.t = 60.0
	storm.level = 0.85
	await _wait(1.0)
	await _shot("tour-8-storm")
	storm.phase = "rain"
	storm.level = 1.0
	raining = true
	await _look_at(0, -12, 0, 0, -0.15)
	await _wait(2.0)
	await _shot("tour-9-rain")
	storm.phase = "done"
	storm.level = 0.0
	raining = false
	await _look_at(7, -2, -8, -2, -0.05)
	await _set_time(17.85)
	await _shot("tour-10-sunset")
	await _set_time(22.0)
	await _shot("tour-11-night")
	get_tree().quit(0)


func _run_autotest() -> void:
	await _wait(0.5)
	await _shot("0-start")
	_on_play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(0.5)
	# Stage 1: hoe, open the gate, harrow
	_select_tool("cuoc")
	await _look(0, -6, PI, -0.5)
	for i in 4:
		_use_tool(MOUSE_BUTTON_LEFT)
		await _wait(0.7)
	_expect(field.avg_till() > 0.0, "hoe tills soil (%.3f)" % field.avg_till())
	await _shot("1-hoe")
	await _look(-7, 0, PI / 2, -0.3)
	_expect(await _press("cửa cống"), "open sluice gate")
	await _wait(2.0)
	_expect(field.water > 0.0, "water flows in (%.2f cm)" % field.water)
	# Stage 2: nursery
	await _look(9.5, -18.6, 0, -0.4)
	_expect(await _press("Ngâm thóc"), "soak seed")
	sleep()
	await _look(13, -13.5, 0, -0.5)
	_expect(await _press("Gieo"), "sow nursery")
	for d in 3:
		_expect(await _press("Tưới"), "water nursery day %d" % (d + 1))
		sleep()
	_expect(nursery.state == "ready", "seedlings ready")
	player.stamina = 100.0
	for i in BUNDLES:
		await _press("Nhổ mạ")
		await _wait(0.3)
	_expect(nursery.state == "pulled", "8 bundles pulled")
	field.till.fill(1.0)
	field.smooth.fill(1.0)
	field.soil_dirty = true
	field.water = 3.0
	await _look(0, 0, PI, -0.4)
	_expect(await _press("cấy"), "start transplanting")
	await _wait(1.6)
	# play the rhythm perfectly for a few rows, then let neighbours finish
	var keys := [KEY_SPACE, KEY_A, KEY_S, KEY_D]
	while transplant.next < 24:
		var n: Dictionary = transplant.notes[transplant.next]
		if transplant.t >= n.time - 0.03:
			transplant.key(keys[n.k])
		await get_tree().process_frame
	await _shot("2-transplant")
	transplant.finish(true)
	_expect(stage == "care" and field.planted_count() > 400, "transplanted %d clumps, aesthetic %.2f" % [field.planted_count(), field.aesthetic])
	# Stage 3: care
	duck_pen_open = true
	for d in 7:
		field.water = 4.0
		sleep()
	await _look(0, -10, PI, -0.25)
	await _wait(0.5)
	await _shot("3-heading")
	sleep()
	_expect(stage == "harvest", "rice ripe after 8 days (health %.2f)" % field.health)
	# Stage 4: harvest
	await _look(-3, -7.6, PI, -0.4)
	_select_tool("liem")
	for i in 4:
		_use_tool(MOUSE_BUTTON_LEFT)
		await _wait(0.6)
	_expect(inv.sheaves > 0, "sickle cuts sheaves (%d)" % inv.sheaves)
	await _shot("4-harvest")
	for c in field.clumps:
		c.cut = true
	inv.sheaves = 0
	barrel_sheaves = 12
	await _look(8.5, -15.2, 0, -0.3)
	_expect(await _press("lượm"), "put sheaves in barrel")
	await _press("Đập lúa")
	await _wait(0.6)
	barrel_paddy += 140.0
	barrel_sheaves = 0
	_expect(await _press("Đổ"), "pour paddy on the courtyard")
	_expect(stage == "drying", "stage drying")
	for k in 4:
		for i in court.mass.size():
			court.spread(i)
	await _look(0, -12.5, 0, -0.5)
	minutes = float(day() - 1) * 1440.0 + 10.0 * 60.0
	rain_at = real_t
	await _wait(3.0)
	_expect(storm.phase == "warning", "rain warning starts")
	await _shot("5-warning")
	for k in 30:
		for p in [Vector2(-1.5, -18.5), Vector2(-0.5, -18.5), Vector2(0.5, -18.5), Vector2(1.5, -18.5), Vector2(-1.5, -15.5), Vector2(-0.5, -15.5), Vector2(0.5, -15.5), Vector2(1.5, -15.5), Vector2(-2.5, -17), Vector2(2.5, -17), Vector2(-3.5, -17), Vector2(3.5, -17), Vector2(-4.5, -17), Vector2(4.5, -17)]:
			court.gather(court.cell_at(p.x, p.y))
	print("  paddy under tarp area: %.2f" % court.share_inside())
	await _look(-7.5, -14.2, 0, -0.3)
	_expect(await _press("Kéo bạt"), "pull tarp")
	await _look(-7.5, -17.6, 0, -0.3)
	_expect(await _press("gạch"), "pick up bricks")
	for c in L.CORNERS:
		await _look(c.x, c.y + 0.9, 0, -0.6)
		_expect(await _press("chặn góc"), "place brick")
	await _look(0, -11, 0, -0.35)
	storm.t = 0.3
	await _wait(3.0)
	_expect(raining, "it rains")
	await _shot("6-rain")
	storm.t = 0.3
	await _wait(1.0)
	await _look(-7.5, -14.2, 0, -0.3)
	_expect(await _press("Gỡ bạt"), "remove tarp after rain")
	storm.phase = "done"
	storm.level = 0.0
	court.moist.fill(0.1)
	await _wait(1.0)
	_expect(mode == "summary", "season summary shown")
	await _shot("7-summary")
	print("AUTOTEST OK")
	get_tree().quit(0)
