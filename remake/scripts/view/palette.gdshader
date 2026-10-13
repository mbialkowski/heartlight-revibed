shader_type canvas_item;
// Colours the indexed screen (red channel = VGA palette index) with the current palette and scales
// it: "sharp bilinear" keeps pixels crisp but evenly sized at any scale (as in lazarus-revibed).

uniform sampler2D idx_tex : filter_nearest, repeat_disable;
uniform sampler2D pal_tex : filter_nearest, repeat_disable;
uniform vec2 src_size = vec2(320.0, 200.0);
uniform vec2 out_scale = vec2(1.0, 1.0);      // output pixels per source pixel
uniform bool smooth_scale = true;

vec3 colour_at(vec2 p) {
	p = clamp(p, vec2(0.0), src_size - 1.0);
	float idx = texture(idx_tex, (p + 0.5) / src_size).r;
	return texture(pal_tex, vec2((floor(idx * 255.0 + 0.5) + 0.5) / 256.0, 0.5)).rgb;
}

void fragment() {
	vec2 texel = UV * src_size;
	if (!smooth_scale) {
		COLOR = vec4(colour_at(floor(texel)), 1.0);
	} else {
		vec2 t = texel - 0.5;
		vec2 f0 = floor(t);
		vec2 f = clamp((t - f0 - 0.5) * out_scale + 0.5, 0.0, 1.0);
		vec3 a = colour_at(f0);
		vec3 b = colour_at(f0 + vec2(1.0, 0.0));
		vec3 c = colour_at(f0 + vec2(0.0, 1.0));
		vec3 d = colour_at(f0 + vec2(1.0, 1.0));
		COLOR = vec4(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), 1.0);
	}
}
