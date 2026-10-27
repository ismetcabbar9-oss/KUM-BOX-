shader_type spatial;
// Tek düzlem zemin: iki ölçekte doku + gürültü ile tekrar kırma (arazi mesh'i gerektirmez).
// Stilize: yalnız renk dokusu (normal/AO dokusu yok), sabit pürüz.
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D variation_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.12;
uniform float macro_tile = 0.0035;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(0.82, 0.78, 0.7);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * tile;
	// İkinci örnek: döndürülmüş ve ölçeklenmiş -> tekrar desenini kırar
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * world_pos.xz * tile * 0.37 + 0.31;
	float v = texture(variation_tex, world_pos.xz * macro_tile).r;
	float m = smoothstep(0.35, 0.65, v);
	vec3 c = mix(texture(albedo_tex, uv).rgb, texture(albedo_tex, uv2).rgb, m);
	ALBEDO = c * mix(tint_a, tint_b, smoothstep(0.2, 0.8, texture(variation_tex, world_pos.xz * macro_tile * 0.31).r));
	ROUGHNESS = 0.95;
}
