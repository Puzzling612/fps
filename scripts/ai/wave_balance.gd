# WaveBalance — single source of truth for wave-scaled combat tuning.
# Pure static formulas; no state. See the balance design doc for derivations.
class_name WaveBalance
extends RefCounted

# ── Static per-wave formulas ──
static func enemy_hp(w: int) -> int:
	# Ramps early, then plateaus at 220 by ~wave 9. Past that, difficulty comes
	# from enemy count / type mix (see enemy_spawner), not bullet-sponge HP.
	return mini(220, 100 + 15 * (w - 1))

# A single enemy's threat is FIXED across all waves — damage, fire rate and
# accuracy never scale. Difficulty rises only through enemy COUNT (the spawner)
# and the shrinking heal packs below.
static func enemy_dmg(_w: int) -> int:
	return 11

static func enemy_interval(_w: int) -> float:
	return 0.95

static func enemy_spread(_w: int) -> float:
	return 3.5

static func heal_amount(w: int) -> int:
	# The difficulty lever: heals get weaker as the waves climb.
	return clampi(int(round(48.0 - 2.0 * (w - 1))), 22, 48)

static func headshot_mult(w: int) -> float:
	return 3.0 + 0.1 * floori((w - 1) / 3.0)

# Distance damage falloff: full to 8m, down to 50% past ~48m.
static func falloff(dist: float) -> float:
	return clampf(1.0 - max(0.0, dist - 8.0) / 40.0, 0.5, 1.0)
