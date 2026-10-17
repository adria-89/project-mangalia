shader_type canvas_item;

// Pause "picture mode": the frozen game (a snapshot as the texture) flattened
// to three tones of the scroll's own ink (shadow, brown, highlight). It
// spreads out from the center as reveal goes 0 -> 1.

uniform vec4 shadow_color : source_color = vec4(0.06, 0.04, 0.03, 1.0);
uniform vec4 mid_color : source_color = vec4(0.51, 0.41, 0.23, 1.0);
uniform vec4 light_color : source_color = vec4(0.85, 0.71, 0.65, 1.0);
// Brightness where shadow turns to brown, and brown to highlight.
uniform float mid_threshold : hint_range(0.0, 1.0) = 0.22;
uniform float light_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 picture = texture(TEXTURE, UV);
	float brightness = dot(picture.rgb, vec3(0.299, 0.587, 0.114));
	vec4 tone = brightness < mid_threshold ? shadow_color
		: (brightness < light_threshold ? mid_color : light_color);
	// Circle from the center (aspect corrected), reaching the corners at reveal 1.
	vec2 aspect = vec2(TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x, 1.0);
	float radius = reveal * length(aspect) * 0.5;
	COLOR = length((UV - 0.5) * aspect) <= radius ? tone : picture;
}
