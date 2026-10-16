// Shared by outline.gdshader and outline_glass.gdshader.
// Inverted-hull outline: the mesh is pushed outward in screen space, so the
// line is the same pixel width at any distance and matches the 2D outlines.
// Needs smooth normals: hard edges split the hull and leave gaps.

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float thickness_px : hint_range(0.0, 8.0) = 1.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (length(dir) > 0.0001) {
		clip.xy += normalize(dir) * thickness_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}
