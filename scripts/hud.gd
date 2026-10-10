# On-screen overlay: clock, objectives, field gauges, stamina, toolbar,
# prompts, message log, the rain banner and the menu screens.
extends CanvasLayer

const TOOLS = preload("res://scripts/tools.gd").TOOLS

signal play_pressed
signal new_season_pressed
signal resume_pressed
signal sens_changed(value: float)
signal invert_changed(value: bool)
signal fov_changed(value: float)
signal quality_changed(level: int)
signal latency_changed(value: bool)

var clock: Label
var objective: RichTextLabel
var stats: RichTextLabel
var stamina_bar: ProgressBar
var inv: Label
var prompt: Label
var banner: PanelContainer
var banner_text: RichTextLabel
var log_box: VBoxContainer
var flash: ColorRect
var vignette: ColorRect
var slots := {}
var start_screen: Control
var pause_screen: Control
var summary_screen: Control
var summary_text: RichTextLabel
var sens_slider: HSlider
var crosshair: Panel
var _cross_state := ""
var sens_label: Label
var invert_box: CheckBox
var fov_slider: HSlider
var fov_label: Label
var quality_buttons: Array = []
var latency_box: CheckBox
var renderer: RichTextLabel
var perf: Label # F3: frame rate, triangles, draw calls
# rhythm mini-game
var rhythm: Control
var rhythm_info: RichTextLabel
var rhythm_track: Panel
var rhythm_score: Label

var _cache := {}


func _panel_style(alpha := 0.4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, alpha)
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


