# 战斗卡牌视图：把固定卡牌定义映射为可拖拽的名称、费用、类型与说明。
class_name BattleCardView
extends DraggableCard

const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")

var card_definition: Resource
var hand_index := -1

@onready var cost_label: Label = %CostLabel
@onready var illustration_rect: TextureRect = %Illustration
@onready var name_label: Label = %NameLabel
@onready var type_label: Label = %TypeLabel
@onready var shot_label: Label = %ShotLabel
@onready var description_label: Label = %DescriptionLabel


# 绑定手牌中的定义与稳定位置；运行时只读取 Resource，不回写配置。
func configure(definition: Resource, index: int) -> void:
	card_definition = definition
	hand_index = index
	if not is_node_ready():
		await ready
	_apply_illustration(definition.illustration)
	cost_label.text = str(definition.cost)
	name_label.text = definition.display_name
	type_label.text = _get_card_type_text(definition.card_type)
	shot_label.text = _get_shot_type_text(definition.shot_type)
	description_label.text = definition.description
	tooltip_text = definition.description


# 专属插画只覆盖卡牌上方的固定画框；留空时隐藏节点，继续显示通用卡牌底板。
func _apply_illustration(illustration: Texture2D) -> void:
	illustration_rect.texture = illustration
	illustration_rect.visible = illustration != null


# 不同卡牌大类使用固定中文短标签，方便小屏快速辨认。
func _get_card_type_text(card_type: int) -> String:
	match card_type:
		CARD_DEFINITION.CardType.ATTACK:
			return "攻击"
		CARD_DEFINITION.CardType.DEFENSE:
			return "防御"
		_:
			return "能力"


# 阶段 3 暂以文字区分射门表现，后续动画只替换该表现层。
func _get_shot_type_text(shot_type: int) -> String:
	match shot_type:
		CARD_DEFINITION.ShotType.STRAIGHT:
			return "直球"
		CARD_DEFINITION.ShotType.BANANA:
			return "香蕉球"
		CARD_DEFINITION.ShotType.LOB:
			return "挑射"
		CARD_DEFINITION.ShotType.RANDOM:
			return "随机射门"
		_:
			return "战术"
