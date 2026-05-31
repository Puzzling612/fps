extends CanvasLayer

@onready var hp_bar: ProgressBar = $HPPanel/HPBar
@onready var hp_label: Label = $HPPanel/HPLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var reload_bar: ProgressBar = $ReloadBar
@onready var round_label: Label = $RoundLabel
@onready var score_label: Label = $ScoreLabel
@onready var center_message: Label = $CenterMessage
@onready var game_over_label: Label = $GameOverLabel
@onready var message_timer: Timer = $MessageTimer
@onready var hit_marker: Label = $HitMarker
@onready var damage_vignette: ColorRect = $DamageVignette

@onready var dash_top: ColorRect = $Crosshair/DashTop
@onready var dash_bottom: ColorRect = $Crosshair/DashBottom
@onready var dash_left: ColorRect = $Crosshair/DashLeft
@onready var dash_right: ColorRect = $Crosshair/DashRight

const CROSSHAIR_INNER_REST: float = 4.0
const CROSSHAIR_OUTER_REST: float = 12.0
const CROSSHAIR_INNER_PEAK: float = 11.0
const CROSSHAIR_OUTER_PEAK: float = 24.0
const CROSSHAIR_FX_DURATION: float = 0.1
const COLOR_REST: Color = Color(1, 1, 1, 0.9)
const COLOR_HEAD: Color = Color(1, 0.15, 0.15, 1)

var _vignette_alpha: float = 0.0
var _hit_marker_alpha: float = 0.0
var _reload_total: float = 0.0
var _reload_remaining: float = 0.0
var _is_reloading: bool = false
var _crosshair_t: float = 0.0

func _ready() -> void:
	GameManager.player_health_changed.connect(_on_hp_changed)
	GameManager.ammo_changed.connect(_on_ammo_changed)
	GameManager.round_started.connect(_on_round_started)
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.game_over_triggered.connect(_on_game_over)
	GameManager.reload_started.connect(_on_reload_started)
	GameManager.reload_finished.connect(_on_reload_finished)
	GameManager.weapon_fired.connect(_on_weapon_fired)
	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.weapon_changed.connect(_on_weapon_changed)
	GameManager.weapon_unlocked.connect(_on_weapon_unlocked)

	center_message.visible = false
	game_over_label.visible = false
	reload_label.visible = false
	reload_bar.visible = false
	message_timer.timeout.connect(_on_message_timeout)
	_apply_crosshair(CROSSHAIR_INNER_REST, CROSSHAIR_OUTER_REST, COLOR_REST)

func _process(delta: float) -> void:
	if _vignette_alpha > 0.0:
		_vignette_alpha = max(0.0, _vignette_alpha - delta * 1.5)
		var c = damage_vignette.color
		c.a = _vignette_alpha
		damage_vignette.color = c

	if _hit_marker_alpha > 0.0:
		_hit_marker_alpha = max(0.0, _hit_marker_alpha - delta * 4.0)
		hit_marker.modulate.a = _hit_marker_alpha

	if _crosshair_t > 0.0:
		_crosshair_t = max(0.0, _crosshair_t - delta)
		var k = _crosshair_t / CROSSHAIR_FX_DURATION  # 1.0 → 0.0
		var inner = lerp(CROSSHAIR_INNER_REST, CROSSHAIR_INNER_PEAK, k)
		var outer = lerp(CROSSHAIR_OUTER_REST, CROSSHAIR_OUTER_PEAK, k)
		var col = COLOR_REST.lerp(COLOR_HEAD, k)
		_apply_crosshair(inner, outer, col)
		if _crosshair_t <= 0.0:
			_apply_crosshair(CROSSHAIR_INNER_REST, CROSSHAIR_OUTER_REST, COLOR_REST)

	if _is_reloading:
		_reload_remaining = max(0.0, _reload_remaining - delta)
		var progress = 0.0
		if _reload_total > 0.0:
			progress = 1.0 - (_reload_remaining / _reload_total)
		reload_bar.value = progress

func _apply_crosshair(inner: float, outer: float, col: Color) -> void:
	dash_top.offset_top = -outer
	dash_top.offset_bottom = -inner
	dash_bottom.offset_top = inner
	dash_bottom.offset_bottom = outer
	dash_left.offset_left = -outer
	dash_left.offset_right = -inner
	dash_right.offset_left = inner
	dash_right.offset_right = outer
	dash_top.color = col
	dash_bottom.color = col
	dash_left.color = col
	dash_right.color = col

func _on_score_changed(value: int) -> void:
	score_label.text = "Score: %d" % value

func _on_game_over() -> void:
	game_over_label.visible = true

func _on_hp_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	hp_label.text = "HP  %d / %d" % [current, maximum]

var _weapon_name: String = "ASSAULT RIFLE"
var _mag: int = 0
var _mag_size: int = 0
var _reserve: int = 0

func _on_ammo_changed(magazine: int, magazine_size: int, reserve: int) -> void:
	_mag = magazine; _mag_size = magazine_size; _reserve = reserve
	_render_ammo()

func _on_weapon_changed(weapon_name: String) -> void:
	_weapon_name = weapon_name
	_render_ammo()

func _render_ammo() -> void:
	ammo_label.text = "%s   %d/%d   %d" % [_weapon_name, _mag, _mag_size, _reserve]

func _on_weapon_unlocked(weapon_name: String) -> void:
	center_message.text = "%s UNLOCKED" % weapon_name
	center_message.visible = true
	message_timer.start()

func _on_reload_started(duration: float) -> void:
	_is_reloading = true
	_reload_total = duration
	_reload_remaining = duration
	reload_label.visible = true
	reload_bar.visible = true
	reload_bar.value = 0.0

func _on_reload_finished() -> void:
	_is_reloading = false
	reload_label.visible = false
	reload_bar.visible = false

func _on_weapon_fired(_from: Vector3, _to: Vector3, hit_enemy: bool, is_headshot: bool) -> void:
	if not hit_enemy:
		return
	if is_headshot:
		# Trigger crosshair expand+red effect. No "HEADSHOT" text.
		_crosshair_t = CROSSHAIR_FX_DURATION
	else:
		_hit_marker_alpha = 1.0
		hit_marker.modulate = Color(1, 0.3, 0.3, 1)

func _on_player_damaged(_amount: int) -> void:
	_vignette_alpha = 0.55
	var c = damage_vignette.color
	c.a = _vignette_alpha
	damage_vignette.color = c

func _on_round_started(n: int) -> void:
	round_label.text = "Round %d" % n
	center_message.text = "ROUND %d" % n
	center_message.visible = true
	message_timer.start()

func _on_message_timeout() -> void:
	center_message.visible = false
