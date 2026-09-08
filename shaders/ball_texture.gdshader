shader_type canvas_item;

// 足球外轮廓由细分网格负责弯曲；这里只旋转 UV，确保月牙朝向和压扁轴不会随花纹转动。
uniform sampler2D ball_texture : source_color, filter_linear, repeat_disable;
uniform float texture_angle = 0.0;
uniform vec4 tint_color : source_color = vec4(0.792, 0.767, 0.624, 1.0);

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float cosine = cos(texture_angle);
	float sine = sin(texture_angle);
	mat2 rotation = mat2(vec2(cosine, sine), vec2(-sine, cosine));
	vec2 rotated_uv = rotation * centered_uv + vec2(0.5);
	float inside = step(0.0, rotated_uv.x) * step(rotated_uv.x, 1.0)
		* step(0.0, rotated_uv.y) * step(rotated_uv.y, 1.0);
	COLOR = texture(ball_texture, rotated_uv) * tint_color;
	COLOR.a *= inside;
}
