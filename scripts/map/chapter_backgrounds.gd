# 章节背景表现映射：地图和战斗共用章节配色入口，不写入本局状态或存档。
extends RefCounted

const BATTLE_ORANGE := preload("res://assets/ui/backgrounds/battle_stage_background_v2.png")
const MAP_ORANGE := preload("res://assets/ui/map/map_background_v3.png")

# 未知章节及图片缺失时回退现有橙色，避免场景进入后出现黑屏背景。
static func get_texture(chapter: int, is_map: bool) -> Texture2D:
	var fallback: Texture2D = MAP_ORANGE if is_map else BATTLE_ORANGE
	if chapter not in [1, 3]:
		return fallback
	var path := ("res://assets/ui/map/map_chapter_%d.png" if is_map else "res://assets/ui/backgrounds/battle_chapter_%d.png") % chapter
	return load_or_fallback(path, fallback)


# 缺失或类型不匹配的背景仅影响显示，不影响地图、遇敌和章节推进。
static func load_or_fallback(path: String, fallback: Texture2D) -> Texture2D:
	if not ResourceLoader.exists(path):
		return fallback
	var texture := load(path) as Texture2D
	return texture if texture != null else fallback


# 动态舞台光同步背景色，避免蓝紫和绿白场景仍被原来的橙光覆盖。
static func get_light_color(chapter: int) -> Color:
	if chapter == 1:
		return Color(0.32, 0.62, 1.0)
	if chapter == 3:
		return Color(0.58, 1.0, 0.76)
	return Color(1.0, 0.25, 0.065)
