// 使用原素材明暗与Alpha；仅最亮的局部高光混入少量白色，避免三类音符整球发灰。
shader_type canvas_item;
varying vec4 type_tint;

void vertex() {
	type_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float brightness = max(source.r, max(source.g, source.b));
	float neutral = smoothstep(0.82, 1.0, min(source.r, min(source.g, source.b))) * 0.16;
	vec3 tinted = mix(type_tint.rgb * brightness, vec3(brightness), neutral);
	COLOR = vec4(tinted, source.a * type_tint.a);
}
