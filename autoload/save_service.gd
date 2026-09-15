# 持久化存档服务：负责版本化 JSON 校验、旧战利品键与游戏历程能量上限迁移及崩溃安全替换。
extends Node

const SAVE_VERSION := 3
const DEFAULT_SAVE_PATH := "user://run_save.json"
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")

# 测试可覆盖路径以隔离真实玩家存档；正式运行始终使用 user:// 下的固定文件。
var save_path := DEFAULT_SAVE_PATH
var last_error := ""


# RunState 先于本服务挂载，因此这里可直接尝试恢复；失败只记录原因并保留未开始状态。
func _ready() -> void:
	load_game()


# v1 英文战利品键先迁移为数字 ID；v2 再补游戏历程级能量上限字段，最终统一升级到 v3。
func _migrate_payload(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("save_version", 0))
	if version == SAVE_VERSION:
		return payload
	var migrated := payload.duplicate(true)
	if version == 1 and payload.get("run_state") is Dictionary:
		var state: Dictionary = migrated.run_state
		var numeric_ids: Array[int] = []
		var legacy_values: Variant = state.get("owned_item_ids", [])
		if legacy_values is Array:
			var rewards := REWARD_SERVICE.new()
			for value in legacy_values:
				if value is not String:
					continue
				var numeric_id: int = rewards.get_item_id_by_legacy_key(value)
				if numeric_id > 0 and numeric_id not in numeric_ids:
					numeric_ids.append(numeric_id)
				else:
					_record_diagnostic("legacy_item_ignored", {"legacy_item_id": value})
		state["owned_item_ids"] = numeric_ids
		migrated["run_state"] = state
		version = 2
	if version == 2 and migrated.get("run_state") is Dictionary:
		var state: Dictionary = migrated.run_state
		state["run_max_energy_bonus"] = maxi(int(state.get("run_max_energy_bonus", 0)), 0)
		migrated["run_state"] = state
		migrated["save_version"] = SAVE_VERSION
		return migrated
	return {}


# 只有结构、版本和 RunState 主体都有效时才视为可继续存档。
func has_valid_save() -> bool:
	return not _read_payload().is_empty()


# 从磁盘读取并恢复指定状态；损坏或不兼容存档返回 false，不改变当前内存状态。
func load_game(target_run_state: Node = null) -> bool:
	var payload := _read_payload()
	if payload.is_empty():
		_record_diagnostic("load_failed", {"reason": last_error})
		return false
	var state := target_run_state if target_run_state != null else get_node_or_null("/root/RunState")
	if state == null:
		last_error = "RunState 不可用"
		return false
	var loaded: bool = state.from_dict(payload.run_state)
	_record_diagnostic("loaded" if loaded else "load_failed", {"save_version": SAVE_VERSION})
	return loaded


# 写入完整安全节点快照；临时文件通过回读解析后才替换正式档，并保留备份用于替换失败回滚。
func save_game(source_run_state: Node = null) -> bool:
	var state := source_run_state if source_run_state != null else get_node_or_null("/root/RunState")
	if state == null:
		last_error = "RunState 不可用"
		return false
	var payload := {"save_version": SAVE_VERSION, "run_state": state.to_dict()}
	var temp_path := save_path + ".tmp"
	var backup_path := save_path + ".bak"
	_remove_if_exists(temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "无法创建临时存档：%s" % FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	if _read_payload_from(temp_path).is_empty():
		last_error = "临时存档回读校验失败"
		_remove_if_exists(temp_path)
		return false

	_remove_if_exists(backup_path)
	if FileAccess.file_exists(save_path):
		var backup_error := DirAccess.rename_absolute(save_path, backup_path)
		if backup_error != OK:
			last_error = "无法备份旧存档：%s" % error_string(backup_error)
			_remove_if_exists(temp_path)
			return false
	var replace_error := DirAccess.rename_absolute(temp_path, save_path)
	if replace_error != OK:
		last_error = "无法提交新存档：%s" % error_string(replace_error)
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, save_path)
		return false
	_remove_if_exists(backup_path)
	last_error = ""
	_record_diagnostic("saved", {"save_version": SAVE_VERSION, "chapter": state.chapter})
	return true


# 读取、解析并迁移存档；任何 JSON/字段错误都降级为无存档，不向启动流程抛出错误。
func _read_payload() -> Dictionary:
	var payload := _read_payload_from(save_path)
	if not payload.is_empty():
		return payload
	# 若进程恰在正式档换名后中断，备份仍是上一安全节点，可用于无损启动恢复。
	return _read_payload_from(save_path + ".bak")


func _read_payload_from(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		last_error = ""
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "无法读取存档：%s" % FileAccess.get_open_error()
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or json.data is not Dictionary:
		last_error = "存档 JSON 已损坏"
		return {}
	var parsed: Dictionary = json.data
	var migrated := _migrate_payload(parsed)
	if migrated.is_empty() or migrated.get("run_state") is not Dictionary:
		last_error = "存档版本或主体无效"
		return {}
	last_error = ""
	return migrated


# 删除仅限服务自身精确派生的临时/备份路径，不触碰其他用户文件。
func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# 存档诊断只记录结果与版本，不记录 user:// 实际路径或文件内容。
func _record_diagnostic(event_name: String, fields: Dictionary) -> void:
	if not is_inside_tree():
		return
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("save", event_name, fields)
