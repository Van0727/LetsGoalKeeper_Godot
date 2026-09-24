# 战斗核心冒烟测试：覆盖基础数值、回合、效果顺序和死亡边界；卡牌契约采用当前1点自伤与1拍延迟。
extends SceneTree

const COMBATANT_STATE := preload("res://scripts/battle/combatant_state.gd")
const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
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
const PITCH_UP := preload("res://data/cards/card_pitch_up.tres")
const PITCH_DOWN := preload("res://data/cards/card_pitch_down.tres")
const PITCH_RESET := preload("res://data/cards/card_pitch_reset.tres")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const EFFECT_DEFINITION := preload("res://scripts/cards/effect_definition.gd")
const RHYTHM_CLOCK := preload("res://scripts/battle/rhythm_clock.gd")

var _failed := false


# 延迟到场景树初始化完成后运行测试集合。
func _initialize() -> void:
	call_deferred("_run")


# 顺序执行所有核心用例，任一断言失败则以非零状态退出。
func _run() -> void:
	_test_damage_shield_and_healing()
	_test_turn_flow_and_victory()
	_test_player_defeat()
	_test_card_costs_and_effects()
	_test_shot_types_multi_hit_and_multi_effect()
	_test_probability_branch_and_interrupt()
	_test_remaining_energy_damage()
	_test_strength_and_weakness_duration()
	_test_remaining_migrated_cards()
	_test_effect_order()
	_test_deterministic_seed()
	_test_rhythm_judgement_and_damage()
	_test_bgm_pitch_card_events()
	_test_discipline_cards_and_forced_turn_end()

	if _failed:
		quit(1)
		return
	print("smoke_battle_core: PASS")
	quit()


# 验证三张音调牌生成准确事件；实际音频变化由战斗表现层消费，核心测试无需音频设备。
func _test_bgm_pitch_card_events() -> void:
	var resolver = preload("res://scripts/battle/effect_resolver.gd").new()
	var source = COMBATANT_STATE.new("玩家", 10, 3)
	var target = COMBATANT_STATE.new("敌人", 10)
	var up_events: Array[Dictionary] = resolver.resolve_card(PITCH_UP, source, target)
	var down_events: Array[Dictionary] = resolver.resolve_card(PITCH_DOWN, source, target)
	var reset_events: Array[Dictionary] = resolver.resolve_card(PITCH_RESET, source, target)
	_assert_equal(up_events[0].get("semitone_delta"), 1, "升调牌产生升高一个半音事件")
	_assert_equal(down_events[0].get("semitone_delta"), -1, "降调牌产生降低一个半音事件")
	_assert_true(reset_events[0].get("reset", false), "原调牌产生恢复原调事件")


# 验证成功出牌才累计纪律计数，默认第5张黄牌、第10张红牌，并在消费红牌后推进回合且重置。
func _test_discipline_cards_and_forced_turn_end() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(20260911)
	var free_card = CARD_DEFINITION.new()
	free_card.card_id = "card_discipline_test"
	free_card.display_name = "纪律测试牌"
	free_card.cost = 0
	free_card.card_type = CARD_DEFINITION.CardType.ABILITY
	var unaffordable_card = CARD_DEFINITION.new()
	unaffordable_card.display_name = "无法支付的纪律测试牌"
	unaffordable_card.cost = 4
	_assert_true(not battle.play_card(unaffordable_card), "能量不足的牌不能打出")
	_assert_equal(battle.player_cards_played_this_turn, 0, "失败出牌不累计纪律计数")
	var issued_colors: Array[String] = []
	battle.discipline_card_issued.connect(func(color: String, _count: int) -> void: issued_colors.append(color))
	for _index in range(4):
		_assert_true(battle.play_card(free_card), "前4张测试牌可正常打出")
	_assert_equal(issued_colors.size(), 0, "第5张牌前不触发纪律警告")
	_assert_true(battle.play_card(free_card), "第5张测试牌可正常打出")
	_assert_equal(issued_colors, ["yellow"], "第5张牌只触发一次黄牌")
	for _index in range(5):
		_assert_true(battle.play_card(free_card), "黄牌后仍可继续出牌直到红牌")
	_assert_equal(issued_colors, ["yellow", "red"], "第10张牌触发红牌")
	_assert_true(battle.red_card_pending, "红牌等待当前牌表现完成")
	_assert_true(not battle.play_card(free_card), "红牌后不能继续出牌")
	var previous_turn: int = battle.turn_number
	_assert_true(battle.force_end_turn_for_red_card(), "表现层可消费红牌并强制结束回合")
	_assert_equal(battle.turn_number, previous_turn + 1, "红牌强制推进到下一回合")
	_assert_equal(battle.player_cards_played_this_turn, 0, "新回合清空出牌计数")
	_assert_true(not battle.red_card_pending, "新回合清除红牌状态")
	battle.free()


