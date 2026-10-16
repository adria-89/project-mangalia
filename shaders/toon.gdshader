shader_type spatial;
// Both sides: open containers are modeled with single walls, seen from inside too.
render_mode cull_disabled;

// Flat cel shading to match the hand-drawn 2D art: hard light/shadow bands,
// a tinted shadow instead of black, and an optional hard-edged highlight.
// Meant for one main light (the lantern); each extra light adds its own bands.
// Turn use_lighting off for props whose texture already has painted shading:
// the texture is then shown exactly as painted, like the 2D art.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform bool use_texture = false;
uniform bool use_lighting = true;

group_uniforms bands;
// Color multiplied in on the shadow side. Warm/purple reads better than gray.
uniform vec4 shadow_color : source_color = vec4(0.45, 0.33, 0.35, 1.0);
// How many lit steps between shadow and full light (1 = classic two-tone).
uniform int bands : hint_range(1, 4) = 1;
// Where the shadow starts: higher = more of the object in shadow.
uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.1;

group_uniforms highlight;
uniform float highlight_strength : hint_range(0.0, 2.0) = 0.0;
uniform float highlight_size : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	vec3 color = albedo.rgb;
	if (use_texture) {
		color *= texture(albedo_texture, UV).rgb;
	}
	if (use_lighting) {
		ALBEDO = color;
	} else {
		ALBEDO = vec3(0.0);
		EMISSION = color;
	}
}

void light() {
	if (use_lighting) {
		float ndl = dot(NORMAL, LIGHT) * ATTENUATION;
		float lit = clamp((ndl - shadow_threshold) / max(1.0 - shadow_threshold, 0.001), 0.0, 1.0);
		lit = ceil(lit * float(bands)) / float(bands);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(shadow_color.rgb, vec3(1.0), lit);

		if (highlight_strength > 0.0) {
			float spec = dot(reflect(-LIGHT, NORMAL), VIEW);
			float spot = step(1.0 - highlight_size * 0.3, spec) * step(0.001, lit);
			SPECULAR_LIGHT += LIGHT_COLOR / PI * spot * highlight_strength;
		}
	}
}