shader_type canvas_item;

// The splash logo filling up, layered cola / beer / rum (bottom to top): only
// its white parts take the liquid, the black lines stay, and the white stays
// white until the drink reaches it. Each layer's top is a level, 0..1 of the
// logo's height from the bottom. A line of surface/foam tops cola and beer,
// fizz rises in both. The surfaces slosh (tilt) and ripple.

uniform float cola_level = 0.0;
uniform float beer_level = 0.0;
uniform float total_level = 0.0;
// Surface tilt: positive = the right side is higher.
uniform float slosh = 0.0;
uniform float ripple = 0.012;
uniform float foam_thickness = 0.03;
// Cola and beer colors from the game's drinks (props/drinks/*.tres).
uniform vec4 cola_color : source_color = vec4(0.24, 0.09, 0.04, 1.0);
uniform vec4 cola_surface : source_color = vec4(0.46, 0.26, 0.15, 1.0);
uniform vec4 cola_fizz : source_color = vec4(0.5, 0.3, 0.18, 1.0);
uniform vec4 beer_color : source_color = vec4(0.85, 0.55, 0.12, 1.0);
uniform vec4 beer_foam : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec4 beer_fizz : source_color = vec4(1.0, 0.82, 0.45, 1.0);
// Warmer than the game's nearly clear rum, or it vanishes on the white
// logo (same tint as the icon's rum).
uniform vec4 rum_color : source_color = vec4(0.91, 0.84, 0.65, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Height of a surface at this x: tilted by the slosh, rippling over time.
float surface(float level, float x) {
	return level + (slosh * (x - 0.5) + ripple * sin(x * 19.0 + TIME * 5.0)) * step(0.001, level);
}

// Small round bubbles drifting up through the fizzy layers.
float bubbles(vec2 uv, vec2 pixel_size) {
	vec2 grid = vec2(uv.x * 30.0, (uv.y + TIME * 0.22) * 14.0);
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - vec2(0.25 + 0.5 * hash(cell + 3.1), 0.5);
	// Cells are wider than tall in pixels: squeeze x so bubbles come out round.
	local.x *= 14.0 / 30.0 * (pixel_size.y / pixel_size.x);
	return step(0.78, hash(cell)) * step(length(local), 0.16);
}

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	// The art is black ink on white: the liquid is multiplied in by how
	// white each pixel is, so the lines stay black and the soft grey edges
	// between them shade the liquid instead of leaving grey specks.
	float white = (art.r + art.g + art.b) / 3.0;
	float height = 1.0 - UV.y;
	float cola_top = surface(cola_level, UV.x);
	float beer_top = max(surface(beer_level, UV.x), cola_top);
	float top = max(surface(total_level, UV.x), beer_top);
	float fizz = bubbles(UV, TEXTURE_PIXEL_SIZE);
	vec3 fill = vec3(1.0);
	if (height < cola_top) {
		fill = height > cola_top - foam_thickness ? cola_surface.rgb : mix(cola_color.rgb, cola_fizz.rgb, fizz);
	} else if (height < beer_top) {
		fill = height > beer_top - foam_thickness ? beer_foam.rgb : mix(beer_color.rgb, beer_fizz.rgb, fizz);
	} else if (height < top) {
		fill = rum_color.rgb;
	}
	COLOR = vec4(fill * white, art.a);
}
