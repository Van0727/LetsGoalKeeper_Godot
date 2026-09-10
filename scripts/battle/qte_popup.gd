# 主动技节奏弹窗：用图片节点呈现三轨四音符，判定仍严格跟随当前BGM时钟。
extends Control

signal qte_finished(result: Dictionary)
signal click_audio_triggered
signal miss_audio_triggered

const NOTE_COUNT := 4
const LANE_COUNT := 3
const TRAVEL_BEATS := 2.0
const NOTE_INTERVAL_BEATS := 0.5
const CLICK_PULSE_SECONDS := 0.18
const CLICK_ATTACK_SECONDS := 0.055
const JUDGEMENT_VISIBLE_SECONDS := 0.42
const TARGET_NOTE_RADIUS := 27.0
const TARGET_HIT_RADIUS := 42.0
const QTE_CLICK_STREAM := preload("res://sound/sounds/qteClick.mp3")
const MISS_STREAM := preload("res://sound/sounds/miss.mp3")
const LANE_TEXTURE := preload("res://assets/placeholders/qte_lane.png")
const TARGET_TEXTURE := preload("res://assets/placeholders/qte_target_ring.png")
const NOTE_TEXTURE := preload("res://assets/placeholders/qte_note.png")
const LANE_COLORS := [
	Color(1.0, 0.3, 0.42),
	Color(1.0, 0.78, 0.22),
	Color(0.25, 0.72, 1.0),
]

var _rhythm_clock: Node
var _rng := RandomNumberGenerator.new()
var _notes: Array[Dictionary] = []
var _running := false
var _first_target_time := 0.0
var _perfect_window_seconds := 0.06
var _good_window_seconds := 0.14
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


# 弹窗常驻战斗UI树但默认隐藏；图片节点预先创建并循环复用，避免QTE中途分配资源。
func _ready() -> void:
	_create_visual_nodes()
	_click_audio = _create_sfx_player("QTEClickAudio", QTE_CLICK_STREAM, 3)
	_miss_audio = _create_sfx_player("QTEMissAudio", MISS_STREAM, 4)
	hide()
	set_process(false)


# 三条轨道、目标圈和四个音符都由PNG节点承担显示，只有文字继续使用Label动态更新。
func _create_visual_nodes() -> void:
	for lane in range(LANE_COUNT):
		var lane_view := _create_texture_view("Lane%d" % lane, LANE_TEXTURE)
		var target_view := _create_texture_view("Target%d" % lane, TARGET_TEXTURE)
		target_view.modulate = LANE_COLORS[lane]
		_lane_views.append(lane_view)
		_target_views.append(target_view)
	for note_index in range(NOTE_COUNT):
		_note_views.append(_create_texture_view("Note%d" % note_index, NOTE_TEXTURE))
	_judgement_label = Label.new()
	_judgement_label.name = "JudgementFeedback"
	_judgement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_judgement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_judgement_label.add_theme_font_size_override("font_size", 22)
	add_child(_judgement_label)


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


# 以当前音乐播放头之后两个拍长作为首个判定点；速度提升1.5倍但目标仍保持逐拍间隔。
func start_qte(rhythm_clock: Node, seed_value: int = 0, target_line_y: float = 278.0) -> bool:
	if _running or rhythm_clock == null:
		return false
	_rhythm_clock = rhythm_clock
	_rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()
	_perfect_window_seconds = float(_rhythm_clock.perfect_window_ms) / 1000.0
	_good_window_seconds = float(_rhythm_clock.good_window_ms) / 1000.0
	_target_line_y = target_line_y
	var beat_duration: float = _rhythm_clock.get_beat_duration()
	var next_beat_time: float = _rhythm_clock.get_next_beat_time(_rhythm_clock.get_music_time())
	# 首个音符仍在下一个整数拍出现并完整移动两拍；只把后续目标压缩为半拍间隔。
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
	for note in _notes:
		if not bool(note.judged) and music_time > float(note.target_time) + _good_window_seconds:
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


