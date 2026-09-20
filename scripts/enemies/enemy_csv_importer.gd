@tool
# 怪物三表导入器：完整校验后暂存、回读、发布，失败时恢复所有已经发布的旧文件。
class_name EnemyCsvImporter
extends RefCounted

const ENEMY := preload("res://scripts/enemies/enemy_definition.gd")
const ACTION := preload("res://scripts/enemies/enemy_action_definition.gd")
const EFFECT := preload("res://scripts/enemies/enemy_action_effect.gd")
const CATALOG := preload("res://scripts/enemies/enemy_catalog.gd")
const POOL := preload("res://scripts/enemies/encounter_pool.gd")
const MONSTER_FIELDS := ["id", "display_name", "tier", "chapter", "max_health", "action_mode", "action_ids", "action_weights", "enabled", "source_file", "image_id"]
const MONSTER_TYPES := ["uint16", "string", "uint8", "uint8", "uint16", "uint8", "uint16_list", "uint16_list", "uint8", "string", "uint16"]
const ACTION_FIELDS := ["id", "display_name", "category", "description", "interrupted_action_id"]
const ACTION_TYPES := ["uint16", "string", "uint8", "string", "uint16"]
# 末列 remark 只供策划阅读；校验其表头与列数，但不写入运行时效果资源。
const EFFECT_FIELDS := ["id", "action_id", "step", "effect_type", "target", "amount", "hits", "turns", "multiplier_percent", "break_rule", "threshold", "remark"]
const EFFECT_TYPES := ["uint16", "uint16", "uint8", "uint8", "uint8", "uint16", "uint8", "uint8", "uint16", "uint8", "uint16", "string"]