# 验证护盾优先吸收、生命扣减和治疗上限。
func _test_damage_shield_and_healing() -> void:
	var combatant = COMBATANT_STATE.new("测试角色", 10)
	combatant.gain_shield(5)
	var first_hit: Dictionary = combatant.take_damage(3)
	_assert_equal(first_hit.absorbed, 3, "伤害小于护盾时吸收量")
	_assert_equal(combatant.shield, 2, "伤害小于护盾时剩余护盾")
	_assert_equal(combatant.health, 10, "伤害小于护盾时生命")

	combatant.take_damage(2)
	_assert_equal(combatant.shield, 0, "伤害等于护盾时剩余护盾")
	_assert_equal(combatant.health, 10, "伤害等于护盾时生命")

	var third_hit: Dictionary = combatant.take_damage(4)
	_assert_equal(third_hit.health_damage, 4, "伤害大于护盾时生命损失")
	_assert_equal(combatant.heal(20), 4, "治疗返回实际恢复量")
	_assert_equal(combatant.health, 10, "治疗不超过最大生命")

	# 溢出伤害只能扣除剩余生命，死亡快照与后续显示均必须归零。
	combatant.health = 3
	var lethal_hit: Dictionary = combatant.take_damage(99)
	_assert_equal(lethal_hit.health_damage, 3, "溢出伤害只记录实际损失的剩余生命")
	_assert_equal(combatant.health, 0, "溢出伤害后生命归零")
	_assert_true(combatant.is_dead(), "生命归零后判定死亡")


# 验证玩家/敌人回合推进及击杀后的胜利状态。
func _test_turn_flow_and_victory() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(42)
	_assert_equal(battle.phase, battle.Phase.PLAYER_TURN, "战斗开始阶段")
	battle.player_guard(6)
	battle.end_player_turn()
	_assert_equal(battle.turn_number, 2, "敌人行动后进入下一回合")
	_assert_equal(battle.player.shield, 0, "玩家新回合清空护盾")
	battle.player_attack(999)
	_assert_equal(battle.phase, battle.Phase.FINISHED, "敌人死亡后结束战斗")
	_assert_equal(battle.enemy.health, 0, "致命伤害不会产生负生命")
	battle.free()


# 验证相同种子生成相同敌人意图和概率卡牌结果。
func _test_deterministic_seed() -> void:
	var first = BATTLE_CONTROLLER.new()
	var second = BATTLE_CONTROLLER.new()
	root.add_child(first)
	root.add_child(second)
	first.setup(12345)
	second.setup(12345)

	for turn in range(5):
		_assert_equal(first.enemy_intent_damage, second.enemy_intent_damage, "固定 seed 的第 %d 次意图" % turn)
		first.end_player_turn()
		second.end_player_turn()

	first.free()
	second.free()

	var first_explosion = BATTLE_CONTROLLER.new()
	var second_explosion = BATTLE_CONTROLLER.new()
	root.add_child(first_explosion)
	root.add_child(second_explosion)
	first_explosion.setup(24680)
	second_explosion.setup(24680)
	first_explosion.play_card(EXPLOSION_BALL)
	second_explosion.play_card(EXPLOSION_BALL)
	_assert_equal(first_explosion.player.health, second_explosion.player.health, "固定 seed 的爆炸球自伤结果")
	_assert_equal(first_explosion.enemy.health, second_explosion.enemy.health, "固定 seed 的爆炸球攻击结果")
	first_explosion.free()
	second_explosion.free()


