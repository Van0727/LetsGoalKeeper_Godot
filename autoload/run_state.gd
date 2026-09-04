# 本局唯一运行状态：保存跨房间生命、牌库ID、战利品ID、伤害加成、流程进度和地图状态。
extends Node

signal run_changed

const MAP_GENERATOR := preload("res://scripts/map/map_generator.gd")
const MAP_STATE := preload("res://scripts/map/map_state.gd")

const DEFAULT_MAX_HEALTH := 100
const FINAL_CHAPTER := 3
const CHAPTER_SEED_STEP := 1000003
const DEFAULT_DECK: Array[String] = [
	"card_straight_shot", "card_straight_shot", "card_straight_shot", "card_straight_shot",
	"card_gloves", "card_gloves", "card_sports_drink", "card_towel",
]

# 对局状态预留给主菜单、结局和后续存档；本任务先接入进行中与通关两条路径。
enum RunStatus {
	NOT_STARTED,
	ACTIVE,
	FAILED,
	COMPLETED,
}

# 奖励结算结果由界面负责映射到场景，避免 RunState 直接依赖具体 UI 文件。
enum RewardFlowResult {
	NO_MAP,
	MAP_CONTINUES,
	CHAPTER_ADVANCED,
	RUN_COMPLETED,
}

var seed := 0
var chapter := 1
var run_status := RunStatus.NOT_STARTED
var player_hp := DEFAULT_MAX_HEALTH
var max_hp := DEFAULT_MAX_HEALTH
var deck_card_ids: Array[String] = []
var owned_item_ids: Array[String] = []
var damage_modifiers := {"all": 0, "straight": 0, "banana": 0, "lob": 0}
var battles_won := 0
var pending_reward_is_boss := false
# 单局路线地图：随 start_new_run 用本局 seed 确定性生成，只在本局内修改。
var map_state: RefCounted = null


# 首次启动若没有本局数据则建立默认新游戏，后续场景切换不会重复重置。
func _ready() -> void:
	if deck_card_ids.is_empty():
		start_new_run(20260904)


# 新游戏彻底覆盖上一局数据，防止生命、牌库、战利品或地图残留。
func start_new_run(seed_value: int) -> void:
	seed = seed_value
	chapter = 1
	run_status = RunStatus.ACTIVE
	max_hp = DEFAULT_MAX_HEALTH
	player_hp = max_hp
	deck_card_ids.assign(DEFAULT_DECK)
	owned_item_ids.clear()
	damage_modifiers = {"all": 0, "straight": 0, "banana": 0, "lob": 0}
	battles_won = 0
	pending_reward_is_boss = false
	_regenerate_map()
	run_changed.emit()


# 用本局 seed 生成当前章节地图；配置缺失时保持无地图，由界面提示而不是静默崩溃。
func _regenerate_map() -> void:
	var generator = MAP_GENERATOR.new()
	var config: Resource = generator.load_config_for_chapter(chapter)
	if config == null:
		map_state = null
		return
	var rng := RandomNumberGenerator.new()
	# 每章从同一本局 seed 派生独立地图，同时保持相同 seed 的完整流程可复现。
	rng.seed = seed + (chapter - 1) * CHAPTER_SEED_STEP
	map_state = generator.generate(config, rng)


# 战斗结束只写回跨房间生命；失败时生命允许保持为0。
func record_battle_health(health: int) -> void:
	player_hp = clampi(health, 0, max_hp)
	run_changed.emit()


# 奖励卡按稳定ID加入本局牌库，允许获得重复卡牌。
func add_card(card_id: String) -> bool:
	if card_id.is_empty():
		return false
	deck_card_ids.append(card_id)
	run_changed.emit()
	return true


# 战利品不可重复；拾取时把固定定义的加成立即汇总到本局数值。
func add_item(item: Resource) -> bool:
	if item == null or item.item_id in owned_item_ids or not item.enabled:
		return false
	owned_item_ids.append(item.item_id)
	var modifier_key: String = item.get_modifier_key()
	if not modifier_key.is_empty():
		damage_modifiers[modifier_key] = damage_modifiers.get(modifier_key, 0) + item.amount
	run_changed.emit()
	return true


# 完成卡牌和战利品两步奖励后推进房间计数，下一战据此选择敌人。
func complete_reward() -> void:
	battles_won += 1
	pending_reward_is_boss = false
	run_changed.emit()


# 两步奖励完成后原子提交房间；Boss 房再按章节进入下一地图或整局通关。
# 结算顺序固定为：奖励入账 → 胜场增加 → 房间完成 → 章节推进，防止中途状态被误判为可继续。
func complete_reward_and_advance() -> int:
	battles_won += 1
	pending_reward_is_boss = false
	if map_state == null or map_state.current_room_id.is_empty():
		run_changed.emit()
		return RewardFlowResult.NO_MAP

	var completed: Dictionary = map_state.complete_current_room()
	if completed.is_empty():
		run_changed.emit()
		return RewardFlowResult.NO_MAP
	if completed.type != MAP_STATE.RoomType.BOSS:
		run_changed.emit()
		return RewardFlowResult.MAP_CONTINUES

	if chapter < FINAL_CHAPTER:
		chapter += 1
		_regenerate_map()
		run_changed.emit()
		return RewardFlowResult.CHAPTER_ADVANCED

	run_status = RunStatus.COMPLETED
	run_changed.emit()
	return RewardFlowResult.RUN_COMPLETED


# 基础治疗入口：恢复指定生命但不超过上限，返回实际恢复量。
func heal_run(amount: int) -> int:
	var healed := mini(max_hp - player_hp, maxi(amount, 0))
	player_hp += healed
	run_changed.emit()
	return healed


# 使用当前休息房的唯一治疗机会；使用记录先写入地图状态，场景重载也不能重复领取。
func use_current_rest(amount: int) -> int:
	if map_state == null or not map_state.mark_current_rest_used():
		return 0
	return heal_run(amount)


# 房间内容结算成功后统一提交路线推进，避免战斗失败或奖励未完成时提前解锁。
func complete_current_room() -> Dictionary:
	if map_state == null:
		return {}
	var completed: Dictionary = map_state.complete_current_room()
	if not completed.is_empty():
		run_changed.emit()
	return completed


# 放弃进行中的房间但不改变路线三态，供战斗失败或主动退出清理临时上下文。
func cancel_current_room() -> bool:
	if map_state == null:
		return false
	var cancelled: bool = map_state.cancel_current_room()
	if cancelled:
		run_changed.emit()
	return cancelled


# 返回当前正在进行的房间；没有地图或尚未进入房间时返回空字典。
func get_current_room() -> Dictionary:
	if map_state == null:
		return {}
	var room_id: String = map_state.current_room_id
	if room_id.is_empty():
		return {}
	return map_state.room_by_id(room_id)
