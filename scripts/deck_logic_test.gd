# 牌堆人工测试场景：展示固定牌库的抽取、出牌补牌、弃牌和回洗结果。
extends Control

const DECK_STATE := preload("res://scripts/cards/deck_state.gd")
const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const BANANA_SHOT := preload("res://data/cards/card_banana_shot.tres")
const LOB_SHOT := preload("res://data/cards/card_lob_shot.tres")
const BARRAGE_SHOT := preload("res://data/cards/card_barrage_shot.tres")
const ATTACK_AND_DEFEND := preload("res://data/cards/card_attack_and_defend.tres")
const EXPLOSION_BALL := preload("res://data/cards/card_explosion_ball.tres")
const ENERGY_SHOT := preload("res://data/cards/card_energy_shot.tres")
const RUN_UP := preload("res://data/cards/card_run_up.tres")
const WEAKNESS := preload("res://data/cards/card_weakness.tres")
const SHOT_GROUP := preload("res://data/cards/card_shot_group.tres")
const DOUBLE_BANANA_SHOT := preload("res://data/cards/card_double_banana_shot.tres")
const BLOODTHIRSTY_BALL := preload("res://data/cards/card_bloodthirsty_ball.tres")
const SPIKED_BALL := preload("res://data/cards/card_spiked_ball.tres")
const RUGBY_BALL := preload("res://data/cards/card_rugby_ball.tres")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const SPORTS_DRINK := preload("res://data/cards/card_sports_drink.tres")
const TOWEL := preload("res://data/cards/card_towel.tres")
const TEST_SEED := 20260902

@onready var zone_status: Label = %ZoneStatus
@onready var hand_status: Label = %HandStatus
@onready var deck_log: TextEdit = %DeckLog

var _deck = DECK_STATE.new()


# 场景加载时建立固定种子的测试牌堆。
func _ready() -> void:
	_reset_deck()


# 抽三张牌并刷新牌区数量。
func _on_draw_pressed() -> void:
	var drawn := _deck.draw_cards(3)
	_log("抽取 %d 张：%s" % [drawn.size(), _card_names(drawn)])
	_refresh_status()


# 打出第一张手牌并验证原位置补牌行为。
func _on_play_pressed() -> void:
	var played := _deck.play_card_at(0)
	if played == null:
		_log("手牌为空，无法出牌")
	else:
		_log("打出 %s，并尝试在原位置补1张" % played.display_name)
	_refresh_status()


# 模拟回合结束并弃掉所有手牌。
func _on_end_turn_pressed() -> void:
	var count := _deck.discard_hand()
	_log("回合结束，弃掉 %d 张手牌" % count)
	_refresh_status()


# 使用相同种子重建牌堆，便于人工对比确定性顺序。
func _on_reset_pressed() -> void:
	_reset_deck()


# 返回迁移测试版主菜单。
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# 创建包含当前已迁移卡牌的测试牌库。
func _reset_deck() -> void:
	deck_log.clear()
	var definitions: Array[Resource] = [
		STRAIGHT_SHOT,
		STRAIGHT_SHOT,
		BANANA_SHOT,
		LOB_SHOT,
		BARRAGE_SHOT,
		ATTACK_AND_DEFEND,
		EXPLOSION_BALL,
		ENERGY_SHOT,
		RUN_UP,
		WEAKNESS,
		SHOT_GROUP,
		DOUBLE_BANANA_SHOT,
		BLOODTHIRSTY_BALL,
		SPIKED_BALL,
		RUGBY_BALL,
		GLOVES,
		SPORTS_DRINK,
		TOWEL,
	]
	_deck.setup(definitions, TEST_SEED)
	_log("牌堆已按固定 seed 初始化")
	_refresh_status()


# 同步抽牌堆、弃牌堆和手牌的界面状态。
func _refresh_status() -> void:
	zone_status.text = "抽牌堆 %d　弃牌堆 %d　手牌 %d" % [
		_deck.draw_pile.size(),
		_deck.discard_pile.size(),
		_deck.hand.size(),
	]
	hand_status.text = "手牌：%s" % _card_names(_deck.hand)


# 将卡牌数组转换为中文名称列表。
func _card_names(cards: Array[Resource]) -> String:
	var names: PackedStringArray = []
	for card in cards:
		names.append(card.display_name)
	return "、".join(names) if not names.is_empty() else "无"


# 追加一条牌堆操作日志并滚动到底部。
func _log(message: String) -> void:
	deck_log.text += message + "\n"
	deck_log.scroll_vertical = deck_log.get_line_count()
