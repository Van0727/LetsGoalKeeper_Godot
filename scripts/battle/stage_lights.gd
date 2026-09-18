# 舞台灯光表现层：六个灯口保持与背景对齐，仅用音乐绝对拍数驱动摆动和拍点亮度，不参与战斗结算。
extends ColorRect

const LIGHT_SHADER := preload("res://scripts/battle/stage_lights.gdshader")
# 移动只占拍首四分之一；100 BPM 时约 0.15 秒到位，余下拍内时间保持角度以强化顿挫。
const MOVE_BEAT_FRACTION := 0.25
# 以背景原始像素测量灯口；左右各三个，第三个是桁架靠下的小灯。
const LAMP_PIXELS := [Vector2(47, 4), Vector2(195, 116), Vector2(99, 279), Vector2(895, 4), Vector2(749, 123), Vector2(842, 279)]
var _light_material: ShaderMaterial
var _angles := PackedFloat32Array()
var _pulse := 0.0
# 独立表现随机源不消耗地图、奖励或战斗随机序列；保留种子供时间回退时重放。
var _rng := RandomNumberGenerator.new()
var _sequence_seed := 0
var _beat_index := -1
var _starts := PackedFloat32Array()
var _targets := PackedFloat32Array()
var _stop_counts := PackedInt32Array()
var _moving := PackedByteArray()


# 每个战斗实例独占材质，避免多个场景或测试相互覆盖参数；不依赖 @tool 或全局类缓存。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light_material = ShaderMaterial.new()
	_light_material.shader = LIGHT_SHADER
	material = _light_material
	var origins := PackedVector2Array()
	for lamp in LAMP_PIXELS:
		origins.append(lamp / 941.0)
	_light_material.set_shader_parameter("origins", origins)
	reset_motion(_rng.seed)
	set_music_timing(0.0, 0.6, 0.025)


# 每灯每拍独立掷等概率动停；连续停两拍后强制移动，目标在安全朝内角度范围随机选择。
# 拍首四分之一平滑插值，之后保持目标角度，不重新抽签；跳帧补齐遗漏拍决策，音乐循环仍保持随机序列。
# 前奏保持初始角度；非法输入冻结角度并降为弱光，不破坏停拍计数。时间回退按种子重放。
func set_music_timing(music_time: float, beat_duration: float, first_beat_offset: float) -> void:
	var valid := is_finite(music_time) and is_finite(beat_duration) and is_finite(first_beat_offset) and beat_duration > 0.0
	var beats := (music_time - first_beat_offset) / beat_duration if valid else 0.0
	# 限制异常外部时刻引发的超大补拍循环；正常战斗可连续运行数小时。
	valid = valid and is_finite(beats) and beats < 100000.0
	if valid:
		var requested_beat := floori(beats) if beats >= 0.0 else -1
		if requested_beat < _beat_index:
			reset_motion(_sequence_seed)
		while _beat_index < requested_beat:
			_begin_next_beat()
		var progress := smoothstep(0.0, MOVE_BEAT_FRACTION, fposmod(beats, 1.0)) if requested_beat >= 0 else 0.0
		for index in range(6):
			_angles[index] = lerpf(_starts[index], _targets[index], progress)
	_pulse = pow(1.0 - fposmod(beats, 1.0), 3.0) if valid and beats >= 0.0 else 0.0
	if _light_material != null:
		_light_material.set_shader_parameter("angles", _angles)
		_light_material.set_shader_parameter("pulse", _pulse)


# 重置纯视觉序列；固定种子支持测试复现，同一场景的音乐回退不会随机跳到另一套动作。
func reset_motion(sequence_seed: int) -> void:
	_sequence_seed = sequence_seed
	_rng.seed = sequence_seed
	_beat_index = -1
	_pulse = 0.0
	_angles.clear()
	_starts.clear()
	_targets.clear()
	_stop_counts = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_moving = PackedByteArray([0, 0, 0, 0, 0, 0])
	for index in range(6):
		var initial := 0.32 if index < 3 else -0.32
		_angles.append(initial)
		_starts.append(initial)
		_targets.append(initial)


# 新拍起点是上一拍完整目标，补拍不依赖最后一帧的角度；移动至少约 0.10 弧度，避免抽中近似静止。
func _begin_next_beat() -> void:
	_beat_index += 1
	for index in range(6):
		_starts[index] = _targets[index]
		var move := _stop_counts[index] >= 2 or _rng.randi_range(0, 1) == 1
		_moving[index] = 1 if move else 0
		if not move:
			_stop_counts[index] += 1
			continue
		_stop_counts[index] = 0
		var target := _rng.randf_range(0.10, 0.54)
		if absf(target - absf(_starts[index])) < 0.10:
			target = _rng.randf_range(0.10, 0.22) if absf(_starts[index]) >= 0.32 else _rng.randf_range(0.42, 0.54)
		_targets[index] = target if index < 3 else -target


# 提供只读快照，用于验证摆动相位和失败回退，不泄露材质写入接口。
func get_light_state() -> Dictionary:
	return {"angles": _angles.duplicate(), "pulse": _pulse, "moving": _moving.duplicate(), "stop_counts": _stop_counts.duplicate(), "beat_index": _beat_index}
