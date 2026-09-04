# 启动场景入口：等待当前节点树完成挂载后再进入主菜单。
extends Node

const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")


# 延迟切换可避免 _ready 阶段节点树仍忙于增删子节点的错误。
func _ready() -> void:
	get_tree().call_deferred("change_scene_to_packed", MAIN_MENU_SCENE)
