# 统一配表导出入口：一次校验并生成卡牌、战利品与战利品目录资源。
extends SceneTree

const TABLE_IMPORTER := preload("res://scripts/cards/card_csv_importer.gd")


func _initialize() -> void:
	var result: Dictionary = TABLE_IMPORTER.new().import_all()
	if not result.ok:
		push_error("配表导出失败：%s" % "; ".join(result.errors))
		quit(1)
		return
	print("配表导出完成：卡牌%d张、卡牌效果%d条、战利品%d件、战利品效果%d条" % [
		result.card_count, result.card_effect_count, result.item_count, result.item_effect_count,
	])
	quit()