# 同轨只判定距离当前时刻最近且仍在Good窗口内的音符；空按不会误伤其他轨道音符。
func judge_lane(lane: int, music_time_override: float = -1.0) -> String:
	if not _running or lane < 0 or lane >= LANE_COUNT:
		return ""
	var music_time: float = (
		_rhythm_clock.get_music_time() if music_time_override < 0.0 else music_time_override
	)
	var candidate: Dictionary = {}
	var closest_error := INF
	for note in _notes:
		if bool(note.judged) or int(note.lane) != lane:
			continue
		var error: float = absf(music_time - float(note.target_time))
		if error <= _good_window_seconds and error < closest_error:
			candidate = note
			closest_error = error
	if candidate.is_empty():
		_show_judgement("Miss")
		_play_miss_audio()
		return ""
	var grade := "Perfect" if closest_error <= _perfect_window_seconds else "Good"
	_apply_judgement(candidate, grade)
	return grade


func _apply_judgement(note: Dictionary, grade: String) -> void:
	note.judged = true
	note.grade = grade
	match grade:
		"Perfect":
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


# 刷新图片节点的位置与颜色；时间和判定数据保持原顺序，不参与视觉节点布局计算。
func _refresh_visual_nodes() -> void:
	if not _running or _rhythm_clock == null:
		return
	var play_area := _get_play_area()
	var target_y := _target_line_y
	var beat_duration: float = _rhythm_clock.get_beat_duration()
	var travel_seconds := beat_duration * TRAVEL_BEATS
	var music_time: float = _rhythm_clock.get_music_time()
	for lane in range(LANE_COUNT):
		var lane_x := _get_lane_x(play_area, lane)
		var lane_view := _lane_views[lane]
		lane_view.position = Vector2(lane_x - 1.5, play_area.position.y)
		lane_view.size = Vector2(3.0, target_y - play_area.position.y)
		lane_view.modulate = Color(LANE_COLORS[lane], 0.42)
		var target_radius := TARGET_NOTE_RADIUS * _get_target_pulse_scale(lane)
		var target_view := _target_views[lane]
		target_view.position = Vector2(lane_x, target_y) - Vector2.ONE * target_radius
		target_view.size = Vector2.ONE * target_radius * 2.0
		target_view.modulate = LANE_COLORS[lane]
	for note_index in range(_notes.size()):
		var note: Dictionary = _notes[note_index]
		var note_view := _note_views[note_index]
		note_view.hide()
		if bool(note.judged):
			continue
		var time_until_target: float = float(note.target_time) - music_time
		if time_until_target > travel_seconds or time_until_target < -_good_window_seconds:
			continue
		var progress := 1.0 - time_until_target / travel_seconds
		var lane: int = int(note.lane)
		var note_x := _get_lane_x(play_area, lane)
		var note_y := lerpf(play_area.position.y, target_y, progress)
		note_view.position = Vector2(note_x, note_y) - Vector2.ONE * 20.0
		note_view.size = Vector2.ONE * 40.0
		note_view.modulate = LANE_COLORS[lane]
		note_view.show()
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


# Perfect、Good、Miss由Label短暂悬浮在目标线上方，避免把动态文字烘焙进图片。
func _refresh_judgement_label(target_y: float) -> void:
	if _judgement_text.is_empty() or _judgement_age >= JUDGEMENT_VISIBLE_SECONDS:
		_judgement_label.hide()
		return
	var color := Color(1.0, 0.4, 0.42)
	if _judgement_text == "Perfect":
		color = Color(1.0, 0.86, 0.3)
	elif _judgement_text == "Good":
		color = Color(0.35, 0.82, 1.0)
	color.a = 1.0 - _judgement_age / JUDGEMENT_VISIBLE_SECONDS
	_judgement_label.text = _judgement_text
	_judgement_label.position = Vector2(0.0, target_y - 70.0)
	_judgement_label.size = Vector2(size.x, 32.0)
	_judgement_label.modulate = color
	_judgement_label.show()


func _get_play_area() -> Rect2:
	return Rect2(Vector2(size.x * 0.08, 36.0), Vector2(size.x * 0.84, maxf(_target_line_y - 36.0, 1.0)))


func _get_lane_x(play_area: Rect2, lane: int) -> float:
	return play_area.position.x + play_area.size.x * (float(lane) + 0.5) / LANE_COUNT
