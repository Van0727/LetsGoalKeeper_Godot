# 遗物单行分页验收：覆盖空栏、整行阈值、满库存、末页、首尾夹紧、删除后页码恢复及浅色背景。
extends SceneTree

var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error(message)

func _set_items(screen: Control, items: Array, count: int) -> void:
	screen.run_state.owned_item_ids.clear()
	for index in range(count):
		screen.run_state.owned_item_ids.append(items[index].id)
	screen._refresh_owned_item_icons()
	await process_frame
	await process_frame

func _visible_icons(screen: Control) -> Array:
	return screen.owned_item_icons.get_children().filter(func(icon: Node) -> bool: return icon.visible)

func _run() -> void:
	var screen := preload("res://scenes/battle.tscn").instantiate() as Control
	root.add_child(screen)
	await process_frame
	var items: Array = screen._reward_service.get_all_items()
	await _set_items(screen, items, 0)
	_check(not screen.owned_item_bar.visible, "空库存隐藏底栏")
	var capacity := maxi(1, int((screen.owned_item_bar.size.x - 8.0 + 2.0) / 34.0))
	await _set_items(screen, items, capacity)
	_check(not screen.item_next.visible, "刚好一行不显示箭头")
	_check(_visible_icons(screen).size() == capacity, "刚好一行完整显示")
	await _set_items(screen, items, capacity + 1)
	_check(screen.item_next.visible and screen.item_previous.disabled, "超出一行显示箭头且首页禁止后退")
	await _set_items(screen, items, items.size())
	var per_page: int = screen._owned_items_per_page
	var first := _visible_icons(screen)
	screen._select_owned_item_icon(first[0], items[0])
	_check(screen.item_detail_popup.visible, "翻页前可查看遗物详情")
	screen.item_next.pressed.emit()
	await process_frame
	_check(not screen.item_detail_popup.visible, "翻页关闭上一行详情")
	_check(screen._owned_item_page == 1, "点击右箭头前进一行")
	_check(_visible_icons(screen)[0] == screen.owned_item_icons.get_child(per_page), "第二行从下一组遗物开始")
	_check(not first[0].visible, "上一行遗物隐藏")
	var last_page := ceili(float(items.size()) / per_page) - 1
	for index in range(last_page + 2):
		screen._change_owned_item_page(1)
	await process_frame
	await process_frame
	_check(screen._owned_item_page == last_page and screen.item_next.disabled, "末页夹紧并禁用右箭头")
	_check(_visible_icons(screen).size() == items.size() - last_page * per_page, "末页显示剩余遗物")
	# 窗口缩窄重新计算容量，并将当前页夹紧到有效范围。
	var original_width: float = screen.owned_item_bar.size.x
	screen.owned_item_bar.size.x = 240.0
	screen._update_owned_item_page()
	_check(screen._owned_items_per_page < per_page, "缩窄后降低每行容量")
	screen.owned_item_bar.size.x = original_width
	screen._update_owned_item_page()
	await process_frame
	for icon in _visible_icons(screen):
		_check(icon.get_global_rect().end.x <= screen.size.x, "末页图标不超出屏幕")
		_check(icon.get_global_rect().end.y <= screen.size.y, "图标底边不超出屏幕")
	var background: ColorRect = screen.owned_item_bar.get_node("Background")
	_check(background.color.a > 0.0 and background.color.a <= 0.15, "背景为非常浅的半透明蒙版")
	if "--capture" in OS.get_cmdline_user_args():
		var output := "res://_local_artifacts/relic_paging"
		_check(DirAccess.make_dir_recursive_absolute(output) == OK, "创建截图目录")
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(output + "/last_page.png") == OK, "保存末页截图")
		screen._owned_item_page = 0
		screen._update_owned_item_page()
		await process_frame
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(output + "/first_page.png") == OK, "保存首页截图")
	await _set_items(screen, items, 1)
	_check(screen._owned_item_page == 0 and not screen.item_next.visible, "删除遗物后恢复有效页码并隐藏箭头")
	screen._change_owned_item_page(-1)
	_check(screen._owned_item_page == 0, "首页后退不会越界")
	screen.queue_free()
	await process_frame
	print("smoke_item_paging: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
