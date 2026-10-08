// 装饰短线用带透明余量的圆角距离场绘制，旋转后仍按屏幕像素平滑边缘。
shader_type canvas_item;
varying vec4 accent_tint;
void vertex() { accent_tint = COLOR; }
void fragment() {
	vec2 point = (UV - vec2(0.5)) * vec2(7.0, 12.0);
	point.y -= clamp(point.y, -2.5, 2.5);
	float distance_to_line = length(point) - 1.5;
	float aa = max(fwidth(distance_to_line), 0.01);
	float alpha = 1.0 - smoothstep(-aa, aa, distance_to_line);
	COLOR = vec4(accent_tint.rgb, accent_tint.a * alpha);
}
