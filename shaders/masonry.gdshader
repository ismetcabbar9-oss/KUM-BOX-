shader_type spatial;
// Kesme taş örgü: blok yüzünde tuğla ızgarası (harç çizgileri). Izgara, bloğun gerçekte
// bölüneceği tuğla boyutuyla aynıdır: kopan tuğlalar duvarda görünen taşlarla birebir.
// Boyut: MultiMesh'te INSTANCE_CUSTOM (xyz = boyut, w = 1: birim küp ölçekli tuğla,
// w = 0.5: gerçek boyutlu blok); tek MeshInstance'ta malzemenin fixed_size değeri.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.82, 0.79, 0.74, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.42, 0.40, 0.37, 1.0);
uniform vec3 brick = vec3(1.5, 1.0, 1.0);
uniform float mortar = 0.045;
uniform float tex_scale = 0.33;
uniform vec4 fixed_size = vec4(0.0);

varying vec3 lpos;
varying vec3 lnrm;
varying vec4 bsize;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec4 s = INSTANCE_CUSTOM;
	if (s.w < 0.25) {
		s = fixed_size;
	}
	bsize = s;
	lpos = s.w > 0.75 ? VERTEX * s.xyz : VERTEX;
	lnrm = NORMAL;
}

void fragment() {
	vec3 size = max(bsize.xyz, vec3(0.01));
	vec3 n = abs(lnrm);
	vec2 uv;
	vec2 cell_d;
	vec3 count = max(round(size / brick), vec3(1.0));
	vec3 cell = size / count;
	vec3 q = lpos + size * 0.5;
	vec3 f = q / cell;
	vec3 edge = min(fract(f), 1.0 - fract(f)) * cell;
	vec3 idx = floor(f);
	float m;
	if (n.x > n.y && n.x > n.z) {
		uv = lpos.zy;
		m = min(edge.y, edge.z);
	} else if (n.y > n.z) {
		uv = lpos.xz;
		m = min(edge.x, edge.z);
	} else {
		uv = lpos.xy;
		m = min(edge.x, edge.y);
	}
	if (bsize.w <= 0.0) {
		m = 1.0;  // boyut bilinmiyor: harçsız
	}
	uv = uv * tex_scale + vec2(hash(idx), hash(idx + 7.0));
	vec3 tex = texture(albedo_tex, uv).rgb;
	float var_c = 0.9 + 0.2 * hash(idx + 3.0);
	float mt = 1.0 - smoothstep(mortar * 0.6, mortar, m);
	ALBEDO = mix(tex * tint.rgb * var_c, mortar_color.rgb, mt);
	vec3 arm = texture(arm_tex, uv).rgb;
	ROUGHNESS = mix(arm.g, 1.0, mt);
	AO = arm.r;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 1.0 - mt;
}
