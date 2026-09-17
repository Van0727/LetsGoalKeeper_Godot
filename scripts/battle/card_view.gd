@tool
# 战斗卡牌视图：显示卡面与柔和外发光，并在编辑器填入预览数据及开放参考图区域。
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
# 每张卡牌独享光晕样式，悬停和拖拽不会影响相邻卡牌。
var _glow_style: StyleBoxFlat
var _glow_hovered := false
var _glow_dragging := false
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
	# 根节点允许光晕向外延伸；仅卡面内容裁切，编辑器参考图继续允许超出画框。
	var editing := Engine.is_editor_hint()
	clip_contents = false
	$Canvas.clip_contents = not editing
	_create_outer_glow()
	editor_reference.visible = editing
	if editing:
		if editor_preview_definition != null:
			configure(editor_preview_definition, -1)
	else:
		# 子类重写 ready 后必须显式初始化父类，保证运行时拖拽事件和回弹位置有效。
		super._ready()
		mouse_entered.connect(func(): _glow_hovered = true; _update_outer_glow())
		mouse_exited.connect(func(): _glow_hovered = false; _update_outer_glow())
		drag_started.connect(func(_card): _glow_dragging = true; _update_outer_glow())
		drag_finished.connect(func(_card, _valid): _glow_dragging = false; _update_outer_glow())


# 光晕放在卡牌底板后方且不接收输入，保持原有命中范围和拖拽布局。
func _create_outer_glow() -> void:
	_glow_style = StyleBoxFlat.new()
	_glow_style.draw_center = false
	_glow_style.set_corner_radius_all(10)
	_glow_style.shadow_offset = Vector2.ZERO
	var glow := Panel.new()
	glow.name = "OuterGlow"
	glow.show_behind_parent = true
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.add_theme_stylebox_override("panel", _glow_style)
	add_child(glow)
	_update_outer_glow()


# 常态铺一层稍明显的青色光晕；悬停或拖拽进一步增强，不遮挡文字与插画。
func _update_outer_glow() -> void:
	var emphasized := _glow_hovered or _glow_dragging
	_glow_style.shadow_size = 11 if emphasized else 8
	_glow_style.shadow_color = Color(0.05, 0.85, 1.0, 0.56 if emphasized else 0.38)


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
