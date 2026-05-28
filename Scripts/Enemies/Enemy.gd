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
var freeze_timer := 0.0
var petrify_timer := 0.0
var root_timer := 0.0
var chill_stacks := 0
var chill_timer := 0.0
var vulnerable_timer := 0.0
var vulnerable_pct := 0.0
var knockback_velocity := Vector2.ZERO
var knockback_timer := 0.0
var dots: Array = []
var dead := false

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
	if dead:
		return
	contact_timer = max(0.0, contact_timer - delta)
	slow_timer = max(0.0, slow_timer - delta)
	freeze_timer = max(0.0, freeze_timer - delta)
	petrify_timer = max(0.0, petrify_timer - delta)
	root_timer = max(0.0, root_timer - delta)
	chill_timer = max(0.0, chill_timer - delta)
	vulnerable_timer = max(0.0, vulnerable_timer - delta)
	_update_dots(delta)
	if dead:
		return
	if chill_timer <= 0.0:
		chill_stacks = 0
	if knockback_timer > 0.0:
		knockback_timer = max(0.0, knockback_timer - delta)
		position += knockback_velocity * delta
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, delta * 7.5)
	var to_player := player.global_position - global_position
	if to_player.length_squared() > 4.0:
		var speed := float(data.get("speed", 50))
		if freeze_timer > 0.0 or petrify_timer > 0.0 or root_timer > 0.0:
			speed = 0.0
		if slow_timer > 0.0:
			speed *= max(0.25, 1.0 - slow_pct)
		position += to_player.normalized() * speed * delta
		sprite.flip_h = to_player.x < 0
	if to_player.length() < radius + float(GameState.stats.get("body_radius", 22)) and contact_timer <= 0.0:
		player.receive_damage(float(data.get("damage", 8)))
		contact_timer = float(data.get("contact_cooldown", 0.65))
	sprite.rotation = sin(Time.get_ticks_msec() * 0.004 + position.x * 0.01) * 0.045

func take_damage(amount: float, is_crit: bool, element: String) -> void:
	if dead:
		return
	if vulnerable_timer > 0.0:
		amount *= 1.0 + vulnerable_pct
	hp -= amount
	sprite.modulate = Color("#eaf6ff") if is_crit else AssetDB.color_for_element(element)
	hp_bar.scale.x = clamp(hp / max_hp, 0.0, 1.0)
	SignalsBus.enemy_damaged.emit(self, amount, is_crit)
	if hp <= 0.0:
		_die()

func add_dot(effect: String, element: String, dps: float, duration: float, stackable := false) -> void:
	if duration <= 0.0 or dps <= 0.0 or dead:
		return
	for dot in dots:
		if str(dot.get("effect", "")) == effect and str(dot.get("element", "")) == element:
			dot["dps"] = max(float(dot.get("dps", 0.0)), dps)
			dot["dur_left"] = max(float(dot.get("dur_left", 0.0)), duration)
			if stackable:
				dot["stacks"] = int(dot.get("stacks", 1)) + 1
			else:
				dot["stacks"] = 1
			return
	dots.append({"effect": effect, "element": element, "dps": dps, "dur_left": duration, "stacks": 1})

func apply_slow(value: float, duration: float) -> void:
	slow_pct = max(slow_pct if slow_timer > 0.0 else 0.0, clamp(value, 0.0, 0.85))
	slow_timer = max(slow_timer, duration)

func add_chill_stack(required := 5, freeze_duration := 0.75) -> void:
	chill_stacks += 1
	chill_timer = 3.0
	apply_slow(0.10 + 0.04 * float(chill_stacks), 1.4)
	if chill_stacks >= required:
		apply_freeze(freeze_duration)
		chill_stacks = 0

func apply_freeze(duration: float) -> void:
	freeze_timer = max(freeze_timer, duration)
	sprite.modulate = Color("#a7ecff")

func apply_petrify(duration: float) -> void:
	petrify_timer = max(petrify_timer, duration)
	sprite.modulate = Color("#d9a441")

func apply_root(duration: float) -> void:
	root_timer = max(root_timer, duration)

func apply_vulnerable(value: float, duration: float) -> void:
	vulnerable_pct = max(vulnerable_pct if vulnerable_timer > 0.0 else 0.0, clamp(value, 0.0, 2.0))
	vulnerable_timer = max(vulnerable_timer, duration)

func apply_knockback(origin: Vector2, value: float, duration := 0.22) -> void:
	var dir := global_position - origin
	if dir.length_squared() < 1.0:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	knockback_velocity = dir.normalized() * max(value * 14.0, 80.0)
	knockback_timer = max(knockback_timer, duration)

func apply_pull(origin: Vector2, value: float, duration := 0.2) -> void:
	var dir := origin - global_position
	if dir.length_squared() < 1.0:
		return
	knockback_velocity = dir.normalized() * max(value * 13.0, 80.0)
	knockback_timer = max(knockback_timer, duration)

func hp_ratio() -> float:
	return hp / max(1.0, max_hp)

func _process(delta: float) -> void:
	if sprite != null:
		var target := Color.WHITE
		if freeze_timer > 0.0:
			target = Color("#a7ecff")
		elif petrify_timer > 0.0:
			target = Color("#d9a441")
		elif vulnerable_timer > 0.0:
			target = Color("#b24ce0")
		sprite.modulate = sprite.modulate.lerp(target, delta * 9.0)

func _update_dots(delta: float) -> void:
	var keep: Array = []
	for dot in dots:
		var dur_left: float = float(dot.get("dur_left", 0.0)) - delta
		var stacks: int = maxi(1, int(dot.get("stacks", 1)))
		var amount: float = float(dot.get("dps", 0.0)) * float(stacks) * delta
		if amount > 0.0:
			hp -= amount
			SignalsBus.enemy_damaged.emit(self, amount, false)
		if dur_left > 0.0 and hp > 0.0:
			dot["dur_left"] = dur_left
			keep.append(dot)
	dots = keep
	if hp <= 0.0:
		hp_bar.scale.x = 0.0
		_die()
	else:
		hp_bar.scale.x = clamp(hp / max_hp, 0.0, 1.0)

func _die() -> void:
	if dead:
		return
	dead = true
	died.emit(self, float(data.get("xp", 1)))
	queue_free()