func _label(text := "", size := 15) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _rich(size := 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	return r


func _boxed(child: Control, alpha := 0.4) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(alpha))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(child)
	return p


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	flash = ColorRect.new()
	flash.color = Color(0.9, 0.94, 1.0, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	vignette = ColorRect.new()
	vignette.color = Color(0.35, 0, 0, 0.0)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	# The captured cursor sits exactly here, so the crosshair must never
	# take mouse events (it used to swallow every look and click).
	crosshair = Panel.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	set_crosshair("aim")

	prompt = _label("", 16)
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offset(prompt, -400, 24, 400, 54)
	root.add_child(prompt)

	var tl := VBoxContainer.new()
	tl.position = Vector2(14, 10)
	tl.custom_minimum_size = Vector2(390, 0)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)
	clock = _label("", 16)
	tl.add_child(clock)
	objective = _rich(14)
	objective.custom_minimum_size = Vector2(380, 0)
	tl.add_child(_boxed(objective))

	stats = _rich(14)
	stats.custom_minimum_size = Vector2(260, 0)
	var sb := _boxed(stats)
	sb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_offset(sb, -284, 10)
	root.add_child(sb)

	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_offset(log_box, -354, 300)
	log_box.custom_minimum_size = Vector2(340, 0)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)

	var bl := VBoxContainer.new()
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_offset(bl, 14, -66)
	root.add_child(bl)
	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(220, 16)
	stamina_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e0b84a")
	fill.set_corner_radius_all(6)
	stamina_bar.add_theme_stylebox_override("fill", fill)
	stamina_bar.add_theme_stylebox_override("background", _panel_style(0.45))
	bl.add_child(_label("Sức lực", 12))
	bl.add_child(stamina_bar)
	inv = _label("", 13)
	bl.add_child(inv)

	var tb := HBoxContainer.new()
	tb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_offset(tb, -300, -74)
	tb.add_theme_constant_override("separation", 5)
	root.add_child(tb)
	for t in TOOLS:
		var l := _label("%s\n%s\n%s" % [t.key - KEY_0, t.name, t.en], 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(78, 0)
		var p := _boxed(l, 0.45)
		tb.add_child(p)
		slots[t.id] = p

	banner_text = _rich(17)
	banner_text.custom_minimum_size = Vector2(620, 0)
	banner = _boxed(banner_text, 0.0)
	(banner.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.47, 0.08, 0.08, 0.8)
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_offset(banner, -320, 150)
	banner.visible = false
	root.add_child(banner)

	perf = _label("", 13)
	perf.set_anchors_preset(Control.PRESET_CENTER_TOP)
	perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offset(perf, -160, 8, 160, 48)
	perf.visible = false
	root.add_child(perf)

	_build_rhythm(root)
	_build_screens(root)
	# Nothing on the in-game overlay may take the mouse: while the cursor is
	# captured it sits at the screen centre, right on the crosshair.
	for c in root.get_children():
		if c != start_screen and c != pause_screen and c != summary_screen:
			_ignore_mouse(c)


func _ignore_mouse(c: Node) -> void:
	if c is Control:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in c.get_children():
		_ignore_mouse(k)


func _build_rhythm(root: Control) -> void:
	rhythm = VBoxContainer.new()
	rhythm.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_offset(rhythm, -360, -230)
	rhythm.custom_minimum_size = Vector2(720, 0)
	rhythm.visible = false
	root.add_child(rhythm)
	rhythm_info = _rich(16)
	rhythm_info.custom_minimum_size = Vector2(720, 0)
	rhythm.add_child(rhythm_info)
	rhythm_track = Panel.new()
	rhythm_track.custom_minimum_size = Vector2(720, 64)
	rhythm_track.clip_contents = true
	var st := _panel_style(0.6)
	st.bg_color = Color(0.12, 0.08, 0.04, 0.65)
	rhythm_track.add_theme_stylebox_override("panel", st)
	rhythm.add_child(rhythm_track)
	var hit := ColorRect.new()
	hit.color = Color("ffe08a")
	hit.position = Vector2(88, 4)
	hit.size = Vector2(4, 56)
	rhythm_track.add_child(hit)
	rhythm_score = _label("", 13)
	rhythm_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rhythm.add_child(rhythm_score)


func make_note(keycap: String, text: String, color: Color) -> ColorRect:
	var n := ColorRect.new()
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.color = color
	n.size = Vector2(52, 48)
	n.position = Vector2(-100, 8)
	var l := _label("%s\n%s" % [keycap, text], 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(52, 48)
	n.add_child(l)
	rhythm_track.add_child(n)
	return n


func _screen(root: Control) -> Array:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.03, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var card := PanelContainer.new()
	var s := _panel_style(0.93)
	s.bg_color = Color(0.11, 0.125, 0.08, 0.95)
	s.border_color = Color(1, 0.88, 0.54, 0.35)
	s.set_border_width_all(1)
	s.set_corner_radius_all(14)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 20
	s.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", s)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	return [bg, v]


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(220, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return b


func _build_screens(root: Control) -> void:
	var s := _screen(root)
	start_screen = s[0]
	var body := _rich(15)
	body.custom_minimum_size = Vector2(720, 0)
	body.text = """[font_size=34][color=#ffe08a]Ruộng Lúa Nước[/color][/font_size]
Một vụ lúa ở làng quê Bắc Bộ, qua đôi mắt người nông dân · [i]A season of wet-rice farming, first-person[/i]

[color=#cfe8a0][b]Điều khiển[/b][/color]
W A S D đi lại · Shift chạy · Chuột (hoặc phím mũi tên) để nhìn quanh · Lăn chuột: đổi dụng cụ
Chuột trái: dùng dụng cụ (tay không: tương tác) · Chuột phải: cào vun thóc
E: tương tác (giữ để lặp lại) · 1–7: chọn dụng cụ · Q: huýt sáo gọi vịt · Esc: tạm dừng, chỉnh độ nhạy chuột
[color=#999999]Nếu W/E không ăn, hãy tắt bộ gõ tiếng Việt (Unikey/EVKey) khi chơi.[/color]

[color=#cfe8a0][b]Một vụ lúa[/b][/color]
1. Cuốc đất, mở cống dẫn nước, bừa bùn nhuyễn
2. Ngâm thóc, gieo mạ, tưới 3 ngày, nhổ mạ, cấy theo nhịp
3. Giữ nước 3–5 cm, rắc tro, bóc trứng ốc, thả vịt
4. Gặt, gánh về, đập lúa, phơi thóc — coi chừng mưa rào!

[color=#999999]Âm thanh được tổng hợp trực tiếp, hãy bật loa.[/color]"""
	s[1].add_child(body)
	var play := _button("Xuống đồng · Play")
	play.pressed.connect(func(): play_pressed.emit())
	s[1].add_child(play)

	s = _screen(root)
	pause_screen = s[0]
	var pt := _rich(16)
	pt.custom_minimum_size = Vector2(360, 0)
	pt.text = "[font_size=24][color=#ffe08a]Tạm nghỉ[/color][/font_size]\nEsc hoặc bấm Tiếp tục để quay lại ruộng."
	s[1].add_child(pt)
	sens_label = _label("", 15)
	s[1].add_child(sens_label)
	sens_slider = HSlider.new()
	sens_slider.min_value = 0.2
	sens_slider.max_value = 3.0
	sens_slider.step = 0.05
	sens_slider.custom_minimum_size = Vector2(360, 24)
	sens_slider.value_changed.connect(_on_sens_slider)
	s[1].add_child(sens_slider)
	invert_box = CheckBox.new()
	invert_box.text = "Đảo chiều chuột lên/xuống · Invert Y"
	invert_box.toggled.connect(func(v: bool): invert_changed.emit(v))
	s[1].add_child(invert_box)
	fov_label = _label("", 15)
	s[1].add_child(fov_label)
	fov_slider = HSlider.new()
	fov_slider.min_value = 55
	fov_slider.max_value = 80
	fov_slider.step = 1
	fov_slider.custom_minimum_size = Vector2(360, 24)
	fov_slider.value_changed.connect(_on_fov_slider)
	s[1].add_child(fov_slider)
	s[1].add_child(_label("Chất lượng đồ họa · Graphics quality (F3: FPS)", 15))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in 3:
		var b := Button.new()
		b.text = ["Thấp · Low", "Vừa · Medium", "Cao · High"][i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(116, 34)
		b.pressed.connect(func(): quality_changed.emit(i))
		qrow.add_child(b)
		quality_buttons.append(b)
	s[1].add_child(qrow)
	latency_box = CheckBox.new()
	latency_box.text = "Giảm độ trễ chuột (VSync mailbox) · Low latency"
	latency_box.toggled.connect(func(v: bool): latency_changed.emit(v))
	s[1].add_child(latency_box)
	renderer = _rich(13)
	renderer.custom_minimum_size = Vector2(360, 0)
	s[1].add_child(renderer)
	s[1].add_child(_label("F11: toàn màn hình · fullscreen", 12))
	var resume := _button("Tiếp tục · Resume")
	resume.pressed.connect(func(): resume_pressed.emit())
	s[1].add_child(resume)
	pause_screen.visible = false

	s = _screen(root)
	summary_screen = s[0]
	summary_text = _rich(15)
	summary_text.custom_minimum_size = Vector2(560, 0)
	s[1].add_child(summary_text)
	var again := _button("Vụ mới")
	again.pressed.connect(func(): new_season_pressed.emit())
	s[1].add_child(again)
	summary_screen.visible = false


func _on_sens_slider(v: float) -> void:
	sens_label.text = "Độ nhạy chuột · Mouse sensitivity: %.2f" % v
	sens_changed.emit(v)


func _on_fov_slider(v: float) -> void:
	fov_label.text = "Góc nhìn · Field of view: %d°" % int(v)
	fov_changed.emit(v)


func set_video_settings(fov: float, quality: int, low_latency: bool) -> void:
	fov_slider.set_value_no_signal(fov)
	fov_label.text = "Góc nhìn · Field of view: %d°" % int(fov)
	quality_buttons[quality].set_pressed_no_signal(true)
	latency_box.set_pressed_no_signal(low_latency)


func set_renderer(text: String) -> void:
	renderer.text = "[color=#bbbbbb]" + text + "[/color]"


func set_mouse_settings(sens: float, invert: bool) -> void:
	sens_slider.set_value_no_signal(sens)
	sens_label.text = "Độ nhạy chuột · Mouse sensitivity: %.2f" % sens
	invert_box.set_pressed_no_signal(invert)


func _offset(c: Control, x: float, y: float, x2 = null, y2 = null) -> void:
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x if x2 == null else x2
	c.offset_bottom = y if y2 == null else y2


func set_text(node: Object, key: String, text: String) -> void:
	if _cache.get(key, null) == text:
		return
	_cache[key] = text
	node.text = text


func tool(id: String) -> void:
	for k in slots:
		var st: StyleBoxFlat = _panel_style(0.45)
		if k == id:
			st.bg_color = Color(0.24, 0.18, 0.04, 0.75)
			st.border_color = Color("ffe08a")
			st.set_border_width_all(2)
		slots[k].add_theme_stylebox_override("panel", st)


# "aim": a small dot · "use": a ring when E / left click would do something.
func set_crosshair(state: String) -> void:
	if state == _cross_state:
		return
	_cross_state = state
	var r := 9 if state == "use" else 2
	_offset(crosshair, -r, -r, r, r)
	var st := StyleBoxFlat.new()
	st.set_corner_radius_all(r)
	st.anti_aliasing = true
	if state == "use":
		st.bg_color = Color(1, 1, 1, 0.0)
		st.border_color = Color(1, 0.95, 0.8, 0.9)
		st.set_border_width_all(2)
	else:
		st.bg_color = Color(1, 1, 1, 0.85)
		st.border_color = Color(0, 0, 0, 0.45)
		st.set_border_width_all(1)
	crosshair.add_theme_stylebox_override("panel", st)


func set_prompt(text: String) -> void:
	set_text(prompt, "prompt", ("[E] " + text) if text != "" else "")


func set_hint(text: String) -> void:
	set_text(prompt, "prompt", text)


func set_banner(text: String) -> void:
	banner.visible = text != ""
	set_text(banner_text, "banner", "[center]" + text + "[/center]" if text != "" else "")


func log_msg(text: String, kind := "info") -> void:
	var colors := {"info": Color("8fc0ff"), "good": Color("8fe06a"), "warn": Color("ffb347"), "bad": Color("ff6b6b")}
	var l := _label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	var st := _panel_style(0.5)
	st.border_color = colors.get(kind, Color.WHITE)
	st.border_width_left = 3
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	log_box.add_child(p)
	while log_box.get_child_count() > 4:
		var old := log_box.get_child(0)
		log_box.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(p, "modulate:a", 0.0, 1.5)
	tw.tween_callback(p.queue_free)
