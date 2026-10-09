shader_type canvas_item;
// Living ground (docs/DESIGN.md §7.5): makes the flat ground fills look less like one tile
// repeated. Everything is placed in world space, so it never shows the 128 px tile grid.
//   - patches: big soft lighter and darker areas over the whole ground;
//   - wind: lighter bands that roll across the grass, the way wind looks over a meadow;
//   - tufts: little grass tufts that sway, leaning further when a gust passes;
//   - flowers: a few small daisies.
// Only pixels close to `grass_key` (the theme's grass colour) get wind, tufts and flowers,
// so sand traps and other patches stay as they are and only get the soft patches.

uniform vec4 grass_key : source_color = vec4(0.659, 0.745, 0.267, 1.0);
uniform float key_tolerance = 0.11;

uniform float patch_size = 700.0;
uniform float patch_strength = 0.06;

uniform vec2 wind_dir = vec2(0.94, 0.34);
uniform float wind_speed = 90.0;
uniform float wind_size = 520.0;
uniform float wind_sheen = 0.07;

uniform float tuft_cell = 54.0;
uniform float tuft_density : hint_range(0.0, 1.0) = 0.6;
uniform float tuft_size = 20.0;
uniform float tuft_lean = 6.0;
uniform vec4 blade_dark : source_color = vec4(0.50, 0.66, 0.18, 1.0);
uniform vec4 blade_light : source_color = vec4(0.80, 0.88, 0.40, 1.0);
uniform vec4 blade_edge : source_color = vec4(0.30, 0.45, 0.12, 0.7);

uniform float flower_density : hint_range(0.0, 1.0) = 0.05;
uniform vec4 petal : source_color = vec4(1.0, 0.98, 0.92, 1.0);
uniform vec4 flower_heart : source_color = vec4(1.0, 0.8, 0.2, 1.0);

uniform float mow_stripes : hint_range(0.0, 1.0) = 0.0;
uniform float mow_width = 160.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return 0.6 * value_noise(p) + 0.3 * value_noise(p * 2.1 + 17.0) + 0.1 * value_noise(p * 4.3 + 41.0);
}

// How strongly the wind leans the grass at `p` right now, 0..1.
float gust(vec2 p) {
	vec2 dir = normalize(wind_dir);
	vec2 q = p - dir * TIME * wind_speed;
	// Stretch across the wind so the gusts read as rolling bands, not blobs.
	vec2 along = vec2(dot(q, dir), dot(q, vec2(-dir.y, dir.x)) * 0.45);
	return smoothstep(0.35, 0.8, fbm(along / wind_size));
}

// Distance from `p` to a blade from `a` to `b` that is `w` wide at `a` and pointed at `b`;
// `t` says how far along it the closest point is.
float blade(vec2 p, vec2 a, vec2 b, float w, out float t) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t) - w * (1.0 - t);
}

