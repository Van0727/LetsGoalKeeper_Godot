# 本局唯一运行状态：保存跨房间数据，并提供与版本化存档服务解耦的纯数据导入/导出契约。
extends Node

signal run_changed

const MAP_GENERATOR := preload("res://scripts/map/map_generator.gd")
const MAP_STATE := preload("res://scripts/map/map_state.gd")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")

const DEFAULT_MAX_HEALTH := 100
const FINAL_CHAPTER := 3
const CHAPTER_SEED_STEP := 1000003
# 初始牌库是明确的基础构筑，不受奖励池库存影响；重复项表示实际持有张数。
const DEFAULT_DECK: Array[String] = [
	"card_straight_shot",
	"card_straight_shot",
	"card_straight_shot",
	"card_gloves",
	"card_gloves",
	"card_sports_drink",
]

# 对局状态供主菜单、战斗和独立结算界面共享；后续存档只需持久化该状态值。
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

# 恢复入口只记录安全节点所属场景，不持久化战斗中的手牌、回合等临时状态。
enum ResumePoint {
	MAP,
	BATTLE,
	REWARD,
	REST,
}

var seed := 0
var chapter := 1
var run_status := RunStatus.NOT_STARTED
var player_hp := DEFAULT_MAX_HEALTH
var max_hp := DEFAULT_MAX_HEALTH
var deck_card_ids: Array[String] = []
# 每张卡本局还能被奖励领取的次数；只保存与配表初始值不同或相同的完整快照，确保读档确定性。
var card_reward_stock: Dictionary = {}
# 战利品持有顺序使用 CSV 第一列数字 ID；英文资源键不得进入运行时状态。
var owned_item_ids: Array[int] = []
var damage_modifiers := {"all": 0, "straight": 0, "banana": 0, "lob": 0}
# 获得战利品后在本次完整游戏历程中持续生效，只有新游戏、通关或死亡后的重开才重置。
var run_max_energy_bonus := 0
var battles_won := 0
# 为兼容既有存档保留旧字段名；true 表示精英或 Boss 胜利仍有第二步奖励品尚未领取。
var pending_reward_is_boss := false
var resume_point := ResumePoint.MAP
# 独立场景与开发测试需要默认牌库；占位局不允许主菜单“继续”，正式新局或读档会清除此标记。
var is_placeholder_run := false
# 主界面测试玩法只在当前进程有效：它不进入存档契约，也不会占用路线地图或章节进度。
var is_test_battle := false
# 单局路线地图：随 start_new_run 用本局 seed 确定性生成，只在本局内修改。
var map_state: RefCounted = null


# 启动时建立仅供独立场景工作的占位局；SaveService 随后可覆盖它，菜单不会把占位局当正式存档。
func _ready() -> void:
	if deck_card_ids.is_empty():
		start_new_run(20260904)
		is_placeholder_run = true


# 新游戏彻底覆盖上一局数据，防止生命、牌库、战利品或地图残留。
func start_new_run(seed_value: int) -> void:
	is_placeholder_run = false
	is_test_battle = false
	seed = seed_value
	chapter = 1
	run_status = RunStatus.ACTIVE
	max_hp = DEFAULT_MAX_HEALTH
	player_hp = max_hp
	# 新局只装入已实装的初始牌；读档路径仍保留原ID，避免下架内容破坏旧存档。
	deck_card_ids.assign(_enabled_default_deck())
	_reset_card_reward_stock()
	owned_item_ids.clear()
	damage_modifiers = {"all": 0, "straight": 0, "banana": 0, "lob": 0}
	run_max_energy_bonus = 0
	battles_won = 0
	pending_reward_is_boss = false
	resume_point = ResumePoint.MAP
	_regenerate_map()
	run_changed.emit()


# 初始牌库允许使用奖励库存为0的开局专属牌，但仍拒绝缺失或未实装资源。
func _enabled_default_deck() -> Array[String]:
	var result: Array[String] = []
	var service = REWARD_SERVICE.new()
	for card_id in DEFAULT_DECK:
		var card: Resource = service.get_card_by_id(card_id)
		if card != null and card.enabled:
			result.append(card_id)
	return result


# 新局从卡牌资源重建奖励库存，任何上局消耗都不得跨局继承。
func _reset_card_reward_stock() -> void:
	card_reward_stock.clear()
	var service = REWARD_SERVICE.new()
	for card: Resource in service.get_all_cards():
		if card != null:
			card_reward_stock[card.card_id] = maxi(int(card.reward_stock), 0)


# 测试玩法沿用牌库与战利品运行数据，但不创建可继续的正式路线，也绝不由 SaveService 持久化。
func start_test_battle(seed_value: int) -> void:
	start_new_run(seed_value)
	is_test_battle = true
	map_state = null
	resume_point = ResumePoint.BATTLE
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


# 战斗失败只终止本局，不提交当前房间；房间上下文由战斗界面随后取消。
func mark_run_failed() -> void:
	run_status = RunStatus.FAILED
	run_changed.emit()


# 奖励卡按稳定ID加入本局牌库，允许获得重复卡牌。
func add_card(card_id: String) -> bool:
	if card_id.is_empty():
		return false
	deck_card_ids.append(card_id)
	run_changed.emit()
	return true


# 奖励确认采用“校验库存→加入牌库→扣库存”的固定顺序，失败时不产生部分消耗。
func claim_reward_card(card_id: String) -> bool:
	var remaining := int(card_reward_stock.get(card_id, 0))
	if remaining <= 0:
		return false
	if not add_card(card_id):
		return false
	card_reward_stock[card_id] = remaining - 1
	run_changed.emit()
	return true


