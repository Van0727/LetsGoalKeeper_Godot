# 鼓手节奏流测试：覆盖BGM拍位与细分阈值、多段连拍、耳返和三类完美主动技。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const ITEM_RUNTIME := preload("res://scripts/battle/battle_item_runtime.gd")
const ITEM_EFFECT := preload("res://scripts/items/item_effect_definition.gd")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const ROTATING := preload("res://data/items/item_rotating_drums.tres")
const ISOLATION := preload("res://data/items/item_drum_isolation_screen.tres")
const RACING := preload("res://data/items/item_racing_drumsticks.tres")
const TROPHY := preload("res://data/items/item_rhythm_game_trophy.tres")
const DOUBLE_PEDAL := preload("res://data/items/item_double_bass_pedal.tres")
const IN_EAR := preload("res://data/items/item_in_ear_monitor.tres")
const BANANA := preload("res://data/cards/card_double_banana_shot.tres")
const STRAIGHT := preload("res://data/cards/card_straight_shot.tres")
const SUPER_ATTACK := preload("res://data/skills/skill_super_attack.tres")
const SUPER_DEFENSE := preload("res://data/skills/skill_super_defense.tres")
const SUPER_ABILITY := preload("res://data/skills/skill_super_ability.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_reward_catalog_and_shields()
	_test_racing_and_rapid_hits()
	_test_in_ear_monitor()
	_test_perfect_skills()
	if _failed:
		quit(1)
		return
	print("smoke_drummer_rhythm_items: PASS")
	quit()


# 第一回合在清盾后加盾；末拍由BGM采样标记控制，非末拍和缺省拍位不触发。
func _test_reward_catalog_and_shields() -> void:
	var ids: Array[String] = []
	for item in REWARD_SERVICE.new().get_all_items():
		ids.append(item.item_id)
	for item in [ROTATING, ISOLATION, RACING, TROPHY, DOUBLE_PEDAL, IN_EAR]:
		_assert_true(item.item_id in ids, "%s已登记到GM奖励目录" % item.display_name)
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(810, null, {}, [ISOLATION])
	_assert_equal(battle.player.shield, 5, "首回合开始时获得5护盾")
	battle.enemy_intent_damage = 0
	_assert_true(battle.end_player_turn(), "结束首回合")
	_assert_equal(battle.player.shield, 0, "第二回合不重复获得隔音屏护盾")
	battle.free()
	var runtime = ITEM_RUNTIME.new()
	runtime.setup([ROTATING], 811)
	_assert_equal(runtime.trigger(ITEM_EFFECT.Trigger.TURN_ENDED, {}).size(), 0, "无BGM拍位不触发回转鼓组")
	_assert_equal(runtime.trigger(ITEM_EFFECT.Trigger.TURN_ENDED, {"is_last_beat": false}).size(), 0, "非末拍不触发回转鼓组")
	var commands: Array[Dictionary] = runtime.trigger(ITEM_EFFECT.Trigger.TURN_ENDED, {"is_last_beat": true})
	_assert_equal(commands.size(), 1, "末拍结束回合发出一次护盾命令")
	_assert_equal(commands[0].amount, 3.0, "末拍获得3护盾")
	var end_battle = BATTLE.new()
	root.add_child(end_battle)
	end_battle.setup(819, null, {}, [ROTATING])
	end_battle.enemy_intent_damage = 8
	_assert_true(end_battle.end_player_turn({"beat_in_bar": 3, "is_last_beat": true}), "末拍结束回合")
	_assert_equal(end_battle.player.health, 95, "末拍3护盾在敌人8伤害前即时生效")
	end_battle.free()


# 1/8及更快才加伤；连拍按同一牌的BGM击打间隔逐段递增而非玩家出牌速度。
func _test_racing_and_rapid_hits() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(812, null, {}, [RACING, DOUBLE_PEDAL])
	battle.enemy.max_health = 200
	battle.enemy.health = 200
	_assert_true(battle.play_card(BANANA, {"grade": 0, "effect_multiplier": 1.0, "subdivision": 8}), "八分细分双段攻击")
	_assert_equal(battle.enemy.health, 189, "两段分别5点和6点伤害")
	battle.player.energy = 3
	_assert_true(battle.play_card(BANANA, {"grade": 0, "effect_multiplier": 1.0, "subdivision": 4}), "四分细分双段攻击")
	_assert_equal(battle.enemy.health, 180, "四分细分不触发竞速鼓棒但仍触发连拍")
	battle.free()
	var long_interval = BANANA.duplicate(true)
	long_interval.multi_hit_interval_beats = 1.0
	var slow_battle = BATTLE.new()
	root.add_child(slow_battle)
	slow_battle.setup(813, null, {}, [DOUBLE_PEDAL])
	slow_battle.enemy.max_health = 100
	slow_battle.enemy.health = 100
	_assert_true(slow_battle.play_card(long_interval), "整拍间隔多段攻击")
	_assert_equal(slow_battle.enemy.health, 94, "整拍间隔不触发双踩")
	slow_battle.free()
	var pedal_runtime = ITEM_RUNTIME.new()
	pedal_runtime.setup([DOUBLE_PEDAL], 820)
	var fifth_hit := {"amount": 3.0, "hit": 5, "rapid_hits": true, "is_enemy_target": true}
	pedal_runtime.trigger(ITEM_EFFECT.Trigger.BEFORE_DAMAGE, fifth_hit)
	_assert_equal(fifth_hit.amount, 7.0, "第五段及以后双踩加伤封顶4")


# 耳返只覆盖成功出牌的本次判定，取消GM勾选后Miss减伤立即恢复。
func _test_in_ear_monitor() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(814, null, {}, [IN_EAR])
	battle.enemy.max_health = 100
	battle.enemy.health = 100
	var miss := {"grade": 2, "grade_name": "Miss", "effect_multiplier": 0.5, "error_ms": 200.0, "beat_index": 2}
	_assert_true(battle.play_card(STRAIGHT, miss), "持耳返的Miss出牌")
	_assert_equal(battle.enemy.health, 94, "耳返将Miss伤害改为Perfect伤害")
	_assert_equal(battle.current_action_context.rhythm_result.grade, 0, "结算上下文记录Perfect")
	_assert_equal(miss.grade, 2, "调用方原始判定不被修改")
	var none: Array[Resource] = []
	battle.debug_sync_items(none, {})
	battle.player.energy = 3
	_assert_true(battle.play_card(STRAIGHT, miss), "取消耳返后再次出牌")
	_assert_equal(battle.enemy.health, 91, "取消后Miss重新按半伤结算")
	battle.free()


# 音游奖杯仅四次全Perfect才翻倍；攻击、护盾和强化倍率翻倍，持续回合保持不变。
func _test_perfect_skills() -> void:
	var perfect := {"perfect": 4, "good": 0, "miss": 0}
	var partial := {"perfect": 3, "good": 1, "miss": 0}
	var attack = BATTLE.new()
	root.add_child(attack)
	attack.setup(815, null, {}, [TROPHY])
	attack.enemy.max_health = 200
	attack.enemy.health = 200
	for index in range(3):
		attack.combo_state.register_card(0)
	_assert_true(attack.play_active_skill(SUPER_ATTACK, perfect), "完美攻击主动技")
	_assert_equal(attack.enemy.health, 140, "30点攻击翻倍为60点")
	attack.free()
	var defense = BATTLE.new()
	root.add_child(defense)
	defense.setup(816, null, {}, [TROPHY])
	for index in range(3):
		defense.combo_state.register_card(1)
	_assert_true(defense.play_active_skill(SUPER_DEFENSE, perfect), "完美防御主动技")
	_assert_equal(defense.player.shield, 36, "18点护盾翻倍为36点")
	defense.free()
	var ability = BATTLE.new()
	root.add_child(ability)
	ability.setup(817, null, {}, [TROPHY])
	for index in range(3):
		ability.combo_state.register_card(2)
	_assert_true(ability.play_active_skill(SUPER_ABILITY, perfect), "完美技能主动技")
	_assert_equal(ability.player.strength_multiplier, 3.0, "强化倍率数值翻倍")
	_assert_equal(ability.player.strength_turns, 3, "强化持续回合不翻倍")
	ability.free()
	var imperfect = BATTLE.new()
	root.add_child(imperfect)
	imperfect.setup(818, null, {}, [TROPHY])
	imperfect.enemy.max_health = 200
	imperfect.enemy.health = 200
	for index in range(3):
		imperfect.combo_state.register_card(0)
	_assert_true(imperfect.play_active_skill(SUPER_ATTACK, partial), "非全Perfect主动技仍释放")
	_assert_equal(imperfect.enemy.health, 170, "Good一次不触发音游奖杯")
	imperfect.free()


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