# 验证 100 BPM 的75ms GREAT、150ms GOOD与剩余 MISS，及变调后窗口和 Miss 的伤害规则。
func _test_rhythm_judgement_and_damage() -> void:
	var clock = RHYTHM_CLOCK.new()
	clock.bpm = 100.0
	clock.first_beat_offset = 0.0
	_assert_equal(clock.perfect_window_ms, 75.0, "默认Great窗口为正负75ms")
	_assert_equal(clock.good_window_ms, 150.0, "默认Good窗口为正负150ms")
	_assert_equal(clock.get_bpm_from_music_path("res://sound/bgm/bg_basicDrum2_bpm100.mp3"), 100.0, "从BGM名称读取整数BPM")
	_assert_equal(clock.get_bpm_from_music_path("res://sound/bgm/boss_bpm127.5.ogg"), 127.5, "从BGM名称读取小数BPM")
	_assert_equal(clock.get_bpm_from_music_path("res://sound/bgm/no_bpm.mp3"), -1.0, "无数值BPM名称返回无效值")
	_assert_equal(clock.get_beat_duration(), 0.6, "100 BPM的一拍为0.6秒")
	_assert_equal(clock.beats_to_seconds(0.25), 0.15, "100 BPM的四分之一拍为0.15秒")
	_assert_equal(clock.beats_to_seconds(0.5), 0.3, "100 BPM的半拍为0.3秒")
	_assert_equal(clock.beats_to_seconds(2.0), 1.2, "100 BPM的两拍为1.2秒")
	_assert_equal(
		clock.get_quantized_loop_duration(12.017, 100.0),
		12.0,
		"MP3尾部填充不会计入单轮节拍时间轴"
	)
	_assert_equal(
		clock.get_quantized_loop_duration(12.017, 100.0) * 10.0,
		120.0,
		"循环十次仍按整数拍累计而不放大尾部误差"
	)
	clock.perfect_window_ms = 75.0
	clock.good_window_ms = 150.0
	_assert_equal(clock.judge_at(0.05).grade, clock.JudgementGrade.PERFECT, "节拍后50ms为最佳判定")
	_assert_equal(clock.judge_at(0.05).grade_name, "Great", "最佳判定对玩家显示为Great")
	_assert_equal(clock.judge_at(0.075).grade, clock.JudgementGrade.PERFECT, "节拍后75ms仍为Great边界")
	_assert_equal(clock.judge_at(0.076).grade, clock.JudgementGrade.GOOD, "超过75ms立即进入Good")
	_assert_equal(clock.judge_at(0.15).grade, clock.JudgementGrade.GOOD, "节拍后150ms为Good边界")
	_assert_equal(clock.judge_at(0.15).grade_name, "Good", "次级判定对玩家保持Good")
	_assert_equal(clock.judge_at(0.151).grade, clock.JudgementGrade.MISS, "超过150ms立即判为Miss")
	_assert_equal(clock.judge_at(0.20).grade, clock.JudgementGrade.MISS, "拍内剩余区间保持Miss")
	_assert_equal(clock.judge_at(0.55).grade, clock.JudgementGrade.PERFECT, "下一拍前50ms为最佳判定")
	_assert_equal(roundi(clock.judge_at(0.55).error_ms), -50, "提前判定保留负误差")
	_assert_equal(clock.judge_at(0.55).target_time, 0.6, "判定结果保留最近拍点供命中同步")
	# 音源时间随 pitch_scale 加速或减速，但玩家按键窗口应维持相同的现实毫秒宽度。
	clock._audio_player = AudioStreamPlayer.new()
	clock._audio_player.pitch_scale = 2.0
	_assert_equal(clock.judge_at(0.70).grade, clock.JudgementGrade.PERFECT, "二倍速下音源晚100ms仍在现实50ms窗口")
	_assert_equal(roundi(clock.judge_at(0.70).error_ms), 50, "升调反馈显示现实时间偏差")
	clock._audio_player.pitch_scale = 0.5
	_assert_equal(clock.judge_at(0.65).grade, clock.JudgementGrade.GOOD, "半速下音源晚50ms对应现实100ms")
	_assert_equal(clock.judge_at(0.70).grade, clock.JudgementGrade.MISS, "半速下现实200ms超过Good窗口")
	clock._last_music_time = 3.0
	clock._last_raw_music_time = 3.0
	clock.set_calibration_offset_ms(-10.0)
	_assert_true(absf(clock._last_music_time - 2.995) < 0.00001, "负向现场校准立即移动缓存时间")
	clock.set_calibration_offset_ms(1000.0)
	_assert_equal(clock.calibration_offset_ms, 500.0, "现场校准限制在安全上限")
	clock._audio_player.free()
	clock._audio_player = null
	_assert_equal(clock.get_next_beat_time(0.15), 0.6, "四分之一拍启动时锚定到下一个整数拍")
	_assert_equal(clock.get_next_beat_time(0.30), 0.6, "半拍启动时锚定到下一个整数拍")
	_assert_equal(clock.get_next_beat_time(0.45), 0.6, "四分之三拍启动时锚定到下一个整数拍")
	_assert_true(
		not clock.did_playback_wrap(4.2, 4.12, 12.0),
		"音频线程的小幅回退不会误判为歌曲循环"
	)
	_assert_true(clock.did_playback_wrap(11.9, 0.1, 12.0), "曲尾回到曲首会识别为真实循环")

	var miss_result: Dictionary = clock.judge_at(0.20)
	var resolver = preload("res://scripts/battle/effect_resolver.gd").new()
	var source = COMBATANT_STATE.new("节奏测试球员", 20, 3)
	var target = COMBATANT_STATE.new("节奏测试目标", 20)
	var shot_events: Array[Dictionary] = resolver.resolve_card(
		STRAIGHT_SHOT,
		source,
		target,
		null,
		{},
		miss_result
	)
	_assert_equal(target.health, 17, "Miss使6点对敌伤害减半")
	_assert_equal(shot_events[0].rhythm_multiplier, 0.5, "伤害事件记录节奏倍率")
	_assert_equal(shot_events[0].attack_delay_beats, 1.0, "射门伤害事件携带当前1拍飞行延迟")
	_assert_equal(shot_events[0].multi_hit_interval_beats, 0.5, "伤害事件携带半拍多段间隔")

	# 真实飞球模式在命中前不得改变生命；提交命中事件后才扣血并更新事件快照。
	var deferred_source = COMBATANT_STATE.new("延迟测试球员", 20, 3)
	var deferred_target = COMBATANT_STATE.new("延迟测试目标", 20)
	var deferred_events: Array[Dictionary] = resolver.resolve_card(
		STRAIGHT_SHOT, deferred_source, deferred_target, null, {}, {}, true
	)
	_assert_equal(deferred_target.health, 20, "足球命中前不提前扣除敌人生命")
	_assert_true(deferred_events[0].deferred_damage, "射门伤害标记为待命中")
	var deferred_battle = BATTLE_CONTROLLER.new()
	deferred_battle.setup(9102)
	var queued_events: Array[Dictionary] = []
	deferred_battle.effect_resolved.connect(func(event: Dictionary) -> void: queued_events.append(event))
	_assert_true(deferred_battle.play_card(STRAIGHT_SHOT, {}, true), "控制器接受待命中射门")
	_assert_equal(deferred_battle.enemy.health, 30, "控制器在命中前保持敌人生命")
	_assert_true(deferred_battle.commit_deferred_damage(queued_events[0]), "目标拍点提交待命中伤害")
	_assert_equal(deferred_battle.enemy.health, 24, "目标拍点正式扣除6点生命")
	_assert_equal(queued_events[0].health_after, 24, "命中事件记录扣血后的真实快照")
	deferred_battle.free()

	var self_damage_source = COMBATANT_STATE.new("自伤测试球员", 20, 3)
	var self_damage_target = COMBATANT_STATE.new("自伤测试目标", 20)
	resolver.resolve_card(SPIKED_BALL, self_damage_source, self_damage_target, null, {}, miss_result)
	_assert_equal(self_damage_source.health, 19, "Miss不缩放卡牌1点自伤")
	_assert_equal(self_damage_target.health, 16, "Miss将尖刺球8点对敌伤害缩放为4点")

	var healing_source = COMBATANT_STATE.new("治疗测试球员", 20, 3)
	healing_source.health = 10
	resolver.resolve_card(SPORTS_DRINK, healing_source, target, null, {}, miss_result)
	_assert_equal(healing_source.health, 16, "Miss不缩放治疗效果")
	clock.free()


