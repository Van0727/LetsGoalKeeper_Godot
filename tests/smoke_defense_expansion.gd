# 九张新增防御牌验收：基础数值、连击中断、半血边界、下一张增益及失败不消费。
extends SceneTree

const BATTLE = preload("res://scripts/battle/battle_controller.gd")
const REWARDS = preload("res://scripts/rewards/reward_service.gd")

func _initialize() -> void:
	call_deferred("_run")

func _card(key: String) -> Resource:
	return load("res://data/cards/card_%s.tres" % key)

func _play(battle, key: String) -> void:
	battle.player.energy = 3
	assert(battle.play_card(_card(key)))

func _run() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(7001)
	# 本测试集中验证卡牌效果，纪律阈值由独立测试覆盖，避免第十张牌截断后续场景。
	battle.red_card_threshold = 99
	battle.enemy.health = 1000
	battle.enemy.max_health = 1000
	var defenses := 0
	for card in REWARDS.new().get_all_cards():
		if int(card.card_type) == 1:
			defenses += 1
	assert(defenses == 15)
	_play(battle, "emergency_save")
	assert(battle.player.shield == 3 and battle.player.energy == 3)
	_play(battle, "steady_position")
	assert(battle.player.shield == 11 and battle.combo_state.count == 0)
	_play(battle, "double_arm_guard")
	assert(battle.player.shield == 25 and battle.player.energy == 1)
	battle.player.health = 51
	_play(battle, "desperate_save")
	assert(battle.player.shield == 30)
	battle.player.health = 50
	_play(battle, "desperate_save")
	assert(battle.player.shield == 39)
	_play(battle, "charged_guard")
	battle.player.energy = 0
	assert(not battle.play_card(_card("gloves")))
	assert(battle.pending_next_defense_shield_bonus == 3)
	_play(battle, "perfect_block")
	assert(battle.player.shield == 51)
	_play(battle, "chain_save")
	assert(battle.player.shield == 59)
	_play(battle, "defensive_counter")
	_play(battle, "straight_shot")
	assert(battle.enemy.health == 992)
	_play(battle, "chain_save")
	assert(battle.player.shield == 68)
	_play(battle, "curve_block")
	_play(battle, "banana_shot")
	assert(battle.enemy.health == 985 and battle.pending_next_banana_bonus == 0)
	_play(battle, "goal_line_save")
	assert(battle.player.shield == 83 and battle.player.health == 53)
	_play(battle, "charged_guard")
	battle.setup(7002)
	assert(battle.pending_next_defense_shield_bonus == 0 and battle.last_played_card_type == -1)
	battle.free()
	print("smoke_defense_expansion: PASS")
	quit()
