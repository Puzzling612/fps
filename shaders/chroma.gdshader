shader_type canvas_item;
render_mode blend_add;

// GL-Compatibility-safe "chroma flash": no SCREEN_TEXTURE / back buffer needed.
// Draws faint red/blue color fringing toward the screen edges, fully transparent
// in the center. `strength` drives both the spread and the brightness.
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	if (strength <= 0.0001) {
		COLOR = vec4(0.0);
	} else {
		// 0 at center, ~1 at the corners.
		float edge = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
		float ring = pow(edge, 2.5) * strength;
		// Red leans one side, blue the other → fringe look.
		float side = UV.x - 0.5;
		vec3 col = vec3(max(side, 0.0), 0.0, max(-side, 0.0)) * 2.0;
		COLOR = vec4(col * ring, ring * 0.85);
	}
}
