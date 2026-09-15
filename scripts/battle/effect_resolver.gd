# 卡牌效果执行器：只负责按数据结算并产出事件，不依赖动画或 UI。
class_name EffectResolver
extends RefCounted

const EFFECT_DEFINITION := preload("res://scripts/cards/effect_definition.gd")
const ITEM_EFFECT := preload("res://scripts/items/item_effect_definition.gd")

# 直接调用且未注入战斗随机数时使用的后备随机数生成器。
var _fallback_rng := RandomNumberGenerator.new()


# 按数组顺序执行卡牌效果；概率失败会跳过当前效果，中断标记会终止后续效果。
func resolve_card(
		card: Resource,
		source,
		opponent,
		rng: RandomNumberGenerator = null,
		damage_modifiers: Dictionary = {},
		rhythm_result: Dictionary = {},
		defer_enemy_shot_damage := false,
		item_runtime = null,
		action_context: Dictionary = {},
		shot_rng: RandomNumberGenerator = null
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	# 节奏倍率只作用于对手受到的直接伤害；自伤、治疗、护盾和状态保持卡牌原始规则。
	var rhythm_multiplier := clampf(
		float(rhythm_result.get("effect_multiplier", 1.0)),
		0.0,
		10.0
	)
	# 卡牌效果倍率只作用可量化数值，不延长力量/虚弱持续回合。
	var card_effect_multiplier := maxf(float(action_context.get("card_effect_multiplier", 1.0)), 0.0)
	for effect in card.effects:
		# 概率事件保留掷骰明细，确保日志、测试和以后回放都能解释结果。
		var chance := clampi(ceili(effect.chance_percent * card_effect_multiplier), 0, 100)
		if chance < 100:
			var active_rng := rng if rng != null else _fallback_rng
			var roll := active_rng.randi_range(1, 100)
			var succeeded := roll <= chance
			events.append({
				"type": "chance",
				"chance_percent": chance,
				"roll": roll,
				"succeeded": succeeded,
			})
			if not succeeded:
				continue

		var recipient = source if effect.target == EFFECT_DEFINITION.Target.SELF else opponent
		match effect.effect_type:
			EFFECT_DEFINITION.EffectType.DAMAGE:
				var applied_rhythm_multiplier := rhythm_multiplier if recipient == opponent else 1.0
				_resolve_damage(
					effect,
					int(action_context.get("shot_type", card.shot_type)),
					card.attack_delay_beats,
					card.multi_hit_interval_beats,
					defer_enemy_shot_damage and recipient == opponent and int(action_context.get("shot_type", card.shot_type)) != 0,
					source,
					recipient,
					events,
					damage_modifiers,
					applied_rhythm_multiplier,
					item_runtime,
					action_context,
					shot_rng
				)
			EFFECT_DEFINITION.EffectType.SHIELD:
				var gained: int = recipient.gain_shield(ceili(effect.amount * card_effect_multiplier))
				events.append({
					"type": "shield",
					"amount": gained,
					"target": recipient,
					"health_after": recipient.health,
					"shield_after": recipient.shield,
				})
			EFFECT_DEFINITION.EffectType.HEAL:
				var healed: int = recipient.heal(ceili(effect.amount * card_effect_multiplier))
				events.append({
					"type": "heal",
					"amount": healed,
					"target": recipient,
					"health_after": recipient.health,
					"shield_after": recipient.shield,
				})
			EFFECT_DEFINITION.EffectType.ENERGY:
				var restored: int = recipient.gain_energy(ceili(effect.amount * card_effect_multiplier))
				events.append({"type": "energy", "amount": restored, "target": recipient})
			EFFECT_DEFINITION.EffectType.APPLY_STRENGTH:
				var strength_turns: int = recipient.apply_strength(effect.multiplier * card_effect_multiplier, effect.amount)
				events.append({
					"type": "strength",
					"multiplier": recipient.strength_multiplier,
					"turns": strength_turns,
					"target": recipient,
				})
			EFFECT_DEFINITION.EffectType.APPLY_WEAKNESS:
				var weakness_turns: int = recipient.apply_weakness(effect.multiplier * card_effect_multiplier, effect.amount)
				events.append({
					"type": "weakness",
					"multiplier": recipient.strength_multiplier,
					"turns": weakness_turns,
					"target": recipient,
				})
			EFFECT_DEFINITION.EffectType.BGM_PITCH_UP:
				# 音调效果只产出表现事件，不让无场景依赖的核心结算器直接访问全局音频节点。
				events.append({"type": "bgm_pitch", "semitone_delta": 1, "reset": false})
			EFFECT_DEFINITION.EffectType.BGM_PITCH_DOWN:
				events.append({"type": "bgm_pitch", "semitone_delta": -1, "reset": false})
			EFFECT_DEFINITION.EffectType.BGM_PITCH_RESET:
				events.append({"type": "bgm_pitch", "semitone_delta": 0, "reset": true})
			EFFECT_DEFINITION.EffectType.BANANA_DIRECTION_LEFT:
				# 仅声明战斗内方向切换；后续香蕉球仍沿用统一的方向与战利品结算路径。
				events.append({"type": "banana_direction", "direction": -1})
			EFFECT_DEFINITION.EffectType.BANANA_DIRECTION_RIGHT:
				events.append({"type": "banana_direction", "direction": 1})
			EFFECT_DEFINITION.EffectType.CUSTOM_RULE:
				# 专属规则已由战斗控制器在整张牌边界处理，此步骤不重复产出表现事件。
				pass
			_:
				events.append({"type": "unsupported", "effect_type": effect.effect_type})

		# 中断发生在当前效果成功结算之后，例如爆炸球先自伤再取消攻击。
		if effect.interrupt_on_success:
			events.append({"type": "effect_interrupted"})
			break
		if opponent.is_dead() or source.is_dead():
			break
	return events


# 逐段结算伤害；每一段独立消耗护盾，目标死亡后立即停止剩余段数。
func _resolve_damage(
		effect: Resource,
		shot_type: int,
		attack_delay_beats: float,
		multi_hit_interval_beats: float,
		defer_damage: bool,
		source,
		recipient,
		events: Array[Dictionary],
		damage_modifiers: Dictionary,
		rhythm_multiplier: float,
		item_runtime = null,
		action_context: Dictionary = {},
		shot_rng: RandomNumberGenerator = null
) -> void:
	var extra_hits := maxi(int(action_context.get("extra_hits", 0)), 0)
	var base_hits := maxi(int(action_context.get("base_hits_override", effect.hits)), 1)
	var resolved_hits := base_hits + extra_hits
	for hit_index in range(resolved_hits):
		# 能量加成读取费用支付后的运行时能量，不回写 EffectDefinition。
		var energy_bonus: int = source.energy * effect.amount_per_energy
		var item_bonus := _get_shot_damage_bonus(shot_type, damage_modifiers)
		# 狂欢节拍追加的球使用独立基础伤害，原牌每段数值和逐段战利品加成保持不变。
		var base_amount: int = int(effect.amount) if hit_index < base_hits else int(action_context.get("extra_hit_amount", effect.amount))
		var scaled_amount: int = base_amount + energy_bonus + item_bonus
		var damage_context := action_context.duplicate(true)
		# 下一次攻击叠层与十牌倍率在整张牌级别锁定；每段分别加固定值，再统一向上取整。
		var attack_bonus := float(action_context.get("attack_bonus", 0.0)) if recipient != source else 0.0
		var attack_multiplier := float(action_context.get("value_multiplier", 1.0)) if recipient != source else 1.0
		damage_context["amount"] = (scaled_amount * source.strength_multiplier * rhythm_multiplier + attack_bonus) * attack_multiplier * float(action_context.get("card_effect_multiplier", 1.0))
		damage_context["hit"] = hit_index + 1
		damage_context["hits"] = resolved_hits
		# 连拍由同一张牌在 BGM 上的相邻击打间隔定义，不读取玩家出牌间隔。
		damage_context["rapid_hits"] = resolved_hits > 1 and multi_hit_interval_beats <= 0.5
		damage_context["shot_type"] = shot_type
		damage_context["is_enemy_target"] = recipient != source
		damage_context["source_health"] = source.health
		damage_context["source_max_health"] = source.max_health
		# 只有非香蕉球被战利品转换且没有固定方向时，每颗真正射向敌人的球独立掷左右。
		# 原生香蕉球继续读取出牌上下文，避免改变“双向香蕉球”等既有牌的方向逻辑。
		var direction_sequence: Array = action_context.get("shot_direction_sequence", [])
		if recipient != source and shot_type == 2 and hit_index < direction_sequence.size():
			damage_context["shot_direction"] = int(direction_sequence[hit_index])
		elif recipient != source and shot_type == 2 and bool(action_context.get("converted_banana_per_hit", false)) and int(damage_context.get("shot_direction", 0)) == 0:
			var direction_rng: RandomNumberGenerator = shot_rng if shot_rng != null else _fallback_rng
			damage_context["shot_direction"] = -1 if direction_rng.randi_range(0, 1) == 0 else 1
		# 桑巴方向奖励逐颗比较并即时推进上一颗香蕉球，同一张交替多段牌也能正确触发。
		if recipient != source and shot_type == 2:
			var current_direction := int(damage_context.get("shot_direction", 0))
			var previous_direction := int(action_context.get("previous_banana_direction", 0))
			var direction_mode := int(action_context.get("banana_direction_bonus_mode", 0))
			if current_direction != 0 and previous_direction != 0:
				if direction_mode == 1 and current_direction != previous_direction:
					damage_context["amount"] = float(damage_context.get("amount", 0.0)) + float(action_context.get("banana_direction_bonus", 0.0))
				elif direction_mode == 2 and current_direction == previous_direction:
					damage_context["amount"] = float(damage_context.get("amount", 0.0)) + float(action_context.get("banana_direction_bonus", 0.0))
			if current_direction != 0:
				action_context["previous_banana_direction"] = current_direction
		var before_commands: Array[Dictionary] = []
		if item_runtime != null:
			before_commands = item_runtime.trigger(ITEM_EFFECT.Trigger.BEFORE_DAMAGE, damage_context)
		# 纹身贴等末端倍率放在所有固定加伤之后，物品获得顺序不再改变结果。
		damage_context["amount"] = float(damage_context.get("amount", 0.0)) * float(damage_context.get("final_damage_multiplier", 1.0))
		# 酒吧骰子的下一次伤害只消费首个对敌伤害段；自伤和非伤害效果不消费。
		if recipient != source and float(action_context.get("pending_damage_multiplier", 1.0)) > 1.0:
			damage_context["amount"] = float(damage_context.get("amount", 0.0)) * float(action_context["pending_damage_multiplier"])
			action_context["pending_damage_multiplier"] = 1.0
		# 所有倍率的最终结果统一向上取整，避免战斗状态和表现事件出现小数。
		var damage := maxi(ceili(float(damage_context.get("amount", 0.0))), 0)
		# 实战射门只生成待命中事件；实际护盾消耗、扣血和死亡判断由足球命中帧提交。
		var result: Dictionary = (
			{"absorbed": 0, "health_damage": 0}
			if defer_damage
			else recipient.take_damage(damage)
		)
		var damage_event := {
			"type": "damage",
			"amount": damage,
			"base_amount": base_amount,
			"energy_bonus": energy_bonus,
			"item_bonus": item_bonus,
			"rhythm_multiplier": rhythm_multiplier,
			"absorbed": result.absorbed,
			"health_damage": result.health_damage,
			"hit": hit_index + 1,
			"hits": resolved_hits,
			"shot_type": shot_type,
			"shot_direction": int(damage_context.get("shot_direction", 0)),
			"item_context": damage_context.duplicate(true),
			"item_commands": before_commands,
			# 表现层读取事件快照，避免结算期间修改 Resource 导致已发出的球改变时序。
			"attack_delay_beats": maxf(attack_delay_beats, 0.0),
			"multi_hit_interval_beats": maxf(multi_hit_interval_beats, 0.0),
			"deferred_damage": defer_damage,
			"target": recipient,
			"health_after": recipient.health,
			"shield_after": recipient.shield,
		}
		if item_runtime != null and not defer_damage:
			var after_context := damage_context.duplicate(true)
			after_context["amount"] = damage
			after_context["health_damage"] = result.health_damage
			damage_event.item_commands.append_array(
				item_runtime.trigger(ITEM_EFFECT.Trigger.AFTER_DAMAGE, after_context)
			)
		events.append(damage_event)
		if not defer_damage and recipient.is_dead():
			break


# 汇总所有射门加成与当前弹道专属加成；非射门效果不会获得战利品伤害。
func _get_shot_damage_bonus(shot_type: int, damage_modifiers: Dictionary) -> int:
	if shot_type == 0:
		return 0
	var bonus: int = damage_modifiers.get("all", 0)
	match shot_type:
		1: bonus += damage_modifiers.get("straight", 0)
		2: bonus += damage_modifiers.get("banana", 0)
		3: bonus += damage_modifiers.get("lob", 0)
	return bonus
