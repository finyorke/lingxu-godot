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
var base_modulate := Color.WHITE
var ability_cds := {}
var active_ability := {}
var last_move_dir := Vector2.RIGHT

func setup(id: String, level_scale: float = 1.0) -> void:
	enemy_id = id
	data = _config_entry("enemies", id).duplicate(true)
	max_hp = float(data.get("hp", 30)) * level_scale
	hp = max_hp
	radius = float(data.get("radius", 20))
	is_boss = bool(data.get("is_boss", false))
	var tint := str(data.get("tint", ""))
	base_modulate = Color(tint) if not tint.is_empty() else Color.WHITE
	sprite = Sprite2D.new()
	sprite.texture = _asset_tex(str(data.get("sprite", id)))
	sprite.scale = Vector2.ONE * float(data.get("sprite_scale", 0.16 if is_boss else 0.085))
	sprite.position = Vector2(0, -radius * 0.7)
	sprite.modulate = base_modulate
	add_child(sprite)
	hp_bar = ColorRect.new()
	hp_bar.color = Color("#f25050")
	hp_bar.size = Vector2(radius * 2.2, 5)
	hp_bar.position = Vector2(-radius * 1.1, -radius * 2.3)
	add_child(hp_bar)
	_setup_ability_cooldowns()

func tick(delta: float, player) -> void:
	if dead:
		return
	_tick_status_timers(delta)
	_update_dots(delta)
	if dead or player == null or not is_instance_valid(player):
		return
	if chill_timer <= 0.0:
		chill_stacks = 0
	_update_knockback(delta)
	_tick_ability_cooldowns(delta)
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length_squared() > 4.0:
		sprite.flip_h = to_player.x < 0
	var ability_blocks: bool = _update_active_ability(delta, player)
	if not ability_blocks and freeze_timer <= 0.0 and petrify_timer <= 0.0:
		if not _try_start_ability(player):
			_move_towards_player(delta, player, to_player)
	var contact_mult: float = float(active_ability.get("contact_damage_mult", 1.0)) if not active_ability.is_empty() else 1.0
	_contact_attack(player, float(data.get("damage", 8)) * contact_mult)
	sprite.rotation = sin(Time.get_ticks_msec() * 0.004 + position.x * 0.01) * (0.075 if _is_charging() else 0.045)

func take_damage(amount: float, is_crit: bool, element: String) -> void:
	if dead:
		return
	if vulnerable_timer > 0.0:
		amount *= 1.0 + vulnerable_pct
	hp -= amount
	sprite.modulate = Color("#eaf6ff") if is_crit else _element_color(element)
	hp_bar.scale.x = clamp(hp / max_hp, 0.0, 1.0)
	_emit_enemy_damaged(amount, is_crit)
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
	active_ability.clear()

func apply_petrify(duration: float) -> void:
	petrify_timer = max(petrify_timer, duration)
	sprite.modulate = Color("#d9a441")
	active_ability.clear()

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
		var target := base_modulate
		if freeze_timer > 0.0:
			target = Color("#a7ecff")
		elif petrify_timer > 0.0:
			target = Color("#d9a441")
		elif vulnerable_timer > 0.0:
			target = Color("#b24ce0")
		elif not active_ability.is_empty() and str(active_ability.get("phase", "")) == "windup":
			target = Color("#e8b259")
		sprite.modulate = sprite.modulate.lerp(target, delta * 9.0)

func _setup_ability_cooldowns() -> void:
	ability_cds.clear()
	var abilities: Array = data.get("abilities", [])
	for i in range(abilities.size()):
		var ability: Dictionary = abilities[i]
		var cooldown: float = max(0.2, float(ability.get("cooldown", 3.0)))
		ability_cds[str(i)] = randf_range(0.25, cooldown * 0.75)

