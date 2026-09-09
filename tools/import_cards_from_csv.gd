@tool
# 编辑器手动入口：在 Godot 脚本编辑器执行本文件，即可将 tables/cards.csv 写入 data/cards。
extends EditorScript

const CARD_CSV_IMPORTER_SCRIPT := preload("res://scripts/cards/card_csv_importer.gd")


func _run() -> void:
	# 导入器及其资源依赖都启用 tool 模式，可按 Godot 官方约定直接创建并执行。
	var importer := CARD_CSV_IMPORTER_SCRIPT.new()
	var result: Dictionary = importer.import_cards()
	if result.ok:
		print("卡牌 CSV 导入完成：%d 张卡牌，%d 条效果" % [result.card_count, result.effect_count])
		return
	for error_text in result.errors:
		push_error(error_text)
