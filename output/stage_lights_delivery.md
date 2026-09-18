# 舞台灯光交付

- 背景：`assets/ui/backgrounds/battle_stage_background_v2.png`
- 尺寸：941×1672，比例 941:1672，PNG RGB，完全不透明。
- 未裁切、未缩放，原始 v1 保留。只移除顶部固定光束，左右各三个灯口保留。
- 六束动态光由 `scripts/battle/stage_lights.gdshader` 绘制，不需要光束位图；在背景子层中与背景同步拉伸。
- 编辑器中灯光层默认为透明，运行时创建独占材质；不使用 `@tool`，编辑器静态视图显示清理后的背景，实际摆动需运行战斗场景查看。
- 灯口坐标（背景原始像素）：左 (47,4)、(195,116)、(99,279)；右 (895,4)、(749,123)、(842,279)。
- `stage_lights.gd` 使用 RhythmClock 的音乐绝对时间，六盏灯每拍独立等概率决定移动或停住；单灯连续停两拍后下一拍强制移动。随机目标在 0.10 至 0.54 弧度的朝内范围内，至少移动约 0.10 弧度，在拍首 25% 时间内平滑到达，余下 75% 保持目标角度；100 BPM 下约 0.15 秒完成移动。停拍角度严格保持，亮度仍随拍衰减，不参与结算、存档或 CSV。
- 随机源与核心玩法隔离，每个场景独占种子；同拍不重新抽签，跳帧补齐遗漏拍点，时间回退按种子重放。异常速度/时间冻结当前角度并恢复弱光，超大时间（十万拍及以上）同样安全回退，避免无界补拍。
- 调节方向范围：`stage_lights.gd` 中的 0.10 至 0.54 弧度；光束宽度为 `0.015 + along * 0.21`，最外侧 12% 为柔边，内部保持均匀，形成明显锥形边界。长度与亮度由 shader 的 fade、light 调整。

## 最终生成提示词

Edit target: the provided existing game battle background. Precise localized lighting edit only. Remove the orange projected spotlight cones/beams in the upper third of the image and reconstruct the underlying dark navy atmosphere and truss details naturally. KEEP ALL SIX spotlight fixtures/luminous lamp apertures at their original locations: three upper left, three upper right, including partially clipped fixtures at image sides. Do not move or redesign any lamp. Keep original stage, orange stage rings, speakers, trusses, equalizer columns, audience glowsticks, foreground DJ console, color palette and composition unchanged. Preserve diffuse orange ambient haze above stage but no directional static beams from lamps. Full opaque edge-to-edge rectangular portrait PNG, target aspect ratio 941:1672, target final size 941x1672. No transparency, no green screen, no new text, logo or UI. This will be the clean background beneath six separately animated game-engine light beams.

## 验收与复现

Godot 4.7.1，GL Compatibility，NVIDIA GTX 1660 Ti。

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/test_userdata'
& 'D:/WorkTools/Godot/Godot_v4.7.1-stable_win64_console.exe' --headless --editor --path . --import --quit
& 'D:/WorkTools/Godot/Godot_v4.7.1-stable_win64_console.exe' --path . --script tests/smoke_stage_lights.gd
& 'D:/WorkTools/Godot/Godot_v4.7.1-stable_win64_console.exe' --headless --path . --script tests/smoke_battle_ui.gd
```

截图：`output/stage_lights_beat_360.png`、`output/stage_lights_between_360.png`、`output/stage_lights_beat_480.png`。

覆盖：真实场景接入、六个原点、前奏不闪拍、拍点亮度、移动拍快速扫动、四分之一拍到位后余拍保持、停拍角度严格保持、各灯独立决策、连续停两拍后强制移动、角度范围、同拍重复采样、跳帧补拍、时间回退重放、随机拍点及连续时间循环边界衔接、暂停、宽屏范围和无效速度/非有限音乐时间回退。Godot 4.7.1 真实 GPU 渲染与灯光测试 PASS。固定种子 7302 的 512 拍中，自由决策移动率 48.87%，强制移动 463 次。总体移动率会因强制规则高于 50%。未进行整首音乐多轮人工试听。

环境诊断：Godot 启动提示无法读取系统证书；战斗 UI 测试退出提示两个 ObjectDB 实例泄漏，测试仍 PASS。首次编辑器扫描因沙盒禁止写系统 APPDATA 而无法保存编辑器设置；后续扫描及测试使用项目内隔离 APPDATA。
