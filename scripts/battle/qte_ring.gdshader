// 用屏幕像素导数平滑圆环边缘，避免小尺寸位图放缩后的阶梯；颜色由技能提供。
shader_type canvas_item;
varying vec4 ring_tint;
void vertex() { ring_tint = COLOR; }
void fragment() {
	float radius = length(UV - vec2(0.5));
	float aa = max(fwidth(radius), 0.001);
	float outer = 1.0 - smoothstep(0.46 - aa, 0.46 + aa, radius);
	float inner = smoothstep(0.37 - aa, 0.37 + aa, radius);
	COLOR = vec4(ring_tint.rgb, ring_tint.a * outer * inner);
}
