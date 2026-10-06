shader_type canvas_item;
// Rolling tread on the tyres drawn into a car body (actors/car/rolling_tread.gd): inside each
// tyre's rectangle, on the dark grey tyre pixels only, light ridges and dark grooves slide along
// the car as it rolls. Everything else is drawn as it is, modulate included.

// The tyres, rear left, front left, rear right, front right: x0, y0, x1, y1 in texture pixels.
// All zero (the default) means no tyres, and the body is drawn untouched.
uniform vec4 wheels[4];
// How far the tread has slid, texture px, wrapped to one PERIOD. Front and rear apart, so a
// handbrake can lock the rear wheels.
uniform float roll_front = 0.0;
uniform float roll_rear = 0.0;
// 0 = crisp tread; 1 = smeared flat, at speeds where a crisp one would strobe.
uniform float blur : hint_range(0.0, 1.0) = 0.0;

const float PERIOD = 5.0;
// Grooves are darkened to GROOVE, ridges brightened to RIDGE (multipliers).
const float GROOVE = 0.55;
const float RIDGE = 1.7;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float spread = max(tex.r, max(tex.g, tex.b)) - min(tex.r, min(tex.g, tex.b));
	// Much the same rule tools/comfy/wheel_rects.py uses: dark, grey and opaque.
	float tyre = (1.0 - smoothstep(0.25, 0.32, luma)) * (1.0 - smoothstep(0.15, 0.2, spread)) * step(0.5, tex.a);
	for (int i = 0; i < 4; i++) {
		vec4 r = wheels[i];
		if (px.x >= r.x && px.x < r.z && px.y >= r.y && px.y < r.w) {
			float roll = (i == 1 || i == 3) ? roll_front : roll_rear;
			float phase = fract((px.x - roll) / PERIOD);
			float ridge = smoothstep(0.1, 0.3, phase) * (1.0 - smoothstep(0.5, 0.7, phase));
			float shade = mix(GROOVE, RIDGE, ridge);
			COLOR.rgb *= mix(1.0, shade, tyre * (1.0 - blur));
		}
	}
}
