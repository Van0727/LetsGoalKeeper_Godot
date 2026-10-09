# 主动技节奏弹窗：复用节拍素材拼出聚光舞台；三轨四音符仍严格跟随BGM，布局由VisualLayout编辑。
extends Control

signal qte_finished(result: Dictionary)
signal click_audio_triggered
signal miss_audio_triggered

const NOTE_COUNT := 4
const LANE_COUNT := 3
const TRAVEL_BEATS := 2.0
# 所有房型统一每拍一个音符，实际秒数随当前BGM速度变化。
const NOTE_INTERVAL_BEATS := 1.0
const CLICK_PULSE_SECONDS := 0.18
const CLICK_ATTACK_SECONDS := 0.055
const JUDGEMENT_VISIBLE_SECONDS := 0.42
const TARGET_HIT_RADIUS := 42.0
const QTE_CLICK_STREAM := preload("res://sound/sounds/qteClick.mp3")
const MISS_STREAM := preload("res://sound/sounds/miss.mp3")
const LANE_TEXTURE := preload("res://assets/ui/battle/firstbeat.png")
const CORE_TEXTURE := preload("res://assets/ui/battle/bigbeat.png")
const LINE_TEXTURE := preload("res://assets/ui/battle/beatline.png")
const TARGET_TEXTURE := preload("res://assets/placeholders/qte_target_ring.png")
const NOTE_TEXTURE := preload("res://assets/placeholders/qte_note.png")
# 攻击主动技沿用攻击牌的橙色基调，避免弹窗轨道和音符偏成浅棕色。
const TYPE_COLORS := {
	CardDefinition.CardType.ATTACK: Color(1.0, 0.45, 0.08),
	CardDefinition.CardType.DEFENSE: Color(0.38, 0.65, 0.87),
	CardDefinition.CardType.ABILITY: Color(0.42, 0.74, 0.48),
}

# 每次成功开启时覆盖颜色，避免连续释放不同类型时沿用上一次显示。
var _skill_color := Color.WHITE

var _rhythm_clock: Node
var _rng := RandomNumberGenerator.new()
var _notes: Array[Dictionary] = []
var _running := false
var _first_target_time := 0.0
# 未初始化时也与常规出牌一致：GREAT 为75ms，GOOD 为150ms，避免独立预览出现旧窗口。
var _perfect_window_seconds := 0.075
var _good_window_seconds := 0.15
var _counts := {"perfect": 0, "good": 0, "miss": 0}
var _target_line_y := 278.0
var _target_pulse_ages := PackedFloat32Array([-1.0, -1.0, -1.0])
var _judgement_text := ""
var _judgement_age := JUDGEMENT_VISIBLE_SECONDS
var _click_audio: AudioStreamPlayer
var _miss_audio: AudioStreamPlayer
var _lane_views: Array[TextureRect] = []
var _target_views: Array[TextureRect] = []
var _note_views: Array[TextureRect] = []
var _judgement_label: Label
var _layout: Control
var _target_markers: Array[Control] = []
var _beam_views: Array[TextureRect] = []
var _beam_edge_views: Array[TextureRect] = []
var _last_hit_effect: Node2D
const HIT_EFFECT := preload("res://scripts/battle/qte_hit_effect.gd")
var _halo_views: Array[TextureRect] = []
var _core_views: Array[TextureRect] = []
var _note_core_views: Array[TextureRect] = []
var _baseline: TextureRect
var _hand_shade: ColorRect
var _beam_texture: GradientTexture2D
var _beam_material: ShaderMaterial
var _edge_material: ShaderMaterial
var _accent_material: ShaderMaterial
var _ring_material: ShaderMaterial
var _core_material: ShaderMaterial
var _ray_views: Array[TextureRect] = []
var _hidden_chrome: Dictionary = {}
var _progress_style: StyleBoxFlat
var _target_layout_offset := 0.0
var _feedback_gap := 25.0
var _instruction_gap := 49.0
# 场景节点是布局唯一来源；运行时只更新音符、脉冲和状态，不反复重置设计者的节点尺寸。
@export_range(0.0, 0.8) var hand_dim_alpha := 0.38


