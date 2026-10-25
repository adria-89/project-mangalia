shader_type canvas_item;

// Colours a body part exported by tools/fapwall/parts.py: R = shade (0 dark
// .. 1 light), G = region (0 skin, 64 flesh, 192 cum, 255 line). The same
// grey part works for every girl; her ramps make it hers.

uniform sampler2D skin_ramp : filter_linear, repeat_disable;
uniform sampler2D flesh_ramp : filter_linear, repeat_disable;
uniform vec4 line_color : source_color = vec4(0.06, 0.06, 0.03, 1.0);
uniform vec4 cum_dark : source_color = vec4(0.82, 0.8, 0.72, 1.0);
uniform vec4 cum_light : source_color = vec4(1.0, 0.99, 0.95, 1.0);
// Wet (0..1): highlights get brighter and larger.
uniform float shine = 0.0;
// Her wetness coating it (0..1, the penis only): glossy runs along it,
// bigger highlights, specks of shine. Snapped to the art's pixels.
uniform float coat = 0.0;
uniform vec4 coat_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);

// Slapped red (each butt half has its own copy of the material): the whole
// cheek reddens, cheek_red 0..1, around cheek_center out to cheek_radius
// (the sprite's own pixels). It tints her skin rather than painting over
// it, so it suits every skin tone. Pixel-snapped.
uniform float cheek_red = 0.0;
uniform vec2 cheek_center = vec2(0.0);
uniform float cheek_radius = 56.0;
// Slapped a lot: a "#" of welts across the cheek, deeper red (hurt 0..1),
// hurt_size pixels across, its strokes hurt_width wide, leaning a little.
uniform float hurt = 0.0;
uniform float hurt_size = 36.0;
uniform float hurt_width = 4.0;
uniform vec4 hurt_tint : source_color = vec4(0.95, 0.22, 0.28, 1.0);
uniform vec4 mark_tint : source_color = vec4(1.0, 0.42, 0.42, 1.0);
// Bending (a penis only): its rows shift sideways, none at the base and
// bend art pixels at the tip, growing with the square of the way along, so
// it curves like two bones on a spring. Whole pixels, so it stays pixel art.
// bend_rect: the art's region (UV); base_at_top: its base is the top row
// (else the bottom one); bend_pad: art pixels of room added either side of
// it to bend into (0 = it doesn't bend).
uniform float bend = 0.0;
uniform vec4 bend_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool base_at_top = false;
uniform float bend_pad = 0.0;

varying vec4 tint;
varying vec2 local;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	tint = COLOR; // modulate
	local = VERTEX;
	if (bend_pad > 0.0) {
		// Widen the quad so the bent art still fits in it.
		float side = sign(UV.x - bend_rect.x - bend_rect.z * 0.5);
		VERTEX.x += side * bend_pad;
		UV.x += side * bend_pad * TEXTURE_PIXEL_SIZE.x;
	}
}

void fragment() {
	vec2 uv = UV;
	if (bend_pad > 0.0) {
		float row = floor((UV.y - bend_rect.y) / TEXTURE_PIXEL_SIZE.y) + 0.5;
		float along = row * TEXTURE_PIXEL_SIZE.y / bend_rect.w;
		along = base_at_top ? along : 1.0 - along;
		uv.x -= round(bend * along * along) * TEXTURE_PIXEL_SIZE.x;
	}
	vec4 part = texture(TEXTURE, uv);
	if (bend_pad > 0.0 && (uv.x < bend_rect.x || uv.x > bend_rect.x + bend_rect.z)) {
		part.a = 0.0; // the room around it (or the next art in the atlas)
	}
	float shade = part.r;
	vec3 color;
	if (part.g > 0.87) {
		color = line_color.rgb;
	} else if (part.g > 0.5) {
		color = mix(cum_dark.rgb, cum_light.rgb, shade);
	} else {
		shade = clamp(shade + shine * smoothstep(0.6, 1.0, shade) * 0.35, 0.0, 1.0);
		color = part.g > 0.125 ? texture(flesh_ramp, vec2(shade, 0.5)).rgb : texture(skin_ramp, vec2(shade, 0.5)).rgb;
		if (cheek_red > 0.0 && part.g <= 0.125) {
			vec2 at = floor(local) + 0.5;
			float red = cheek_red * (1.0 - smoothstep(cheek_radius * 0.55, cheek_radius, distance(at, cheek_center)));
			color = mix(color, color * mark_tint.rgb * 1.3, red * 0.85);
			if (hurt > 0.0) {
				vec2 p = at - cheek_center;
				p.x += p.y * 0.25; // leaning
				float gap = hurt_size * 0.18; // each pair of strokes sits this far either side
				bool within = abs(p.x) < hurt_size * 0.5 && abs(p.y) < hurt_size * 0.5;
				bool stroke = abs(abs(p.x) - gap) < hurt_width * 0.5 || abs(abs(p.y) - gap) < hurt_width * 0.5;
				if (within && stroke) {
					color = mix(color, color * hurt_tint.rgb * 1.2, hurt * 0.9);
				}
			}
		}
		if (coat > 0.0) {
			// Whole art pixels, so it stays pixel art at any size.
			vec2 texel = floor(uv / TEXTURE_PIXEL_SIZE);
			// Wet patches (3x3-pixel blobs) that grow together into a full coat.
			float blob = hash(floor(texel / 3.0));
			float covered = step(1.0 - coat * 1.15, blob);
			color = mix(color, color * 1.1 + coat_color.rgb * 0.12, covered * 0.7);
			// Highlights spread as it gets wetter.
			color = mix(color, coat_color.rgb, step(0.86 - coat * 0.3, shade) * coat * 0.6);
			// A bright rim just inside its outline, where the wet catches the light.
			vec4 left = texture(TEXTURE, uv - vec2(TEXTURE_PIXEL_SIZE.x, 0.0));
			vec4 right = texture(TEXTURE, uv + vec2(TEXTURE_PIXEL_SIZE.x, 0.0));
			float rim = max(step(left.a, 0.5) + step(0.87, left.g), step(right.a, 0.5) + step(0.87, right.g));
			rim = min(rim, 1.0);
			color = mix(color, coat_color.rgb * 1.2, rim * covered * coat * 0.7);
			// Glints sliding along it.
			float column = hash(vec2(texel.x, 7.0));
			float glint = step(fract(texel.y * 0.025 - TIME * 0.35 + column * 0.15), 0.05);
			color = mix(color, vec3(1.0), glint * covered * coat * 0.8);
			// Twinkling specks, each on its own beat.
			float speck = hash(texel);
			float twinkle = step(0.975 - coat * 0.03, speck) * step(0.3, sin(TIME * 6.0 + speck * 60.0));
			color = mix(color, vec3(1.0), twinkle * coat);
		}
	}
	COLOR = vec4(color, part.a) * tint;
}
