extends Control

@onready var instruction_label: Label = %InstructionLabel
@onready var card: DraggableCard = %DraggableCard


func _ready() -> void:
	card.card_played.connect(_on_card_played)


func _on_card_played(_card: DraggableCard) -> void:
	instruction_label.text = "出牌成功！控制台已输出 card_played"


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