# 战利品不可重复；拾取时把固定定义的伤害与游戏历程级能量上限立即汇总。
func add_item(item: Resource) -> bool:
	if item == null or item.id in owned_item_ids or not item.enabled:
		return false
	owned_item_ids.append(item.id)
	var modifier_key: String = item.get_modifier_key()
	if not modifier_key.is_empty():
		damage_modifiers[modifier_key] = damage_modifiers.get(modifier_key, 0) + item.amount
	run_max_energy_bonus += maxi(int(item.run_max_energy_bonus), 0)
	run_changed.emit()
	return true


# GM 取消勾选只移除指定已拥有战利品，并撤销它贡献的静态伤害及游戏历程级能量上限。
# 新式触发效果由当前 BattleItemRuntime 同步移除；存档只保存唯一数字 ID。
func remove_item(item: Resource) -> bool:
	if item == null or item.id not in owned_item_ids:
		return false
	owned_item_ids.erase(item.id)
	var modifier_key: String = item.get_modifier_key()
	if not modifier_key.is_empty():
		damage_modifiers[modifier_key] = maxi(int(damage_modifiers.get(modifier_key, 0)) - item.amount, 0)
	run_max_energy_bonus = maxi(run_max_energy_bonus - maxi(int(item.run_max_energy_bonus), 0), 0)
	run_changed.emit()
	return true


# 完成当前战斗的全部奖励后推进房间计数；普通怪为卡牌，精英和 Boss 还包含奖励品。
func complete_reward() -> void:
	battles_won += 1
	pending_reward_is_boss = false
	run_changed.emit()


# 当前奖励完成后原子提交房间；只有 Boss 房在奖励完成后按章节进入下一地图或整局通关。
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


# 导出仅包含 JSON 可表达的稳定字段；战斗临时态不属于安全节点存档范围。
func to_dict() -> Dictionary:
	return {
		"seed": seed,
		"chapter": chapter,
		"run_status": run_status,
		"player_hp": player_hp,
		"max_hp": max_hp,
		"deck_card_ids": deck_card_ids.duplicate(),
		"card_reward_stock": card_reward_stock.duplicate(true),
		"owned_item_ids": owned_item_ids.duplicate(),
		"damage_modifiers": damage_modifiers.duplicate(true),
		"run_max_energy_bonus": run_max_energy_bonus,
		"battles_won": battles_won,
		"pending_reward_is_boss": pending_reward_is_boss,
		"resume_point": resume_point,
		"map_state": map_state.to_dict() if map_state != null else null,
	}


# 从版本迁移后的字典恢复完整本局；缺失字段采用安全默认值，避免旧档或残缺字段阻止启动。
func from_dict(data: Dictionary) -> bool:
	is_placeholder_run = false
	seed = int(data.get("seed", 0))
	chapter = clampi(int(data.get("chapter", 1)), 1, FINAL_CHAPTER)
	run_status = clampi(int(data.get("run_status", RunStatus.NOT_STARTED)), RunStatus.NOT_STARTED, RunStatus.COMPLETED)
	max_hp = maxi(int(data.get("max_hp", DEFAULT_MAX_HEALTH)), 1)
	player_hp = clampi(int(data.get("player_hp", max_hp)), 0, max_hp)
	deck_card_ids = _string_array(data.get("deck_card_ids", DEFAULT_DECK))
	card_reward_stock = _reward_stock_dictionary(data.get("card_reward_stock", null))
	owned_item_ids = _positive_int_array(data.get("owned_item_ids", []))
	var saved_modifiers: Dictionary = data.get("damage_modifiers", {}) if data.get("damage_modifiers", {}) is Dictionary else {}
	damage_modifiers = {
		"all": int(saved_modifiers.get("all", 0)),
		"straight": int(saved_modifiers.get("straight", 0)),
		"banana": int(saved_modifiers.get("banana", 0)),
		"lob": int(saved_modifiers.get("lob", 0)),
	}
	run_max_energy_bonus = maxi(int(data.get("run_max_energy_bonus", 0)), 0)
	battles_won = maxi(int(data.get("battles_won", 0)), 0)
	pending_reward_is_boss = bool(data.get("pending_reward_is_boss", false))
	resume_point = clampi(int(data.get("resume_point", ResumePoint.MAP)), ResumePoint.MAP, ResumePoint.REST)
	var saved_map: Variant = data.get("map_state")
	if saved_map is Dictionary:
		map_state = MAP_STATE.new()
		map_state.from_dict(saved_map)
	else:
		map_state = null
	run_changed.emit()
	return true


# 旧档缺少库存时按当前配表初始化；新档只接纳已知卡牌的非负整数并以配表上限封顶。
func _reward_stock_dictionary(value: Variant) -> Dictionary:
	_reset_card_reward_stock()
	if value is not Dictionary:
		return card_reward_stock.duplicate(true)
	var restored := card_reward_stock.duplicate(true)
	for card_id in restored:
		if not value.has(card_id):
			continue
		var raw_value: Variant = value[card_id]
		if (raw_value is int or raw_value is float) and not raw_value is bool:
			restored[card_id] = clampi(int(raw_value), 0, int(restored[card_id]))
	return restored


# JSON 数组恢复为强类型稳定 ID 数组，并忽略无法转换为有效 ID 的异常项。
func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is not Array:
		return result
	for entry in value:
		if entry is String and not entry.is_empty():
			result.append(entry)
	return result


# JSON 数值统一显式转回整数；布尔、字符串、零和负数均视为损坏字段并忽略。
func _positive_int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is not Array:
		return result
	for entry in value:
		if (entry is int or entry is float) and not entry is bool:
			var item_id := int(entry)
			if item_id > 0 and item_id not in result:
				result.append(item_id)
	return result
