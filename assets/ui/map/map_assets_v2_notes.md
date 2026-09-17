# 地图素材 v2 交付说明

唯一参考：用户提供的 codex-clipboard-ab387d0a-c136-45ce-bed8-db260f33ea13.png（941×1672）。

本批未覆盖旧素材，未修改场景或脚本，未接入 Godot。尺寸与 Alpha 已回读；Godot 导入与真实游戏显示未验证。

|文件|最终尺寸|处理方式|
|---|---|---|
|boss_icon_v2.png|256×256|原图图标裁片作为编辑输入；去除背景和光环，补全名字底板遮挡处|
|enemy_nameplate_v2.png|256×72|原图名字底板裁片作为编辑输入；去字，补全内部|
|boss_nameplate_v2.png|320×86|原图 Boss 名字底板裁片作为编辑输入；去字，补全内部|
|enemy_node_base_v2.png|192×192|原图节点裁片作为编辑输入；去足球，补全盘面和被标签遮挡的下沿|
|boss_node_base_v2.png|300×300|原图 Boss 节点裁片作为编辑输入；去图标与名字底板，补全盘面和下沿|
|route_line_v2.png|64×384|直接从原图连线采样，校正方向并去草地，边缘 Alpha 渐隐|
|map_background_v2.png|720×1280|整屏原图作为编辑输入；去除顶部 UI、节点、标签和路线，补全遮挡区|

## 提示词与约束

- Boss 图标：Extract this EXACT original robot goalkeeper icon onto transparent background. Preserve simple smooth dark blue purple face, plain orange oval eyes, orange angular mouth, three short tabs. Remove goal net, luminous backing ring, rays, background and nameplate. Complete only the hidden bottom area. No metallic panels, facial seams, glossy eyes or redesigned shape.
- 普通名字底板：Precise edit of this exact cropped nameplate. Remove only white Chinese lettering; fill with existing flat dark navy interior. Preserve simple thin cyan capsule border, original shape, restrained glow and colors. No bevel, metal segments, highlights, decorations or redesign. Transparent background.
- Boss 名字底板：Precise edit of this exact cropped Boss nameplate. Remove only white Chinese text, replace with same flat dark purple/navy interior. Preserve thin pink capsule border and small glow. No bevel, segments, new highlights or redesign. Transparent background.
- 普通节点底板：Precise extraction edit of actual ordinary node crop. Remove football and upper-right connection dot; restore simple dark navy disk. Preserve white/cyan luminous circular border and blue side rim. Complete bottom edge hidden by label. No metal plates, segments, new highlight or redesign. Transparent background.
- Boss 节点底板：Precise extraction edit of actual Boss node crop. Remove robot face, top tabs and nameplate. Keep white/pink neon circular ring, dark navy/purple disk and radial magenta rays. Fill hidden disk and lower arc. Remove goal net/grass outside node. No metal segments, new highlights, extra ring or redesign. Transparent background.
- 场景背景：Edit attached original screen, do not redesign. Remove top navigation/title/buttons and all nodes/nameplates/icons/routes/dots. Inpaint only those areas with original pitch, field markings, stadium and sky. Lock high-angle perspective, original goal position, side advertising panels, stadium arrows, crowd, green texture and white markings. Do not shift goal down, expand sky or create a new stadium. Opaque 9:16 PNG.
- 连线：没有生图；直接原图采样。

## 已知限制

除连线外，裁片去字、去图标、透明隔离及遮挡区补全使用图片编辑模型，并非无损像素分层。原图没有隐藏区域的像素，补全部分不能保证完全一致。编辑结果的光晕和盘面有细微变化，需用户视觉确认，不宣称像素级复刻通过。

所有素材保持长宽比例缩放至批准画布；小比例差异用透明空间容纳，不拉伸主体。场景背景按9:16缩放，差异仅为源图取整。缩放产生的接近不透明 Alpha（≥250）归一化为255，保留轮廓抗锯齿和光晕透明渐变。
