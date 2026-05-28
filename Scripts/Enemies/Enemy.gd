extends Node2D
class_name LingxuEnemy

signal died(enemy, xp_amount)

var enemy_id := "xie_wolf"
var data := {}
var hp := 1.0
var max_hp := 1.0
var radius := 20.0
var contact_timer := 0.0
var sprite: Sprite2D
var hp_bar: ColorRect
var is_boss := false
var slow_timer := 0.0
var slow_pct := 0.0

func setup(id: String, level_scale: float = 1.0) -> void:
	enemy_id = id
	data = ConfigDB.entry("enemies", id).duplicate(true)
	max_hp = float(data.get("hp", 30)) * level_scale
	hp = max_hp
	radius = float(data.get("radius", 20))
	is_boss = bool(data.get("is_boss", false))
	sprite = Sprite2D.new()
	sprite.texture = AssetDB.tex(str(data.get("sprite", id)))
	sprite.scale = Vector2.ONE * (0.16 if is_boss else 0.085)
	sprite.position = Vector2(0, -radius * 0.7)
	add_child(sprite)
	hp_bar = ColorRect.new()
	hp_bar.color = Color("#f25050")
	hp_bar.size = Vector2(radius * 2.2, 5)
	hp_bar.position = Vector2(-radius * 1.1, -radius * 2.3)
	add_child(hp_bar)

func tick(delta: float, player: YunxiPlayer) -> void:
	contact_timer = max(0.0, contact_timer - delta)
	slow_timer = max(0.0, slow_timer - delta)
	var to_player := player.global_position - global_position
	if to_player.length_squared() > 4.0:
		var speed := float(data.get("speed", 50))
		if slow_timer > 0.0:
			speed *= max(0.25, 1.0 - slow_pct)
		position += to_player.normalized() * speed * delta
		sprite.flip_h = to_player.x < 0
	if to_player.length() < radius + float(GameState.stats.get("body_radius", 22)) and contact_timer <= 0.0:
		player.receive_damage(float(data.get("damage", 8)))
		contact_timer = float(data.get("contact_cooldown", 0.65))
	sprite.rotation = sin(Time.get_ticks_msec() * 0.004 + position.x * 0.01) * 0.045

func take_damage(amount: float, is_crit: bool, element: String) -> void:
	hp -= amount
	sprite.modulate = Color("#eaf6ff") if is_crit else AssetDB.color_for_element(element)
	hp_bar.scale.x = clamp(hp / max_hp, 0.0, 1.0)
	if element == "water":
		slow_timer = 1.4
		slow_pct = 0.24
	SignalsBus.enemy_damaged.emit(self, amount, is_crit)
	if hp <= 0.0:
		died.emit(self, float(data.get("xp", 1)))
		queue_free()

func hp_ratio() -> float:
	return hp / max(1.0, max_hp)

func _process(delta: float) -> void:
	if sprite != null:
		sprite.modulate = sprite.modulate.lerp(Color.WHITE, delta * 9.0)
