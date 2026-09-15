# 战利品目录：由统一配表导入流程生成，集中保存全部固定定义，供奖励池和 GM 面板读取。
class_name ItemCatalog
extends Resource

# 保持 CSV 主表顺序，运行时按品级和启用状态再筛选，不能在此保存单局状态。
@export var items: Array[Resource] = []