# 验证复合卡牌严格按效果数组顺序执行。
func _test_effect_order() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(5)
	battle.player.health = 99

	var heal_effect = EFFECT_DEFINITION.new()
	heal_effect.effect_type = EFFECT_DEFINITION.EffectType.HEAL
	heal_effect.target = EFFECT_DEFINITION.Target.SELF
	heal_effect.amount = 6
	var self_damage_effect = EFFECT_DEFINITION.new()
	self_damage_effect.effect_type = EFFECT_DEFINITION.EffectType.DAMAGE
	self_damage_effect.target = EFFECT_DEFINITION.Target.SELF
	self_damage_effect.amount = 3
	var ordered_card = CARD_DEFINITION.new()
	ordered_card.display_name = "顺序测试"
	ordered_card.cost = 0
	var ordered_effects: Array[Resource] = [heal_effect, self_damage_effect]
	ordered_card.effects = ordered_effects

	battle.play_card(ordered_card)
	_assert_equal(battle.player.health, 97, "效果按数组顺序先治疗再自伤")
	battle.free()


# 验证射门类型、多段护盾消耗、死亡截断和多效果卡牌。
func _test_shot_types_multi_hit_and_multi_effect() -> void:
	var resolver = preload("res://scripts/battle/effect_resolver.gd").new()
	var source = COMBATANT_STATE.new("测试射手", 20, 10)
	var target = COMBATANT_STATE.new("测试门将", 40)

	var banana_events: Array[Dictionary] = resolver.resolve_card(BANANA_SHOT, source, target)
	_assert_equal(banana_events.size(), 1, "香蕉球产生一次伤害事件")
	_assert_equal(banana_events[0].shot_type, BANANA_SHOT.ShotType.BANANA, "香蕉球事件保留弹道类型")

	var lob_events: Array[Dictionary] = resolver.resolve_card(LOB_SHOT, source, target)
	_assert_equal(lob_events[0].shot_type, LOB_SHOT.ShotType.LOB, "挑射事件保留弹道类型")
	_assert_equal(lob_events[0].attack_delay_beats, 2.0, "挑射事件携带2拍延迟")

	target.shield = 4
	var barrage_events: Array[Dictionary] = resolver.resolve_card(BARRAGE_SHOT, source, target)
	_assert_equal(barrage_events.size(), 4, "连续射门逐段产生四次伤害事件")
	_assert_equal(barrage_events[0].multi_hit_interval_beats, 0.25, "连续射门事件携带四分之一拍间隔")
	_assert_equal(barrage_events[0].absorbed, 3, "第一段伤害消耗护盾")
	_assert_equal(barrage_events[1].absorbed, 1, "第二段伤害消耗剩余护盾")
	_assert_equal(barrage_events[2].health_damage, 3, "第三段伤害作用于生命")
	_assert_equal(barrage_events[3].health_damage, 3, "第四段伤害作用于生命")
	# 表现层依赖逐段快照在每球命中时更新血条，不能只读取已变成最终值的目标对象。
	_assert_equal(barrage_events[0].health_after, 27, "第一段结算后生命快照")
	_assert_equal(barrage_events[1].health_after, 25, "第二段结算后生命快照")
	_assert_equal(barrage_events[2].health_after, 22, "第三段结算后生命快照")
	_assert_equal(barrage_events[3].health_after, 19, "第四段结算后生命快照")
	var lethal_target = COMBATANT_STATE.new("低生命目标", 4)
	var lethal_events: Array[Dictionary] = resolver.resolve_card(BARRAGE_SHOT, source, lethal_target)
	_assert_equal(lethal_events.size(), 2, "多段攻击在目标死亡后停止后续段数")

	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(101)
	_assert_true(battle.play_card(ATTACK_AND_DEFEND), "可打出多效果卡牌")
	_assert_equal(battle.enemy.health, 25, "多效果卡牌先造成伤害")
	_assert_equal(battle.player.shield, 5, "多效果卡牌再获得护盾")
	battle.free()


