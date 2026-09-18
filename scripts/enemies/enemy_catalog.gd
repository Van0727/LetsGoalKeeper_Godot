@tool
# 怪物目录：新内容按数字 ID 查找，旧英文缓存仅通过白名单迁移，禁止拼接任意资源路径。
class_name EnemyCatalog
extends Resource

@export var enemies: Array[Resource] = []
@export var actions: Array[Resource] = []
# 6101～6111 永久保留给旧版敌人，避免重进存档时把旧敌人替换成新设计。
const LEGACY_IDS := {
	"enemy_bear": 6101, "enemy_chicken": 6102, "enemy_elephant_boss": 6103,
	"enemy_mantis_boss": 6104, "enemy_penguin": 6105, "enemy_raccoon_boss": 6106,
	"enemy_robot": 6107, "enemy_snake": 6108, "enemy_training_raccoon_boss": 6109,
	"enemy_turtle": 6110, "enemy_zebra": 6111,
}


# 未知 ID 安全返回空值；旧资源只在首次兼容读取时复制并补充数字 ID，不回写文件。
func find_enemy(numeric_id: int) -> Resource:
	for definition in enemies:
		if definition.id == numeric_id:
			return definition
	for key in LEGACY_IDS:
		if LEGACY_IDS[key] == numeric_id:
			var definition: Resource = load("res://data/enemies/%s.tres" % key)
			if definition != null:
				var migrated: Resource = definition.duplicate(true)
				migrated.id = numeric_id
				return migrated
	return null


# 新缓存仍使用原存档字符串字段，但内容为十进制数字；不改变存档字段结构。
func resolve_cached_id(value: String) -> Resource:
	if value.is_valid_int():
		return find_enemy(value.to_int())
	if LEGACY_IDS.has(value):
		return find_enemy(LEGACY_IDS[value])
	push_warning("无法迁移怪物缓存ID：%s" % value)
	return null


# 行为 ID 是目录内唯一键，用于蓄力取消后的替代行为。
func find_action(numeric_id: int) -> Resource:
	for action in actions:
		if action.id == numeric_id:
			return action
	return null
