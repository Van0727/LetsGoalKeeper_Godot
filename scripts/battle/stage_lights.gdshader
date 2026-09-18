// 六束宽锥舞台光：实体光束内部均匀，边界只保留窄柔边；独立加色层位于角色/UI 下方。
// 不使用 TIME，移动与停拍均由音乐绝对时间控制，暂停不会自行摆动。
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec2 origins[6];
uniform float angles[6];
uniform float pulse = 0.0;

void fragment() {
	// 与背景使用相同拉伸空间，灯口在宽屏及基准画面中始终重合。
	vec2 point = UV * vec2(1.0, 1672.0 / 941.0);
	float light = 0.0;
	for (int i = 0; i < 6; i++) {
		vec2 direction = vec2(sin(angles[i]), cos(angles[i]));
		vec2 offset = point - origins[i];
		float along = dot(offset, direction);
		float across = abs(dot(offset, vec2(direction.y, -direction.x)));
		float width = 0.015 + max(along, 0.0) * 0.21;
		// 只在最外侧约 12% 宽度过渡，避免高斯雾状光吞掉边界。
		float soft_edge = 1.0 - smoothstep(width * 0.88, width, across);
		float fade = smoothstep(-0.006, 0.012, along) * (1.0 - smoothstep(0.24, 0.63, along));
		light += soft_edge * fade * (0.19 + 0.08 * pulse);
	}
	COLOR = vec4(vec3(1.0, 0.25, 0.065), min(light, 0.6));
}
