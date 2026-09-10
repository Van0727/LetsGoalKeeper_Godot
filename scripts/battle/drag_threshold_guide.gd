# 战斗拖拽阈值引导：使用图片显示横向阈值线，并按越线状态显示释放提示。
class_name DragThresholdGuide
extends Control

@onready var prompt_label: Label = %PromptLabel


# 引导线默认隐藏，避免未操作时占据战场视觉焦点。
func _ready() -> void:
	hide()
	prompt_label.hide()


# 开始拖拽时展示虚线，但尚未越线前不提前提示可以出牌。
func begin_drag() -> void:
	show()
	prompt_label.hide()


# 卡牌越过阈值后才显示释放提示；返回线下时立即撤销提示。
func set_qualified(qualified: bool) -> void:
	prompt_label.visible = qualified


# 结束拖拽后同时隐藏虚线和提示，避免结算期间残留引导。
func end_drag() -> void:
	prompt_label.hide()
	hide()
