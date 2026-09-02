extends Control

@onready var status_label: Label = %StatusLabel


func _on_start_button_pressed() -> void:
	status_label.text = "战斗系统尚未接入"