# 同时覆盖爆炸球成功自伤中断与失败继续攻击两条分支。
func _test_probability_branch_and_interrupt() -> void:
	var resolver = preload("res://scripts/battle/effect_resolver.gd").new()
	var success_rng := _find_rng_for_chance_result(true)
	var success_source = COMBATANT_STATE.new("爆炸触发者", 20, 3)
	var success_target = COMBATANT_STATE.new("未受攻击目标", 20)
	var success_events: Array[Dictionary] = resolver.resolve_card(
		EXPLOSION_BALL,
		success_source,
		success_target,
		success_rng
	)
	_assert_true(success_events[0].succeeded, "爆炸球成功分支触发")
	_assert_equal(success_source.health, 17, "爆炸球触发时对自身造成3点伤害")
	_assert_equal(success_target.health, 20, "爆炸球触发后中断敌方伤害")
	_assert_equal(success_events[-1].type, "effect_interrupted", "爆炸球记录中断事件")

	var failure_rng := _find_rng_for_chance_result(false)
	var failure_source = COMBATANT_STATE.new("安全射手", 20, 3)
	var failure_target = COMBATANT_STATE.new("受攻击目标", 20)
	var failure_events: Array[Dictionary] = resolver.resolve_card(
		EXPLOSION_BALL,
		failure_source,
		failure_target,
		failure_rng
	)
	_assert_true(not failure_events[0].succeeded, "爆炸球失败分支未触发")
	_assert_equal(failure_source.health, 20, "爆炸球未触发时不造成自伤")
	_assert_equal(failure_target.health, 6, "爆炸球未触发时造成14点伤害")
	_assert_equal(failure_events.size(), 2, "爆炸球未触发时继续后续效果")


