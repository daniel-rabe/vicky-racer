shader_type canvas_item;
// A prize not won yet: only its outline, flat, so a child can see what is still to find.

uniform vec4 tint : source_color = vec4(0.36, 0.27, 0.2, 0.32);

void fragment() {
	COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a);
}
