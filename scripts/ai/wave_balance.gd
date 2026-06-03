# WaveBalance — single source of truth for wave-scaled combat tuning.
# Pure static formulas; no state. See the balance design doc for derivations.
class_name WaveBalance
extends RefCounted

# ── Static per-wave formulas ──
static func enemy_hp(_w: int) -> int:
	# FIXED across all waves. Difficulty comes from enemy count / density
	# (see enemy_spawner), never from bullet-sponge HP. 200 here means after
	# type multipliers the toughest enemy is 200 HP — well under a sniper
	# headshot (150 × 3.0 = 450), so a scoped headshot one-shots ANY enemy.
	return 200

# A single enemy's threat is FIXED across all waves — damage, fire rate and
# accuracy never scale. Difficulty rises only through enemy COUNT (the spawner)
# and the shrinking heal packs below.
static func enemy_dmg(_w: int) -> int:
	# 3: compensates for the leaner heal economy (heal 20, fewer/spread packs →
	# throughput ~4.2→2.0 DPS). At dmg 3 worst-case incoming ~7.6 DPS, so net
	# pressure (~5.6 DPS) matches the previously-good balance. max_concurrent is
	# left alone — its kill-rate↔respawn balance is what makes kills relieve heat.
	return 3

static func enemy_interval(_w: int) -> float:
	return 0.95

static func enemy_spread(_w: int) -> float:
	return 3.5

static func heal_amount(_w: int) -> int:
	# Fixed at 20. Light top-up only; combined with fewer, spread-out packs this
	# keeps heal throughput ~2 DPS so survival comes from cover + kills, not
	# pickup circuits. enemy_dmg is balanced against this (see enemy_dmg).
	return 20

static func headshot_mult(_w: int) -> float:
	# FIXED. A headshot always deals 3× — combined with fixed 200 HP this
	# guarantees a sniper headshot (450) one-shots every enemy at any wave.
	return 3.0

# Distance damage falloff: full to 8m, down to 50% past ~48m.
static func falloff(dist: float) -> float:
	return clampf(1.0 - max(0.0, dist - 8.0) / 40.0, 0.5, 1.0)
