# 暴力流界面测试：真实战斗中蒙眼布限制手牌、换牌按钮即时可用，并兼容狼牙鼓槌停抽。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const BLIND := preload("res://data/items/item_blindfold.tres")
const WOLF := preload("res://data/items/item_spiked_drum_mallet.tres")
const BIG := preload("res://data/items/item_big_drum_mallet.tres")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	# 本进程内重置占位局，不调用存档写入接口。
	battle.run_state.start_new_run(931)
	battle.run_state.add_item(BLIND)
	battle.run_state.add_item(WOLF)
	battle.start_new_battle(TURTLE)
	await process_frame
	_assert_equal(battle.deck_state.hand.size(), 1, "蒙眼布实战手牌只有1张")
	_assert_equal(battle.controller.blindfold_charges, 3, "换牌初始3次")
	_assert_equal(battle.skill_button.text, "换牌 3/3", "主动技按钮改为换牌")
	battle._on_skill_pressed()
	_assert_equal(battle.controller.blindfold_charges, 2, "点击按钮消耗1次换牌")
	_assert_equal(battle.deck_state.hand.size(), 1, "换牌后仍只有1张手牌")
	# 直接用核心提交一张手牌，避开飞球动画；狼牙停抽后由蒙眼换牌从空手补入新牌。
	battle.controller.enemy.max_health = 500
	battle.controller.enemy.health = 500
	battle.controller.player.energy = 3
	_assert_true(battle.controller.play_card_from_hand(battle.deck_state, 0), "狼牙状态出牌")
	_assert_equal(battle.deck_state.hand.size(), 0, "狼牙鼓槌停止自动补牌")
	# 无关GM勾选只能同步效果，不能意外绕过狼牙鼓槌的停抽规则。
	battle._gm_menu_open = true
	battle.gm_items_page.show()
	var checkbox := CheckBox.new()
	battle._on_gm_item_toggled(true, BIG, checkbox)
	_assert_equal(battle.deck_state.hand.size(), 0, "勾选无关GM物品不会补牌")
	checkbox.free()
	battle._gm_menu_open = false
	battle.gm_items_page.hide()
	battle._on_skill_pressed()
	_assert_equal(battle.controller.blindfold_charges, 1, "空手换牌也消耗充能")
	_assert_equal(battle.deck_state.hand.size(), 1, "空手换牌可抽入1张，组合不卡死")
	battle.free()
	if _failed:
		quit(1)
		return
	print("smoke_drummer_violent_ui: PASS")
	quit()


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
