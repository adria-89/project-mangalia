shader_type spatial;
render_mode unshaded, cull_disabled;

// Drink inside a container. The mesh is a closed cylinder filling the inside
// (and a bit above the rim, for the head to pile up into); everything above
// the (world-space, sloshing) surface plane plus the head is cut away.
// Front faces are the drink's side, back faces show through the cut and
// read as the top seen from above. Purely visual: the foam is not drink.
//
// Toon look: noise textures are compared against thresholds into 2-3 flat
// tones (bubble cells on the foam, rising fizz specks in the beer).

uniform vec4 liquid_color : source_color = vec4(0.85, 0.55, 0.12, 1.0);
uniform vec4 surface_color : source_color = vec4(0.98, 0.93, 0.78, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
// Foam tones: inside the bubbles, and the lines between them.
uniform vec4 foam_shade : source_color = vec4(0.93, 0.85, 0.68, 1.0);
uniform vec4 foam_edge : source_color = vec4(0.8, 0.65, 0.42, 1.0);
uniform vec4 fizz_color : source_color = vec4(1.0, 0.82, 0.45, 1.0);
// A point on the surface and its normal, both in world space.
uniform vec3 surface_point = vec3(0.0);
uniform vec3 surface_normal = vec3(0.0, 1.0, 0.0);
// Head thickness above the surface (world units); 0 = no head.
uniform float foam_height = 0.0;
// The container's axis: bottom of the drink, up direction, height to the rim
// and the drink's radius, all in world space.
uniform vec3 axis_point = vec3(0.0);
uniform vec3 axis_up = vec3(0.0, 1.0, 0.0);
uniform float axis_height = 1.0;
uniform float radius = 0.5;

// Worley cells (bubbles, fizz), big soft cells (lumpy top edge), clouds
// (bubble size variation).
uniform sampler2D cells_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D lump_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
// World units per noise tile on the foam: smaller = smaller bubbles.
uniform float bubble_size = 0.25;
// Cell value from which a pixel is bubble shade / bubble edge.
uniform float shade_from = 0.4;
uniform float edge_from = 0.6;
// How much the head's top edge goes up and down (1 = by its full height),
// and how fast it churns.
uniform float lump_amount = 0.7;
uniform float lump_speed = 0.08;
// Foam motion: drift (tiles/s, rises and slides), twist (how far a slowly
// moving swirl field bends the bubbles), and how much each bubble swells and
// shrinks (each on its own beat) at what speed.
uniform vec2 foam_drift = vec2(0.04, 0.12);
uniform float foam_twist = 0.35;
uniform float twist_speed = 0.15;
uniform float foam_swell = 0.12;
uniform float swell_speed = 2.5;
// Toward the top of the head the bubbles get this many times smaller (= more
// of them), with more lines between them.
uniform float top_density = 2.2;
uniform float top_edge_boost = 0.08;
// Rising fizz in the beer: tile size, rise speed (world units/s), how much,
// and how many times more of it just under the head.
uniform float fizz_size = 0.12;
uniform float fizz_speed = 0.12;
uniform float fizz_amount = 0.07;
uniform float fizz_top_boost = 2.5;
// Lower part of the beer (fraction of the height) is drawn a shade darker.
uniform float dark_below = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Bubble cells at uv (in tiles). top: 0 = bottom of the head, 1 = its top.
vec3 foam_tone(vec2 uv, float top) {
	uv += foam_drift * TIME;
	// Twist: bend the pattern along a slowly drifting swirl field (two cloud
	// samples, offset so x and y bend differently).
	float t = TIME * twist_speed;
	vec2 swirl = vec2(
		texture(cloud_noise, uv * 0.15 + vec2(t, 0.0)).r,
		texture(cloud_noise, uv * 0.15 + vec2(0.37, 0.71) - vec2(0.0, t)).r) - 0.5;
	uv += swirl * foam_twist * 2.0;
	// Big bubbles below, more small ones toward the top.
	float c = mix(texture(cells_noise, uv).r, texture(cells_noise, uv * top_density + 0.5).r, top);
	float cloud = texture(cloud_noise, uv * 0.25).r;
	c += (cloud - 0.5) * 0.3;
	// Swell: each patch grows and shrinks on its own beat (lower value =
	// more of the cell inside the bubble).
	c -= sin(TIME * swell_speed + cloud * TAU * 3.0) * foam_swell;
	if (c > edge_from - top * top_edge_boost) {
		return foam_edge.rgb;
	}
	return c > shade_from ? foam_shade.rgb : foam_color.rgb;
}

void fragment() {
	// Cylinder coordinates around the axis: angle (0..1) and height.
	vec3 rel = world_pos - axis_point;
	float h = dot(rel, axis_up);
	// Picked so the angle wraps (the pattern's seam) on the far side, -z.
	vec3 tangent = normalize(cross(axis_up, vec3(-1.0, 0.0, 0.0)));
	vec3 bitangent = cross(axis_up, tangent);
	vec3 around = rel - axis_up * h;
	float angle = atan(dot(around, bitangent), dot(around, tangent)) / TAU + 0.5;

	float d = dot(world_pos - surface_point, surface_normal);
	// The head's top goes up and down around the glass, slowly churning.
	float lump = texture(lump_noise, vec2(angle * 2.0, TIME * lump_speed)).r;
	float foam_top = foam_height * (1.0 + lump_amount * (lump - 0.5));
	if (d > foam_top) {
		discard;
	}
	bool in_foam = d > 0.0;
	if (!in_foam && h > axis_height) {
		discard; // only the head may rise over the rim
	}

	if (FRONT_FACING) {
		if (in_foam) {
			float tiles = max(round(TAU * radius / bubble_size), 1.0);
			float top = clamp(d / max(foam_top, 0.0001), 0.0, 1.0);
			ALBEDO = foam_tone(vec2(angle * tiles, h / bubble_size), top);
		} else {
			vec3 color = h < axis_height * dark_below ? liquid_color.rgb * 0.8 : liquid_color.rgb;
			float tiles = max(round(TAU * radius / fizz_size), 1.0);
			// Rising, wobbling side to side, and gathering just under the head.
			vec2 fizz_uv = vec2(angle * tiles, (h - TIME * fizz_speed) / fizz_size);
			fizz_uv.x += sin(fizz_uv.y * 2.0 + TIME * 3.0) * 0.08;
			float near_top = smoothstep(-axis_height * 0.25, 0.0, d);
			float f = texture(cells_noise, fizz_uv).r;
			ALBEDO = f < fizz_amount * (1.0 + fizz_top_boost * near_top) ? fizz_color.rgb : color;
		}
	} else {
		if (foam_height < 0.0005) {
			ALBEDO = surface_color.rgb;
		} else {
			// Texture the top where the view ray meets the head's (flat) top.
			vec3 dir = normalize(world_pos - CAMERA_POSITION_WORLD);
			vec3 top_point = surface_point + surface_normal * foam_height;
			float denom = dot(dir, surface_normal);
			vec3 hit = world_pos;
			if (abs(denom) > 0.0001) {
				hit = CAMERA_POSITION_WORLD + dir * dot(top_point - CAMERA_POSITION_WORLD, surface_normal) / denom;
			}
			vec3 top_rel = hit - axis_point;
			ALBEDO = foam_tone(vec2(dot(top_rel, tangent), dot(top_rel, bitangent)) / bubble_size, 1.0);
		}
	}
}