# 弹窗常驻战斗UI树但默认隐藏；图片节点预先创建并循环复用，避免QTE中途分配资源。
func _ready() -> void:
	_layout = get_node_or_null("VisualLayout")
	if _layout == null:
		_layout = preload("res://scenes/qte_presentation.tscn").instantiate()
		add_child(_layout)
	for key in ["Left", "Center", "Right"]:
		_target_markers.append(_layout.get_node("Targets/" + key))
		# 编辑器中的真实节拍图仅作布局预览；运行时由可缩放的三层组合显示。
		_target_markers[-1].self_modulate.a = 0.0
	_target_layout_offset = _layout.get_node("Targets").position.y - 278.0
	_feedback_gap = _layout.get_node("FeedbackAnchor").position.y - _layout.get_node("Targets").position.y
	_instruction_gap = _layout.get_node("Instruction").position.y - _layout.get_node("Targets").position.y
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_create_visual_nodes()
	_click_audio = _create_sfx_player("QTEClickAudio", QTE_CLICK_STREAM, 3)
	_miss_audio = _create_sfx_player("QTEMissAudio", MISS_STREAM, 4)
	visibility_changed.connect(_restore_chrome_when_hidden)
	hide()
	set_process(false)


# 复用已有大节拍、白色圆环和横线；光束只用Godot渐变资源，不新增或重绘位图。
func _create_visual_nodes() -> void:
	_core_material = ShaderMaterial.new()
	_core_material.shader = preload("res://scripts/battle/qte_core_tint.gdshader")
	# 光束与圆环使用独立材质，保证渐隐不影响球体纹理和其他横线。
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = preload("res://scripts/battle/qte_beam.gdshader")
	_edge_material = _beam_material.duplicate() as ShaderMaterial
	_edge_material.set_shader_parameter("edge_mode", 1.0)
	_ring_material = ShaderMaterial.new()
	_ring_material.shader = preload("res://scripts/battle/qte_ring.gdshader")
	_accent_material = ShaderMaterial.new()
	_accent_material.shader = preload("res://scripts/battle/qte_accent.gdshader")
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.22, 0.78, 0.88, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
	_beam_texture = GradientTexture2D.new()
	_beam_texture.gradient = gradient
	_beam_texture.width = 64
	_beam_texture.height = 256
	_hand_shade = ColorRect.new()
	_hand_shade.name = "HandShade"
	_hand_shade.color = Color(0.015, 0.02, 0.04, hand_dim_alpha)
	_hand_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand_shade)
	for lane in range(LANE_COUNT):
		_beam_views.append(_create_texture_view("Beam%d" % lane, _beam_texture))
		_beam_views[-1].material = _beam_material.duplicate()
		for side in range(2):
			var edge := _create_texture_view("BeamEdge%d_%d" % [lane, side], LANE_TEXTURE)
			edge.material = _edge_material.duplicate()
			_beam_edge_views.append(edge)
		_lane_views.append(_create_texture_view("Lane%d" % lane, LANE_TEXTURE))
		_lane_views[-1].material = _edge_material.duplicate()
	_baseline = _create_texture_view("JudgementLine", LINE_TEXTURE)
	_baseline.material = _core_material
	for lane in range(LANE_COUNT):
		_halo_views.append(_create_texture_view("Halo%d" % lane, TARGET_TEXTURE))
		_halo_views[-1].material = _ring_material
		_target_views.append(_create_texture_view("Target%d" % lane, TARGET_TEXTURE))
		_target_views[-1].material = _ring_material
		_core_views.append(_create_texture_view("Core%d" % lane, CORE_TEXTURE))
		_core_views[-1].material = _core_material
		for ray in range(4):
			_ray_views.append(_create_texture_view("Ray%d_%d" % [lane, ray], LANE_TEXTURE))
			_ray_views[-1].material = _accent_material
	for note_index in range(NOTE_COUNT):
		_note_core_views.append(_create_texture_view("NoteCore%d" % note_index, CORE_TEXTURE))
		_note_core_views[-1].material = _core_material
		_note_views.append(_create_texture_view("Note%d" % note_index, NOTE_TEXTURE))
		_note_views[-1].material = _ring_material
	_judgement_label = Label.new()
	_judgement_label.name = "JudgementFeedback"
	_judgement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_judgement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_judgement_label.add_theme_font_size_override("font_size", 22)
	_judgement_label.add_theme_constant_override("outline_size", 3)
	_judgement_label.add_theme_color_override("font_outline_color", Color(0.25, 0.07, 0.015))
	add_child(_judgement_label)
	# 固定文案位于音轨上方，始终压在光束前面保持可读。
	_layout.z_index = 1
	# 每个弹窗独享进度样式，切换类型不会污染场景资源或其他实例。
	_progress_style = _layout.get_node("Progress").get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	_layout.get_node("Progress").add_theme_stylebox_override("normal", _progress_style)


