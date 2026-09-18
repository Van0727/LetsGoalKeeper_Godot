# 节拍同步诊断：离线解码当前鼓点，报告每拍附近的能量峰及起音；不修改音乐、配置或判定参数。
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

# 用引擎自身解码避免外部解码器的 MP3 填充差异；峰值不等于起音，二者均输出供判断。
func _run() -> void:
	var music := load("res://sound/bgm/bg_basicDrum2_bpm100.mp3") as AudioStream
	var playback := music.instantiate_playback()
	playback.start()
	var rate := AudioServer.get_mix_rate()
	var bin_frames := maxi(roundi(rate * 0.002), 1)
	var energy := PackedFloat32Array()
	for bin_index in range(ceili(7.2 * rate / bin_frames)):
		var frames := playback.mix_audio(1.0, bin_frames)
		var peak := 0.0
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		energy.append(peak)
	playback.stop()
	for beat_index in range(12):
		var target := beat_index * 0.6
		var start := maxi(floori((target - 0.15) * rate / bin_frames), 0)
		var end := mini(ceili((target + 0.15) * rate / bin_frames), energy.size() - 1)
		var peak_index := start
		for index in range(start, end + 1):
			if energy[index] > energy[peak_index]:
				peak_index = index
		var onset_index := peak_index
		while onset_index > start and energy[onset_index - 1] >= energy[peak_index] * 0.15:
			onset_index -= 1
		print("beat=%d target=%.3f onset_error_ms=%.1f peak_error_ms=%.1f peak=%.3f" % [beat_index, target, (onset_index * bin_frames / float(rate) - target) * 1000, (peak_index * bin_frames / float(rate) - target) * 1000, energy[peak_index]])
	quit()
