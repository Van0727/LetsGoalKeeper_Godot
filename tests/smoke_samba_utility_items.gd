# 桑巴通用战利品测试：验证技能计数、下一次攻击的整牌消费、独立追加打击和黄牌回合边界。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const ITEM_RUNTIME := preload("res://scripts/battle/battle_item_runtime.gd")
const ITEM_EFFECT := preload("res://scripts/items/item_effect_definition.gd")
const WISH := preload("res://data/items/item_wishing_bracelet.tres")
const FEATHER := preload("res://data/items/item_parrot_feather.tres")
const SLIPPER := preload("res://data/items/item_national_flip_flops.tres")
const CUP := preload("res://data/items/item_hercules_cup.tres")
const AXE := preload("res://data/items/item_lumberjack_axe.tres")
const SKILL := preload("res://data/cards/card_pitch_up.tres")
const ATTACK := preload("res://data/cards/card_double_banana_shot.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_skill_rewards()
	_test_cup_and_axe()
	_test_slipper_probability()
	_test_slipper_deferred_order()
	if _failed:
		quit(1)
		return
	print("smoke_samba_utility_items: PASS")
	quit()


# 第二张技能返还能量；羽毛叠层由下一张双段攻击整体消费，费用不足不消费。
func _test_skill_rewards() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(71, null, {}, [WISH, FEATHER])
	battle.enemy.max_health = 200
	battle.enemy.health = 200
	_assert_true(battle.play_card(SKILL), "首张技能牌成功")
	_assert_equal(battle.player.energy, 2, "首张技能不回能")
	_assert_true(battle.play_card(SKILL), "第二张技能牌成功")
	_assert_equal(battle.player.energy, 2, "第二张技能支付后回1能量")
	battle.player.energy = 0
	_assert_true(not battle.play_card(ATTACK), "能量不足的攻击不成功")
	_assert_equal(battle.item_runtime.counters.get("parrot_feather_bonus"), 2, "失败出牌不消费羽毛")
	battle.player.energy = 3
	_assert_true(battle.play_card(ATTACK), "双段攻击成功")
	_assert_equal(battle.enemy.health, 190, "羽毛每段各加2")
	_assert_true(not battle.item_runtime.counters.has("parrot_feather_bonus"), "攻击后清除羽毛叠层")
	battle.free()


# 十张牌充能后才翻倍；黄牌后的加伤仅在当前回合生效。
func _test_cup_and_axe() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(72, null, {}, [CUP, AXE])
	battle.enemy.max_health = 500
	battle.enemy.health = 500
	for index in range(10):
		battle.player.energy = 3
		_assert_true(battle.play_card(SKILL), "累计第%d张牌" % (index + 1))
	_assert_equal(battle.item_runtime.counters.get("hercules_cup_cards"), 10, "十牌计数封顶")
	_assert_true(battle.force_end_turn_for_red_card(), "第十张红牌后推进回合")
	_assert_true(not battle.item_runtime.counters.has("lumberjack_yellow_active"), "新回合黄牌加伤清除")
	battle.player.energy = 3
	_assert_true(battle.play_card(ATTACK), "十牌后的攻击成功")
	_assert_equal(battle.enemy.health, 488, "新回合每段3点翻倍为6")
	_assert_equal(battle.item_runtime.counters.get("hercules_cup_cards"), 1, "翻倍消费后本张攻击重新计数")
	battle.free()
	var yellow_battle = BATTLE.new()
	root.add_child(yellow_battle)
	yellow_battle.setup(74, null, {}, [AXE])
	yellow_battle.enemy.max_health = 200
	yellow_battle.enemy.health = 200
	for index in range(5):
		yellow_battle.player.energy = 3
		_assert_true(yellow_battle.play_card(SKILL), "黄牌前第%d张技能" % (index + 1))
	yellow_battle.player.energy = 3
	_assert_true(yellow_battle.play_card(ATTACK), "黄牌后的攻击成功")
	_assert_equal(yellow_battle.enemy.health, 190, "黄牌后两段各加2伤害")
	yellow_battle.free()


# 概率在每张攻击牌出牌时仅掷一次；自定义100%效果验证追加打击并检查0%不生效。
func _test_slipper_probability() -> void:
	var item = SLIPPER.duplicate(true)
	item.effects[0].chance_percent = 100
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(73, null, {}, [item])
	battle.enemy.max_health = 200
	battle.enemy.health = 200
	_assert_true(battle.play_card(ATTACK), "人字拖测试攻击")
	_assert_equal(battle.enemy.health, 189, "两段3伤害后追加一次5伤害")
	battle.free()
	var runtime = ITEM_RUNTIME.new()
	runtime.setup([SLIPPER], 74)
	var attack_context := {"card_type": 0}
	for index in range(100):
		attack_context.erase("slipper_damage")
		runtime.trigger(ITEM_EFFECT.Trigger.BEFORE_CARD_PLAYED, attack_context)
		_assert_true(float(attack_context.get("slipper_damage", 0.0)) in [0.0, 5.0], "人字拖只产生一次固定伤害")


# 实战待命中模式按两颗原球再人字拖排序，出牌瞬间不得提前扣血。
func _test_slipper_deferred_order() -> void:
	var item = SLIPPER.duplicate(true)
	item.effects[0].chance_percent = 100
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(75, null, {}, [item])
	battle.enemy.max_health = 200
	battle.enemy.health = 200
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(ATTACK, {}, true), "待命中模式的人字拖攻击")
	_assert_equal(battle.enemy.health, 200, "出牌瞬间原球和人字拖均未扣血")
	_assert_equal(events.size(), 3, "两颗原球后仅排入一次人字拖")
	_assert_equal(events[2].shot_type, 0, "人字拖不冒充原足球弹道")
	for event in events:
		_assert_true(battle.commit_deferred_damage(event), "按队列提交一段命中")
	_assert_equal(battle.enemy.health, 189, "两颗原球命中后追加5点伤害")
	battle.free()


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
