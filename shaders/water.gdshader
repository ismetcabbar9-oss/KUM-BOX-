shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
// Hendek suyu: iki kayan dalga gürültüsünden normal, kenarda koyu/bulanık.

uniform vec4 deep : source_color = vec4(0.10, 0.17, 0.15, 0.9);
uniform vec4 shallow : source_color = vec4(0.22, 0.30, 0.24, 0.8);

varying vec3 wpos;

float h(vec2 p) {
	return sin(p.x * 0.9 + TIME * 1.1) * 0.5 + sin(p.y * 1.3 - TIME * 0.8) * 0.35 + sin((p.x + p.y) * 2.1 + TIME * 1.7) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float e = 0.15;
	float dx = h(p + vec2(e, 0.0)) - h(p - vec2(e, 0.0));
	float dz = h(p + vec2(0.0, e)) - h(p - vec2(0.0, e));
	vec3 n = normalize(vec3(-dx * 0.25, 1.0, -dz * 0.25));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec4 c = mix(deep, shallow, 0.5 + 0.5 * sin(p.x * 0.05 + p.y * 0.07));
	ALBEDO = c.rgb;
	ALPHA = mix(c.a, 1.0, fres);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
