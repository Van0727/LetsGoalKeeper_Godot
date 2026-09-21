# 怪物配表验收：覆盖三行契约、缺失/重复/越界/无效引用、失败无写入、发布回滚和资源回读。
extends SceneTree

const IMPORTER := preload("res://scripts/enemies/enemy_csv_importer.gd")
const CATALOG := preload("res://data/enemies/enemy_catalog.tres")
const MAP := preload("res://scripts/map/map_state.gd")
const GENERATOR := preload("res://scripts/map/map_generator.gd")
const POOL := preload("res://data/encounters/chapter_1.tres")
var _failed := false
# 沙箱与本地编辑器的 user:// 可写性可能不同；夹具放在项目缓存并在测试末清理。
var _directory := "res://.godot/monster_tables_%d" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var importer := IMPORTER.new()
	var result := importer.validate_tables()
	_check(result.ok, "正式三表校验成功")
	if result.ok:
		_check(result.monsters.size() == 13 and result.actions.size() == 44 and result.effect_count == 54, "正式数据数量")
		_check(is_equal_approx(result.monsters[6021].battle_image_scale, 2.5), "大象战斗图片缩放倍率读取正确")
	DirAccess.make_dir_recursive_absolute(_directory)
	var rows := _read_rows("res://tables/monsters.csv")
	# 夹具只取第一章六只；第三章正式数据由下方目录与章节池回读覆盖。
	rows = rows.slice(0, 3) + rows.slice(3).filter(func(row: Array) -> bool: return row[3] == "1")
	# 自建怪物夹具使用6091～6096号段，隔离正式ID与资源路径。
	for index in range(3, rows.size()):
		rows[index][0] = str(6091 + index - 3)
		rows[index][9] = "enemy_test_%d" % index
	var valid_path := _directory.path_join("valid.csv")
	_write_rows(valid_path, rows)
	var random_rows: Array = rows.duplicate(true)
	random_rows[3][5] = "1"
	random_rows[3][7] = "3;1;2"
	var random_path := _directory.path_join("random.csv")
	_write_rows(random_path, random_rows)
	_check(importer.validate_tables(random_path).ok, "合法带权随机配置可导入")
	random_rows[3][7] = ""
	_write_rows(random_path, random_rows)
	_check(importer.validate_tables(random_path).ok, "随机空权重等概率可导入")
	var output := _directory.path_join("enemies")
	var encounters := _directory.path_join("encounters")
	var catalog_path := _directory.path_join("catalog.tres")
	var good := importer.import_monsters(valid_path, output, "res://tables/monster_actions.csv", "res://tables/monster_action_effects.csv", encounters, catalog_path)
	_check(good.ok, "临时三表生成并回读")
	if good.ok:
		var catalog: Resource = ResourceLoader.load(catalog_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		_check(catalog.enemies.size() == 6 and catalog.actions.size() == 44, "目录收录完整")
		_check(catalog.find_enemy(6091).action_ids == [1, 2, 3], "列表写入正确")
		_check(catalog.find_enemy(6091).image_id == 7001, "图片ID生成资源回读正确")
		_check(is_equal_approx(catalog.find_enemy(6091).battle_image_scale, 1.0), "默认战斗图片缩放倍率生成资源回读正确")
		_check(catalog.find_action(2).effects[1].amount == 2, "附带流血回读正确")
	var failing_output := _directory.path_join("must_not_exist")
	var missing := importer.import_monsters(_directory.path_join("missing.csv"), failing_output)
	_check(not missing.ok and not DirAccess.dir_exists_absolute(failing_output), "缺失文件不生成部分资源")
	for scenario in ["header", "types", "comments", "duplicate", "range", "reference", "filename", "weight", "charge_random", "image_duplicate", "image_missing", "image_range", "image_scale"]:
		var bad_rows: Array = rows.duplicate(true)
		match scenario:
			"header": bad_rows[1][0] = "wrong_id"
			"types": bad_rows[2][0] = "string"
			"comments": bad_rows[0][0] = ""
			"duplicate": bad_rows[4][0] = bad_rows[3][0]
			"range": bad_rows[3][4] = "0"
			"reference": bad_rows[3][6] = "65535"
			"filename": bad_rows[3][9] = "../bad"
			"image_duplicate": bad_rows[4][10] = bad_rows[3][10]
			"image_missing": bad_rows[3][10] = "7002"
			"image_range": bad_rows[3][10] = "65536"
			"image_scale": bad_rows[3][11] = "0"
			"weight":
				bad_rows[3][5] = "1"
				bad_rows[3][7] = "1;0"
			"charge_random": bad_rows[6][5] = "1"
		var bad_path := _directory.path_join(scenario + ".csv")
		_write_rows(bad_path, bad_rows)
		var before := FileAccess.get_file_as_bytes(catalog_path)
		var bad := importer.import_monsters(bad_path, output, "res://tables/monster_actions.csv", "res://tables/monster_action_effects.csv", encounters, catalog_path)
		_check(not bad.ok, "%s应拒绝" % scenario)
		_check(FileAccess.get_file_as_bytes(catalog_path) == before, "%s失败保留旧目录" % scenario)
	var bad_actions := _read_rows("res://tables/monster_actions.csv")
	bad_actions[12][4] = "65535"
	var bad_actions_path := _directory.path_join("bad_actions.csv")
	_write_rows(bad_actions_path, bad_actions)
	_check(not importer.validate_tables(valid_path, bad_actions_path).ok, "替代行为无效引用拒绝")
	var bad_effects := _read_rows("res://tables/monster_action_effects.csv")
	bad_effects[3][3] = "255"
	var bad_effects_path := _directory.path_join("bad_effects.csv")
	_write_rows(bad_effects_path, bad_effects)
	_check(not importer.validate_tables(valid_path, "res://tables/monster_actions.csv", bad_effects_path).ok, "效果枚举越界拒绝")
	# 中文备注只校验末列结构，内容可调整且不能改变效果资源的结算字段。
	var remark_rows := _read_rows("res://tables/monster_action_effects.csv")
	remark_rows[3][11] = "策划可自行修改的中文说明"
	var remark_path := _directory.path_join("remark.csv")
	_write_rows(remark_path, remark_rows)
	var remark_result := importer.validate_tables(valid_path, "res://tables/monster_actions.csv", remark_path)
	_check(remark_result.ok and remark_result.actions[1].effects[0].amount == 5, "备注不参与效果结算")
	remark_rows[1][11] = "wrong_remark"
	_write_rows(remark_path, remark_rows)
	_check(not importer.validate_tables(valid_path, "res://tables/monster_actions.csv", remark_path).ok, "备注列表头错误被拒绝")
	for row in remark_rows:
		row.pop_back()
	_write_rows(remark_path, remark_rows)
	_check(not importer.validate_tables(valid_path, "res://tables/monster_actions.csv", remark_path).ok, "备注列缺失被拒绝")
	_test_related_tables(importer, valid_path)
	# 最后一个输出路径故意使用目录，模拟前面资源已发布后发生IO失败。
	var blocked_catalog := _directory.path_join("blocked_catalog")
	DirAccess.make_dir_recursive_absolute(blocked_catalog)
	var before_monster := FileAccess.get_file_as_bytes(output.path_join("enemy_test_3.tres"))
	var before_pool := FileAccess.get_file_as_bytes(encounters.path_join("chapter_1.tres"))
	var changed_rows: Array = rows.duplicate(true)
	changed_rows[3][4] = "31"
	var changed_path := _directory.path_join("changed.csv")
	_write_rows(changed_path, changed_rows)
	var rolled_back := importer.import_monsters(changed_path, output, "res://tables/monster_actions.csv", "res://tables/monster_action_effects.csv", encounters, blocked_catalog)
	_check(not rolled_back.ok, "发布IO失败明确返回失败")
	_check(FileAccess.get_file_as_bytes(output.path_join("enemy_test_3.tres")) == before_monster, "已发布怪物回滚")
	_check(FileAccess.get_file_as_bytes(encounters.path_join("chapter_1.tres")) == before_pool, "已发布遭遇池回滚")
	_test_cache_and_pool()
	_cleanup(_directory)
	print("smoke_monster_tables: %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


# 行为表与效果表分别覆盖缺失、表头、重复ID、数值越界和关联引用，不能只验证怪物主表。
func _test_related_tables(importer: RefCounted, monsters_path: String) -> void:
	for table_name in ["monster_actions", "monster_action_effects"]:
		for scenario in ["missing", "header", "duplicate", "range", "reference"]:
			var rows := _read_rows("res://tables/%s.csv" % table_name)
			var path := _directory.path_join(table_name + "_" + scenario + ".csv")
			match scenario:
				"header": rows[1][0] = "bad_id"
				"duplicate": rows[4][0] = rows[3][0]
				"range": rows[3][2 if table_name == "monster_actions" else 5] = "99999"
				"reference": rows[3][4 if table_name == "monster_actions" else 1] = "65535"
			if scenario != "missing":
				_write_rows(path, rows)
			var result: Dictionary = importer.validate_tables(monsters_path, path if table_name == "monster_actions" else "res://tables/monster_actions.csv", path if table_name == "monster_action_effects" else "res://tables/monster_action_effects.csv")
			_check(not result.ok, "%s的%s错误被拒绝" % [table_name, scenario])


# 新数字缓存保持原字段类型往返；旧英文只按白名单迁移，无法映射值不会加载任意文件。
func _test_cache_and_pool() -> void:
	_check(CATALOG.resolve_cached_id("6001").id == 6001, "数字查找")
	_check(CATALOG.resolve_cached_id("enemy_turtle").id == 6110, "旧乌龟迁移")
	_check(CATALOG.resolve_cached_id("enemy_turtle").id == 6110, "重复旧值稳定映射")
	_check(CATALOG.resolve_cached_id("unknown_old") == null, "无法映射的旧值忽略")
	_check(CATALOG.find_enemy(65535) == null, "无效数字ID安全返回空")
	var rng := RandomNumberGenerator.new()
	rng.seed = 918
	var map = GENERATOR.new().generate(load("res://data/maps/map_chapter_1.tres"), rng)
	map.set_enemy_id(map.rooms[0].id, "6001")
	var restored = MAP.new()
	restored.from_dict(map.to_dict())
	_check(restored.get_enemy_id(map.rooms[0].id) == "6001", "新缓存存档往返")
	var pool: Resource = POOL.duplicate(true)
	pool.enemies[0].encounter_enabled = false
	rng.seed = 918
	for iteration in range(30):
		_check(pool.pick_enemy(0, rng).id in [6002, 6003], "禁用项退出遭遇池")
	_check(POOL.enemies.size() == 6, "正式遭遇池完整")


func _read_rows(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	var rows: Array = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1:
			rows.append(Array(row))
	return rows


func _write_rows(path: String, rows: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	for row in rows:
		file.store_csv_line(PackedStringArray(row))
	file.close()


# 仅清理本进程创建的测试目录，不触碰正式数据与用户存档。
func _cleanup(path: String) -> void:
	for child in DirAccess.get_directories_at(path):
		_cleanup(path.path_join(child))
	for child in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)