# 搜索一个能稳定产生指定 50% 判定结果的种子，避免测试依赖随机运气。
func _find_rng_for_chance_result(expected_success: bool) -> RandomNumberGenerator:
	for candidate_seed in range(1, 1000):
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate_seed
		if (probe.randi_range(1, 100) <= 50) == expected_success:
			var result := RandomNumberGenerator.new()
			result.seed = candidate_seed
			return result
	return RandomNumberGenerator.new()


# 验证能量射门读取的是支付费用后的剩余能量。
func _test_remaining_energy_damage() -> void:
	var full_energy_battle = BATTLE_CONTROLLER.new()
	root.add_child(full_energy_battle)
	full_energy_battle.setup(303)
	_assert_true(full_energy_battle.play_card(ENERGY_SHOT), "满能量时可打出能量射门")
	_assert_equal(full_energy_battle.player.energy, 2, "能量射门先支付1点费用")
	_assert_equal(full_energy_battle.enemy.health, 20, "剩余2点能量时造成10点伤害")
	full_energy_battle.free()

	var last_energy_battle = BATTLE_CONTROLLER.new()
	root.add_child(last_energy_battle)
	last_energy_battle.setup(304)
	last_energy_battle.player.energy = 1
	_assert_true(last_energy_battle.play_card(ENERGY_SHOT), "最后1点能量可打出能量射门")
	_assert_equal(last_energy_battle.player.energy, 0, "最后1点能量被支付")
	_assert_equal(last_energy_battle.enemy.health, 24, "无剩余能量时只造成6点基础伤害")
	last_energy_battle.free()


