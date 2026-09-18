# 第一章怪物行为验收：正常循环、格挡边界、流血致死、有限反伤、多入口蓄力打断及随机确定性。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const CATALOG := preload("res://data/enemies/enemy_catalog.tres")
const STATE := preload("res://scripts/battle/combatant_state.gd")
const BARRAGE := preload("res://data/cards/card_barrage_shot.tres")
const GROUP := preload("res://data/cards/card_shot_group.tres")
const SKILL := preload("res://data/skills/skill_super_attack.tres")
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_chicken_and_bleed()
	_test_turtle_and_rabbit()
	_test_boar_charge()
	_test_elephant_charge()
	_test_thorns_and_death()
	_test_random_mode()
	print("smoke_chapter_one_monsters: %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _battle(id: int) -> Node:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(918, CATALOG.find_enemy(id))
	return battle


func _test_chicken_and_bleed() -> void:
	var battle = _battle(6001)
	_check(battle.get_enemy_intent_damage() == 5, "鸡第一行为伤害5")
	battle.end_player_turn()
	_check(battle.player.health == 95 and battle.current_enemy_action.id == 2, "固定列表推进至撕裂")
	battle.end_player_turn()
	_check(battle.player.health == 92 and battle.player.bleed_turns == 2, "伤害后施加流血，不在施加时立刻跳血")
	battle.player.gain_shield(2)
	battle.end_player_turn()
	_check(battle.player.health == 92 and battle.player.bleed_turns == 1, "流血可被护盾吸收且计时推进")
	_check(battle.enemy.shield == 5 and battle.current_enemy_action.id == 1, "防御只获得护盾并循环")
	battle.end_player_turn()
	_check(battle.player.health == 85 and battle.player.bleed_turns == 0, "第二次流血后到期，随后执行普通攻击")
	battle.free()
	var state = STATE.new("流血测试", 20)
	state.apply_bleed(2, 2)
	state.apply_bleed(1, 3)
	state.apply_bleed(0, 99)
	_check(state.bleed_amount == 2 and state.bleed_turns == 3, "重复流血不累加，非法参数忽略")
	state.single_block = 5
	state.tick_bleed()
	_check(state.health == 18 and state.single_block == 5, "流血不消耗攻击格挡")
	battle = _battle(6001)
	battle.player.health = 1
	battle.player.apply_bleed(2, 1)
	battle.end_player_turn()
	_check(battle.phase == battle.Phase.FINISHED and battle.turn_number == 1 and battle.enemy.shield == 0, "流血致死停止敌方行动与下一回合")
	battle.free()


func _test_turtle_and_rabbit() -> void:
	var battle = _battle(6002)
	battle.end_player_turn()
	_check(battle.enemy.shield == 8 and battle.enemy.single_block == 4 and battle.player.health == 100, "缩壳执行多个防御效果，仍是单次行为")
	battle.player_attack(0)
	_check(battle.enemy.single_block == 4, "零伤害不能消费格挡")
	battle.play_card(BARRAGE)
	_check(battle.enemy.single_block == 0 and battle.enemy.health == 35, "首段3被格挡，后续9先扣8盾再扣1血")
	battle.end_player_turn()
	_check(battle.player.health == 94 and battle.enemy.shield == 0, "怪物行动开始清除护盾与架势")
	battle.free()
	battle = _battle(6003)
	for id in [6, 6, 7, 6]:
		_check(battle.current_enemy_action.id == id, "固定列表允许重复行为")
		battle.end_player_turn()
	_check(battle.player.health == 82, "兔子多段攻击正确结算")
	battle.free()


# 正常失败路径保留重炮；同步伤害、延迟命中、主动技均由真实受伤入口统计。
func _test_boar_charge() -> void:
	var battle = _battle(6011)
	battle.end_player_turn()
	battle.end_player_turn()
	_check(battle.current_enemy_action.id == 10 and battle.enemy_charge_threshold == 3, "蓄力后展示重炮")
	battle.player_attack(1)
	battle.player_attack(1)
	_check(not battle.enemy_charge_interrupted, "2次命中未达阈值")
	var hp: int = battle.player.health
	battle.end_player_turn()
	_check(battle.player.health == hp - 18 and battle.enemy_charge_rule == 0, "未打断执行18伤害并清空蓄力")
	battle.free()
	battle = _battle(6011)
	battle.end_player_turn()
	battle.end_player_turn()
	var deferred: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void:
		if event.get("deferred_damage", false):
			deferred.append(event)
	)
	battle.play_card(GROUP, {}, true)
	_check(battle.enemy_charge_progress == 0 and deferred.size() == 4, "出牌未命中不能提前打断")
	for index in range(3):
		battle.commit_deferred_damage(deferred[index])
	_check(battle.enemy_charge_interrupted and battle.current_enemy_action.id == 11, "第三次真实命中立即替换意图")
	_check("已打断" in battle.get_enemy_intent_text() and battle.get_enemy_intent_damage() == 6, "取消后的意图与伤害一致")
	battle.commit_deferred_damage(deferred[3])
	hp = battle.player.health
	battle.end_player_turn()
	_check(battle.player.health == hp - 6 and battle.current_enemy_action.id == 8, "替代行为只执行一次，原列表继续推进")
	battle.free()
	battle = _battle(6011)
	battle.end_player_turn()
	battle.end_player_turn()
	battle.combo_state.register_card(0)
	battle.combo_state.register_card(0)
	battle.combo_state.register_card(0)
	battle.play_active_skill(SKILL)
	_check(battle.enemy_charge_progress == 1, "主动技一次伤害只算一次命中")
	battle.player_attack(1, "item")
	battle.player_attack(1)
	_check(battle.enemy_charge_interrupted, "物品与普通攻击共用命中规则")
	battle.free()


