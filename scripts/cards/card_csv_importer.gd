@tool
# 卡牌 CSV 导入器：卡牌按效果模板 ID 复用步骤，并由卡牌行提供各步骤的战斗数值。
class_name CardCsvImporter
extends RefCounted

const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const EFFECT_DEFINITION := preload("res://scripts/cards/effect_definition.gd")

const FIELD_NAMES := [
	"id", "display_name", "description", "cost", "card_type", "shot_type", "rarity",
	"attack_delay_beats", "multi_hit_interval_beats", "effect_id", "amounts", "hits",
	"amounts_per_energy", "multipliers", "chances", "interrupts", "source_file",
]
const FIELD_TYPES := [
	"uint16", "string", "string", "uint8", "uint8", "uint8", "uint8", "float32", "float32",
	"uint16", "uint16_list", "uint8_list", "uint8_list", "uint8_list",
	"uint8_list", "uint8_list", "string",
]
const EFFECT_FIELD_NAMES := [
	"effect_id", "name", "description",
]
const EFFECT_FIELD_TYPES := [
	"uint16", "string", "string",
]
const STEP_FIELD_NAMES := ["effect_id", "effect_index", "effect_type", "target", "description"]
const STEP_FIELD_TYPES := ["uint16", "uint8", "uint8", "uint8", "string"]


# 三张表先完整校验再写入资源；缺失模板、错位参数和孤立步骤都不能造成部分写入。
func import_cards(
		csv_path := "res://tables/cards.csv",
		output_directory := "res://data/cards",
		effects_path := "res://tables/effects.csv",
		steps_path := "res://tables/effect_steps.csv"
) -> Dictionary:
	var errors: Array[String] = []
	var file := FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["无法打开卡牌 CSV：%s" % csv_path]}
	var comment_row := _read_csv_row(file)
	var field_row := _read_csv_row(file)
	var type_row := _read_csv_row(file)
	if comment_row.size() != FIELD_NAMES.size() or not _row_matches(field_row, FIELD_NAMES) or not _row_matches(type_row, FIELD_TYPES):
		return {"ok": false, "errors": ["CSV 前三行表头与卡牌配置约定不一致"]}

	var cards := {}
	var ids := {}
	var previous_id := 0
	var line_number := 3
	while not file.eof_reached():
		var row := _read_csv_row(file)
		line_number += 1
		if row.is_empty() or (row.size() == 1 and row[0].strip_edges().is_empty()):
			continue
		var numeric_id := _parse_card_row(row, line_number, cards, ids, errors)
		if numeric_id > 0:
			if numeric_id < previous_id:
				errors.append("卡牌主表第%d行ID必须从低到高排列" % line_number)
			previous_id = numeric_id
	file.close()
	var templates := {}
	var effects_file := FileAccess.open(effects_path, FileAccess.READ)
	if effects_file == null:
		errors.append("无法打开卡牌效果 CSV：%s" % effects_path)
	else:
		var effect_comment := _read_csv_row(effects_file)
		var effect_fields := _read_csv_row(effects_file)
		var effect_types := _read_csv_row(effects_file)
		if effect_comment.size() != EFFECT_FIELD_NAMES.size() or not _row_matches(effect_fields, EFFECT_FIELD_NAMES) or not _row_matches(effect_types, EFFECT_FIELD_TYPES):
			errors.append("效果 CSV 前三行表头与配置约定不一致")
		else:
			line_number = 3
			previous_id = 0
			while not effects_file.eof_reached():
				var effect_row := _read_csv_row(effects_file)
				line_number += 1
				if effect_row.is_empty() or (effect_row.size() == 1 and effect_row[0].strip_edges().is_empty()):
					continue
				var template_id := _parse_effect_row(effect_row, line_number, templates, errors)
				if template_id > 0:
					if template_id < previous_id:
						errors.append("效果模板表第%d行ID必须从低到高排列" % line_number)
					previous_id = template_id
		effects_file.close()
	var steps_file := FileAccess.open(steps_path, FileAccess.READ)
	if steps_file == null:
		errors.append("无法打开效果步骤 CSV：%s" % steps_path)
	else:
		var step_comment := _read_csv_row(steps_file)
		var step_fields := _read_csv_row(steps_file)
		var step_types := _read_csv_row(steps_file)
		if step_comment.size() != STEP_FIELD_NAMES.size() or not _row_matches(step_fields, STEP_FIELD_NAMES) or not _row_matches(step_types, STEP_FIELD_TYPES):
			errors.append("效果步骤 CSV 前三行表头与配置约定不一致")
		else:
			line_number = 3
			previous_id = 0
			while not steps_file.eof_reached():
				var step_row := _read_csv_row(steps_file)
				line_number += 1
				if step_row.is_empty() or (step_row.size() == 1 and step_row[0].strip_edges().is_empty()):
					continue
				var step_id := _parse_step_row(step_row, line_number, templates, errors)
				if step_id > 0:
					if step_id < previous_id:
						errors.append("效果步骤表第%d行ID必须从低到高排列" % line_number)
					previous_id = step_id
		steps_file.close()
	for template_id in templates:
		if templates[template_id]["steps"].is_empty():
			errors.append("效果模板 %d 没有步骤" % template_id)
	for source_file in cards:
		var card: Dictionary = cards[source_file]
		if not templates.has(card.effect_id):
			errors.append("卡牌 %s 引用不存在的效果ID %d" % [source_file, card.effect_id])
			continue
		var steps: Array = templates[card.effect_id]["steps"]
		if card.values.size() != steps.size():
			errors.append("卡牌 %s 的参数组数必须等于效果步骤数 %d" % [source_file, steps.size()])
			continue
		for index in range(steps.size()):
			var effect_data: Dictionary = steps[index].duplicate()
			effect_data.merge(card.values[index])
			card.effects.append(effect_data)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if cards.is_empty():
		return {"ok": false, "errors": ["CSV 未包含任何卡牌记录"]}

	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	if directory_error != OK:
		return {"ok": false, "errors": ["无法创建卡牌输出目录：%s" % output_directory]}
	for source_file in cards:
		var card_error := _save_and_verify_card(cards[source_file], output_directory)
		if not card_error.is_empty():
			errors.append(card_error)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "card_count": cards.size(), "effect_count": _effect_count(cards)}


