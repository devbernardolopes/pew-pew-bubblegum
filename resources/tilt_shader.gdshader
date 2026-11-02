shader_type canvas_item;

uniform float tilt_amount : hint_range(-1.0, 1.0) = 0.0;
uniform float glow_amount : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	vec2 skewed_uv = UV;
	skewed_uv.x += tilt_amount * (UV.y - 0.5);
	COLOR = texture(TEXTURE, skewed_uv);
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), glow_amount * 0.6);
}
