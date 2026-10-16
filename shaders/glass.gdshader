shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;

// Cartoon glass: a faint tint you see the drink through, a solid band where
// the wall turns away from the camera, and hard white highlight streaks that
// stay put relative to the camera (like painted-on shine).
// Drawn twice (ToonProp sets it up): first the back faces (far wall, inside),
// then the front faces over them, so the layers never sort wrong.
// keep_bands keeps the texture's metal bands (blue-ish pixels) solid.

uniform bool back_pass = false;

uniform vec4 glass_color : source_color = vec4(0.82, 0.95, 1.0, 0.12);
uniform vec4 back_color : source_color = vec4(0.7, 0.88, 0.95, 0.1);
uniform vec4 edge_color : source_color = vec4(0.85, 0.97, 1.0, 0.75);
// How far in from the silhouette the edge band reaches (0 = none).
uniform float edge_width : hint_range(0.0, 1.0) = 0.35;

group_uniforms highlight;
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
// Streaks as ranges of the view-space normal's x (-1 = left edge, 1 = right).
uniform vec2 streak_wide = vec2(-0.72, -0.5);
uniform vec2 streak_thin = vec2(-0.38, -0.3);

group_uniforms texture;
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform bool use_texture = false;
uniform bool keep_bands = true;

void fragment() {
	if (FRONT_FACING == back_pass) {
		discard;
	}
	vec4 color = back_pass ? back_color : glass_color;
	if (!back_pass) {
		float facing = abs(dot(NORMAL, VIEW));
		if (facing < edge_width) {
			color = edge_color;
		}
		// Only on the sides, not on surfaces facing up/down (rim, bottom).
		bool side = abs(NORMAL.y) < 0.6;
		bool wide = NORMAL.x > streak_wide.x && NORMAL.x < streak_wide.y;
		bool thin = NORMAL.x > streak_thin.x && NORMAL.x < streak_thin.y;
		if (side && (wide || thin)) {
			color = highlight_color;
		}
	}
	if (use_texture && keep_bands) {
		vec3 tex = texture(albedo_texture, UV).rgb;
		if (tex.b > tex.r) {
			color = vec4(tex, 1.0);
		}
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
