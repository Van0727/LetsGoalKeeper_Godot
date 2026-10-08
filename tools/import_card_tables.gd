# 卡牌三表独立导入入口：仅重建卡牌并回读校验，不触碰道具和怪物资源。
extends SceneTree

func _initialize() -> void:
	var result: Dictionary = preload("res://scripts/cards/card_csv_importer.gd").new().import_cards()
	if not result.ok:
		push_error("卡牌导出失败：%s" % "; ".join(result.errors))
		quit(1)
		return
	print("卡牌导出完成：%d张卡牌、%d条效果" % [result.card_count, result.effect_count])
	quit()
