extends Node2D
class_name LingxuProjectile

var weapon := {}
var velocity := Vector2.ZERO
var ttl := 1.2
var pierce_left := 1
var radius := 18.0
var hit_ids := {}
var sprite: Sprite2D

func setup(weapon_data: Dictionary, origin: Vector2, target_pos: Vector2) -> void:
	weapon = weapon_data.duplicate(true)
	global_position = origin
	var dir := target_pos - origin
	if dir.length_squared() < 4.0:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	velocity = dir.normalized() * 560.0
	ttl = 1.3
	pierce_left = int(weapon.get("pierce", 0)) + 1
	radius = 20.0 + float(weapon.get("tier", 1)) * 2.0
	sprite = Sprite2D.new()
	sprite.texture = AssetDB.tex(str(weapon.get("art_id", "icon_metal")))
	sprite.scale = Vector2(0.13, 0.13)
	sprite.rotation = velocity.angle()
	add_child(sprite)

func tick(delta: float, enemies: Array, player: YunxiPlayer) -> bool:
	ttl -= delta
	position += velocity * delta
	rotation = velocity.angle()
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or hit_ids.has(enemy.get_instance_id()):
			continue
		var hit_radius := radius + float(enemy.radius)
		if global_position.distance_squared_to(enemy.global_position) <= hit_radius * hit_radius:
			hit_ids[enemy.get_instance_id()] = true
			var result := GameState.calculate_weapon_damage(weapon, enemy)
			enemy.take_damage(float(result["amount"]), bool(result["is_crit"]), str(result["element"]))
			player.heal_from_lifesteal(float(result["amount"]))
			_spawn_hit_fx(enemy.global_position, str(result["element"]), bool(result["is_crit"]))
			SignalsBus.hud_request_hitstop.emit(0.025 if bool(result["is_crit"]) else 0.012)
			pierce_left -= 1
			if pierce_left <= 0:
				queue_free()
				return false
	if ttl <= 0.0:
		queue_free()
		return false
	return true

func _spawn_hit_fx(pos: Vector2, element: String, is_crit: bool) -> void:
	var fx := Sprite2D.new()
	fx.texture = AssetDB.tex("fx_crit" if is_crit else "fx_%s" % element)
	fx.global_position = pos
	fx.scale = Vector2(0.16, 0.16)
	fx.modulate = Color(1, 1, 1, 0.85)
	get_tree().current_scene.add_child(fx)
	var tween := create_tween()
	tween.tween_property(fx, "scale", Vector2(0.34, 0.34), 0.16)
	tween.parallel().tween_property(fx, "modulate:a", 0.0, 0.16)
	tween.tween_callback(fx.queue_free)