# 主表每个数字 ID 只能出现一次；资源文件名仍是运行时和存档使用的英文稳定 ID。
func _parse_card_row(row: PackedStringArray, line_number: int, cards: Dictionary, ids: Dictionary, errors: Array[String]) -> int:
	if row.size() != FIELD_NAMES.size():
		errors.append("第%d行列数应为%d，实际为%d" % [line_number, FIELD_NAMES.size(), row.size()])
		return -1
	var numeric_id := _parse_uint(row[0], 1, 65535, "ID", line_number, errors)
	var cost := _parse_uint(row[3], 0, 99, "能量费用", line_number, errors)
	var card_type := _map_value(row[4], {1: CARD_DEFINITION.CardType.ATTACK, 2: CARD_DEFINITION.CardType.ABILITY, 3: CARD_DEFINITION.CardType.DEFENSE}, "卡牌类型", line_number, errors)
	var shot_type := _map_value(row[5], {0: CARD_DEFINITION.ShotType.NONE, 1: CARD_DEFINITION.ShotType.STRAIGHT, 2: CARD_DEFINITION.ShotType.BANANA, 3: CARD_DEFINITION.ShotType.LOB, 4: CARD_DEFINITION.ShotType.RANDOM}, "射门类型", line_number, errors)
	var rarity := _map_value(row[6], {1: CARD_DEFINITION.Rarity.COMMON, 2: CARD_DEFINITION.Rarity.BOSS}, "稀有度", line_number, errors)
	var delay := _parse_float(row[7], 0.0, 16.0, "攻击延迟拍数", line_number, errors)
	var interval := _parse_float(row[8], 0.0, 16.0, "多段攻击间隔拍数", line_number, errors)
	var effect_id := _parse_uint(row[9], 1, 65535, "效果ID", line_number, errors)
	var amounts := _parse_uint_list(row[10], 0, 999, "基础数值", line_number, errors)
	var hits := _parse_uint_list(row[11], 1, 99, "生效次数", line_number, errors)
	var amounts_per_energy := _parse_uint_list(row[12], 0, 255, "每点剩余能量加成", line_number, errors)
	var multipliers := _parse_uint_list(row[13], 0, 255, "效果倍率", line_number, errors)
	var chances := _parse_uint_list(row[14], 0, 100, "触发概率", line_number, errors)
	var interrupts := _parse_uint_list(row[15], 0, 1, "成功后中断", line_number, errors)
	var source_file := row[16].strip_edges()
	if source_file.is_empty() or not _is_safe_resource_name(source_file):
		errors.append("第%d行资源文件名无效：%s" % [line_number, source_file])
		return -1
	if numeric_id < 0 or cost < 0 or card_type < 0 or shot_type < 0 or rarity < 0 or delay < 0 or interval < 0.0 or effect_id < 0:
		return -1
	var value_count := amounts.size()
	if value_count == 0 or hits.size() != value_count or amounts_per_energy.size() != value_count or multipliers.size() != value_count or chances.size() != value_count or interrupts.size() != value_count:
		errors.append("卡牌主表第%d行各数值列的参数组数必须相同且不为空" % line_number)
		return -1
	if not _id_matches_card_type(numeric_id, card_type):
		errors.append("第%d行ID %d 不在卡牌类型%d对应号段内" % [line_number, numeric_id, row[4].to_int()])
		return -1
	if ids.has(numeric_id):
		errors.append("卡牌主表第%d行ID %d 重复" % [line_number, numeric_id])
		return -1
	if cards.has(source_file):
		errors.append("卡牌主表第%d行资源文件名 %s 重复" % [line_number, source_file])
		return -1

	var card_data := {
		"id": numeric_id,
		"source_file": source_file,
		"display_name": row[1],
		"description": row[2],
		"cost": cost,
		"card_type": card_type,
		"shot_type": shot_type,
		"rarity": rarity,
		"attack_delay_beats": delay,
		"multi_hit_interval_beats": interval,
		"effect_id": effect_id,
		"values": [],
		"effects": [],
	}
	for index in range(value_count):
		card_data.values.append({
			"amount": amounts[index], "hits": hits[index],
			"amount_per_energy": amounts_per_energy[index],
			"multiplier": multipliers[index] / 100.0,
			"chance_percent": chances[index],
			"interrupt_on_success": interrupts[index] == 1,
		})
	cards[source_file] = card_data
	ids[numeric_id] = source_file
	return numeric_id


