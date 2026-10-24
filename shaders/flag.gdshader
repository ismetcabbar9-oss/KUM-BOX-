shader_type spatial;
render_mode cull_disabled;
// Sancak kumaşı: direğe bağlı kenar sabit, uca doğru artan dalga.

uniform vec4 cloth : source_color = vec4(0.55, 0.06, 0.05, 1.0);
uniform vec4 emblem : source_color = vec4(0.85, 0.7, 0.2, 1.0);

void vertex() {
	float k = UV.x;  // 0: direk tarafı
	VERTEX.z += sin(VERTEX.x * 2.2 - TIME * 6.0) * 0.35 * k + sin(VERTEX.y * 3.0 - TIME * 4.0) * 0.08 * k;
	VERTEX.y -= k * k * 0.25;
}

void fragment() {
	vec2 c = UV - vec2(0.5);
	float cross_band = step(abs(c.x), 0.07) + step(abs(c.y), 0.09);
	ALBEDO = mix(cloth.rgb, emblem.rgb, clamp(cross_band, 0.0, 1.0));
	ROUGHNESS = 0.9;
}
