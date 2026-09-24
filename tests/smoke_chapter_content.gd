# 章节内容冒烟测试：验证三章地图主题、敌人池完整性、确定性选择与Boss生命成长曲线。
extends SceneTree

const MAP_GENERATOR := preload("res://scripts/map/map_generator.gd")
const ENEMY_DEFINITION := preload("res://scripts/enemies/enemy_definition.gd")
const CATALOG := preload("res://data/enemies/enemy_catalog.tres")

var _failed := false


# 延迟到资源系统初始化完成后再批量读取三章配置。
func _initialize() -> void:
	call_deferred("_run")


# 每章都必须拥有合法地图，以及普通、精英、Boss 三种可用敌人。
func _run() -> void:
	var generator = MAP_GENERATOR.new()
	var theme_colors: Array[Color] = []
	var boss_health_by_chapter: Array[int] = []
	for chapter in range(1, 4):
		var map_config: Resource = generator.load_config_for_chapter(chapter)
		_assert_true(map_config != null and map_config.is_valid(), "第%d章地图配置合法" % chapter)
		if map_config != null:
			_assert_equal(map_config.chapter, chapter, "第%d章地图编号" % chapter)
			_assert_true(not map_config.chapter_name.is_empty(), "第%d章显示名称" % chapter)
			theme_colors.append(map_config.map_background_color)

		var pool_path := "res://data/encounters/chapter_%d.tres" % chapter
		_assert_true(ResourceLoader.exists(pool_path), "第%d章遭遇池存在" % chapter)
		if not ResourceLoader.exists(pool_path):
			continue
		var pool: Resource = load(pool_path)
		_assert_equal(pool.chapter, chapter, "第%d章遭遇池编号" % chapter)
		for tier in [ENEMY_DEFINITION.Tier.NORMAL, ENEMY_DEFINITION.Tier.ELITE, ENEMY_DEFINITION.Tier.BOSS]:
			_test_tier(pool, chapter, tier)
		var boss_rng := RandomNumberGenerator.new()
		boss_rng.seed = chapter * 100 + ENEMY_DEFINITION.Tier.BOSS
		var boss: Resource = pool.pick_enemy(ENEMY_DEFINITION.Tier.BOSS, boss_rng)
		if boss != null:
			boss_health_by_chapter.append(boss.max_health)

	_assert_equal(_unique_colors(theme_colors), 3, "三章地图占位主题可区分")
	_assert_equal(boss_health_by_chapter, [120, 165, 220], "三章Boss生命按120→165→220平稳成长")
	if _failed:
		quit(1)
		return
	print("smoke_chapter_content: PASS")
	quit()


# 相同章节、级别和 seed 必须选到同一稳定 ID，且该 ID 能映射回同名资源文件。
func _test_tier(pool: Resource, chapter: int, tier: int) -> void:
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = chapter * 100 + tier
	second_rng.seed = first_rng.seed
	var first: Resource = pool.pick_enemy(tier, first_rng)
	var second: Resource = pool.pick_enemy(tier, second_rng)
	var label := "第%d章%s池" % [chapter, _tier_name(tier)]
	_assert_true(first != null, "%s非空" % label)
	if first == null or second == null:
		return
	_assert_true(first.encounter_enabled, "%s敌人已启用" % label)
	_assert_true(first.max_health > 6, "%s不再使用生命6占位值" % label)
	_assert_equal(first.enemy_id, second.enemy_id, "%s选择可复现" % label)
	# 新配表怪物由数字目录定位，旧第二章资源仍从根目录按英文键加载。
	if first.id >= 6001 and first.id <= 6099:
		_assert_true(CATALOG.find_enemy(first.id) != null, "%s数字ID可从目录加载" % label)
		var directory := "chapter_one" if chapter == 1 else "chapter_%d" % chapter
		_assert_true(ResourceLoader.exists("res://data/enemies/%s/%s.tres" % [directory, first.enemy_id]), "%s独立资源可加载" % label)
	else:
		_assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % first.enemy_id), "%s旧版稳定ID可加载" % label)


# 级别中文名只用于测试错误定位，不参与任何资源键判断。
func _tier_name(tier: int) -> String:
	match tier:
		ENEMY_DEFINITION.Tier.ELITE:
			return "精英"
		ENEMY_DEFINITION.Tier.BOSS:
			return "Boss"
		_:
			return "普通"


# 统计不同章节主题色数量，防止内容配置复制后忘记区分视觉占位。
func _unique_colors(colors: Array[Color]) -> int:
	var unique: Array[Color] = []
	for color in colors:
		if color not in unique:
			unique.append(color)
	return unique.size()


# 通用相等断言，失败时保留章节和级别标签。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言，允许一次运行列出全部内容缺口。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