# 纯校验入口不写资源；统一工具可在卡牌与战利品写入前先验证怪物表。
func validate_tables(monsters_path := "res://tables/monsters.csv", actions_path := "res://tables/monster_actions.csv", effects_path := "res://tables/monster_action_effects.csv") -> Dictionary:
	var errors: Array[String] = []
	var monster_rows := _read_table(monsters_path, MONSTER_FIELDS, MONSTER_TYPES, errors)
	var action_rows := _read_table(actions_path, ACTION_FIELDS, ACTION_TYPES, errors)
	var effect_rows := _read_table(effects_path, EFFECT_FIELDS, EFFECT_TYPES, errors)
	var monsters := {}
	var actions := {}
	var effect_ids := {}
	var source_files := {}
	var image_ids := {}
	for row in action_rows:
		var action = ACTION.new()
		action.id = _integer(row.id, 1, 65535, "行为ID", errors)
		action.display_name = row.display_name
		action.category = _integer(row.category, 0, 2, "行为类别", errors)
		action.description = row.description
		action.interrupted_action_id = _integer(row.interrupted_action_id, 0, 65535, "替代行为ID", errors)
		if action.display_name.is_empty() or action.description.is_empty():
			errors.append("行为名称与意图说明不能为空")
		_unique(action.id, actions, "行为ID", errors)
		actions[action.id] = action
	for row in effect_rows:
		var effect_id := _integer(row.id, 1, 65535, "效果ID", errors)
		_unique(effect_id, effect_ids, "效果ID", errors)
		effect_ids[effect_id] = true
		var action_id := _integer(row.action_id, 1, 65535, "效果关联行为ID", errors)
		var step := _integer(row.step, 1, 255, "效果步骤", errors)
		var effect = EFFECT.new()
		effect.effect_type = _integer(row.effect_type, 0, 9, "效果类型", errors)
		effect.target = _integer(row.target, 0, 1, "目标", errors)
		effect.amount = _integer(row.amount, 0, 999, "效果数值", errors)
		effect.hits = _integer(row.hits, 1, 20, "次数", errors)
		effect.turns = _integer(row.turns, 0, 99, "持续回合", errors)
		effect.multiplier = _integer(row.multiplier_percent, 0, 1000, "倍率百分比", errors) / 100.0
		effect.break_rule = _integer(row.break_rule, 0, 5, "蓄力打断规则", errors)
		effect.threshold = _integer(row.threshold, 0, 9999, "打断阈值", errors)
		if not actions.has(action_id):
			errors.append("效果引用不存在的行为ID：%d" % action_id)
			continue
		var action: Resource = actions[action_id]
		if step != action.effects.size() + 1:
			errors.append("行为%d步骤必须从1连续递增" % action_id)
		_validate_effect(action, effect, errors)
		action.effects.append(effect)
	for action_id in actions:
		var action: Resource = actions[action_id]
		if action.effects.is_empty():
			errors.append("行为%d没有效果" % action_id)
		# 多条蓄力效果表达或条件；重复规则会使阈值含义不明确。
		var charge_rules := {}
		for effect in action.effects:
			if effect.effect_type == EFFECT.Type.CHARGE:
				if charge_rules.has(effect.break_rule):
					errors.append("行为%d蓄力打断规则重复" % action_id)
				charge_rules[effect.break_rule] = true
		if action.category == ACTION.Category.ATTACK:
			var has_direct_damage := false
			for effect in action.effects:
				has_direct_damage = has_direct_damage or effect.effect_type in [EFFECT.Type.DAMAGE, EFFECT.Type.DRAIN]
			if not has_direct_damage:
				errors.append("攻击行为必须含直接伤害，纯状态应属于技能")
		if action.interrupted_action_id > 0:
			if not actions.has(action.interrupted_action_id) or action.interrupted_action_id == action.id:
				errors.append("行为%d的替代行为引用无效" % action_id)
			elif actions[action.interrupted_action_id].category != ACTION.Category.ATTACK or actions[action.interrupted_action_id].interrupted_action_id > 0:
				errors.append("蓄力替代行为必须为不含替代引用的攻击")
	for row in monster_rows:
		var monster = ENEMY.new()
		monster.id = _integer(row.id, 6001, 6099, "怪物ID（6001～6099）", errors)
		monster.display_name = row.display_name
		monster.tier = _integer(row.tier, 0, 2, "级别", errors)
		monster.chapter = _integer(row.chapter, 1, 3, "章节", errors)
		monster.max_health = _integer(row.max_health, 1, 9999, "生命", errors)
		monster.action_mode = _integer(row.action_mode, 0, 1, "行动模式", errors)
		monster.encounter_enabled = _integer(row.enabled, 0, 1, "启用", errors) == 1
		monster.enemy_id = row.source_file
		# 0 保留旧怪物占位图；非零图片必须唯一且文件存在，防止导出后显示错误怪物。
		monster.image_id = _integer(row.image_id, 0, 65535, "怪物图片ID", errors)
		if monster.image_id > 0:
			_unique(monster.image_id, image_ids, "怪物图片ID", errors)
			image_ids[monster.image_id] = true
			var image_path := "res://assets/ui/enemies/%d.png" % monster.image_id
			if not FileAccess.file_exists(image_path):
				errors.append("怪物图片不存在：%s" % image_path)
		var safe_name := RegEx.new()
		safe_name.compile("^enemy_[a-z0-9_]+$")
		if safe_name.search(monster.enemy_id) == null:
			errors.append("资源文件名必须是安全的enemy_英文名称")
		if CATALOG.LEGACY_IDS.has(monster.enemy_id):
			errors.append("新怪物不能覆盖旧存档保留资源：%s" % monster.enemy_id)
		if monster.display_name.is_empty():
			errors.append("怪物名称不能为空")
		_unique(monster.id, monsters, "怪物ID", errors)
		_unique(monster.enemy_id, source_files, "资源文件名", errors)
		source_files[monster.enemy_id] = true
		monster.action_ids.assign(_integer_list(row.action_ids, false, "行为列表", errors))
		monster.action_weights.assign(_integer_list(row.action_weights, true, "权重列表", errors))
		if monster.action_mode == ENEMY.ActionMode.SEQUENCE and not monster.action_weights.is_empty():
			errors.append("固定模式权重必须留空")
		if monster.action_mode == ENEMY.ActionMode.WEIGHTED_RANDOM and not monster.action_weights.is_empty() and monster.action_weights.size() != monster.action_ids.size():
			errors.append("随机权重数量必须与行为数量一致")
		var categories := {}
		var has_charge := false
		var has_finisher := false
		for action_id in monster.action_ids:
			if not actions.has(action_id):
				errors.append("怪物%d引用不存在的行为%d" % [monster.id, action_id])
				continue
			var action: Resource = actions[action_id]
			monster.actions.append(action)
			categories[action.category] = true
			has_finisher = has_finisher or action.interrupted_action_id > 0
			for effect in action.effects:
				has_charge = has_charge or effect.effect_type == EFFECT.Type.CHARGE
		if categories.is_empty() or categories.size() > 3:
			errors.append("怪物必须拥有1～3种行为类别")
		if has_charge != has_finisher:
			errors.append("蓄力行为与带替代引用的重击必须成对配置")
		# 首版蓄力只支持固定列表中紧邻重击，防止随机模式留下永不消耗的蓄力状态。
		if has_charge:
			if monster.action_mode != ENEMY.ActionMode.SEQUENCE:
				errors.append("蓄力首版仅支持固定循环")
			for index in range(monster.actions.size()):
				var action: Resource = monster.actions[index]
				var is_charge := false
				for effect in action.effects:
					is_charge = is_charge or effect.effect_type == EFFECT.Type.CHARGE
				var following: Resource = monster.actions[(index + 1) % monster.actions.size()]
				if is_charge and following.interrupted_action_id == 0:
					errors.append("蓄力后必须紧邻可取消的重击")
				if action.interrupted_action_id > 0:
					var previous: Resource = monster.actions[(index - 1 + monster.actions.size()) % monster.actions.size()]
					var previous_charge := false
					for effect in previous.effects:
						previous_charge = previous_charge or effect.effect_type == EFFECT.Type.CHARGE
					if not previous_charge:
						errors.append("可取消的重击前必须有蓄力")
		monsters[monster.id] = monster
	if monsters.is_empty() or actions.is_empty():
		errors.append("怪物表和行为表不能为空")
	return {"ok": errors.is_empty(), "errors": errors, "monsters": monsters, "actions": actions, "effect_count": effect_ids.size()}