# 验证力量/虚弱倍率、同类延时、相反状态替换及各自回合结束后的持续时间扣减。
func _test_strength_and_weakness_duration() -> void:
	var status_target = COMBATANT_STATE.new("状态测试角色", 20)
	_assert_equal(status_target.apply_strength(1.5, 2), 2, "首次施加力量持续2回合")
	_assert_equal(status_target.apply_strength(1.5, 2), 4, "重复力量只增加持续时间")
	_assert_equal(status_target.strength_multiplier, 1.5, "重复力量不叠加倍率")
	_assert_equal(status_target.apply_weakness(0.5, 2), 2, "虚弱替换力量并重置持续时间")
	_assert_equal(status_target.strength_multiplier, 0.5, "相反状态替换倍率")

	var strength_battle = BATTLE_CONTROLLER.new()
	root.add_child(strength_battle)
	strength_battle.setup(401)
	_assert_true(strength_battle.play_card(RUN_UP), "可打出助跑")
	_assert_equal(strength_battle.player.strength_turns, 2, "助跑赋予2回合力量")
	_assert_true(strength_battle.play_card(STRAIGHT_SHOT), "力量状态下可打出射门")
	_assert_equal(strength_battle.enemy.health, 21, "力量使6点伤害变为9点")
	strength_battle.end_player_turn()
	_assert_equal(strength_battle.player.strength_turns, 1, "玩家完成回合后力量减1回合")
	strength_battle.play_card(STRAIGHT_SHOT)
	_assert_equal(strength_battle.enemy.health, 12, "下一回合力量仍然生效")
	strength_battle.end_player_turn()
	_assert_equal(strength_battle.player.strength_multiplier, 1.0, "力量到期后恢复正常倍率")
	strength_battle.free()

	var weakness_battle = BATTLE_CONTROLLER.new()
	root.add_child(weakness_battle)
	weakness_battle.setup(402)
	var raw_intent: int = weakness_battle.enemy_intent_damage
	_assert_true(weakness_battle.play_card(WEAKNESS), "可打出虚弱")
	_assert_equal(
		weakness_battle.get_enemy_intent_damage(),
		roundi(raw_intent * 0.5),
		"虚弱立即更新敌人最终意图"
	)
	var health_before_attack: int = weakness_battle.player.health
	var first_weak_damage: int = weakness_battle.get_enemy_intent_damage()
	weakness_battle.end_player_turn()
	_assert_equal(
		weakness_battle.player.health,
		health_before_attack - first_weak_damage,
		"敌人攻击应用虚弱倍率"
	)
	_assert_equal(weakness_battle.enemy.strength_turns, 1, "敌人完成回合后虚弱减1回合")
	weakness_battle.end_player_turn()
	_assert_equal(weakness_battle.enemy.strength_multiplier, 1.0, "虚弱到期后恢复正常倍率")
	weakness_battle.free()


# 验证阶段2补齐卡牌的段数、射门类型、效果顺序与自伤死亡中断。
func _test_remaining_migrated_cards() -> void:
	var resolver = preload("res://scripts/battle/effect_resolver.gd").new()

	var group_source = COMBATANT_STATE.new("组射门球员", 20, 3)
	var group_target = COMBATANT_STATE.new("组射门目标", 30)
	var group_events: Array[Dictionary] = resolver.resolve_card(SHOT_GROUP, group_source, group_target)
	_assert_equal(group_events.size(), 4, "一组射门按当前资源产生4段伤害事件")
	_assert_equal(group_target.health, 22, "一组射门总计造成8点伤害")
	_assert_equal(group_events[0].shot_type, SHOT_GROUP.ShotType.RANDOM, "一组射门保留随机射门类型")

	var double_source = COMBATANT_STATE.new("双向香蕉球球员", 20, 3)
	var double_target = COMBATANT_STATE.new("双向香蕉球目标", 20)
	var double_events: Array[Dictionary] = resolver.resolve_card(
		DOUBLE_BANANA_SHOT,
		double_source,
		double_target
	)
	_assert_equal(double_events.size(), 2, "双向香蕉球产生2段伤害事件")
	_assert_equal(double_target.health, 14, "双向香蕉球总计造成6点伤害")
	_assert_equal(double_events[0].shot_type, DOUBLE_BANANA_SHOT.ShotType.BANANA, "双向香蕉球保留香蕉球类型")

	var blood_source = COMBATANT_STATE.new("嗜血球球员", 20, 3)
	blood_source.health = 10
	var blood_target = COMBATANT_STATE.new("嗜血球目标", 20)
	var blood_events: Array[Dictionary] = resolver.resolve_card(
		BLOODTHIRSTY_BALL,
		blood_source,
		blood_target
	)
	_assert_equal(blood_events[0].type, "damage", "嗜血球先造成伤害")
	_assert_equal(blood_events[1].type, "heal", "嗜血球后恢复生命")
	_assert_equal(blood_target.health, 14, "嗜血球造成6点伤害")
	_assert_equal(blood_source.health, 13, "嗜血球恢复3点生命")

	var spike_source = COMBATANT_STATE.new("尖刺球球员", 20, 3)
	var spike_target = COMBATANT_STATE.new("尖刺球目标", 20)
	var spike_events: Array[Dictionary] = resolver.resolve_card(SPIKED_BALL, spike_source, spike_target)
	_assert_equal(spike_events[0].target, spike_source, "尖刺球第一效果目标是自己")
	_assert_equal(spike_source.health, 19, "尖刺球先造成1点自伤")
	_assert_equal(spike_target.health, 12, "尖刺球再对敌人造成8点伤害")

	# 生命恰好等于当前自伤1点，验证先自伤致死就停止对敌攻击。
	var fatal_source = COMBATANT_STATE.new("濒死尖刺球球员", 1, 3)
	var safe_target = COMBATANT_STATE.new("未受伤目标", 20)
	var fatal_events: Array[Dictionary] = resolver.resolve_card(SPIKED_BALL, fatal_source, safe_target)
	_assert_equal(fatal_events.size(), 1, "尖刺球自伤致死后中断后续效果")
	_assert_equal(safe_target.health, 20, "尖刺球自伤致死时不再攻击敌人")

	var rugby_source = COMBATANT_STATE.new("橄榄球球员", 20, 3)
	var rugby_target = COMBATANT_STATE.new("橄榄球目标", 20)
	var rugby_events: Array[Dictionary] = resolver.resolve_card(RUGBY_BALL, rugby_source, rugby_target)
	_assert_equal(rugby_events[0].shot_type, RUGBY_BALL.ShotType.RANDOM, "橄榄球保留随机射门类型")
	_assert_equal(rugby_target.health, 13, "橄榄球造成7点伤害")


