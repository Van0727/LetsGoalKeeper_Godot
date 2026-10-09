# 房间选曲验收：覆盖普通房恢复原鼓点、精英/Boss 固定曲、非法房型回退及循环播放/BPM同步。
extends SceneTree

const MUSIC := preload("res://scripts/battle/battle_music.gd")
const CLOCK := preload("res://scripts/battle/rhythm_clock.gd")
const SERVICE := preload("res://autoload/bgm_service.gd")
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for index in range(128):
		var stream := MUSIC.select_for_room({"type": MUSIC.MAP_STATE.RoomType.NORMAL})
		_check(stream == MUSIC.NORMAL_DRUM_2, "普通房重复进入始终使用原100 BPM鼓点")
	_check(MUSIC.select_for_room({"type": MUSIC.MAP_STATE.RoomType.ELITE}) == MUSIC.ELITE_DRUM, "精英固定曲")
	_check(MUSIC.select_for_room({"type": MUSIC.MAP_STATE.RoomType.BOSS}) == MUSIC.BOSS_DRUM, "Boss固定曲")
	for room in [{}, {"type": -1}, {"type": MUSIC.MAP_STATE.RoomType.REST}]:
		_check(MUSIC.select_for_room(room) == MUSIC.NORMAL_DRUM_2, "缺失或非战斗房型安全回退")
	var service := SERVICE.new()
	var clock := CLOCK.new()
	root.add_child(service)
	root.add_child(clock)
	for entry in [[MUSIC.NORMAL_DRUM_2, 100.0], [MUSIC.ELITE_DRUM, 81.5], [MUSIC.BOSS_DRUM, 72.0]]:
		clock.music = entry[0]
		var source_loop: bool = (clock.music as AudioStreamMP3).loop
		var player := service.start_battle_bgm(clock.music)
		_check(clock.start_music_with_player(player), "曲目加载并启动")
		_check(is_equal_approx(clock.bpm, entry[1]), "节拍速度同步所选曲目")
		_check((player.stream as AudioStreamMP3).loop, "战斗曲循环播放")
		_check((clock.music as AudioStreamMP3).loop == source_loop and player.stream != clock.music, "循环设置只修改运行副本")
	clock.free()
	service.free()
	if not _failed:
		print("smoke_battle_music: PASS")
	quit(1 if _failed else 0)


func _check(value: bool, label: String) -> void:
	if not value:
		_failed = true
		push_error(label)