# 调用方提供真实技能名称，避免三类主动技都显示同一攻击文案。
func set_skill_title(title: String) -> void:
	_layout.get_node("SkillTitle").text = title


func _create_texture_view(node_name: String, texture_resource: Texture2D) -> TextureRect:
	var view := TextureRect.new()
	view.name = node_name
	view.texture = texture_resource
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	return view


# QTE音效统一进入SFX总线；有限多声部允许快速连点或低帧率补记多个Miss时保留反馈。
func _create_sfx_player(node_name: String, stream: AudioStream, polyphony: int) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.bus = &"SFX"
	player.max_polyphony = polyphony
	add_child(player)
	return player


# 从同一 BGM 播放头安排四音符；类型决定三轨统一色，无效类型拒绝开启且不改变当前状态。
func start_qte(rhythm_clock: Node, seed_value: int = 0, target_line_y: float = 278.0, card_type: int = CardDefinition.CardType.ATTACK) -> bool:
	if _running or rhythm_clock == null:
		return false
	if not TYPE_COLORS.has(card_type):
		return false
	_skill_color = TYPE_COLORS[card_type]
	_rhythm_clock = rhythm_clock
	_rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()
	# 配置值是玩家听到的现实秒数；判定时再换算为当前音源时间，避免变调后窗口缩水或膨胀。
	_perfect_window_seconds = float(_rhythm_clock.perfect_window_ms) / 1000.0
	_good_window_seconds = float(_rhythm_clock.good_window_ms) / 1000.0
	_target_line_y = target_line_y + _target_layout_offset
	var beat_duration: float = _rhythm_clock.get_beat_duration()
	var next_beat_time: float = _rhythm_clock.get_next_beat_time(_rhythm_clock.get_music_time())
	# 首个音符在下一个整数拍出现并完整移动两拍；后续目标每隔一拍到达判定线。
	_first_target_time = next_beat_time + beat_duration * TRAVEL_BEATS
	_notes.clear()
	_counts = {"perfect": 0, "good": 0, "miss": 0}
	_target_pulse_ages = PackedFloat32Array([-1.0, -1.0, -1.0])
	_judgement_text = ""
	_judgement_age = JUDGEMENT_VISIBLE_SECONDS
	var lane_sequence := _generate_lane_sequence()
	for note_index in range(NOTE_COUNT):
		_notes.append({
			"lane": lane_sequence[note_index],
			"target_time": _first_target_time + beat_duration * NOTE_INTERVAL_BEATS * note_index,
			"judged": false,
		})
	_running = true
	_set_battle_chrome_hidden()
	show()
	set_process(true)
	_refresh_visual_nodes()
	return true