func _tick_status_timers(delta: float) -> void:
	contact_timer = max(0.0, contact_timer - delta)
	slow_timer = max(0.0, slow_timer - delta)
	freeze_timer = max(0.0, freeze_timer - delta)
	petrify_timer = max(0.0, petrify_timer - delta)
	root_timer = max(0.0, root_timer - delta)
	chill_timer = max(0.0, chill_timer - delta)
	vulnerable_timer = max(0.0, vulnerable_timer - delta)

func _update_knockback(delta: float) -> void:
	if knockback_timer <= 0.0:
		return
	knockback_timer = max(0.0, knockback_timer - delta)
	position += knockback_velocity * delta
	knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, delta * 7.5)

func _tick_ability_cooldowns(delta: float) -> void:
	for key in ability_cds.keys():
		ability_cds[key] = max(0.0, float(ability_cds[key]) - delta)

func _try_start_ability(player) -> bool:
	if freeze_timer > 0.0 or petrify_timer > 0.0 or not active_ability.is_empty():
		return false
	var abilities: Array = data.get("abilities", [])
	if abilities.is_empty():
		return false
	var dist: float = global_position.distance_to(player.global_position)
	for i in range(abilities.size()):
		var ability: Dictionary = abilities[i]
		if float(ability_cds.get(str(i), 0.0)) > 0.0:
			continue
		if dist < float(ability.get("min_range", 0.0)) or dist > float(ability.get("range", 9999.0)):
			continue
		if randf() > float(ability.get("chance", 1.0)):
			continue
		_start_ability(i, ability, player)
		return true
	return false

func _start_ability(index: int, ability: Dictionary, player) -> void:
	var cooldown: float = max(0.2, float(ability.get("cooldown", 3.0)))
	ability_cds[str(index)] = cooldown * randf_range(0.86, 1.18)
	active_ability = ability.duplicate(true)
	active_ability["phase"] = "windup"
	active_ability["time"] = max(0.05, float(ability.get("windup", 0.35)))
	active_ability["target_pos"] = player.global_position
	if str(ability.get("type", "shot")) == "slam":
		_queue_slam_attack(ability, player)

func _update_active_ability(delta: float, player) -> bool:
	if active_ability.is_empty():
		return false
	if freeze_timer > 0.0 or petrify_timer > 0.0:
		active_ability.clear()
		return false
	active_ability["time"] = float(active_ability.get("time", 0.0)) - delta
	match str(active_ability.get("type", "shot")):
		"charge":
			return _update_charge_ability(delta, player)
		"slam":
			if float(active_ability.get("time", 0.0)) <= 0.0:
				active_ability.clear()
			return true
		"blink":
			if float(active_ability.get("time", 0.0)) <= 0.0:
				_finish_blink_ability(player)
				active_ability.clear()
			return true
		_:
			if float(active_ability.get("time", 0.0)) <= 0.0:
				_fire_projectile_pattern(player)
				active_ability.clear()
			return true

func _update_charge_ability(delta: float, player) -> bool:
	var phase := str(active_ability.get("phase", "windup"))
	if phase == "windup":
		if float(active_ability.get("time", 0.0)) <= 0.0:
			var target_pos: Vector2 = active_ability.get("target_pos", player.global_position)
			var dir: Vector2 = target_pos - global_position
			if dir.length_squared() < 4.0:
				dir = player.global_position - global_position
			if dir.length_squared() < 4.0:
				dir = last_move_dir
			active_ability["phase"] = "dash"
			active_ability["time"] = max(0.08, float(active_ability.get("duration", 0.34)))
			active_ability["charge_dir"] = dir.normalized()
			active_ability["contact_damage_mult"] = float(active_ability.get("damage_mult", 1.25))
		return true
	var dir: Vector2 = active_ability.get("charge_dir", last_move_dir)
	if dir.length_squared() > 0.01 and root_timer <= 0.0:
		last_move_dir = dir.normalized()
		position += last_move_dir * float(active_ability.get("speed", 360.0)) * delta
	if float(active_ability.get("time", 0.0)) <= 0.0:
		active_ability.clear()
	return true

