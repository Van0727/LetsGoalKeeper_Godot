# 主动技节奏弹窗：在战斗界面内遮罩原有操作，按当前BGM生成三轨四音符并汇总判定结果。
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
const WAVE_BAR_COUNT := 72
const WAVE_EDGE_COLOR := Color(0.25, 0.36, 0.78, 0.72)
const WAVE_CENTER_COLOR := Color(0.28, 0.92, 0.92, 0.94)
const QTE_CLICK_STREAM := preload("res://sound/sounds/qteClick.mp3")
const MISS_STREAM := preload("res://sound/sounds/miss.mp3")
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


# 弹窗常驻战斗UI树但默认隐藏，运行时只重绘轨道和音符，不创建或切换场景。
func _ready() -> void:
	_click_audio = _create_sfx_player("QTEClickAudio", QTE_CLICK_STREAM, 3)
	_miss_audio = _create_sfx_player("QTEMissAudio", MISS_STREAM, 4)
	hide()
	set_process(false)


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
	for note_index in range(NOTE_COUNT):
		_notes.append({
			"lane": _rng.randi_range(0, LANE_COUNT - 1),
			"target_time": _first_target_time + beat_duration * NOTE_INTERVAL_BEATS * note_index,
			"judged": false,
		})
	_running = true
	show()
	set_process(true)
	queue_redraw()
	return true


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
	queue_redraw()
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


# 绘制三条轨道、底部判定圆和活动音符；位置只由目标拍点和播放头差值决定。
func _draw() -> void:
	if not _running or _rhythm_clock == null:
		return
	var play_area := _get_play_area()
	var target_y := _target_line_y
	var beat_duration: float = _rhythm_clock.get_beat_duration()
	var travel_seconds := beat_duration * TRAVEL_BEATS
	var music_time: float = _rhythm_clock.get_music_time()
	_draw_waveform_target_line(play_area, target_y)
	for lane in range(LANE_COUNT):
		var lane_x := _get_lane_x(play_area, lane)
		draw_line(Vector2(lane_x, play_area.position.y), Vector2(lane_x, target_y), Color(0.45, 0.78, 1.0, 0.42), 3.0)
		var target_radius := TARGET_NOTE_RADIUS * _get_target_pulse_scale(lane)
		draw_circle(Vector2(lane_x, target_y), target_radius, Color(LANE_COLORS[lane], 0.32))
		draw_arc(Vector2(lane_x, target_y), target_radius, 0.0, TAU, 40, LANE_COLORS[lane], 4.0)
	for note in _notes:
		if bool(note.judged):
			continue
		var time_until_target: float = float(note.target_time) - music_time
		if time_until_target > travel_seconds or time_until_target < -_good_window_seconds:
			continue
		var progress := 1.0 - time_until_target / travel_seconds
		var lane: int = int(note.lane)
		var note_x := _get_lane_x(play_area, lane)
		var note_y := lerpf(play_area.position.y, target_y, progress)
		draw_circle(Vector2(note_x, note_y), 17.0, LANE_COLORS[lane])
		draw_arc(Vector2(note_x, note_y), 20.0, 0.0, TAU, 32, Color.WHITE, 3.0)
	_draw_judgement_feedback(target_y)


# 点击动画先在55毫秒内放大到1.28倍，再快速回弹至原尺寸。
func _get_target_pulse_scale(lane: int) -> float:
	var age: float = _target_pulse_ages[lane]
	if age < 0.0:
		return 1.0
	if age <= CLICK_ATTACK_SECONDS:
		return lerpf(1.0, 1.28, age / CLICK_ATTACK_SECONDS)
	var release_progress := (age - CLICK_ATTACK_SECONDS) / (CLICK_PULSE_SECONDS - CLICK_ATTACK_SECONDS)
	return lerpf(1.28, 1.0, clampf(release_progress, 0.0, 1.0))


# Perfect、Good、Miss短暂悬浮在横线上方，颜色沿用既有节奏反馈且不增加边框控件。
func _draw_judgement_feedback(target_y: float) -> void:
	if _judgement_text.is_empty() or _judgement_age >= JUDGEMENT_VISIBLE_SECONDS:
		return
	var color := Color(1.0, 0.4, 0.42)
	if _judgement_text == "Perfect":
		color = Color(1.0, 0.86, 0.3)
	elif _judgement_text == "Good":
		color = Color(0.35, 0.82, 1.0)
	color.a = 1.0 - _judgement_age / JUDGEMENT_VISIBLE_SECONDS
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(_judgement_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22)
	draw_string(
		font,
		Vector2((size.x - text_size.x) * 0.5, target_y - 48.0),
		_judgement_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		22,
		color
	)


# QTE横线复制原波形静止中心线的72段蓝青渐变，且宽度与波形控件的8%～92%范围一致。
func _draw_waveform_target_line(play_area: Rect2, target_y: float) -> void:
	var spacing: float = play_area.size.x / float(WAVE_BAR_COUNT)
	var bar_width: float = maxf(spacing * 0.42, 1.0)
	for bar_index in range(WAVE_BAR_COUNT):
		var normalized_x := (float(bar_index) + 0.5) / float(WAVE_BAR_COUNT)
		var center_weight := 1.0 - absf(normalized_x * 2.0 - 1.0)
		var color := WAVE_EDGE_COLOR.lerp(WAVE_CENTER_COLOR, center_weight)
		color.a *= 0.18
		var x := play_area.position.x + (float(bar_index) + 0.5) * spacing
		draw_line(Vector2(x, target_y - 0.5), Vector2(x, target_y + 0.5), color, bar_width, true)


func _get_play_area() -> Rect2:
	return Rect2(Vector2(size.x * 0.08, 36.0), Vector2(size.x * 0.84, maxf(_target_line_y - 36.0, 1.0)))


func _get_lane_x(play_area: Rect2, lane: int) -> float:
	return play_area.position.x + play_area.size.x * (float(lane) + 0.5) / LANE_COUNT