# 首音允许全轨随机；后续只选上一轨及相邻轨。前三音可同轨，但第四音不得形成四连同轨。
func _generate_lane_sequence() -> PackedInt32Array:
	var lanes := PackedInt32Array()
	if NOTE_COUNT <= 0:
		return lanes
	lanes.append(_rng.randi_range(0, LANE_COUNT - 1))
	for note_index in range(1, NOTE_COUNT):
		var previous_lane: int = lanes[note_index - 1]
		lanes.append(_rng.randi_range(
			maxi(previous_lane - 1, 0),
			mini(previous_lane + 1, LANE_COUNT - 1)
		))
	if lanes.size() == 4 and lanes[0] == lanes[1] and lanes[1] == lanes[2] and lanes[2] == lanes[3]:
		# 前三个保持合法的同轨结果，只把末音移到相邻轨；中轨仍随机选择左右方向。
		if lanes[3] == 1:
			lanes[3] = 0 if _rng.randi_range(0, 1) == 0 else 2
		else:
			lanes[3] = 1
	return lanes


# 每帧依据音乐绝对时间计算位置并补记越过窗口的Miss，同时推进点击动画和判定浮字。
func _process(delta: float) -> void:
	if not _running:
		return
	for lane in range(LANE_COUNT):
		if _target_pulse_ages[lane] >= 0.0:
			_target_pulse_ages[lane] += maxf(delta, 0.0)
			if _target_pulse_ages[lane] >= CLICK_PULSE_SECONDS:
				_target_pulse_ages[lane] = -1.0
	_judgement_age += maxf(delta, 0.0)
	var music_time: float = _rhythm_clock.get_music_time()
	var good_source_seconds := _get_source_window_seconds(_good_window_seconds)
	for note in _notes:
		if not bool(note.judged) and music_time > float(note.target_time) + good_source_seconds:
			_apply_judgement(note, "Miss")
	_refresh_visual_nodes()
	if _judged_count() == NOTE_COUNT:
		_finish_qte()


# 鼠标与单指触摸只在横线三个目标音符附近触发判定，遮罩其他区域仅拦截底层战斗输入。
func _gui_input(event: InputEvent) -> void:
	if not _running:
		return
	var pointer_position := Vector2.ZERO
	var pressed := false
	if event is InputEventMouseButton:
		pointer_position = event.position
		pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventScreenTouch:
		pointer_position = event.position
		pressed = event.pressed
	if not pressed:
		return
	var lane := _lane_at_pointer(pointer_position)
	if lane >= 0:
		_activate_lane(lane)
	accept_event()


# 每次点击先播放触感反馈；若这是最后一音，判定链会在同帧继续触发独立的踢球音效。
func _activate_lane(lane: int, music_time_override: float = -1.0) -> String:
	_target_pulse_ages[lane] = 0.0
	_click_audio.play()
	click_audio_triggered.emit()
	return judge_lane(lane, music_time_override)


# 可点击半径略大于可见音符，保证移动端易点；三轨重叠时选择横向距离最近的一轨。
func _lane_at_pointer(pointer_position: Vector2) -> int:
	if absf(pointer_position.y - _target_line_y) > TARGET_HIT_RADIUS:
		return -1
	var play_area := _get_play_area()
	var nearest_lane := -1
	var nearest_distance := INF
	for lane in range(LANE_COUNT):
		var lane_x := _get_lane_x(play_area, lane)
		var distance := absf(pointer_position.x - lane_x)
		if distance <= TARGET_HIT_RADIUS and distance < nearest_distance:
			nearest_lane = lane
			nearest_distance = distance
	return nearest_lane


# 同轨只判定距离当前时刻最近且仍在现实 Good 窗口内的音符；空按不会误伤其他轨道音符。
func judge_lane(lane: int, music_time_override: float = -1.0) -> String:
	if not _running or lane < 0 or lane >= LANE_COUNT:
		return ""
	var music_time: float = (
		_rhythm_clock.get_music_time() if music_time_override < 0.0 else music_time_override
	)
	var candidate: Dictionary = {}
	var closest_error := INF
	var good_source_seconds := _get_source_window_seconds(_good_window_seconds)
	for note in _notes:
		if bool(note.judged) or int(note.lane) != lane:
			continue
		var error: float = absf(music_time - float(note.target_time))
		if error <= good_source_seconds and error < closest_error:
			candidate = note
			closest_error = error
	if candidate.is_empty():
		_spawn_note_effect(lane, "Miss", _target_line_y)
		_show_judgement("Miss")
		_play_miss_audio()
		return ""
	var grade := "Great" if closest_error <= _get_source_window_seconds(_perfect_window_seconds) else "Good"
	_apply_judgement(candidate, grade, music_time)
	return grade


