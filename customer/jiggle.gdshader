shader_type canvas_item;

// Grayscale weight mask, same size as the sprite: white = moves fully,
// black/transparent = stays put. Weight is red * alpha so transparent
// padding never moves.
uniform sampler2D jiggle_mask : filter_nearest;
// Current spring displacement, in sprite pixels.
uniform vec2 spring_offset = vec2(0.0);
// 0 = no squish, 0.3 = flattened by 30% against the counter.
uniform float squish = 0.0;
// Where the chest touches the counter (UV y) and its horizontal center (UV x).
uniform float chest_bottom = 1.0;
uniform float chest_center_x = 0.5;
// Front copy: only draw the masked part, so it sits over the counter.
uniform bool front_only = false;
uniform float front_threshold = 0.35;
// Lights out (0 = lit, 1 = pitch black): everything goes black except the
// white parts of the eyes mask, which keep their color.
uniform sampler2D eyes_mask : filter_nearest;
uniform bool has_eyes_mask = false;
uniform float lights_out : hint_range(0.0, 1.0) = 0.0;
// 1 = eyes closed (they go dark too), for a blink in the dark.
uniform float blink : hint_range(0.0, 1.0) = 0.0;
// 1 = the current face has its eyes drawn shut, so nothing should glow.
uniform float eyes_shut : hint_range(0.0, 1.0) = 0.0;
// Blush overlay (same canvas as the sprite), faded in by blush_amount.
uniform sampler2D blush_tex : filter_nearest;
uniform float blush_amount : hint_range(0.0, 1.0) = 0.0;
// Nervous (anime gloom): a blue gradient pours down from the top of the
// sprite (nervous_reveal 0 -> 1), strongest at the top and gone by
// nervous_depth (UV y), plus an overlay (sweat drops, same canvas) that may
// sit outside her outline. nervous_amount fades the whole thing.
uniform sampler2D nervous_tex : filter_nearest, hint_default_transparent;
uniform float nervous_amount : hint_range(0.0, 1.0) = 0.0;
uniform float nervous_reveal : hint_range(0.0, 1.0) = 0.0;
uniform vec4 nervous_color : source_color = vec4(0.25, 0.38, 0.85, 1.0);
uniform float nervous_strength : hint_range(0.0, 1.0) = 0.55;
uniform float nervous_depth : hint_range(0.0, 1.0) = 0.6;
// Water ripple: rows shift sideways in a wave that runs down the sprite.
// ripple_amount = size in sprite pixels (0 = off), ripple_time drives it.
uniform float ripple_amount = 0.0;
uniform float ripple_time = 0.0;
uniform float ripple_waves = 6.0; // waves from top to bottom
uniform float ripple_speed = 18.0;
// Drunk sway: the same sideways row shift, but a long slow wave that never
// stops. drunk_sway = size in sprite pixels (0 = sober), drunk_time drives it.
uniform float drunk_sway = 0.0;
uniform float drunk_time = 0.0;
uniform float drunk_waves = 1.3;
uniform float drunk_speed = 1.8;

void fragment() {
	float weight = texture(jiggle_mask, UV).r * texture(jiggle_mask, UV).a;
	vec2 uv = UV;
	if (ripple_amount > 0.0) {
		uv.x += sin(UV.y * ripple_waves * TAU - ripple_time * ripple_speed) * ripple_amount * TEXTURE_PIXEL_SIZE.x;
	}
	if (drunk_sway > 0.0) {
		uv.x += sin(UV.y * drunk_waves * TAU - drunk_time * drunk_speed) * drunk_sway * TEXTURE_PIXEL_SIZE.x;
	}
	// Squish: compress toward the contact line and bulge sideways.
	float s = squish * weight;
	uv.y = chest_bottom - (chest_bottom - uv.y) / max(1.0 - s, 0.2);
	uv.x = chest_center_x + (uv.x - chest_center_x) / (1.0 + s * 0.6);
	uv -= spring_offset * weight * TEXTURE_PIXEL_SIZE;
	vec4 color = texture(TEXTURE, uv);
	if (blush_amount > 0.0) {
		vec4 b = texture(blush_tex, uv);
		color.rgb = mix(color.rgb, b.rgb, b.a * blush_amount);
	}
	if (nervous_amount > 0.0) {
		float edge = nervous_reveal * (nervous_depth + 0.15);
		float covered = 1.0 - smoothstep(edge - 0.15, edge, UV.y);
		float fade = 1.0 - smoothstep(0.0, nervous_depth, UV.y);
		color.rgb = mix(color.rgb, nervous_color.rgb, covered * fade * nervous_strength * nervous_amount);
		vec4 n = texture(nervous_tex, uv);
		color.rgb = mix(color.rgb, n.rgb, n.a * nervous_amount);
		color.a = max(color.a, n.a * nervous_amount);
	}
	if (front_only) {
		// Use the mask at the sampled spot so the cut-out moves with the chest.
		vec4 m = texture(jiggle_mask, uv);
		if (m.r * m.a < front_threshold) {
			color.a = 0.0;
		}
	}
	if (lights_out > 0.0) {
		float eye = 0.0;
		if (has_eyes_mask) {
			vec4 e = texture(eyes_mask, uv);
			eye = e.r * e.a * (1.0 - max(blink, eyes_shut));
		}
		color.rgb = mix(color.rgb, vec3(0.0), lights_out * (1.0 - eye));
	}
	COLOR = color;
}
