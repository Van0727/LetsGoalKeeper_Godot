# 统一配表导出入口：生成卡牌、战利品以及怪物三表的目录与章节遭遇资源。
extends SceneTree

const TABLE_IMPORTER := preload("res://scripts/cards/card_csv_importer.gd")
const ENEMY_IMPORTER := preload("res://scripts/enemies/enemy_csv_importer.gd")


func _initialize() -> void:
	var enemy_importer := ENEMY_IMPORTER.new()
	var enemy_validation: Dictionary = enemy_importer.validate_tables()
	if not enemy_validation.ok:
		push_error("怪物配表校验失败：%s" % "; ".join(enemy_validation.errors))
		quit(1)
		return
	var result: Dictionary = TABLE_IMPORTER.new().import_all()
	if not result.ok:
		push_error("配表导出失败：%s" % "; ".join(result.errors))
		quit(1)
		return
	print("配表导出完成：卡牌%d张、卡牌效果%d条、战利品%d件、战利品效果%d条" % [
		result.card_count, result.card_effect_count, result.item_count, result.item_effect_count,
	])
	var enemies: Dictionary = enemy_importer.import_monsters()
	if not enemies.ok:
		push_error("怪物配表导出失败：%s" % "; ".join(enemies.errors))
		quit(1)
		return
	print("怪物导出完成：%d只怪物、%d种行为、%d个效果步骤" % [enemies.monster_count, enemies.action_count, enemies.effect_count])
	quit()