# QTE 目标坐标是音源秒数，窗口配置是现实秒数；播放倍率可能在 QTE 期间变化，故每次即时读取。
func _get_source_window_seconds(real_seconds: float) -> float:
	return real_seconds * float(_rhythm_clock.get_playback_rate()) if _rhythm_clock != null else real_seconds


func _apply_judgement(note: Dictionary, grade: String, judged_time: float = -1.0) -> void:
	# 消失前按当次实际判定时间取音符位置；早按、晚按和自动Miss都在音符处反馈。
	var event_time := float(_rhythm_clock.get_music_time()) if judged_time < 0.0 else judged_time
	var travel := float(_rhythm_clock.get_beat_duration()) * TRAVEL_BEATS
	var progress := 1.0 - (float(note.target_time) - event_time) / maxf(travel, 0.001)
	var note_y := lerpf(_get_play_area().position.y, _target_line_y, progress)
	_spawn_note_effect(int(note.lane), grade, note_y)
	note.judged = true
	note.grade = grade
	match grade:
		"Great":
			_counts.perfect += 1
		"Good":
			_counts.good += 1
		_:
			_counts.miss += 1
			_play_miss_audio()
	_show_judgement(grade)
	# 点击命中最后一个待判音符时立即结束，避免等到下一帧才播放足球起脚音。
	if _judged_count() == NOTE_COUNT:
		_finish_qte()


# 判定结果只保存为短时绘制状态，不创建新面板或永久标签。
func _show_judgement(grade: String) -> void:
	_judgement_text = grade
	_judgement_age = 0.0
	_refresh_visual_nodes()


# 点击时机错误和音符自然超时共用出牌Miss音效。
func _play_miss_audio() -> void:
	_miss_audio.play()
	miss_audio_triggered.emit()


func _judged_count() -> int:
	return int(_counts.perfect) + int(_counts.good) + int(_counts.miss)


# 最后一个音符判定完成的同一帧关闭遮罩并交出结果，让宿主立即衔接超级足球。
func _finish_qte() -> void:
	if not _running:
		return
	_running = false
	set_process(false)
	var result := _counts.duplicate(true)
	result["total"] = NOTE_COUNT
	result["score"] = int(_counts.perfect) * 2 + int(_counts.good)
	hide()
	qte_finished.emit(result)


