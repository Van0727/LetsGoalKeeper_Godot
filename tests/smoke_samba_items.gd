# 桑巴奖励品测试：覆盖左右加伤、球型覆盖、连续计数、多段独立加伤及延迟命中治疗。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const ITEM_DEFINITION := preload("res://scripts/items/item_definition.gd")
const ITEM_EFFECT := preload("res://scripts/items/item_effect_definition.gd")
const ITEM_RUNTIME := preload("res://scripts/battle/battle_item_runtime.gd")
const LEFT := preload("res://data/items/item_golden_left_foot.tres")
const RIGHT := preload("res://data/items/item_golden_right_foot.tres")
const BANANA := preload("res://data/items/item_banana.tres")
const GORILLA := preload("res://data/items/item_gorilla_doll.tres")
const MASTER := preload("res://data/items/item_free_kick_master_license.tres")
const DOUBLE_BANANA := preload("res://data/cards/card_double_banana_shot.tres")
const STRAIGHT := preload("res://data/cards/card_straight_shot.tres")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const RANDOM_SHOT := preload("res://data/cards/card_barrage_shot.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_direction_and_conversion()
	_test_streak()
	_test_streak_cap_and_random_shot()
	_test_delayed_healing()
	_test_gorilla_probability()
	if _failed:
		quit(1)
		return
	print("smoke_samba_items: PASS")
	quit()


# 左右球分别计算，每张双段球每段都加 2；香蕉将原直球覆盖为实际香蕉球。
func _test_direction_and_conversion() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(101, null, {}, [LEFT, RIGHT, BANANA])
	battle.enemy.max_health = 100
	battle.enemy.health = 100
	battle.set_banana_shot_direction(-1)
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(DOUBLE_BANANA), "左香蕉球成功出牌")
	_assert_equal(battle.enemy.health, 90, "左香蕉球两段各造成5伤害")
	_assert_equal(_damage_amounts(events), [5, 5], "多段左右加成逐段独立")
	battle.player.energy = 3
	battle.set_banana_shot_direction(1)
	events.clear()
	_assert_true(battle.play_card(STRAIGHT), "原直球成功出牌")
	_assert_equal(battle.current_action_context.actual_shot_type, 2, "香蕉奖励在结算前覆盖直球")
	_assert_equal(battle.current_action_context.shot_direction, 1, "方向接口切换为右侧")
	_assert_equal(_damage_events(events)[0].shot_type, 2, "事件球型与核心球型一致")
	_assert_equal(_damage_events(events)[0].shot_direction, 1, "事件方向与核心方向一致")
	battle.free()


# 首张香蕉球无额外层数，第二张 +1；非射门不打断，其他射门打断并从 0 重新开始。
func _test_streak() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(202, null, {}, [MASTER])
	battle.enemy.max_health = 200
	battle.enemy.health = 200
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(DOUBLE_BANANA), "第一张香蕉球")
	_assert_equal(_damage_amounts(events), [3, 3], "第一张双段牌不额外加成")
	battle.player.energy = 0
	_assert_true(not battle.play_card(DOUBLE_BANANA), "费用不足不能出牌")
	_assert_equal(battle.item_runtime.counters.get("banana_streak"), 0, "失败出牌不推进连续计数")
	battle.player.energy = 3
	events.clear()
	_assert_true(battle.play_card(GLOVES), "非射门防御牌")
	battle.player.energy = 3
	events.clear()
	_assert_true(battle.play_card(DOUBLE_BANANA), "第二张香蕉球")
	_assert_equal(_damage_amounts(events), [4, 4], "连续层数按牌推进且每段生效")
	battle.player.energy = 3
	_assert_true(battle.play_card(STRAIGHT), "其他射门打断香蕉连击")
	battle.player.energy = 3
	events.clear()
	_assert_true(battle.play_card(DOUBLE_BANANA), "打断后的香蕉球")
	_assert_equal(_damage_amounts(events), [3, 3], "打断后从首张零层重新开始")
	battle.free()