void fragment() {
	vec4 base = COLOR;  // already the tile texture times modulate
	vec3 col = base.rgb;

	float patches = fbm(world / patch_size) * 2.0 - 1.0;
	col *= 1.0 + patch_strength * patches;

	float grass = 1.0 - smoothstep(key_tolerance * 0.6, key_tolerance, distance(base.rgb, grass_key.rgb));
	if (grass > 0.0) {
		vec3 g = col;
		vec2 dir = normalize(wind_dir);
		if (mow_stripes > 0.0) {
			float m = fract(dot(world, vec2(0.7071, 0.7071)) / (2.0 * mow_width));
			float stripe = smoothstep(0.47, 0.53, m) - smoothstep(0.97, 1.0, m);
			g *= 1.0 + mow_stripes * (stripe * 2.0 - 1.0) * 0.05;
		}
		float here = gust(world);
		g = mix(g, g * 1.18 + vec3(0.02, 0.03, 0.0), here * wind_sheen / 0.07 * 0.5);

		vec2 cell = floor(world / tuft_cell);
		float aa = 0.8;
		// Tufts come in clumps: a slow noise decides where the grass is long.
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 c = cell + vec2(float(x), float(y));
				vec2 h = hash2(c);
				float pick = hash1(c + 7.3);
				vec2 root = (c + 0.2 + 0.6 * h) * tuft_cell;
				vec2 off = world - root;
				// Skip cells whose tuft or flower can't reach this pixel (keeps it cheap on the web).
				if (abs(off.x) > tuft_size * 1.25 + tuft_lean || off.y > tuft_size * 0.5 || off.y < -tuft_size * 1.5) {
					continue;
				}
				float clump = smoothstep(0.3, 0.7, value_noise(root / 380.0 + 5.0));
				if (pick < tuft_density * (0.25 + 0.75 * clump)) {
					float size = tuft_size * (0.8 + 0.45 * h.y);
					// The camera never turns, so tufts stand up the screen like a picture-book
					// meadow and the wind pushes their tips sideways.
					float lean = (gust(root) * tuft_lean + sin(TIME * 2.1 + h.x * 6.28) * 0.7) * sign(dir.x + 0.001);
					// A soft shadow at the foot of the tuft.
					vec2 sh = (world - root - vec2(1.5, 0.5)) / vec2(size * 0.75, size * 0.22);
					g *= 1.0 - 0.13 * (1.0 - smoothstep(0.6, 1.0, length(sh)));
					float d = 1e5;
					float tt = 0.0;
					for (int k = 0; k < 5; k++) {
						float fk = float(k) / 4.0 - 0.5;
						float ang = fk * 1.25 + (hash1(c + float(k)) - 0.5) * 0.3;
						float len = size * (1.0 - 0.45 * abs(fk) * 2.0 + 0.2 * hash1(c + float(k) + 3.1));
						vec2 up = vec2(sin(ang), -cos(ang)) * len;
						vec2 bend = vec2(lean * (0.6 + 0.4 * len / size), 0.0);
						vec2 base_k = root + vec2(fk * size * 0.35, 0.0);
						vec2 mid = base_k + up * 0.5 + bend * 0.25;
						vec2 tip = base_k + up + bend;
						float w = size * 0.13;
						float t1;
						float t2;
						// The lower half narrows from w to w/2, the upper half from w/2 to a point.
						float d1 = blade(world, base_k, mid, w, t1) - w * 0.5 * t1;
						float d2 = blade(world, mid, tip, w * 0.5, t2);
						float dk = min(d1, d2);
						if (dk < d) {
							d = dk;
							tt = d1 < d2 ? t1 * 0.5 : 0.5 + t2 * 0.5;
						}
					}
					float outline = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
					float fill = 1.0 - smoothstep(-aa, aa, d);
					g = mix(g, blade_edge.rgb, outline * blade_edge.a);
					vec3 bc = mix(blade_dark.rgb, blade_light.rgb, smoothstep(0.1, 1.0, tt) + here * 0.12);
					g = mix(g, bc, fill);
				} else if (pick > 1.0 - flower_density * clump) {
					vec2 fc = root + vec2(gust(root) * tuft_lean * 0.3 * sign(dir.x + 0.001), 0.0);
					vec2 rel = world - fc;
					float r = length(rel);
					float a = atan(rel.y, rel.x) + h.y * 6.28;
					float petals = 4.0 + 1.3 * cos(a * 5.0);
					g *= 1.0 - 0.12 * (1.0 - smoothstep(petals - aa, petals + 1.5, length(rel - vec2(1.2, 1.6))));
					g = mix(g, blade_edge.rgb, (1.0 - smoothstep(petals + 1.0 - aa, petals + 1.0 + aa, r)) * blade_edge.a);
					g = mix(g, petal.rgb, 1.0 - smoothstep(petals - aa, petals + aa, r));
					g = mix(g, flower_heart.rgb, 1.0 - smoothstep(1.8 - aa, 1.8 + aa, r));
				}
			}
		}
		col = mix(col, g, grass);
	}
	COLOR = vec4(col, base.a);
}
