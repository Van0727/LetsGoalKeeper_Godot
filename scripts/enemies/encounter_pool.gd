@tool
# 章节遭遇池：供导入器生成，按房间级别筛选已启用敌人，并用注入随机数执行确定性选择。
class_name EncounterPool
extends Resource

const ENEMY_DEFINITION := preload("res://scripts/enemies/enemy_definition.gd")

@export_range(1, 99, 1) var chapter := 1
@export var enemies: Array[Resource] = []


# 返回指定级别的全部可用敌人，供地图规划器在不消费全局随机状态的前提下统一排除重复。
func get_candidates(tier: int) -> Array[Resource]:
	var candidates: Array[Resource] = []
	for enemy in enemies:
		if enemy != null and enemy.encounter_enabled and enemy.tier == tier:
			candidates.append(enemy)
	return candidates


# 地图规划先使用房型匹配的怪物；普通/精英池不足以解开去重约束时，再用本章其他非Boss怪物补位。
# Boss 房始终严格限定 Boss 池，防止终点战的内容和强度被降级。
func get_planning_candidates(tier: int) -> Array[Resource]:
	var preferred := get_candidates(tier)
	if tier == ENEMY_DEFINITION.Tier.BOSS:
		return preferred
	for enemy in enemies:
		if (
			enemy != null
			and enemy.encounter_enabled
			and enemy.tier != ENEMY_DEFINITION.Tier.BOSS
			and enemy not in preferred
		):
			preferred.append(enemy)
	return preferred


# 从指定级别中选择敌人；空池输出明确错误并返回空值，由调用方决定降级方式。
func pick_enemy(tier: int, rng: RandomNumberGenerator) -> Resource:
	var candidates := get_candidates(tier)
	if candidates.is_empty():
		push_error("第%d章的%s敌人池为空" % [chapter, _get_tier_text(tier)])
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


# 错误信息使用中文房型，方便内容缺失时直接定位配置。
func _get_tier_text(tier: int) -> String:
	match tier:
		ENEMY_DEFINITION.Tier.ELITE:
			return "精英"
		ENEMY_DEFINITION.Tier.BOSS:
			return "Boss"
		_:
			return "普通"
