# 首轮数值平衡验收：锁定八张牌的资源数值，验证续航、多段和同向香蕉收益。
extends SceneTree

const BATTLE = preload("res://scripts/battle/battle_controller.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var amounts := {"bloodthirsty_ball": 5, "spinning_hat_trick": 4, "cutback_triangle": 5,
		"double_kick_combo": 3, "cymbal_block": 5, "reinforced_post": 6,
		"double_arm_guard": 14, "desperate_save": 5}
	for key in amounts:
		assert(load("res://data/cards/card_%s.tres" % key).effects[0].amount == amounts[key])
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(9001)
	battle.red_card_threshold = 99
	battle.enemy.health = 1000
	battle.enemy.max_health = 1000
	battle.player.health = 50
	var card = load("res://data/cards/card_bloodthirsty_ball.tres")
	assert(battle.play_card(card))
	assert(battle.enemy.health == 995 and battle.player.health == 53)
	# 连续同向香蕉只增加条件规定的2点，不因基础值调整重复放大。
	battle.set_banana_shot_direction(-1)
	battle.player.energy = 3
	assert(battle.play_card(load("res://data/cards/card_cutback_triangle.tres")))
	assert(battle.enemy.health == 990)
	assert(battle.play_card(load("res://data/cards/card_cutback_triangle.tres")))
	assert(battle.enemy.health == 983)
	battle.player.energy = 3
	assert(battle.play_card(load("res://data/cards/card_spinning_hat_trick.tres")))
	assert(battle.enemy.health == 971)
	battle.free()
	print("smoke_card_balance: PASS")
	quit()
