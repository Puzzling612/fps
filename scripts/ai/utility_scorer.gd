# UtilityScorer — scores candidate tactical actions for one enemy, given the
# current situation (context) and the learned PlayerProfile. The Behavior Tree
# (Step 3) calls this inside its combat/search selector; in Step 2 the enemy
# state machine calls pick_action() directly.
#
# Score(action) = Base + Σ Context + Σ Adapt(profile)*confidence + noise
class_name UtilityScorer
extends RefCounted

# Action identifiers (string keys are cheap and debuggable)
const ENGAGE  := "engage"    # hold preferred range, light strafe, fire
const STRAFE  := "strafe"    # orbit the player while firing
const PUSH    := "push"      # aggressively close the distance
const COVER   := "cover"     # break LOS / seek cover, peek
const FLANK   := "flank"     # move to a flank slot (behind player view)
const RETREAT := "retreat"   # fall back when badly hurt

# context keys expected:
#   distance:float, health_ratio:float, has_los:bool, in_cover:bool,
#   has_flank_slot:bool, preferred_distance:float, min_distance:float
static func pick_action(ctx: Dictionary, profile: PlayerProfile) -> String:
	var scores := _score_all(ctx, profile)
	var best := ENGAGE
	var best_s := -INF
	for k in scores:
		if scores[k] > best_s:
			best_s = scores[k]
			best = k
	return best

static func _score_all(ctx: Dictionary, profile: PlayerProfile) -> Dictionary:
	var dist: float = ctx.get("distance", 12.0)
	var hp: float = ctx.get("health_ratio", 1.0)
	var has_los: bool = ctx.get("has_los", false)
	var in_cover: bool = ctx.get("in_cover", false)
	var has_flank: bool = ctx.get("has_flank_slot", false)
	var pref: float = ctx.get("preferred_distance", 11.0)
	var mind: float = ctx.get("min_distance", 6.0)
	var c: float = profile.confidence()

	var s := {
		ENGAGE: 0.0, STRAFE: 0.0, PUSH: 0.0,
		COVER: 0.0, FLANK: 0.0, RETREAT: 0.0,
	}

	# ── Base values ──
	s[ENGAGE] = 45.0
	s[STRAFE] = 40.0
	s[PUSH]   = 25.0
	s[COVER]  = 20.0
	s[FLANK]  = 22.0 if has_flank else -100.0
	s[RETREAT] = -100.0

	# ── Context: distance ──
	if dist > pref + 4.0:
		s[PUSH]   += 18.0
		s[ENGAGE] -= 8.0
	elif dist < mind:
		s[STRAFE] += 12.0
		s[COVER]  += 8.0
		s[PUSH]   -= 20.0
	else:
		s[STRAFE] += 10.0
		s[ENGAGE] += 8.0

	# ── Context: line of sight ──
	if not has_los:
		s[ENGAGE] -= 30.0
		s[STRAFE] -= 25.0
		s[PUSH]   += 15.0   # advance to regain LOS
		s[FLANK]  += 15.0

	# ── Context: self health ──
	s[RETREAT] += (1.0 - hp) * 120.0          # crosses 0 around ~30% hp
	s[COVER]   += (1.0 - hp) * 40.0
	s[PUSH]    -= (1.0 - hp) * 30.0
	if in_cover:
		s[COVER] += 10.0

	# ── Adaptive modifiers (scaled by confidence) — the learning core ──
	if profile.is_sniper():
		s[FLANK] += 50.0 * c
		s[COVER] += 20.0 * c
		s[PUSH]  -= 30.0 * c

	if profile.is_rusher():
		s[COVER]  += 30.0 * c      # let them come, punish from cover
		s[STRAFE] += 15.0 * c
		s[PUSH]   -= 25.0 * c

	if profile.is_long_range():
		s[PUSH]  += 25.0 * c       # deny their range by closing
		s[FLANK] += 15.0 * c

	if profile.is_camper():
		s[FLANK] += 25.0 * c       # dig them out from the side
		s[PUSH]  += 15.0 * c

	# Player strafes hard one way → flanking the opposite side pays off
	if absf(profile.strafe_bias) > 0.4:
		s[FLANK] += 20.0 * c

	# High player headshot ratio → don't peek straight, prefer cover/flank
	if profile.headshot_ratio > 0.35:
		s[COVER] += 20.0 * c
		s[ENGAGE] -= 15.0 * c

	# ── Per-enemy noise to avoid lockstep / robotic patterns ──
	for k in s:
		s[k] += randf_range(-4.0, 4.0)

	return s