# 连续层数封顶 +5；随机球型由核心先锁定，伤害事件与方向保持一致。
func _test_streak_cap_and_random_shot() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(212, null, {}, [MASTER])
	battle.enemy.max_health = 1000
	battle.enemy.health = 1000
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	for card_index in range(7):
		battle.player.energy = 3
		events.clear()
		_assert_true(battle.play_card(DOUBLE_BANANA), "连续香蕉球第%d张" % (card_index + 1))
		if card_index == 6:
			_assert_equal(_damage_amounts(events), [8, 8], "连续加成最多+5")
	_assert_equal(battle.item_runtime.counters.get("banana_streak"), 5, "运行时计数封顶5")
	battle.free()

	var random_battle = BATTLE.new()
	root.add_child(random_battle)
	random_battle.setup(213)
	random_battle.enemy.max_health = 1000
	random_battle.enemy.health = 1000
	var random_events: Array[Dictionary] = []
	random_battle.effect_resolved.connect(func(event: Dictionary) -> void: random_events.append(event))
	_assert_true(random_battle.play_card(RANDOM_SHOT), "随机球型出牌")
	for event in _damage_events(random_events):
		_assert_equal(event.shot_type, random_battle.current_action_context.actual_shot_type, "随机球型事件与核心一致")
		_assert_equal(event.shot_direction, random_battle.current_action_context.shot_direction, "随机方向事件与核心一致")
	random_battle.free()


# 用同一配置的测试副本把概率设为 100%，明确验证治疗仅在真实命中后发生。
func _test_delayed_healing() -> void:
	var guaranteed := ITEM_DEFINITION.new()
	guaranteed.item_id = "test_gorilla_guaranteed"
	var effect := ITEM_EFFECT.new()
	effect.trigger = ITEM_EFFECT.Trigger.AFTER_DAMAGE
	effect.operation = ITEM_EFFECT.Operation.EMIT_COMMAND
	effect.target_key = "gain_health"
	effect.amount = 1.0
	effect.shot_filter = ITEM_EFFECT.ShotFilter.BANANA
	effect.target_filter = ITEM_EFFECT.TargetFilter.ENEMY
	guaranteed.effects = [effect]
	_assert_equal(GORILLA.effects[0].chance_percent, 25, "正式玩偶保持25%概率")
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(303, null, {}, [guaranteed])
	battle.player.health = 90
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(DOUBLE_BANANA, {}, true), "延迟香蕉球出牌")
	_assert_equal(battle.player.health, 90, "足球飞行前不提前治疗")
	var damage_events := _damage_events(events)
	_assert_equal(damage_events.size(), 2, "双段攻击生成两个待命中事件")
	_assert_true(battle.commit_deferred_damage(damage_events[0]), "第一段命中")
	_assert_equal(battle.player.health, 91, "第一段实际命中后立即治疗")
	_assert_true(battle.commit_deferred_damage(damage_events[1]), "第二段命中")
	_assert_equal(battle.player.health, 92, "第二段独立治疗")
	_assert_true(not battle.commit_deferred_damage(damage_events[1]), "重复命中不能重复治疗")
	battle.free()


# 同种子下概率序列应一致；自伤和非香蕉球绝不进入玩偶的 25% 掷骰。
func _test_gorilla_probability() -> void:
	var first := ITEM_RUNTIME.new()
	var second := ITEM_RUNTIME.new()
	first.setup([GORILLA], 404)
	second.setup([GORILLA], 404)
	var successes := 0
	for _index in range(200):
		var context := {"shot_type": 2, "is_enemy_target": true}
		var first_triggered := first.trigger(ITEM_EFFECT.Trigger.AFTER_DAMAGE, context).size()
		var second_triggered := second.trigger(ITEM_EFFECT.Trigger.AFTER_DAMAGE, context).size()
		_assert_equal(first_triggered, second_triggered, "相同种子玩偶概率可复现")
		successes += first_triggered
	_assert_true(successes > 0 and successes < 200, "25%概率既非必发也非永不触发")
	_assert_equal(first.trigger(ITEM_EFFECT.Trigger.AFTER_DAMAGE, {"shot_type": 2, "is_enemy_target": false}).size(), 0, "自伤不触发玩偶")
	_assert_equal(first.trigger(ITEM_EFFECT.Trigger.AFTER_DAMAGE, {"shot_type": 1, "is_enemy_target": true}).size(), 0, "非香蕉球不触发玩偶")


func _damage_events(events: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if event.get("type") == "damage":
			result.append(event)
	return result


func _damage_amounts(events: Array[Dictionary]) -> Array:
	var result := []
	for event in _damage_events(events):
		result.append(event.amount)
	return result


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failed = true
		push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failed = true
		push_error("%s：条件未满足" % label)
