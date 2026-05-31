# PlayerProfile — a snapshot of observed player behaviour.
# Pure data + derived-label helpers. One instance per memory tier
# (recent / mid / total). Updated via EMA so memory cost is constant.
class_name PlayerProfile
extends RefCounted

# ── Weapon / engagement ──
var weapon_usage: Dictionary = {}      # "rifle": shots, ...  (extensible; 1 weapon for now)
var avg_engage_distance: float = 12.0  # EMA of player→enemy distance when player fires
var headshot_ratio: float = 0.0        # EMA: 1.0 on headshot, 0.0 otherwise
var close_shots: float = 0.0           # EMA mass of <12m shots
var long_shots: float = 0.0            # EMA mass of >25m shots

# ── Movement ──
var avg_move_speed: float = 0.0        # EMA of horizontal speed
var jump_rate: float = 0.0             # EMA (1.0 spikes on a jump)
var strafe_bias: float = 0.0           # EMA, -1(left).. +1(right)
var strafe_frequency: float = 0.0      # EMA of direction-flip events

# ── Space ──
var position_heatmap: Dictionary = {}  # quantized cell key -> weight
var cover_usage: float = 0.0           # EMA: 1.0 while near cover/LOS-broken

# ── Derived tendency scores (0..1) ──
var rush_tendency: float = 0.0
var sniper_tendency: float = 0.0
var camp_tendency: float = 0.0

# ── Confidence ──
var sample_count: int = 0

func confidence() -> float:
	return clamp(float(sample_count) / 250.0, 0.0, 1.0)

# ── Derived labels ──
func is_sniper() -> bool:     return sniper_tendency > 0.55
func is_rusher() -> bool:     return rush_tendency  > 0.55
func is_camper() -> bool:     return camp_tendency  > 0.55
func is_long_range() -> bool: return avg_engage_distance > 22.0

# Recompute tendency scores from raw EMA signals.
func recompute_tendencies(max_speed: float) -> void:
	var speed_n: float = clamp(avg_move_speed / max(max_speed, 0.01), 0.0, 1.0)
	var dist_n: float  = clamp(avg_engage_distance / 35.0, 0.0, 1.0)
	var long_n: float  = clamp(long_shots, 0.0, 1.0)
	var close_n: float = clamp(close_shots, 0.0, 1.0)

	rush_tendency = clamp(
		0.45 * speed_n + 0.35 * close_n + 0.20 * (1.0 - cover_usage), 0.0, 1.0)
	sniper_tendency = clamp(
		0.50 * long_n + 0.30 * dist_n + 0.20 * (1.0 - speed_n), 0.0, 1.0)
	camp_tendency = clamp(
		0.45 * (1.0 - speed_n) + 0.35 * cover_usage + 0.20 * long_n, 0.0, 1.0)

func snapshot() -> Dictionary:
	return {
		"avg_engage_distance": snappedf(avg_engage_distance, 0.1),
		"avg_move_speed": snappedf(avg_move_speed, 0.1),
		"strafe_bias": snappedf(strafe_bias, 0.01),
		"headshot_ratio": snappedf(headshot_ratio, 0.01),
		"rush": snappedf(rush_tendency, 0.01),
		"sniper": snappedf(sniper_tendency, 0.01),
		"camp": snappedf(camp_tendency, 0.01),
		"confidence": snappedf(confidence(), 0.01),
		"samples": sample_count,
	}
