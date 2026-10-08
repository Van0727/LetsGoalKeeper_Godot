# 主动技聚光界面交付

## 素材与实现

- 复用 `assets/ui/battle/bigbeat.png`、`firstbeat.png`、`beatline.png` 和既有 QTE 白色圆环；背景、怪物、手牌仍读取正式游戏资源。
- 没有生图、裁图、覆盖位图或改变素材尺寸。光束由 Godot GradientTexture2D 实现；节拍着色保留原纹理明暗和 Alpha。
- 三轨四音符、音乐时间、判定窗口、音效及命中结算保持原流程。目标线视觉位置为原波形中心加场景编辑偏移，点击坐标共用目标标记。
- 普通节拍、操作栏和行为气泡在 QTE 内临时让出空间，关闭后恢复每个节点原来的可见性和 modulate。

## 编辑位置

打开 `scenes/qte_presentation.tscn`：

- `SkillTitle`：标题位置、宽度、字号。
- `Progress`：进度位置、尺寸。
- `PlayArea`：音符下落起点。
- `Targets`：三个判定圈共同高度；`Left/Center/Right`：横向位置与圈尺寸。编辑器显示真实节拍图作预览。
- `FeedbackAnchor`：GREAT/GOOD/MISS 位置与宽度。
- `Instruction`：提示位置、文案与字号。

运行时标题、进度、判定文字由数据更新。界面基准360×640；截图为同尺寸PNG RGB，不作为游戏纹理引用。

## 验收

- Godot 4.7.1 `--headless --editor --import`：完成。
- `--script res://tests/smoke_qte_popup.gd`：PASS，覆盖原三轨输入、四音符、音乐时机、变速窗口、输入锁、延迟结算和恢复。
- `--script res://tests/smoke_qte_presentation.gd -- --capture`：PASS，使用实际 OpenGL 渲染器，覆盖三类颜色、布局和点击同步、进度、非法入口和原UI可见性恢复。
- 查看 `output/qte_spotlight_0.png`、`qte_spotlight_1.png`、`qte_spotlight_2.png`，核对怪物、提示与手牌的显示。
- QTE回归脚本退出仍报告8个ObjectDB实例及3个资源占用；断言通过，本轮视觉验收脚本退出也报告8个ObjectDB实例及2个资源占用。本次未扩大到该退出清理问题。
- 未进行人工触摸设备实机操作；鼠标与触摸仍共用原输入分支。

## 官方文档依据

- [Godot 4.7 GradientTexture2D](https://docs.godotengine.org/en/4.7/classes/class_gradienttexture2d.html)
- [Godot 4.7 CanvasItem shader](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/canvas_item_shader.html)：vertex COLOR 通过 varying 保留类型染色，避免 fragment 默认采样后再次乘红色原图导致蓝绿变暗。

## 2026-10-08 柔和光束修订

- 三类类型色改为柔和橙、蓝、绿；光束顶部位于视口外48像素。
- 光束主体、侧边和中心线采用横向软边与纵向尾部渐隐，尾部延伸到判定线下70像素。
- 圆环使用屏幕像素导数抗锯齿，球体继续复用已有素材及线性过滤。
- Godot 4.7.1 实际 OpenGL 截图验收及 QTE 判定回归均 PASS；退出清理告警如上，尚未排查。
- 已检查360×640三色截图；未验证其他缩放倍率和触屏实机。

## 透视修订

- 光轨上方向中轨内收，宽度由远端0.48倍逐渐展开至判定线1倍；尾部沿透视继续延伸并渐隐。
- 音符保持原有时序，尺寸从0.62倍增至1倍；横向移动与光轨共用透视映射。
- 特效使用判定时音符的实际透视坐标，判定圈与输入热区保持编辑器布局。
- 三色实际OpenGL截图及透视坐标、尺寸、非法入口、末音特效断言通过；本轮视觉测试退出无清理告警。
- QTE回归PASS，退出仍有8个ObjectDB实例及3个资源占用告警；未验证触屏实机。

## 斜轨抗锯齿修订

- 光束几何两侧增加透明绘制余量，避免窄斜线边缘平滑被几何边界裁断。
- 侧边与中心线采用fwidth屏幕像素覆盖率；短装饰线改为带透明余量的圆角距离场。
- 实际OpenGL三色360×640与540×960（1.5倍窗口）渲染测试均PASS；截图已检查。
- QTE判定回归PASS；本轮退出报告4个ObjectDB实例及1个资源占用，仍未排查退出清理。
- 官方依据：https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shader_functions.html#shader-func-fwidth
