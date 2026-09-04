# 角色反馈冒烟测试：验证伤害、治疗、护盾文本及状态数值同步。
extends SceneTree

const TEST_SCENE := preload("res://scenes/character_feedback_test.tscn")


# 延迟运行以等待场景树准备完成。
func _initialize() -> void:
	call_deferred("_run")


# 实例化反馈场景，调用交互入口并检查每一步的数值结果。
func _run() -> void:
	var test_scene := TEST_SCENE.instantiate()
	root.add_child(test_scene)
	await process_frame

	var player_display := test_scene.get_node("%PlayerDisplay")
	var enemy_display := test_scene.get_node("%EnemyDisplay")

	test_scene._on_damage_enemy_pressed()
	_assert_equal(enemy_display.health_bar.value, 24.0, "敌人受伤后生命")

	test_scene._on_shield_player_pressed()
	test_scene._on_damage_player_pressed()
	_assert_equal(player_display.health_bar.value, 100.0, "护盾吸收后玩家生命")
	_assert_equal(player_display.shield_label.text, "护盾  1", "受击后剩余护盾")

	test_scene._on_damage_player_pressed()
	test_scene._on_heal_player_pressed()
	_assert_equal(player_display.health_bar.value, 100.0, "治疗不超过最大生命")

	test_scene._on_reset_pressed()
	_assert_equal(enemy_display.health_bar.value, 30.0, "重置敌人生命")
	_assert_equal(player_display.shield_label.text, "护盾  0", "重置玩家护盾")

	print("smoke_character_feedback: PASS")
	quit()


# 通用相等断言；失败时立即输出对应功能标签。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])
	quit(1)
