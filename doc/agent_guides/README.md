# Agent 专项规则索引

本目录保存只在特定任务中加载的项目规则。根目录 `AGENTS.md` 保存全项目始终适用的约束与准确路由；专项细则只在本目录维护，避免重复和漂移。

| 文档 | 必须读取的场景 |
| --- | --- |
| [`csv_and_import_rules.md`](csv_and_import_rules.md) | 修改策划 CSV、导入器或生成资源 |
| [`godot_verification.md`](godot_verification.md) | 修改 Godot 代码、场景、资源或导入流程后的验证 |
| [`image_asset_rules.md`](image_asset_rules.md) | 生成、处理或接入任何游戏图片，或从整屏参考图复刻 UI |
| [`monster_art_rules.md`](monster_art_rules.md) | 生成、处理或接入怪物图片 |
| [`card_art_rules.md`](card_art_rules.md) | 生成、处理或接入卡牌插画 |
| [`save_compatibility.md`](save_compatibility.md) | 修改存档格式、本局状态、正式数字 ID 或旧档迁移 |
| [`agent_task_contract.md`](agent_task_contract.md) | 主代理委派任何子任务 |

使用规则：

- 只读取当前任务命中的专项文档，不因存在文档而给小任务增加无关流程。
- 一个任务命中多个领域时，按任务阶段依次读取并遵守对应文档。
- 怪物和卡牌图片任务同时读取通用图片规范与对应专项规范；专项规范只覆盖其明确声明的差异。
- 专项规则与根规则冲突时，先暂停并报告；不得自行选择较宽松的解释。
- 更新规则时只修改其唯一事实来源，并同步检查根路由是否仍准确。
