shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_always;

// Outline for glass props. The normal outline is opaque and draws before the
// glass, so its far side would show through as a black blob. This one is in
// the transparent pass with a higher render_priority than the glass: it draws
// after it, and the depth the glass wrote hides everything but the silhouette.

#include "res://shaders/outline.gdshaderinc"

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