# 所有音符、光束、光圈与线条共用当前技能类型色；原有橙红纹理先经着色器换色，避免蓝绿相乘变黑。
# 时间和判定数据保持原顺序，不参与视觉节点布局计算。
func _refresh_visual_nodes() -> void:
	if not _running or _rhythm_clock == null:
		return
	var play_area := _get_play_area()
	var target_y := _target_line_y
	var beat_duration: float = _rhythm_clock.get_beat_duration()
	var travel_seconds := beat_duration * TRAVEL_BEATS
	var music_time: float = _rhythm_clock.get_music_time()
	var good_source_seconds := _get_source_window_seconds(_good_window_seconds)
	for lane in range(LANE_COUNT):
		var lane_x := _get_lane_x(play_area, lane)
		var lane_view := _lane_views[lane]
		lane_view.position = Vector2(lane_x - 1.5, -48.0)
		lane_view.size = Vector2(3.0, maxf(target_y + 118.0, 1.0))
		lane_view.modulate = _skill_color
		_update_track_perspective(lane_view, lane_x)
		var beam := _beam_views[lane]
		beam.position = Vector2(lane_x - 28.0, -48.0)
		beam.size = Vector2(56.0, maxf(target_y - beam.position.y + 70.0, 1.0))
		beam.modulate = _skill_color
		_update_track_perspective(beam, lane_x)
		# 光束及侧边从屏幕外连续进入，判定线下共用渐隐，避免出现硬切断口。
		for side in range(2):
			var edge := _beam_edge_views[lane * 2 + side]
			edge.position = Vector2(lane_x - 21.0 + side * 40.0, beam.position.y)
			edge.size = Vector2(2.0, beam.size.y)
			edge.modulate = Color(_skill_color, 0.78)
			_update_track_perspective(edge, edge.position.x + edge.size.x * 0.5)
		var target_radius := _target_markers[lane].size.x * 0.5 * _get_target_pulse_scale(lane)
		var target_view := _target_views[lane]
		target_view.position = Vector2(lane_x, target_y) - Vector2.ONE * target_radius
		target_view.size = Vector2.ONE * target_radius * 2.0
		target_view.modulate = _skill_color.lightened(0.65)
		var halo := _halo_views[lane]
		halo.position = Vector2(lane_x, target_y) - Vector2.ONE * target_radius * 1.3
		halo.size = Vector2.ONE * target_radius * 2.6
		halo.modulate = Color(_skill_color, 0.4)
		var core := _core_views[lane]
		core.position = Vector2(lane_x, target_y) - Vector2.ONE * target_radius * 0.8
		core.size = Vector2.ONE * target_radius * 1.6
		core.modulate = _skill_color
		for ray in range(4):
			var accent := _ray_views[lane * 4 + ray]
			var angle := PI * 0.25 + ray * PI * 0.5
			# 保留可见3×8短线，外围透明余量供旋转抗锯齿使用。
			accent.size = Vector2(7, 12)
			accent.pivot_offset = accent.size * 0.5
			accent.rotation = angle - PI * 0.5
			accent.position = Vector2(lane_x, target_y) + Vector2.from_angle(angle) * (target_radius + 10.0) - accent.size * 0.5
			accent.modulate = Color(_skill_color.lightened(0.2), 0.9)
	for note_index in range(_notes.size()):
		var note: Dictionary = _notes[note_index]
		var note_view := _note_views[note_index]
		note_view.hide()
		_note_core_views[note_index].hide()
		if bool(note.judged):
			continue
		var time_until_target: float = float(note.target_time) - music_time
		if time_until_target > travel_seconds or time_until_target < -good_source_seconds:
			continue
		var progress := 1.0 - time_until_target / travel_seconds
		var lane: int = int(note.lane)
		var note_scale := lerpf(0.62, 1.0, clampf(progress, 0.0, 1.0))
		var note_y := lerpf(play_area.position.y, target_y, progress)
		var note_position := Vector2(_get_perspective_x(lane, note_y), note_y)
		note_view.position = note_position - Vector2.ONE * 20.0 * note_scale
		note_view.size = Vector2.ONE * 40.0 * note_scale
		note_view.modulate = _skill_color.lightened(0.65)
		var note_core := _note_core_views[note_index]
		note_core.position = note_position - Vector2.ONE * 17.0 * note_scale
		note_core.size = Vector2.ONE * 34.0 * note_scale
		note_core.modulate = _skill_color
		note_core.show()
		note_view.show()
	_baseline.modulate = _skill_color
	_progress_style.border_color = _skill_color.lightened(0.2)
	_progress_style.shadow_color = Color(_skill_color, 0.3)
	_baseline.position = Vector2(12.0, target_y - 1.0)
	_baseline.size = Vector2(maxf(size.x - 24.0, 1.0), 2.0)
	_hand_shade.position = Vector2(0, target_y + 62.0)
	_hand_shade.size = Vector2(size.x, maxf(size.y - _hand_shade.position.y, 1.0))
	_layout.get_node("Progress").text = "%d / %d" % [_judged_count(), NOTE_COUNT]
	_layout.get_node("Instruction").position.y = target_y + _instruction_gap
	_refresh_judgement_label(target_y)


# 点击动画先在55毫秒内放大到1.28倍，再快速回弹至原尺寸。
func _get_target_pulse_scale(lane: int) -> float:
	var age: float = _target_pulse_ages[lane]
	if age < 0.0:
		return 1.0
	if age <= CLICK_ATTACK_SECONDS:
		return lerpf(1.0, 1.28, age / CLICK_ATTACK_SECONDS)
	var release_progress := (age - CLICK_ATTACK_SECONDS) / (CLICK_PULSE_SECONDS - CLICK_ATTACK_SECONDS)
	return lerpf(1.28, 1.0, clampf(release_progress, 0.0, 1.0))


