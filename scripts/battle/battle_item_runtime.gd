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


# GM 实时同步物品列表，不重置仍持有奖励的计数和随机流；取消的物品只清理自身状态。
func sync_items(item_definitions: Array[Resource]) -> void:
	var next_ids := {}
	for item in item_definitions:
		if item != null:
			next_ids[item.item_id] = true
	for item in items:
		if item == null or next_ids.has(item.item_id):
			continue
		for effect in item.effects:
			if effect != null and not effect.counter_key.is_empty():
				counters.erase(effect.counter_key)
		for usage_key in _used_this_turn.keys():
			if String(usage_key).begins_with(item.item_id + ":"):
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
			var usage_key := "%s:%d" % [item.item_id, effect_index]
			if effect.once_per_turn and _used_this_turn.get(usage_key, false):
				continue
			if not _matches(effect, context):
				continue
			var chance := clampi(effect.chance_percent, 0, 100)
			if chance <= 0 or (chance < 100 and _rng.randi_range(1, 100) > chance):
				continue
			_apply_effect(effect, context, commands, item.item_id)
			if effect.once_per_turn:
				_used_this_turn[usage_key] = true
	return commands


func _matches(effect: Resource, context: Dictionary) -> bool:
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
		item_id: String
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
			# 首张香蕉球为 0 层；其他射门打断，非射门不参与。多段命中不重复推进。
			if int(context.get("shot_type", 0)) == 2:
				counters[effect.counter_key] = mini(int(counters.get(effect.counter_key, -1)) + 1, effect.counter_maximum)
			else:
				counters[effect.counter_key] = 0
		ITEM_EFFECT.Operation.ADD_COUNTER:
			context[effect.target_key] = float(context.get(effect.target_key, 0.0)) + int(counters.get(effect.counter_key, 0)) * effect.amount