# 效果模板 ID 独立于卡牌 ID；末列描述仅供策划查看，不参与资源生成或战斗结算。
func _parse_effect_row(row: PackedStringArray, line_number: int, templates: Dictionary, errors: Array[String]) -> int:
	if row.size() != EFFECT_FIELD_NAMES.size():
		errors.append("效果模板表第%d行列数应为%d，实际为%d" % [line_number, EFFECT_FIELD_NAMES.size(), row.size()])
		return -1
	var numeric_id := _parse_uint(row[0], 1, 65535, "效果ID", line_number, errors)
	if numeric_id < 0:
		return -1
	if row[1].strip_edges().is_empty() or templates.has(numeric_id):
		errors.append("效果模板表第%d行名称为空或ID %d 重复" % [line_number, numeric_id])
		return -1
	templates[numeric_id] = {"name": row[1], "steps": []}
	return numeric_id


# 步骤只定义行为与目标；末列描述仅供策划查看，战斗数值从引用模板的卡牌行填入。
func _parse_step_row(row: PackedStringArray, line_number: int, templates: Dictionary, errors: Array[String]) -> int:
	if row.size() != STEP_FIELD_NAMES.size():
		errors.append("效果步骤表第%d行列数应为%d，实际为%d" % [line_number, STEP_FIELD_NAMES.size(), row.size()])
		return -1
	var numeric_id := _parse_uint(row[0], 1, 65535, "效果ID", line_number, errors)
	var effect_index := _parse_uint(row[1], 1, 255, "效果序号", line_number, errors)
	var effect_type := _map_value(row[2], {1: EFFECT_DEFINITION.EffectType.DAMAGE, 2: EFFECT_DEFINITION.EffectType.SHIELD, 3: EFFECT_DEFINITION.EffectType.HEAL, 4: EFFECT_DEFINITION.EffectType.ENERGY, 5: EFFECT_DEFINITION.EffectType.APPLY_STRENGTH, 6: EFFECT_DEFINITION.EffectType.APPLY_WEAKNESS, 7: EFFECT_DEFINITION.EffectType.BGM_PITCH_UP, 8: EFFECT_DEFINITION.EffectType.BGM_PITCH_DOWN, 9: EFFECT_DEFINITION.EffectType.BGM_PITCH_RESET, 10: EFFECT_DEFINITION.EffectType.BANANA_DIRECTION_LEFT, 11: EFFECT_DEFINITION.EffectType.BANANA_DIRECTION_RIGHT}, "效果类型", line_number, errors)
	var target := _map_value(row[3], {1: EFFECT_DEFINITION.Target.SELF, 2: EFFECT_DEFINITION.Target.ENEMY}, "效果目标", line_number, errors)
	if numeric_id < 0 or effect_index < 0 or effect_type < 0 or target < 0:
		return -1
	if not templates.has(numeric_id):
		errors.append("效果步骤表第%d行引用不存在的效果ID %d" % [line_number, numeric_id])
		return -1
	var steps: Array = templates[numeric_id]["steps"]
	if steps.size() != effect_index - 1:
		errors.append("效果步骤表第%d行序号必须从1连续递增" % line_number)
		return -1
	steps.append({"effect_type": effect_type, "target": target})
	return numeric_id


