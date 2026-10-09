# 战斗选曲：普通房固定使用原100 BPM鼓点，精英与 Boss 使用各自曲目；不写入本局状态。
extends RefCounted

const MAP_STATE := preload("res://scripts/map/map_state.gd")
const NORMAL_DRUM_2 := preload("res://sound/bgm/bg_basicDrum2_bpm100.mp3")
const ELITE_DRUM := preload("res://sound/bgm/bg_eliteDrum1_bpm144.mp3")
const BOSS_DRUM := preload("res://sound/bgm/bg_bossDrum1_bpm163.mp3")


# 各房型使用固定曲目；无房间的测试战斗及非法房型保留原基础鼓点。
static func select_for_room(room: Dictionary) -> AudioStream:
	match room.get("type", -1):
		MAP_STATE.RoomType.NORMAL:
			return NORMAL_DRUM_2
		MAP_STATE.RoomType.ELITE:
			return ELITE_DRUM
		MAP_STATE.RoomType.BOSS:
			return BOSS_DRUM
	return NORMAL_DRUM_2
