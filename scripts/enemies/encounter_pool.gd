# 章节遭遇池：按房间级别筛选已启用敌人，并用注入随机数执行确定性选择。
class_name EncounterPool
extends Resource

const ENEMY_DEFINITION := preload("res://scripts/enemies/enemy_definition.gd")

@export_range(1, 99, 1) var chapter := 1
@export var enemies: Array[Resource] = []


# 从指定级别中选择敌人；空池输出明确错误并返回空值，由调用方决定降级方式。
func pick_enemy(tier: int, rng: RandomNumberGenerator) -> Resource:
	var candidates: Array[Resource] = []
	for enemy in enemies:
		if enemy != null and enemy.encounter_enabled and enemy.tier == tier:
			candidates.append(enemy)
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
