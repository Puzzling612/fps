# WaveBalance — single source of truth for wave-scaled combat tuning.
# Pure static formulas; no state. See the balance design doc for derivations.
class_name WaveBalance
extends RefCounted

# ── Static per-wave formulas ──
static func enemy_hp(w: int) -> int:
	return 100 + 15 * (w - 1)

static func enemy_dmg(w: int) -> int:
	return int(round(6.0 + 1.4 * (w - 1)))

static func enemy_interval(w: int) -> float:
	return max(0.6, 1.05 - 0.05 * (w - 1))

static func enemy_spread(w: int) -> float:
	return max(1.0, 5.0 - 0.35 * (w - 1))

static func heal_amount(w: int) -> int:
	return clampi(int(round(45.0 - 1.5 * (w - 1))), 25, 45)

static func headshot_mult(w: int) -> float:
	return 3.0 + 0.1 * floori((w - 1) / 3.0)

# Distance damage falloff: full to 8m, down to 50% past ~48m.
static func falloff(dist: float) -> float:
	return clampf(1.0 - max(0.0, dist - 8.0) / 40.0, 0.5, 1.0)
