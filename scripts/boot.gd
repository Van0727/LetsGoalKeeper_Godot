extends Node

const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")


func _ready() -> void:
	get_tree().change_scene_to_packed(MAIN_MENU_SCENE)
