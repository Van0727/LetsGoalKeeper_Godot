# 本局唯一运行状态：保存跨房间生命、牌库ID、战利品ID、伤害加成和流程进度。
extends Node

signal run_changed

const DEFAULT_MAX_HEALTH := 100
const DEFAULT_DECK: Array[String] = [
	"card_straight_shot", "card_straight_shot", "card_straight_shot", "card_straight_shot",
	"card_gloves", "card_gloves", "card_sports_drink", "card_towel",
]

var seed := 0
var chapter := 1
var player_hp := DEFAULT_MAX_HEALTH
var max_hp := DEFAULT_MAX_HEALTH
var deck_card_ids: Array[String] = []
var owned_item_ids: Array[String] = []
var damage_modifiers := {"all": 0, "straight": 0, "banana": 0, "lob": 0}
var battles_won := 0
var pending_reward_is_boss := false


# 首次启动若没有本局数据则建立默认新游戏，后续场景切换不会重复重置。
func _ready() -> void:
	if deck_card_ids.is_empty():
		start_new_run(20260904)


# 新游戏彻底覆盖上一局数据，防止生命、牌库或战利品残留。
func start_new_run(seed_value: int) -> void:
	seed = seed_value
	chapter = 1
	max_hp = DEFAULT_MAX_HEALTH
	player_hp = max_hp
	deck_card_ids.assign(DEFAULT_DECK)
	owned_item_ids.clear()
	damage_modifiers = {"all": 0, "straight": 0, "banana": 0, "lob": 0}
	battles_won = 0
	pending_reward_is_boss = false
	run_changed.emit()


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
