@tool
# 战斗卡牌视图：显示运行时卡牌，并在编辑器填入预览数据及开放参考图区域。
class_name BattleCardView
extends DraggableCard

const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
# 默认预览使用新攻守兼备成品；同步卡牌定义，避免工具初始化覆盖为旧插画。
const EDITOR_PREVIEW_CARD := preload("res://data/cards/card_attack_and_defend.tres")
# 类型徽章直接裁自已确认参考图；保留原图英文和配色用于快速扫读。
const ATTACK_BADGE := preload("res://assets/ui/cards/card_type_attack.png")
const DEFENSE_BADGE := preload("res://assets/ui/cards/card_type_defense.png")
const SKILL_BADGE := preload("res://assets/ui/cards/card_type_skill.png")

var card_definition: Resource
var hand_index := -1
# 编辑器预览只服务卡面排版；战斗运行时始终由手牌数据调用 configure 覆盖。
@export var editor_preview_definition: Resource = EDITOR_PREVIEW_CARD:
	set(value):
		editor_preview_definition = value
		if is_node_ready() and Engine.is_editor_hint() and value != null:
			configure(value, -1)

@onready var cost_label: Label = %CostLabel
@onready var illustration_rect: TextureRect = %Illustration
@onready var editor_reference: Sprite2D = %EditorReference
@onready var name_label: Label = %NameLabel
@onready var category_badge: TextureRect = %CategoryBadge
@onready var shot_label: Label = %ShotLabel
@onready var description_label: Label = %DescriptionLabel


# 在编辑器中自动填入一张真实卡牌，使设计人员能直接拖动节点并检查文本折行。
func _ready() -> void:
	# 参考图仅服务编辑器对照：编辑时解除根节点裁切，运行时隐藏并恢复卡面裁切。
	var editing := Engine.is_editor_hint()
	clip_contents = not editing
	editor_reference.visible = editing
	if editing:
		if editor_preview_definition != null:
			configure(editor_preview_definition, -1)
	else:
		# 子类重写 ready 后必须显式初始化父类，保证运行时拖拽事件和回弹位置有效。
		super._ready()


# 绑定手牌中的定义与稳定位置；运行时只读取 Resource，不回写配置。
func configure(definition: Resource, index: int) -> void:
	card_definition = definition
	hand_index = index
	if not is_node_ready():
		await ready
	_apply_illustration(definition.illustration)
	cost_label.text = str(definition.cost)
	name_label.text = definition.display_name
	category_badge.texture = _get_card_type_badge(definition.card_type)
	# 射门表现仍用于结算与后续动画，但不再挤占卡牌底部的类别信息区。
	shot_label.text = _get_shot_type_text(definition.shot_type)
	description_label.text = definition.description
	tooltip_text = definition.description


# 专属插画只覆盖卡牌上方的固定画框；留空时隐藏节点，继续显示通用卡牌底板。
func _apply_illustration(illustration: Texture2D) -> void:
	illustration_rect.texture = illustration
	illustration_rect.visible = illustration != null


# 三类使用原图徽章；能力与未知类别安全回退到 SKILL，避免出现空白类别区。
func _get_card_type_badge(card_type: int) -> Texture2D:
	match card_type:
		CARD_DEFINITION.CardType.ATTACK:
			return ATTACK_BADGE
		CARD_DEFINITION.CardType.DEFENSE:
			return DEFENSE_BADGE
		_:
			return SKILL_BADGE


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