# 验证敌人致命攻击进入失败状态且生命不会为负。
func _test_player_defeat() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(7)
	battle.player.take_damage(99)
	battle.end_player_turn()
	_assert_equal(battle.phase, battle.Phase.FINISHED, "玩家死亡后结束战斗")
	_assert_equal(battle.player.health, 0, "敌人致命攻击后玩家生命")
	battle.free()


# 验证费用支付、基础效果、回能上限以及手牌成功/失败流转。
func _test_card_costs_and_effects() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(88)
	battle.player.take_damage(10)

	_assert_true(battle.play_card(STRAIGHT_SHOT), "能量充足时可打攻击牌")
	_assert_equal(battle.player.energy, 2, "攻击牌支付能量")
	_assert_equal(battle.enemy.health, 24, "攻击效果造成伤害")
	_assert_true(battle.play_card(GLOVES), "能量充足时可打防御牌")
	_assert_equal(battle.player.shield, 6, "防御效果增加护盾")
	_assert_true(battle.play_card(SPORTS_DRINK), "能量充足时可打治疗牌")
	_assert_equal(battle.player.health, 96, "治疗效果不超过最大生命")
	_assert_true(not battle.play_card(STRAIGHT_SHOT), "能量不足时拒绝出牌")
	_assert_equal(battle.enemy.health, 24, "能量不足不结算效果")

	battle.end_player_turn()
	_assert_equal(battle.player.energy, 3, "新玩家回合恢复满能量")
	_assert_true(battle.play_card(TOWEL), "可打出回能牌")
	_assert_equal(battle.player.energy, 3, "回能牌费用和效果依次结算且不超过上限")

	var deck = DECK_STATE.new()
	var cards: Array[Resource] = [STRAIGHT_SHOT, GLOVES, SPORTS_DRINK, TOWEL]
	deck.setup(cards, 17)
	deck.draw_cards(3)
	battle.player.energy = 0
	var hand_before: Array[Resource] = deck.hand.duplicate()
	_assert_true(not battle.play_card_from_hand(deck, 0), "费用不足时手牌出牌失败")
	_assert_equal(deck.hand, hand_before, "费用不足不移动手牌")
	battle.player.energy = 3
	_assert_true(battle.play_card_from_hand(deck, 0), "费用充足时从手牌出牌")
	_assert_equal(deck.discard_pile.size(), 1, "成功出牌后进入弃牌堆")
	battle.free()


# 通用相等断言：记录失败但继续执行其余用例，便于一次看到全部问题。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
