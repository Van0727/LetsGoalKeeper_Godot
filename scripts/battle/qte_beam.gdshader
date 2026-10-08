// 光束从屏幕外进入，横向软边保留轨道范围，纵向在判定线下逐渐消失。
shader_type canvas_item;
uniform float edge_mode = 0.0;
// 每条光束独享参数，以判定线为近端，屏幕顶部向舞台中央收束。
uniform float lane_offset = 0.0;
uniform float rect_width = 56.0;
uniform float target_fraction = 0.85;
varying vec4 beam_tint;
varying vec2 padded_uv;
void vertex() {
	beam_tint = COLOR;
	float depth = mix(0.48, 1.0, UV.y / max(target_fraction, 0.01));
	// 两侧预留透明绘制余量，像素平滑才能覆盖几何边界外，避免斜边被三角形直接裁断。
	float padded_x = (UV.x - 0.5) * (rect_width + 6.0);
	padded_uv = vec2(padded_x / rect_width + 0.5, UV.y);
	VERTEX.x = rect_width * 0.5 + padded_x * depth + lane_offset * (1.0 - depth);
}
void fragment() {
	float distance_to_center = abs(padded_uv.x - 0.5);
	float aa = max(fwidth(padded_uv.x), 0.001);
	float soft_side = 1.0 - smoothstep(0.32, 0.5, distance_to_center);
	float line_side = 1.0 - smoothstep(0.5 - aa, 0.5 + aa, distance_to_center);
	float side = mix(soft_side, line_side, edge_mode);
	float tail = 1.0 - smoothstep(0.72, 1.0, UV.y);
	float strength = mix(0.28, 0.65, edge_mode);
	COLOR = vec4(beam_tint.rgb, beam_tint.a * side * tail * strength);
}
