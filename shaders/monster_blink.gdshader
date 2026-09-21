shader_type canvas_item;

// 单图怪物眨眼材质：只覆盖配置过的眼部椭圆区域，未配置的怪物不会使用本材质。
uniform float blink_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 left_eye_center = vec2(0.378, 0.528);
uniform vec2 right_eye_center = vec2(0.632, 0.528);
uniform vec2 eye_radius = vec2(0.061, 0.066);

float ellipse_mask(vec2 uv, vec2 center, vec2 radius) {
	vec2 local = (uv - center) / radius;
	return 1.0 - smoothstep(0.88, 1.0, dot(local, local));
}

vec4 close_eye(vec4 base_color, vec4 lid_color, vec2 uv, vec2 center) {
	vec2 local = (uv - center) / eye_radius;
	float mask = ellipse_mask(uv, center, eye_radius);
	// 眼皮从上下向中央合拢；保留一条很细的暗线，让闭眼状态仍有表情方向。
	float cover = blink_amount * smoothstep(
		max(0.0, 1.0 - blink_amount),
		max(0.08, 1.08 - blink_amount),
		abs(local.y)
	);
	return mix(base_color, lid_color, mask * cover);
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec4 left_lid = texture(TEXTURE, vec2(UV.x, left_eye_center.y - eye_radius.y * 1.22));
	vec4 right_lid = texture(TEXTURE, vec2(UV.x, right_eye_center.y - eye_radius.y * 1.22));
	color = close_eye(color, left_lid, UV, left_eye_center);
	color = close_eye(color, right_lid, UV, right_eye_center);
	COLOR = color * COLOR;
}
