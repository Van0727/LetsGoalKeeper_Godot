# 卡牌插画冒烟测试：覆盖46张配表资源存在、数字ID与图片引用，以及本批25张成品规格和缺图回退。
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var file := FileAccess.open("res://tables/cards.csv", FileAccess.READ)
	assert(file != null)
	for header in range(3):
		file.get_csv_line()
	var count := 0
	var new_art_count := 0
	var ids := {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= 1:
			continue
		var id := int(row[0])
		assert(not ids.has(id))
		ids[id] = true
		var source := row[16]
		var definition = load("res://data/cards/%s.tres" % source)
		assert(definition != null and definition.id == id)
		assert(definition.illustration != null)
		assert(ResourceLoader.exists(definition.illustration.resource_path))
		# 手套及此前攻击牌保留原已确认引用；本批仅检查新接入的技能与五张防御牌。
		if (id >= 2001 and id <= 2020) or (id >= 3002 and id <= 3006):
			assert(definition.illustration.resource_path == "res://assets/ui/cards/%s_rounded_v1.png" % source)
			assert(definition.illustration.get_size() == Vector2(342, 316))
			new_art_count += 1
		count += 1
	assert(count == 46 and new_art_count == 25)
	var view = load("res://scenes/card_view.tscn").instantiate()
	root.add_child(view)
	assert(view.editor_preview_definition.id == 2001)
	view.configure(view.editor_preview_definition, -1)
	assert(view.illustration_rect.texture == view.editor_preview_definition.illustration)
	assert(view.illustration_rect.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR)
	assert(view.illustration_rect.size.is_equal_approx(Vector2(85.416664, 79)))
	view._apply_illustration(null)
	assert(not view.illustration_rect.visible)
	view.queue_free()
	await process_frame
	print("smoke_card_art: PASS | all_cards=46 | new_art=25")
	quit()