func _test_elephant_charge() -> void:
	var battle = _battle(6021)
	battle.end_player_turn()
	battle.end_player_turn()
	_check(battle.enemy.shield == 16 and battle.enemy.single_block == 6, "大象铁壁防御")
	battle.end_player_turn()
	_check(battle.enemy.single_block == 0 and battle.enemy.shield == 0, "蓄力开始前结束旧架势")
	battle.enemy.gain_shield(10)
	battle.enemy.single_block = 6
	battle.player_attack(10)
	_check(battle.enemy_charge_progress == 4, "格挡量不计入有效伤害")
	battle.player_attack(13)
	_check(battle.enemy_charge_progress == 17 and not battle.enemy_charge_interrupted, "护盾吸收计入有效伤害，17未达阈值")
	battle.player_attack(1)
	_check(battle.current_enemy_action.id == 18 and battle.enemy_charge_progress == 18, "恰好18点打断")
	var hp: int = battle.player.health
	battle.end_player_turn()
	_check(battle.player.health == hp - 8, "大象取消后伤害8")
	battle.setup(919, CATALOG.find_enemy(6021))
	_check(battle.enemy_charge_rule == 0 and battle.enemy.single_block == 0, "重新建局清空临时状态")
	for turn in range(3):
		battle.end_player_turn()
	hp = battle.player.health
	battle.end_player_turn()
	_check(battle.player.health == hp - 22, "大象未打断执行22伤害")
	battle.free()


func _test_thorns_and_death() -> void:
	var battle = _battle(6012)
	battle.end_player_turn()
	battle.player.gain_shield(2)
	battle.play_card(GROUP)
	_check(battle.player.health == 98 and battle.enemy_thorns_remaining == 0, "4段只反伤前2次，反伤可被玩家护盾吸收")
	battle.end_player_turn()
	_check(battle.enemy_thorns_remaining == 0, "架势行动边界结束")
	battle.free()
	battle = _battle(6012)
	battle.end_player_turn()
	battle.player.health = 2
	battle.play_card(GROUP)
	_check(battle.phase == battle.Phase.FINISHED and battle.enemy.shield == 8, "首段反伤致死，停止剩余同步多段")
	battle.free()
	battle = _battle(6012)
	battle.end_player_turn()
	battle.player.health = 2
	battle.enemy.shield = 0
	battle.enemy.health = 1
	var result := {"victory": true}
	battle.battle_finished.connect(func(victory: bool) -> void: result.victory = victory)
	battle.player_attack(2)
	_check(battle.player.is_dead() and battle.enemy.is_dead() and not result.victory, "有限反伤同时死亡按玩家失败")
	battle.free()


# 使用保留测试ID6099，随机列表可等概率或配置正权重，种子相同则行动完全一致。
func _test_random_mode() -> void:
	var definition: Resource = CATALOG.find_enemy(6001).duplicate(true)
	definition.id = 6099
	definition.action_mode = 1
	definition.action_ids.assign([1, 3])
	definition.actions.assign([CATALOG.find_action(1), CATALOG.find_action(3)])
	definition.action_weights.assign([3, 1])
	var first = BATTLE.new()
	var second = BATTLE.new()
	root.add_child(first)
	root.add_child(second)
	first.setup(920, definition)
	second.setup(920, definition)
	var seen := {}
	for turn in range(12):
		_check(first.current_enemy_action.id == second.current_enemy_action.id, "随机模式固定种子可复现")
		seen[first.current_enemy_action.id] = true
		first.end_player_turn()
		second.end_player_turn()
	_check(seen.size() == 2, "随机列表两项均可选中")
	first.free()
	second.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)
