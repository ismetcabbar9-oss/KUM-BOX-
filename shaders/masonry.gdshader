shader_type spatial;
// Kesme taş örgü: blok yüzünde küçük tuğla ızgarası (harç çizgileri). Izgara, bloğun
// kırılınca ayrılacağı tuğla boyutuyla aynıdır: kopan parçalar duvarda görünen taşlarla
// birebir (orta parça = harçla tutunmuş 2×2×2 küçük tuğla).
// Stilize: yalnız renk dokusu + harç + çatlak (normal/AO dokusu yok).
//
// Boyut ve durum: MultiMesh'te INSTANCE_CUSTOM, tek MeshInstance'ta malzemenin fixed_size'ı.
//   xyz = boyut
//   w = 2       : birim küp ölçekli tuğla (BrickPool)
//   w = 0.5..1  : gerçek boyutlu blok; 0.5 sağlam, 1'e doğru artan hasar (çatlak)
//   w = 0       : boyut bilinmiyor (harçsız)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.82, 0.79, 0.74, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.42, 0.40, 0.37, 1.0);
uniform vec3 brick = vec3(1.0, 0.75, 0.75);
uniform float mortar = 0.03;
uniform float tex_scale = 0.33;
uniform vec4 fixed_size = vec4(0.0);

varying vec3 lpos;
varying vec3 lnrm;
varying vec4 bsize;
varying float dmg;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

void vertex() {
	vec4 s = INSTANCE_CUSTOM;
	if (s.w < 0.25) {
		s = fixed_size;
	}
	bool is_brick = s.w > 1.5;
	dmg = (!is_brick && s.w >= 0.5) ? clamp((s.w - 0.5) / 0.49, 0.0, 1.0) : 0.0;
	bsize = vec4(s.xyz, is_brick ? 1.0 : (s.w >= 0.25 ? 0.5 : 0.0));
	lpos = is_brick ? VERTEX * s.xyz : VERTEX;
	lnrm = NORMAL;
}

void fragment() {
	vec3 size = max(bsize.xyz, vec3(0.01));
	vec3 n = abs(lnrm);
	vec2 face;
	vec3 count = max(round(size / brick), vec3(1.0));
	vec3 cell = size / count;
	vec3 q = lpos + size * 0.5;
	vec3 f = q / cell;
	vec3 edge = min(fract(f), 1.0 - fract(f)) * cell;
	vec3 idx = floor(f);
	float m;
	if (n.x > n.y && n.x > n.z) {
		face = lpos.zy;
		m = min(edge.y, edge.z);
	} else if (n.y > n.z) {
		face = lpos.xz;
		m = min(edge.x, edge.z);
	} else {
		face = lpos.xy;
		m = min(edge.x, edge.y);
	}
	if (bsize.w <= 0.0) {
		m = 1.0;  // boyut bilinmiyor: harçsız
	}
	vec2 uv = face * tex_scale + vec2(hash(idx), hash(idx + 7.0));
	vec3 tex = texture(albedo_tex, uv).rgb;
	float var_c = 0.88 + 0.24 * hash(idx + 3.0);
	float mt = 1.0 - smoothstep(mortar * 0.6, mortar, m);
	vec3 col = mix(tex * tint.rgb * var_c, mortar_color.rgb, mt);
	float rough = mix(0.85, 1.0, mt);
	// Çatlaklar: hasar arttıkça kalınlaşan, taş yüzünde dallanan hücre kenarları
	if (dmg > 0.01) {
		vec2 cu = face * 1.1;
		vec2 ip = floor(cu);
		vec2 fp = fract(cu);
		float f1 = 8.0;
		float f2 = 8.0;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 o = vec2(float(i), float(j));
				vec2 r = o + hash2(ip + o) - fp;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
		float e = sqrt(f2) - sqrt(f1);
		float w = 0.015 + 0.06 * dmg;
		float show = smoothstep(0.1, 0.7, dmg + 0.4 * hash2(ip).x - 0.2);
		float crack = (1.0 - smoothstep(0.0, w, e)) * show;
		col *= 1.0 - 0.8 * crack;
		col = mix(col, col * vec3(0.92, 0.9, 0.86), dmg * 0.4);  // tozlanma
		rough = mix(rough, 1.0, crack);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
