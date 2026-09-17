# 费用面板验收：覆盖独立资源、零费用、超上限临时费用及真实渲染截图。
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(360, 640)
	var screen = load("res://scenes/battle.tscn").instantiate()
	root.add_child(screen)
	await create_timer(2.0).timeout
	assert(screen.get_node("EnergyPanel").texture != null, "背景资源不可缺失")
	assert(screen.get_node("EnergyPanel/LightningIcon").texture != null, "闪电资源不可缺失")
	assert(screen.energy_label.text == "%d/%d" % [screen.controller.player.energy, screen.controller.player.max_energy])
	screen.controller.player.energy = 0
	screen.controller.state_changed.emit()
	assert(screen.energy_label.text.begins_with("0/"), "零费用正常显示")
	screen.controller.player.energy = screen.controller.player.max_energy + 2
	screen.controller.state_changed.emit()
	assert(screen.energy_label.text == "%d/%d" % [screen.controller.player.energy, screen.controller.player.max_energy], "临时费用不截断")
	screen.controller.player.energy = screen.controller.player.max_energy
	screen.controller.state_changed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://energy_panel_preview.png")
	print("smoke_energy_panel: PASS")
	quit()
