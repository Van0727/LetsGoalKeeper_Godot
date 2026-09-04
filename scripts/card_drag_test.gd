# 卡牌拖拽测试场景：展示有效出牌信号和返回主菜单流程。
extends Control

@onready var instruction_label: Label = %InstructionLabel
@onready var card: DraggableCard = %DraggableCard


# 订阅卡牌出牌信号。
func _ready() -> void:
	card.card_played.connect(_on_card_played)


# 在界面和控制台反馈一次有效出牌。
func _on_card_played(_card: DraggableCard) -> void:
	instruction_label.text = "出牌成功！控制台已输出 card_played"


# 返回迁移测试版主菜单。
func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