# 三种判定复用现有全大写、金绿红语义；反馈放在线下，不遮住飞来的音符。
func _refresh_judgement_label(target_y: float) -> void:
	if _judgement_text.is_empty() or _judgement_age >= JUDGEMENT_VISIBLE_SECONDS:
		_judgement_label.hide()
		return
	var color := Color(1.0, 0.4, 0.42)
	if _judgement_text == "Great":
		color = Color(1.0, 0.86, 0.3)
	elif _judgement_text == "Good":
		color = Color(0.31, 0.88, 0.42)
	color.a = 1.0 - _judgement_age / JUDGEMENT_VISIBLE_SECONDS
	_judgement_label.text = _judgement_text.to_upper()
	_judgement_label.position = Vector2(_layout.get_node("FeedbackAnchor").position.x, target_y + _feedback_gap)
	_judgement_label.size = _layout.get_node("FeedbackAnchor").size
	_judgement_label.modulate = color
	_judgement_label.show()


# 光轨、音符及命中特效使用同一透视映射；到达判定线时精确回到编辑器目标位置。
func _get_perspective_x(lane: int, y: float) -> float:
	var center_x := _get_lane_x(_get_play_area(), 1)
	var depth := lerpf(0.48, 1.0, (y + 48.0) / maxf(_target_line_y + 48.0, 1.0))
	return center_x + (_get_lane_x(_get_play_area(), lane) - center_x) * depth


# 每个轨道材质独享变形参数；渐隐尾部继续沿相同透视延伸，避免判定线处突然折断。
func _update_track_perspective(view: TextureRect, track_x: float) -> void:
	var material := view.material as ShaderMaterial
	material.set_shader_parameter("lane_offset", _get_lane_x(_get_play_area(), 1) - track_x)
	material.set_shader_parameter("rect_width", view.size.x)
	material.set_shader_parameter("target_fraction", (_target_line_y - view.position.y) / maxf(view.size.y, 1.0))

func _get_play_area() -> Rect2:
	return _layout.get_node("PlayArea").get_rect()


func _get_lane_x(_play_area: Rect2, lane: int) -> float:
	# 横向点击坐标与可编辑的目标标记共用来源，拖动目标不会让点击热区留在旧位置。
	return _target_markers[lane].get_rect().get_center().x


# QTE临时让出普通节拍与操作栏，逐节点记住原可见性；关闭后精确恢复，不统一强制打开。
func _set_battle_chrome_hidden() -> void:
	_hidden_chrome.clear()
	for path in ["RhythmFeedback", "RhythmWaveform", "RhythmAccentWaveform", "Footer", "EnergyPanel", "StatusLabel", "MonsterInfo/BehaviorPanel", "MonsterInfo/TalkingBubble"]:
		var item := get_parent().get_node_or_null(path) as CanvasItem
		if item != null:
			_hidden_chrome[item] = {"visible": item.visible, "modulate": item.modulate}
			item.modulate.a = 0.0
			item.hide()


# 正常完成和外部关闭共用恢复入口；释放宿主过程中忽略已经销毁的节点。
func _restore_chrome_when_hidden() -> void:
	if visible:
		return
	for item in _hidden_chrome:
		if is_instance_valid(item):
			item.visible = _hidden_chrome[item].visible
			item.modulate = _hidden_chrome[item].modulate
	_hidden_chrome.clear()


# 特效挂在弹窗外，末音同帧关闭QTE并交出结果，特效仍独立播放到结束。
func _spawn_note_effect(lane: int, grade: String, note_y: float) -> void:
	var effect := HIT_EFFECT.new()
	get_parent().add_child(effect)
	effect.z_index = z_index + 1
	effect.global_position = get_global_transform() * Vector2(_get_perspective_x(lane, note_y), note_y)
	effect.configure(_skill_color, grade == "Miss")
	_last_hit_effect = effect
