shader_type canvas_item;

// Mechsodus's pause menu screen: the screen behind in two tones, its bright
// parts color_b (red) and the rest color_a (black). The node's alpha (its
// color and modulate) fades it, so it can flash on and fade out.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 color_a : source_color = vec4(0.0, 0.0, 0.0, 1.0); // black
uniform vec4 color_b : source_color = vec4(0.8, 0.0, 0.0, 1.0); // red

void fragment() {
	vec4 screen = texture(screen_texture, SCREEN_UV);
	float brightness = dot(screen.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(color_a, color_b, step(0.7, brightness)).rgb, COLOR.a);
}