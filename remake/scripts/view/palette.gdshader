shader_type canvas_item;
// Colours an indexed image (red channel = VGA palette index, alpha 0 = transparent) with the
// current palette and scales it with "sharp bilinear" (crisp, evenly sized pixels at any scale),
// as in lazarus-revibed. Used for the 320x200 screen and the 640x400 menu text layer; `dim`
// darkens the screen under a menu.

uniform sampler2D idx_tex : filter_nearest, repeat_disable;
uniform sampler2D pal_tex : filter_nearest, repeat_disable;
uniform vec2 src_size = vec2(320.0, 200.0);
uniform vec2 out_scale = vec2(1.0, 1.0);      // output pixels per source pixel
uniform bool smooth_scale = true;
uniform float dim = 1.0;

vec4 colour_at(vec2 p) {
	p = clamp(p, vec2(0.0), src_size - 1.0);
	vec4 t = texture(idx_tex, (p + 0.5) / src_size);
	vec3 c = texture(pal_tex, vec2((floor(t.r * 255.0 + 0.5) + 0.5) / 256.0, 0.5)).rgb * dim;
	return vec4(c * t.a, t.a);                 // premultiplied, so transparent edges blend right
}

void fragment() {
	vec2 texel = UV * src_size;
	vec4 col;
	if (!smooth_scale) {
		col = colour_at(floor(texel));
	} else {
		vec2 t = texel - 0.5;
		vec2 f0 = floor(t);
		vec2 f = clamp((t - f0 - 0.5) * out_scale + 0.5, 0.0, 1.0);
		vec4 a = colour_at(f0);
		vec4 b = colour_at(f0 + vec2(1.0, 0.0));
		vec4 c = colour_at(f0 + vec2(0.0, 1.0));
		vec4 d = colour_at(f0 + vec2(1.0, 1.0));
		col = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	}
	COLOR = col.a > 0.0 ? vec4(col.rgb / col.a, col.a) : vec4(0.0);
}