func _fire_projectile_pattern(player) -> void:
	var arena := get_parent()
	if arena == null or not arena.has_method("spawn_enemy_projectile"):
		return
	var origin := global_position + Vector2(0, -radius * 0.45)
	var target_pos: Vector2 = active_ability.get("target_pos", player.global_position)
	var aim := target_pos - origin
	if aim.length_squared() < 4.0:
		aim = player.global_position - origin
	if aim.length_squared() < 4.0:
		aim = last_move_dir
	var count := maxi(1, int(active_ability.get("count", 1)))
	var spread := float(active_ability.get("spread", 0.0))
	for i in range(count):
		var offset := 0.0
		if count > 1:
			offset = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(count - 1))
		var shot_dir := aim.normalized().rotated(offset)
		var projectile_data := {
			"speed": float(active_ability.get("speed", 280.0)),
			"radius": float(active_ability.get("projectile_radius", 13.0)),
			"damage": _ability_damage(active_ability),
			"element": str(active_ability.get("element", data.get("hex_element", "fire"))),
			"art_id": str(active_ability.get("art_id", "fx_%s" % str(active_ability.get("element", "fire")))),
			"ttl": float(active_ability.get("ttl", 3.0)),
			"visual_scale": float(active_ability.get("visual_scale", 0.1))
		}
		arena.spawn_enemy_projectile(origin, origin + shot_dir * 120.0, projectile_data)

func _queue_slam_attack(ability: Dictionary, player) -> void:
	var arena := get_parent()
	if arena == null or not arena.has_method("queue_enemy_area_attack"):
		return
	var center := global_position
	match str(ability.get("center", "self")):
		"player":
			center = player.global_position
		"ahead":
			var dir: Vector2 = player.global_position - global_position
			if dir.length_squared() < 4.0:
				dir = last_move_dir
			center = global_position + dir.normalized() * float(ability.get("offset", radius + 55.0))
		_:
			center = global_position
	arena.queue_enemy_area_attack(center, float(ability.get("radius", 86.0)), max(0.05, float(ability.get("windup", 0.55))), _ability_damage(ability), str(ability.get("element", data.get("hex_element", "earth"))))

func _finish_blink_ability(player) -> void:
	var arena := get_parent()
	var from_pos := global_position
	var dir: Vector2 = player.global_position - global_position
	if dir.length_squared() < 4.0:
		dir = last_move_dir
	var target: Vector2 = player.global_position - dir.normalized() * float(active_ability.get("behind_distance", 92.0))
	if arena != null and arena.has_method("_clamp_point_to_arena"):
		target = arena.call("_clamp_point_to_arena", target, 54.0)
	global_position = target
	if arena != null and arena.has_method("_spawn_fx"):
		arena.call("_spawn_fx", from_pos, "fx_warning", 0.16)
		arena.call("_spawn_fx", global_position, "fx_warning", 0.16)
	if arena != null and arena.has_method("queue_enemy_area_attack"):
		arena.queue_enemy_area_attack(global_position, float(active_ability.get("strike_radius", 54.0)), 0.18, _ability_damage(active_ability), str(active_ability.get("element", data.get("hex_element", "metal"))))

func _ability_damage(ability: Dictionary) -> float:
	if ability.has("damage"):
		return float(ability.get("damage", 0.0))
	return float(data.get("damage", 8.0)) * float(ability.get("damage_mult", 1.0))

func _move_towards_player(delta: float, player, to_player: Vector2) -> void:
	if to_player.length_squared() <= 4.0:
		return
	var speed := _current_speed()
	if speed <= 0.0:
		return
	var dir := _desired_move_dir(player, to_player)
	if dir.length_squared() <= 0.01:
		return
	last_move_dir = dir.normalized()
	position += last_move_dir * speed * delta

