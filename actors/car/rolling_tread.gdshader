shader_type canvas_item;
// Wheels drawn into a car body (actors/car/rolling_tread.gd). Inside each tyre's rectangle, on
// the dark grey tyre pixels only, light ridges and dark grooves slide along the car as it
// rolls. The front pair also turns with the steering: the tyre is lifted out of the picture and
// drawn again, turned round its axle, behind the body. Everything else is drawn as it is,
// modulate included.

// The tyres, rear left, front left, rear right, front right: x0, y0, x1, y1 in texture pixels.
// All zero (the default) means no tyres, and the body is drawn untouched.
uniform vec4 wheels[4];
// How far the tread has slid, texture px, wrapped to one PERIOD. Front and rear apart, so a
// handbrake can lock the rear wheels.
uniform float roll_front = 0.0;
uniform float roll_rear = 0.0;
// 0 = crisp tread; 1 = smeared flat, at speeds where a crisp one would strobe.
uniform float blur : hint_range(0.0, 1.0) = 0.0;
// How far the front wheels are turned, radians; positive = to the car's right.
uniform float steer = 0.0;

const float PERIOD = 5.0;
// Grooves are darkened to GROOVE, ridges brightened to RIDGE (multipliers).
const float GROOVE = 0.55;
const float RIDGE = 1.7;
// The picture is drawn this many px taller above and below, so a turned tyre at the edge of
// the picture is not cut off.
const float PAD = 6.0;
// Mostly only the outer part of a tyre shows; the rest is under the body. A whole tyre is
// taken to be at least this wide, px; turned, some of the hidden part comes out.
const float TYRE_WIDTH = 13.0;
// Rubber where the picture has none to show: the hidden part, hubs, gaps.
const vec3 HIDDEN_TYRE = vec3(0.16, 0.16, 0.17);
// How much lighter than the tyre rule the shine on a front tyre may be, and the rounding of a
// turned tyre's corners, px.
const float SHINE = 0.25;
const float CORNER = 3.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
	float out_y = UV.y * 2.0 - 1.0;
	VERTEX.y += out_y * PAD;
	UV.y += out_y * PAD * TEXTURE_PIXEL_SIZE.y;
}

// Much the same rule tools/comfy/wheel_rects.py uses: dark, grey and opaque.
// `light` widens it to the lighter grey shine on the rubber.
float tyre_of(vec4 tex, float light) {
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float spread = max(tex.r, max(tex.g, tex.b)) - min(tex.r, min(tex.g, tex.b));
	return (1.0 - smoothstep(0.25 + light, 0.32 + light, luma)) * (1.0 - smoothstep(0.15, 0.2, spread)) * step(0.5, tex.a);
}

vec3 tread(vec3 rgb, float tyre, float x, float roll) {
	float phase = fract((x - roll) / PERIOD);
	float ridge = smoothstep(0.1, 0.3, phase) * (1.0 - smoothstep(0.5, 0.7, phase));
	return rgb * mix(1.0, mix(GROOVE, RIDGE, ridge), tyre * (1.0 - blur));
}

bool inside(vec2 p, vec4 r) {
	return p.x >= r.x && p.x < r.z && p.y >= r.y && p.y < r.w;
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = UV * size;
	bool on_picture = UV.y >= 0.0 && UV.y <= 1.0;
	vec4 body = on_picture ? texture(TEXTURE, UV) : vec4(0.0);
	vec4 wheel = vec4(0.0);
	for (int i = 0; i < 4; i++) {
		vec4 r = wheels[i];
		if (r.z <= r.x) {
			continue;
		}
		bool front = i == 1 || i == 3;
		if (!front || abs(steer) < 0.001) {
			if (inside(px, r)) {
				body.rgb = tread(body.rgb, tyre_of(body, 0.0), px.x, front ? roll_front : roll_rear);
			}
			continue;
		}
		// A front tyre, turned: take its rubber out of the body (lights, hubs and the like
		// stay)...
		if (inside(px, r)) {
			body.a *= 1.0 - tyre_of(body, SHINE);
		}
		// ...and draw them turned, round the middle of the whole tyre, part of which is
		// hidden under the body.
		float hidden = max(TYRE_WIDTH - (r.w - r.y), 0.0);
		bool top = r.y + r.w < size.y;
		vec4 whole = top ? vec4(r.x, r.y, r.z, r.w + hidden) : vec4(r.x, r.y - hidden, r.z, r.w);
		vec2 axle = (whole.xy + whole.zw) * 0.5;
		vec2 d = px - axle;
		vec2 q = axle + vec2(cos(steer) * d.x + sin(steer) * d.y, -sin(steer) * d.x + cos(steer) * d.y);
		// ...and draw it again, turned: a rounded block of rubber, in the tyre's own colours
		// where they are rubber.
		vec2 half_size = (whole.zw - whole.xy) * 0.5;
		vec2 corner = abs(q - axle) - half_size + CORNER;
		float outside = length(max(corner, 0.0)) + min(max(corner.x, corner.y), 0.0) - CORNER;
		float cover = clamp(0.5 - outside, 0.0, 1.0);
		if (cover > 0.0) {
			vec4 tex = texture(TEXTURE, clamp(q, r.xy + 0.5, r.zw - 0.5) / size);
			float rubber = tyre_of(tex, SHINE);
			if (q.y < r.y || q.y >= r.w) {
				rubber = 0.0;  // the hidden part
			}
			vec3 rgb = mix(HIDDEN_TYRE, tex.rgb, rubber);
			wheel = vec4(tread(rgb, 1.0, q.x, roll_front), cover);
		}
	}
	// The body is drawn over the turned tyres.
	vec4 c = vec4(body.rgb * body.a + wheel.rgb * wheel.a * (1.0 - body.a), body.a + wheel.a * (1.0 - body.a));
	c.rgb /= max(c.a, 0.0001);
	COLOR = c * tint;
}