# 保存后强制绕过旧缓存重新加载并逐字段比对；只有回读一致才算导入成功。
func _save_and_verify_card(data: Dictionary, output_directory: String) -> String:
	var resource_path := "%s/%s.tres" % [output_directory, data["source_file"]]
	var stable_id: String = data["source_file"]
	if ResourceLoader.exists(resource_path):
		var existing := load(resource_path)
		var existing_id: Variant = existing.get("card_id") if existing != null else ""
		if existing_id is String and not String(existing_id).is_empty():
			stable_id = existing_id
	var card := CARD_DEFINITION.new()
	card.card_id = stable_id
	card.display_name = data.display_name
	card.description = data.description
	card.cost = data.cost
	card.card_type = data.card_type
	card.shot_type = data.shot_type
	card.attack_delay_beats = data.attack_delay_beats
	card.multi_hit_interval_beats = data.multi_hit_interval_beats
	card.rarity = data.rarity
	for effect_data in data.effects:
		var effect := EFFECT_DEFINITION.new()
		effect.effect_type = effect_data.effect_type
		effect.target = effect_data.target
		effect.amount = effect_data.amount
		effect.hits = effect_data.hits
		effect.amount_per_energy = effect_data.amount_per_energy
		effect.multiplier = effect_data.multiplier
		effect.chance_percent = effect_data.chance_percent
		effect.interrupt_on_success = effect_data.interrupt_on_success
		card.effects.append(effect)
	var save_error := ResourceSaver.save(card, resource_path)
	if save_error != OK:
		return "保存卡牌失败：%s（错误码%d）" % [resource_path, save_error]
	var saved_card := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return _verify_saved_card(saved_card, card, resource_path)


# 对导入器实际写入磁盘的结果做独立回读，覆盖卡牌字段、效果顺序和所有战斗数值。
func _verify_saved_card(saved_card: Resource, expected_card: Resource, resource_path: String) -> String:
	if saved_card == null:
		return "导入后无法重新加载卡牌：%s" % resource_path
	for property_name in ["card_id", "display_name", "description", "cost", "card_type", "shot_type", "rarity"]:
		if saved_card.get(property_name) != expected_card.get(property_name):
			return "导入回读不一致：%s 的 %s" % [resource_path, property_name]
	if not is_equal_approx(saved_card.attack_delay_beats, expected_card.attack_delay_beats):
		return "导入回读不一致：%s 的 attack_delay_beats" % resource_path
	if not is_equal_approx(saved_card.multi_hit_interval_beats, expected_card.multi_hit_interval_beats):
		return "导入回读不一致：%s 的 multi_hit_interval_beats" % resource_path
	if saved_card.effects.size() != expected_card.effects.size():
		return "导入回读不一致：%s 的效果数量" % resource_path
	for effect_index in range(expected_card.effects.size()):
		var saved_effect: Resource = saved_card.effects[effect_index]
		var expected_effect: Resource = expected_card.effects[effect_index]
		for property_name in ["effect_type", "target", "amount", "hits", "amount_per_energy", "chance_percent", "interrupt_on_success"]:
			if saved_effect.get(property_name) != expected_effect.get(property_name):
				return "导入回读不一致：%s 的效果%d字段 %s" % [resource_path, effect_index + 1, property_name]
		if not is_equal_approx(saved_effect.multiplier, expected_effect.multiplier):
			return "导入回读不一致：%s 的效果%d倍率" % [resource_path, effect_index + 1]
	return ""


