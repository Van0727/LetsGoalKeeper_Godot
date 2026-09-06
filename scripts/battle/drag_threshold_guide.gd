# 战斗拖拽阈值引导：仅在拖动卡牌时绘制横向虚线，并按越线状态显示释放提示。
class_name DragThresholdGuide
extends Control

const DASH_WIDTH := 13.0
const DASH_GAP := 9.0
const LINE_COLOR := Color(0.94, 0.96, 1.0, 0.9)

@onready var prompt_label: Label = %PromptLabel


# 引导线默认隐藏，避免未操作时占据战场视觉焦点。
func _ready() -> void:
	hide()
	prompt_label.hide()


# 开始拖拽时展示虚线，但尚未越线前不提前提示可以出牌。
func begin_drag() -> void:
	show()
	prompt_label.hide()
	queue_redraw()


# 卡牌越过阈值后才显示释放提示；返回线下时立即撤销提示。
func set_qualified(qualified: bool) -> void:
	prompt_label.visible = qualified


# 结束拖拽后同时隐藏虚线和提示，避免结算期间残留引导。
func end_drag() -> void:
	prompt_label.hide()
	hide()


# 用短线段绘制稳定的虚线，不依赖额外纹理资源并可随视口宽度自动延展。
func _draw() -> void:
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(minf(x + DASH_WIDTH, size.x), 0), LINE_COLOR, 3.0)
		x += DASH_WIDTH + DASH_GAP
