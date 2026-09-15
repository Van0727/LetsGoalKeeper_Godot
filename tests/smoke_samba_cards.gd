# 桑巴卡牌测试：覆盖方向比较、固定左右序列、技能蓄力、动态段数、逐段护盾和回合清理。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const BANANA := preload("res://data/cards/card_banana_shot.tres")
const OUTSIDE := preload("res://data/cards/card_outside_curve.tres")
const DUET := preload("res://data/cards/card_samba_duet.tres")
const HAT_TRICK := preload("res://data/cards/card_spinning_hat_trick.tres")
const CUTBACK := preload("res://data/cards/card_cutback_triangle.tres")
const FINALE := preload("res://data/cards/card_carnival_finale.tres")
const RAINBOW := preload("res://data/cards/card_rainbow_dribble.tres")
const SWITCH := preload("res://data/cards/card_agile_switch.tres")
const FEINT := preload("res://data/cards/card_chain_feint.tres")
const BEAT := preload("res://data/cards/card_carnival_beat.tres")
const WAVE := preload("res://data/cards/card_mexican_wave.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_direction_attacks()
	_test_skill_buffs_and_energy()
	_test_failed_attack_keeps_pending_buff()
	_test_extra_hits_and_shield()
	_test_finale_and_turn_reset()
	if _failed:
		quit(1)
		return
	print("smoke_samba_cards: PASS")
	quit()


# 左右二重奏逐颗更新方向；后续同向与反向攻击分别读取最后一颗的方向。
func _test_direction_attacks() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(901)
	battle.enemy.max_health = 200
	battle.enemy.health = 200
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(DUET), "桑巴二重奏成功")
	_assert_equal(_damage_directions(events), [-1, 1], "二重奏固定先左后右")
	_assert_equal(battle.last_banana_direction, 1, "最后方向记录右侧")
	battle.player.energy = 3
	battle.set_banana_shot_direction(-1)
	events.clear()
	_assert_true(battle.play_card(OUTSIDE), "反向外脚背成功")
	_assert_equal(_damage_amounts(events), [8], "反向外脚背获得3点加成")
	battle.player.energy = 3
	events.clear()
	_assert_true(battle.play_card(CUTBACK), "同向倒三角成功")
	_assert_equal(_damage_amounts(events), [6], "同向倒三角获得2点加成")
	battle.player.energy = 3
	events.clear()
	_assert_true(battle.play_card(HAT_TRICK), "回旋帽子戏法成功")
	_assert_equal(_damage_directions(events), [-1, 1, -1], "帽子戏法按起始方向交替")
	battle.free()


# 费用不足不是成功出牌，不能消费彩虹过人的强制香蕉与逐段加伤。
func _test_failed_attack_keeps_pending_buff() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(905)
	battle.enemy.max_health = 100
	battle.enemy.health = 100
	_assert_true(battle.play_card(RAINBOW), "失败路径前先打出彩虹过人")
	battle.player.energy = 0
	_assert_true(not battle.play_card(BANANA), "能量不足的攻击被拒绝")
	_assert_true(battle.pending_force_attack_banana, "失败攻击不消费强制香蕉")
	_assert_equal(battle.pending_next_banana_bonus, 1, "失败攻击不消费逐段加伤")
	battle.player.energy = 3
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(BANANA), "补足能量后攻击成功")
	_assert_equal(_damage_amounts(events), [7], "保留的彩虹增益在成功攻击时结算")
	battle.free()


# 彩虹强制下一张攻击变香蕉并加伤；连续假动作仅在此前已有技能时返还能量。
func _test_skill_buffs_and_energy() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(902)
	battle.enemy.max_health = 200
	battle.enemy.health = 200
	_assert_true(battle.play_card(RAINBOW), "彩虹过人成功")
	_assert_equal(battle.player.energy, 2, "彩虹过人支付1能量")
	_assert_true(battle.play_card(FEINT), "连续假动作成功")
	_assert_equal(battle.player.energy, 2, "已有技能时假动作支付后返还1能量")
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(BANANA), "蓄力后的香蕉球成功")
	_assert_equal(_damage_amounts(events), [9], "彩虹+1与假动作+2叠加到下一张香蕉球")
	_assert_true(not battle.pending_force_attack_banana, "彩虹状态由下一张攻击消费")
	battle.free()


# 狂欢节拍按技能数追加固定2伤球；人浪只在真实多段命中后逐段获得护盾。
func _test_extra_hits_and_shield() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(903)
	battle.enemy.max_health = 200
	battle.enemy.health = 200
	_assert_true(battle.play_card(BEAT), "狂欢节拍成功")
	battle.player.energy = 3
	_assert_true(battle.play_card(WAVE), "人浪助威成功")
	battle.player.energy = 3
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(BANANA, {}, true), "追加球以延迟命中模式发射")
	var damage_events := _damage_events(events)
	_assert_equal(_damage_amounts(events), [6, 2], "节拍快照为下一张香蕉追加一颗2伤球")
	_assert_equal(battle.player.shield, 0, "足球命中前不提前获得护盾")
	for event in damage_events:
		_assert_true(battle.commit_deferred_damage(event), "逐颗提交真实命中")
	_assert_equal(battle.player.shield, 2, "两颗球命中后逐段获得护盾")
	battle.free()


# 终曲按此前技能数增加段数；所有标注“本回合”的待用效果在新回合安全清除。
func _test_finale_and_turn_reset() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(904)
	battle.enemy.max_health = 500
	battle.enemy.health = 500
	_assert_true(battle.play_card(SWITCH), "灵巧换边成功")
	battle.player.energy = 3
	_assert_true(battle.play_card(BEAT), "终曲前技能一成功")
	battle.player.energy = 3
	_assert_true(battle.play_card(WAVE), "终曲前技能二成功")
	battle.player.energy = 3
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(FINALE), "嘉年华终曲成功")
	_assert_equal(_damage_amounts(events), [5, 5, 5, 5, 3, 3], "终曲与节拍追加球都获得换边的逐段加伤")
	_assert_true(battle.end_player_turn(), "正常结束玩家回合")
	_assert_equal(battle.skill_cards_played_this_turn, 0, "新回合技能计数清零")
	_assert_equal(battle.pending_turn_banana_bonus, 0, "新回合清除换边加伤")
	_assert_equal(battle.pending_turn_banana_extra_hits, 0, "新回合清除节拍追加段")
	_assert_true(not battle.pending_turn_multihit_shield, "新回合清除人浪状态")
	battle.free()


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


func _damage_directions(events: Array[Dictionary]) -> Array:
	var result := []
	for event in _damage_events(events):
		result.append(event.shot_direction)
	return result


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