# CSV 的 UTF-8 BOM 只可能出现在首个字段，读取时移除以保证字段名匹配。
func _read_csv_row(file: FileAccess) -> PackedStringArray:
	var row := file.get_csv_line()
	if not row.is_empty():
		row[0] = row[0].trim_prefix("\ufeff")
	return row


# CSV 行是 PackedStringArray，约定表头是常量数组；逐项比较可兼容两种容器且避免构造型常量解析失败。
func _row_matches(row: PackedStringArray, expected: Array) -> bool:
	if row.size() != expected.size():
		return false
	for column_index in range(expected.size()):
		if row[column_index] != expected[column_index]:
			return false
	return true


# 策划表仅允许小写英文、数字和下划线文件名，避免 CSV 配置越过 cards 输出目录。
func _is_safe_resource_name(value: String) -> bool:
	for character in value:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_".contains(character):
			return false
	return true


# 数字 ID 按卡牌类别分段，防止配置错类后仍生成看似合法的资源。
func _id_matches_card_type(numeric_id: int, card_type: int) -> bool:
	match card_type:
		CARD_DEFINITION.CardType.ATTACK:
			return numeric_id >= 1001 and numeric_id <= 1999
		CARD_DEFINITION.CardType.ABILITY:
			return numeric_id >= 2001 and numeric_id <= 2999
		CARD_DEFINITION.CardType.DEFENSE:
			return numeric_id >= 3001 and numeric_id <= 3999
	return false


func _parse_uint(value: String, minimum: int, maximum: int, label: String, line_number: int, errors: Array[String]) -> int:
	var text := value.strip_edges()
	if not text.is_valid_int():
		errors.append("第%d行%s必须是整数" % [line_number, label])
		return -1
	var parsed := text.to_int()
	if parsed < minimum or parsed > maximum:
		errors.append("第%d行%s必须在%d到%d之间" % [line_number, label, minimum, maximum])
		return -1
	return parsed


# 多步骤数值在同一单元格用竖线分隔；逐项执行原有范围检查，避免隐式转换吞掉坏值。
func _parse_uint_list(value: String, minimum: int, maximum: int, label: String, line_number: int, errors: Array[String]) -> Array[int]:
	var values: Array[int] = []
	for part in value.split("|", true):
		var parsed := _parse_uint(part, minimum, maximum, label, line_number, errors)
		if parsed < 0:
			return []
		values.append(parsed)
	return values


func _parse_float(value: String, minimum: float, maximum: float, label: String, line_number: int, errors: Array[String]) -> float:
	var text := value.strip_edges()
	if not text.is_valid_float():
		errors.append("第%d行%s必须是小数" % [line_number, label])
		return -1.0
	var parsed := text.to_float()
	if parsed < minimum or parsed > maximum:
		errors.append("第%d行%s必须在%.1f到%.1f之间" % [line_number, label, minimum, maximum])
		return -1.0
	return parsed


func _map_value(value: String, mapping: Dictionary, label: String, line_number: int, errors: Array[String]) -> int:
	var parsed := _parse_uint(value, 0, 255, label, line_number, errors)
	if parsed < 0:
		return -1
	if not mapping.has(parsed):
		errors.append("第%d行%s取值%d无效" % [line_number, label, parsed])
		return -1
	return mapping[parsed]


func _effect_count(cards: Dictionary) -> int:
	var count := 0
	for source_file in cards:
		count += cards[source_file]["effects"].size()
	return count
