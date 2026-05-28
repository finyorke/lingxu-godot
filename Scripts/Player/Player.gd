extends Node2D
class_name YunxiPlayer

signal died

var hp := 110.0
var shield := 60.0
var velocity := Vector2.ZERO
var facing := Vector2.DOWN
var dash_time := 0.0
var dash_cd := 0.0
var iframe_time := 0.0
var shield_delay := 0.0
var sprite: Sprite2D
var shadow: ColorRect

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = AssetDB.tex("char_yunxi")
	sprite.scale = Vector2(0.11, 0.11)
	sprite.position = Vector2(0, -26)
	add_child(sprite)
	shadow = ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.22)
	shadow.size = Vector2(50, 18)
	shadow.position = Vector2(-25, 16)
	add_child(shadow)
	hp = float(GameState.stats.get("max_hp", 110))
	shield = float(GameState.stats.get("max_qi_shield", 60))

func tick(delta: float, arena_radius: Vector2) -> void:
	dash_cd = max(0.0, dash_cd - delta)
	iframe_time = max(0.0, iframe_time - delta)
	shield_delay = max(0.0, shield_delay - delta)
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 1.0:
		input = input.normalized()
	if input.length_squared() > 0.01:
		facing = input.normalized()
	var speed := float(GameState.stats.get("move_speed", 160)) * (1.0 + float(GameState.stats.get("speed_pct", 0.0)))
	if Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
		dash_time = float(GameState.stats.get("dash_duration", 0.18))
		dash_cd = float(GameState.stats.get("dash_cooldown", 2.2))
		iframe_time = float(GameState.stats.get("dash_iframes", 0.30))
		SignalsBus.hud_request_shake.emit(4.0, 0.12)
	if dash_time > 0.0:
		dash_time -= delta
		velocity = (facing if input.length_squared() <= 0.01 else input.normalized()) * float(GameState.stats.get("dash_speed", 640))
	else:
		velocity = input * speed
	position += velocity * delta
	_clamp_to_ellipse(arena_radius)
	_regen(delta)
	_update_visual(delta)

func _regen(delta: float) -> void:
	hp = min(float(GameState.stats.get("max_hp", 110)), hp + float(GameState.stats.get("hp_regen", 0.0)) * delta)
	if shield_delay <= 0.0:
		shield = min(float(GameState.stats.get("max_qi_shield", 60)), shield + float(GameState.stats.get("qi_shield_regen", 8.0)) * delta)

func receive_damage(amount: float) -> void:
	if iframe_time > 0.0:
		return
	if randf() < clamp(float(GameState.stats.get("dodge", 0.0)), 0.0, 0.60):
		SignalsBus.hud_request_shake.emit(2.0, 0.08)
		return
	var armor := float(GameState.stats.get("armor", 0.0))
	var mitigated := amount * (1.0 - armor / (armor + 60.0)) if armor > 0.0 else amount
	shield_delay = float(GameState.stats.get("qi_shield_delay", 3.5))
	if shield > 0.0:
		var absorbed: float = min(shield, mitigated)
		shield -= absorbed
		mitigated -= absorbed
	hp -= mitigated
	iframe_time = 0.24
	sprite.modulate = Color("#f25050")
	SignalsBus.player_damaged.emit(mitigated)
	SignalsBus.hud_request_shake.emit(8.0, 0.16)
	if hp <= 0.0:
		died.emit()

func heal_from_lifesteal(amount: float) -> void:
	var heal := amount * float(GameState.stats.get("lifesteal", 0.0))
	if heal > 0.0:
		hp = min(float(GameState.stats.get("max_hp", 110)), hp + heal)

func _clamp_to_ellipse(radius: Vector2) -> void:
	var v := position
	var metric := (v.x * v.x) / (radius.x * radius.x) + (v.y * v.y) / (radius.y * radius.y)
	if metric > 1.0:
		position = v / sqrt(metric)

func _update_visual(delta: float) -> void:
	var moving := velocity.length_squared() > 20.0
	sprite.rotation = sin(Time.get_ticks_msec() * 0.006) * (0.045 if moving else 0.018)
	sprite.position.y = -28 + sin(Time.get_ticks_msec() * 0.005) * (5 if moving else 2)
	sprite.flip_h = facing.x < -0.1
	if iframe_time <= 0.0:
		sprite.modulate = sprite.modulate.lerp(Color.WHITE, delta * 12.0)

func hp_ratio() -> float:
	return hp / max(1.0, float(GameState.stats.get("max_hp", 110)))
