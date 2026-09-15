# 单场奖励品运行时：持有计数、每回合消费标记与统一触发入口，不修改共享奖励品 Resource。
class_name BattleItemRuntime
extends RefCounted

const ITEM_EFFECT := preload("res://scripts/items/item_effect_definition.gd")

var items: Array[Resource] = []
var counters: Dictionary = {}
var _used_this_turn: Dictionary = {}
var _rng := RandomNumberGenerator.new()


# 每场战斗复制奖励品引用并重置临时态；固定 seed 使概率奖励可复现和可测试。
func setup(item_definitions: Array[Resource], seed_value: int) -> void:
	items = item_definitions.duplicate()
	counters.clear()
	_used_this_turn.clear()
	_rng.seed = seed_value


func start_turn() -> void:
	_used_this_turn.clear()


# 结构性战利品只按数字 ID 查询；通用数值效果仍走 trigger 配置表。
func has_item(item_id: int) -> bool:
	for item in items:
		if item != null and item.id == item_id:
			return true
	return false


# 酒吧骰子复用本场奖励品随机流；固定种子下正反面可复现，GM 切换不重置随机序列。
func roll_percent(chance_percent: int) -> bool:
	return _rng.randi_range(1, 100) <= clampi(chance_percent, 0, 100)


# GM 实时同步物品列表，不重置仍持有奖励的计数和随机流；取消的物品只清理自身状态。
func sync_items(item_definitions: Array[Resource]) -> void:
	var next_ids := {}
	for item in item_definitions:
		if item != null:
			next_ids[item.id] = true
	for item in items:
		if item == null or next_ids.has(item.id):
			continue
		for effect in item.effects:
			if effect != null and not effect.counter_key.is_empty():
				counters.erase(effect.counter_key)
		for usage_key in _used_this_turn.keys():
			if String(usage_key).begins_with("%d:" % item.id):
				_used_this_turn.erase(usage_key)
	items = item_definitions.duplicate()


# 按奖励品获得顺序和效果表顺序执行；返回命令供控制器在对应安全阶段实施结构性行为。
func trigger(trigger_type: int, context: Dictionary) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	for item in items:
		if item == null:
			continue
		for effect_index in range(item.effects.size()):
			var effect: Resource = item.effects[effect_index]
			if effect == null or effect.trigger != trigger_type:
				continue
			var usage_key := "%d:%d" % [item.id, effect_index]
			if effect.once_per_turn and _used_this_turn.get(usage_key, false):
				continue
			if not _matches(effect, context):
				continue
			var chance := clampi(effect.chance_percent, 0, 100)
			if chance <= 0 or (chance < 100 and _rng.randi_range(1, 100) > chance):
				continue
			_apply_effect(effect, context, commands, item.id)
			if effect.once_per_turn:
				_used_this_turn[usage_key] = true
	return commands


func _matches(effect: Resource, context: Dictionary) -> bool:
	if int(context.get("turn_number", 1)) > effect.maximum_turn:
		return false
	if effect.beat_in_bar_filter >= 0 and int(context.get("beat_in_bar", -1)) != effect.beat_in_bar_filter:
		return false
	if effect.requires_last_beat and not bool(context.get("is_last_beat", false)):
		return false
	if int(context.get("subdivision", 0)) < effect.minimum_subdivision:
		return false
	if effect.requires_rapid_hits and not bool(context.get("rapid_hits", false)):
		return false
	if effect.source_health_below_percent > 0 and int(context.get("source_health", 0)) * 100 >= int(context.get("source_max_health", 1)) * effect.source_health_below_percent:
		return false
	if effect.requires_shot and int(context.get("shot_type", 0)) == 0:
		return false
	if effect.target_filter == ITEM_EFFECT.TargetFilter.ENEMY and not bool(context.get("is_enemy_target", false)):
		return false
	if effect.target_filter == ITEM_EFFECT.TargetFilter.SELF and bool(context.get("is_enemy_target", true)):
		return false
	if effect.card_filter != ITEM_EFFECT.CardFilter.ANY and int(context.get("card_type", -1)) != effect.card_filter - 1:
		return false
	if effect.shot_filter != ITEM_EFFECT.ShotFilter.ANY and int(context.get("shot_type", -1)) != effect.shot_filter - 1:
		return false
	if effect.direction_filter != ITEM_EFFECT.DirectionFilter.ANY:
		var required_direction := -1 if effect.direction_filter == ITEM_EFFECT.DirectionFilter.LEFT else 1
		if int(context.get("shot_direction", 0)) != required_direction:
			return false
	if effect.rhythm_filter != ITEM_EFFECT.RhythmFilter.ANY and int(context.get("rhythm_grade", -1)) != effect.rhythm_filter - 1:
		return false
	var counter_value := int(counters.get(effect.counter_key, 0)) if not effect.counter_key.is_empty() else 0
	return counter_value >= effect.counter_minimum and counter_value <= effect.counter_maximum


func _apply_effect(
		effect: Resource,
		context: Dictionary,
		commands: Array[Dictionary],
		item_id: int
) -> void:
	match effect.operation:
		ITEM_EFFECT.Operation.ADD:
			context[effect.target_key] = float(context.get(effect.target_key, 0.0)) + effect.amount
		ITEM_EFFECT.Operation.MULTIPLY:
			context[effect.target_key] = float(context.get(effect.target_key, 0.0)) * effect.amount
		ITEM_EFFECT.Operation.SET:
			context[effect.target_key] = effect.amount
		ITEM_EFFECT.Operation.INCREMENT_COUNTER:
			counters[effect.counter_key] = clampi(
				int(counters.get(effect.counter_key, 0)) + ceili(effect.amount),
				effect.counter_minimum,
				effect.counter_maximum
			)
		ITEM_EFFECT.Operation.CLEAR_COUNTER:
			counters.erase(effect.counter_key)
		ITEM_EFFECT.Operation.EMIT_COMMAND:
			commands.append({"command": effect.target_key, "amount": effect.amount, "item_id": item_id})
		ITEM_EFFECT.Operation.UPDATE_BANANA_STREAK:
			# 首张香蕉球为 0 层；其他射门删除连击态，使下一张仍从 0 层开始。非射门不参与。
			if int(context.get("shot_type", 0)) == 2:
				counters[effect.counter_key] = mini(int(counters.get(effect.counter_key, -1)) + 1, effect.counter_maximum)
			else:
				counters.erase(effect.counter_key)
		ITEM_EFFECT.Operation.ADD_COUNTER:
			context[effect.target_key] = float(context.get(effect.target_key, 0.0)) + int(counters.get(effect.counter_key, 0)) * effect.amount
		ITEM_EFFECT.Operation.SET_COUNTER:
			counters[effect.counter_key] = clampi(ceili(effect.amount), 0, effect.counter_maximum)
		ITEM_EFFECT.Operation.ADD_HIT_STACK:
			context[effect.target_key] = float(context.get(effect.target_key, 0.0)) + mini(int(context.get("hit", 1)), effect.counter_maximum) * effect.amount
		ITEM_EFFECT.Operation.MULTIPLY_FINAL_DAMAGE:
			context["final_damage_multiplier"] = float(context.get("final_damage_multiplier", 1.0)) * effect.amount