# 对效果的业务组合进行验证；不允许类别写攻击却只获得护盾，也不允许无阈值蓄力。
func _validate_effect(action: Resource, effect: Resource, errors: Array[String]) -> void:
	var attack_effects := [EFFECT.Type.DAMAGE, EFFECT.Type.DRAIN, EFFECT.Type.BLEED]
	var defense_effects := [EFFECT.Type.SHIELD, EFFECT.Type.BLOCK, EFFECT.Type.THORNS]
	if action.category == ACTION.Category.ATTACK and effect.effect_type not in attack_effects:
		errors.append("攻击行为仅支持伤害、吸血与流血")
	if action.category == ACTION.Category.DEFENSE and effect.effect_type not in defense_effects:
		errors.append("防御行为仅支持护盾、格挡与反伤")
	if effect.effect_type in [EFFECT.Type.DAMAGE, EFFECT.Type.DRAIN, EFFECT.Type.BLEED, EFFECT.Type.WEAKNESS] and effect.target != EFFECT.Target.PLAYER:
		errors.append("伤害、吸血、流血、虚弱目标必须为玩家")
	if effect.effect_type in [EFFECT.Type.SHIELD, EFFECT.Type.HEAL, EFFECT.Type.STRENGTH, EFFECT.Type.BLOCK, EFFECT.Type.THORNS, EFFECT.Type.CHARGE] and effect.target != EFFECT.Target.ENEMY:
		errors.append("防御、治疗、强化、蓄力目标必须为自身")
	if effect.effect_type in [EFFECT.Type.BLEED, EFFECT.Type.WEAKNESS, EFFECT.Type.STRENGTH] and effect.turns <= 0:
		errors.append("持续状态回合必须为正数")
	if effect.effect_type not in [EFFECT.Type.BLEED, EFFECT.Type.WEAKNESS, EFFECT.Type.STRENGTH] and effect.turns != 0:
		errors.append("非持续状态的回合必须填0，架势按固定边界失效")
	if effect.effect_type not in [EFFECT.Type.DAMAGE, EFFECT.Type.DRAIN, EFFECT.Type.THORNS] and effect.hits != 1:
		errors.append("只有伤害、吸血和反伤允许填写多次")
	if effect.effect_type not in [EFFECT.Type.WEAKNESS, EFFECT.Type.STRENGTH] and effect.multiplier != 1.0:
		errors.append("非力量/虚弱效果倍率必须填100")
	if effect.effect_type in [EFFECT.Type.WEAKNESS, EFFECT.Type.STRENGTH, EFFECT.Type.CHARGE] and effect.amount != 0:
		errors.append("力量、虚弱和蓄力不使用amount，必须填0")
	if effect.effect_type == EFFECT.Type.WEAKNESS and effect.multiplier > 1.0:
		errors.append("虚弱倍率不能超过100%")
	if effect.effect_type == EFFECT.Type.STRENGTH and effect.multiplier < 1.0:
		errors.append("力量倍率不能低于100%")
	if effect.effect_type == EFFECT.Type.CHARGE:
		if action.category != ACTION.Category.SKILL or effect.break_rule == EFFECT.BreakRule.NONE or effect.threshold <= 0:
			errors.append("蓄力必须属于技能且具有有效打断条件")
	elif effect.break_rule != EFFECT.BreakRule.NONE or effect.threshold != 0:
		errors.append("只有蓄力效果可填写打断条件")


