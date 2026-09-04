# 两步奖励界面：战斗胜利后先选一张卡，再选一个未拥有战利品并进入下一战。
extends Control

const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")

enum Phase { CARD, ITEM }

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var run_label: Label = %RunLabel
@onready var choice_buttons: Array[Button] = [%Choice0, %Choice1, %Choice2]

var phase := Phase.CARD
var choices: Array[Resource] = []
var _service := REWARD_SERVICE.new()
var _rng := RandomNumberGenerator.new()
var run_state: Node


# 奖励随机数由本局seed和已胜场数派生，相同进度可复现同一组候选。
func _ready() -> void:
	run_state = get_node_or_null("/root/RunState")
	# 独立场景回归没有 Autoload 时使用局部新局，保持奖励界面可单独验收。
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
	_rng.seed = run_state.seed + run_state.battles_won * 1009 + 61
	for index in range(choice_buttons.size()):
		choice_buttons[index].pressed.connect(_on_choice_pressed.bind(index))
	_show_card_choices()


# 展示当前战斗级别对应的三张候选卡。
func _show_card_choices() -> void:
	phase = Phase.CARD
	title_label.text = "选择卡牌奖励"
	subtitle_label.text = "选择1张加入本局牌库"
	choices = _service.generate_card_choices(run_state.pending_reward_is_boss, _rng)
	_refresh_buttons()


# 展示未拥有战利品；池耗尽时提供明确的继续入口。
func _show_item_choices() -> void:
	phase = Phase.ITEM
	title_label.text = "选择战利品"
	subtitle_label.text = "选择1件，本局后续战斗立即生效"
	choices = _service.generate_item_choices(
		run_state.pending_reward_is_boss,
		run_state.owned_item_ids,
		_rng
	)
	_refresh_buttons()
	if choices.is_empty():
		subtitle_label.text = "该奖励池已没有新的战利品"
		choice_buttons[0].show()
		choice_buttons[0].text = "继续下一战"


# 将当前候选映射到固定三个按钮，池不足时隐藏多余槽位而不复制奖励。
func _refresh_buttons() -> void:
	run_label.text = "生命 %d/%d　牌库 %d　战利品 %d" % [
		run_state.player_hp, run_state.max_hp,
		run_state.deck_card_ids.size(), run_state.owned_item_ids.size(),
	]
	for index in range(choice_buttons.size()):
		var button := choice_buttons[index]
		if index >= choices.size():
			button.hide()
			continue
		button.show()
		var definition := choices[index]
		button.text = "%s\n%s" % [definition.display_name, definition.description]


# 卡牌选择后进入战利品步骤；两项奖励完成后才提交房间完成并推进路线。
func _on_choice_pressed(index: int) -> void:
	if phase == Phase.CARD:
		if index >= choices.size():
			return
		run_state.add_card(choices[index].card_id)
		_show_item_choices()
		return

	if not choices.is_empty():
		if index >= choices.size():
			return
		run_state.add_item(choices[index])
	var returns_to_map: bool = run_state.map_state != null and run_state.map_state.current_room_id != ""
	run_state.complete_reward()
	if returns_to_map:
		# 只有卡牌和战利品奖励都处理完毕，战斗房才正式变为已访问并解锁后续路线。
		run_state.complete_current_room()
		get_tree().change_scene_to_file("res://scenes/map_screen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/battle.tscn")


# 奖励阶段允许返回主菜单，但不会把未完成奖励误记为完成。
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