func _current_speed() -> float:
	var speed := float(data.get("speed", 50))
	if freeze_timer > 0.0 or petrify_timer > 0.0 or root_timer > 0.0:
		return 0.0
	if slow_timer > 0.0:
		speed *= max(0.25, 1.0 - slow_pct)
	return speed

func _desired_move_dir(player, to_player: Vector2) -> Vector2:
	var dist := to_player.length()
	if dist <= 0.01:
		return Vector2.ZERO
	var dir := to_player / dist
	match str(data.get("behavior", "chase")):
		"ranged":
			var preferred := float(data.get("preferred_range", 320.0))
			if dist < preferred * 0.72:
				return -dir
			if dist > preferred * 1.12:
				return dir
			var orbit := Vector2(-dir.y, dir.x)
			return orbit * (-1.0 if int(get_instance_id()) % 2 == 0 else 1.0)
		"skirmisher":
			if dist < 130.0:
				return -dir
			return (dir + Vector2(-dir.y, dir.x) * 0.35).normalized()
		_:
			return dir

func _contact_attack(player, amount: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) < radius + _game_stat("body_radius", 22.0) and contact_timer <= 0.0:
		player.receive_damage(amount)
		contact_timer = float(data.get("contact_cooldown", 0.65))

func _is_charging() -> bool:
	return not active_ability.is_empty() and str(active_ability.get("type", "")) == "charge" and str(active_ability.get("phase", "")) == "dash"

func _update_dots(delta: float) -> void:
	var keep: Array = []
	for dot in dots:
		var dur_left: float = float(dot.get("dur_left", 0.0)) - delta
		var stacks: int = maxi(1, int(dot.get("stacks", 1)))
		var amount: float = float(dot.get("dps", 0.0)) * float(stacks) * delta
		if amount > 0.0:
			hp -= amount
			_emit_enemy_damaged(amount, false)
		if dur_left > 0.0 and hp > 0.0:
			dot["dur_left"] = dur_left
			keep.append(dot)
	dots = keep
	if hp <= 0.0:
		hp_bar.scale.x = 0.0
		_die()
	else:
		hp_bar.scale.x = clamp(hp / max_hp, 0.0, 1.0)

func _root_node(name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null

func _config_entry(table_name: String, id: String) -> Dictionary:
	var config := _root_node("ConfigDB")
	if config != null and config.has_method("entry"):
		var entry = config.call("entry", table_name, id)
		if typeof(entry) == TYPE_DICTIONARY:
			return entry
	return {}

func _asset_tex(id: String) -> Texture2D:
	var asset_db := _root_node("AssetDB")
	if asset_db != null and asset_db.has_method("tex"):
		var tex = asset_db.call("tex", id)
		if tex is Texture2D:
			return tex
	return null

func _element_color(element: String) -> Color:
	var asset_db := _root_node("AssetDB")
	if asset_db != null and asset_db.has_method("color_for_element"):
		var color = asset_db.call("color_for_element", element)
		if color is Color:
			return color
	match element:
		"metal":
			return Color("#eaf6ff")
		"wood":
			return Color("#7ccb5a")
		"water":
			return Color("#5aa9e0")
		"fire":
			return Color("#f27348")
		"earth":
			return Color("#d9a441")
		_:
			return Color("#5fe0c8")

func _game_stat(key: String, fallback: float) -> float:
	var game_state := _root_node("GameState")
	if game_state != null:
		var stats = game_state.get("stats")
		if typeof(stats) == TYPE_DICTIONARY:
			return float(stats.get(key, fallback))
	return fallback

func _emit_enemy_damaged(amount: float, is_crit: bool) -> void:
	var bus := _root_node("SignalsBus")
	if bus != null and bus.has_signal("enemy_damaged"):
		bus.emit_signal("enemy_damaged", self, amount, is_crit)

func _die() -> void:
	if dead:
		return
	dead = true
	died.emit(self, float(data.get("xp", 1)))
	queue_free()