# 先暂存并深度回读全部资源，再发布；目录和章节池仅由本表拥有的章节生成。
func import_monsters(monsters_path := "res://tables/monsters.csv", output_directory := "res://data/enemies/chapter_one", actions_path := "res://tables/monster_actions.csv", effects_path := "res://tables/monster_action_effects.csv", encounters_directory := "res://data/encounters", catalog_path := "res://data/enemies/enemy_catalog.tres") -> Dictionary:
	var result := validate_tables(monsters_path, actions_path, effects_path)
	if not result.ok:
		return result
	var catalog = CATALOG.new()
	for monster in result.monsters.values():
		catalog.enemies.append(monster)
	for action in result.actions.values():
		catalog.actions.append(action)
	var outputs := {}
	var pools := {}
	for monster in catalog.enemies:
		# 保留第一章既有路径；新章节写入独立目录，避免所有资源误落在 chapter_one。
		var monster_directory: String = output_directory
		if monster.chapter > 1:
			monster_directory = output_directory.get_base_dir().path_join("chapter_%d" % monster.chapter)
		outputs[monster_directory.path_join(monster.enemy_id + ".tres")] = monster.duplicate(true)
		if not pools.has(monster.chapter):
			var pool = POOL.new()
			pool.chapter = monster.chapter
			pools[monster.chapter] = pool
		pools[monster.chapter].enemies.append(monster.duplicate(true))
	for chapter in pools:
		var tiers := {}
		for monster in pools[chapter].enemies:
			if monster.encounter_enabled:
				tiers[monster.tier] = true
		if tiers.size() != 3:
			return {"ok": false, "errors": ["第%d章必须包含启用的小怪、精英和Boss" % chapter]}
		outputs[encounters_directory.path_join("chapter_%d.tres" % chapter)] = pools[chapter]
	outputs[catalog_path] = catalog.duplicate(true)
	var stage_directory := "res://.godot/monster_stage_%d" % OS.get_process_id()
	if DirAccess.make_dir_recursive_absolute(stage_directory) != OK:
		return {"ok": false, "errors": ["无法创建怪物暂存目录"]}
	var staged := {}
	var errors: Array[String] = []
	for path in outputs:
		var stage_path := stage_directory.path_join("%d.tres" % staged.size())
		staged[path] = stage_path
		var resource: Resource = outputs[path]
		if ResourceSaver.save(resource, stage_path) != OK:
			errors.append("暂存写入失败：%s" % path)
			break
		var readback: Resource = ResourceLoader.load(stage_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if readback == null or _snapshot(readback) != _snapshot(resource):
			errors.append("暂存资源回读不一致：%s" % path)
			break
	var previous := {}
	if errors.is_empty():
		for path in staged:
			previous[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
			if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK or DirAccess.copy_absolute(staged[path], path) != OK:
				errors.append("发布失败，回滚全部本次文件：%s" % path)
				break
			var readback: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			if readback == null or _snapshot(readback) != _snapshot(outputs[path]):
				errors.append("发布回读失败，回滚全部本次文件：%s" % path)
				break
	if not errors.is_empty():
		for path in previous:
			if previous[path] == null:
				if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
					errors.append("回滚删除失败：%s" % path)
			else:
				var file := FileAccess.open(path, FileAccess.WRITE)
				if file == null:
					errors.append("回滚恢复失败：%s" % path)
				else:
					file.store_buffer(previous[path])
					file.close()
	for stage_path in staged.values():
		if FileAccess.file_exists(stage_path):
			DirAccess.remove_absolute(stage_path)
	DirAccess.remove_absolute(stage_directory)
	return {"ok": errors.is_empty(), "errors": errors, "monster_count": catalog.enemies.size(), "action_count": catalog.actions.size(), "effect_count": result.effect_count}


# 比较所有导出业务属性及嵌套效果，忽略资源路径、UID和脚本缓存。
func _snapshot(resource: Resource) -> Dictionary:
	var result := {}
	for property in resource.get_property_list():
		var key: String = property.name
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or property.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var value: Variant = resource.get(key)
		if value is Array:
			var values: Array = []
			for element in value:
				values.append(_snapshot(element) if element is Resource else element)
			result[key] = values
		else:
			result[key] = value
	return result


# 使用 Godot CSV 解析器处理引号与逗号；三行结构、说明行非空及ID排序都严格校验。
func _read_table(path: String, fields: Array, types: Array, errors: Array[String]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("无法打开CSV：%s" % path)
		return rows
	var comments := file.get_csv_line()
	var names := file.get_csv_line()
	var declared_types := file.get_csv_line()
	if comments.size() != fields.size() or Array(names) != fields or Array(declared_types) != types:
		errors.append("CSV前三行结构错误：%s" % path)
		return rows
	for comment in comments:
		if comment.strip_edges().is_empty():
			errors.append("中文说明行不能有空列：%s" % path)
	var previous_id := 0
	while not file.eof_reached():
		var values := file.get_csv_line()
		if values.size() == 1 and values[0].is_empty():
			continue
		if values.size() != fields.size():
			errors.append("CSV数据列数错误：%s" % path)
			continue
		var row := {}
		for index in range(fields.size()):
			row[fields[index]] = values[index]
		if not values[0].is_valid_int() or values[0].to_int() < previous_id:
			errors.append("CSV首列ID必须为升序整数：%s" % path)
		previous_id = values[0].to_int()
		rows.append(row)
	return rows


func _integer(value: String, minimum: int, maximum: int, label: String, errors: Array[String]) -> int:
	if not value.is_valid_int() or value.to_int() < minimum or value.to_int() > maximum:
		errors.append("%s必须为%d～%d的整数，实际：%s" % [label, minimum, maximum, value])
		return minimum
	return value.to_int()


# 分号仅用于单元格内部的整数列表，CSV列解析仍由 get_csv_line 完成。
func _integer_list(value: String, allow_empty: bool, label: String, errors: Array[String]) -> Array[int]:
	var result: Array[int] = []
	if allow_empty and value.is_empty():
		return result
	for part in value.split(";", true):
		result.append(_integer(part, 1, 65535, label, errors))
	return result


func _unique(key: Variant, values: Dictionary, label: String, errors: Array[String]) -> void:
	if values.has(key):
		errors.append("%s重复：%s" % [label, key])
