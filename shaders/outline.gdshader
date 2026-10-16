shader_type spatial;
render_mode unshaded, cull_front;

// Black outline around toon props (see outline.gdshaderinc).

#include "res://shaders/outline.gdshaderinc"

void fragment() {
	ALBEDO = outline_color.rgb;
}
