shader_type canvas_item;

// Circular sniper scope: opaque black mask outside the lens circle, a thin ring
// border, and fine crosshair lines inside. No screen sampling → GL-Compat safe.
uniform float aspect = 1.777;        // viewport width / height (keeps circle round)
uniform float radius = 0.42;         // lens radius in UV-height units

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x *= aspect;
	float d = length(p);

	// Opaque black everywhere outside the lens.
	float outside = smoothstep(radius, radius + 0.003, d);

	// Bright-ish ring just inside the rim.
	float ring = smoothstep(radius - 0.012, radius - 0.004, d) - smoothstep(radius - 0.004, radius, d);

	// Thin crosshair: full-width/height hairlines + a center dot gap.
	float line = 0.0;
	if (d < radius) {
		float lw = 0.0010;
		if (abs(p.x) < lw || abs(p.y) < lw) line = 1.0;
	}

	float alpha = max(outside, max(ring * 0.6, line * 0.9));
	COLOR = vec4(vec3(0.0), alpha);
}
