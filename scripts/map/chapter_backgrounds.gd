# 章节背景表现映射：第一章橙色、第二章蓝紫、第三章绿白，地图和战斗共用入口，不写存档。
extends RefCounted

const BATTLE_ORANGE := preload("res://assets/ui/backgrounds/battle_stage_background_v2.png")
const MAP_ORANGE := preload("res://assets/ui/map/map_background_v3.png")

# 未知章节及图片缺失时回退现有橙色，避免场景进入后出现黑屏背景。
static func get_texture(chapter: int, is_map: bool) -> Texture2D:
	var fallback: Texture2D = MAP_ORANGE if is_map else BATTLE_ORANGE
	if chapter not in [2, 3]:
		return fallback
	# 旧第一章蓝紫素材用于第二章；仅交换映射，保留正式文件路径和未知章节回退。
	var image_chapter := 1 if chapter == 2 else 3
	var path := ("res://assets/ui/map/map_chapter_%d.png" if is_map else "res://assets/ui/backgrounds/battle_chapter_%d.png") % image_chapter
	return load_or_fallback(path, fallback)


# 缺失或类型不匹配的背景仅影响显示，不影响地图、遇敌和章节推进。
static func load_or_fallback(path: String, fallback: Texture2D) -> Texture2D:
	if not ResourceLoader.exists(path):
		return fallback
	var texture := load(path) as Texture2D
	return texture if texture != null else fallback


# 动态舞台光同步背景色，避免蓝紫和绿白场景仍被原来的橙光覆盖。
static func get_light_color(chapter: int) -> Color:
	if chapter == 2:
		return Color(0.32, 0.62, 1.0)
	if chapter == 3:
		return Color(0.58, 1.0, 0.76)
	return Color(1.0, 0.25, 0.065)
