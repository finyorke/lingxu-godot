extends Node

const ENEMY_SCENE := preload("res://Scenes/Enemies/Enemy.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array = []
	ConfigDB.load_all()
	AssetDB.load_manifest()
	GameState.start_run(["metal", "wood", "water", "fire", "earth"], [], "five")

	var arena = load("res://Scenes/Arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	await get_tree().process_frame

	_check_fire_feedback(arena, failures, "pojun_dagger", Vector2(230, 20), "WeaponPath_dash")
	_check_fire_feedback(arena, failures, "frost_needle", Vector2(260, -40), "WeaponPath_fan")
	_check_fire_feedback(arena, failures, "rock_spike", Vector2(250, 40), "WeaponSpike_rock_spike")
	_check_fire_feedback(arena, failures, "zhenyue_chu", Vector2(240, 0), "WeaponArea_quake_zhenyue_chu")
	_check_fire_feedback(arena, failures, "wanjian_banner", Vector2(280, -20), "WeaponSummonGate_0_wanjian_banner")

	_clear_enemies(arena)
	_spawn_test_enemy(arena, Vector2(150, 0), 18.0)
	arena._fire_weapon(_weapon("moonwheel"), -1)
	if not _has_node_named(arena, "WeaponOrbit_orbit_moonwheel"):
		failures.append("orbit weapon did not create orbit feedback")

	arena._fire_weapon(_weapon("xuangui_talisman"), -1)
	if not _has_node_named(arena, "WeaponShield_xuangui_talisman"):
		failures.append("shield weapon did not create shield feedback")

	_clear_enemies(arena)
	var explode_enemy := _spawn_test_enemy(arena, Vector2(220, 0), 20.0)
	arena._hit_enemy(_weapon("exploding_charm"), explode_enemy, explode_enemy.global_position, true)
	if not _has_node_named(arena, "WeaponHit_exploding_charm"):
		failures.append("direct hit did not create weapon source badge")
	if not _has_node_named(arena, "WeaponArea_explode_exploding_charm"):
		failures.append("explode secondary did not create source area feedback")

	if failures.is_empty():
		print("WEAPON FEEDBACK OK: source badges and class-specific attack feedback verified.")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

func _check_fire_feedback(arena: Node, failures: Array, weapon_id: String, target_pos: Vector2, expected_prefix: String) -> void:
	_clear_enemies(arena)
	_spawn_test_enemy(arena, target_pos, 20.0)
	arena._fire_weapon(_weapon(weapon_id), -1)
	if not _has_node_named(arena, expected_prefix):
		failures.append("%s did not create %s feedback" % [weapon_id, expected_prefix])

func _weapon(id: String) -> Dictionary:
	var weapon: Dictionary = ConfigDB.entry("weapons", id).duplicate(true)
	weapon["id"] = id
	weapon["tier"] = 1
	return weapon

func _spawn_test_enemy(arena: Node, pos: Vector2, scale: float) -> LingxuEnemy:
	var enemy: LingxuEnemy = ENEMY_SCENE.instantiate()
	enemy.position = pos
	enemy.setup("xie_wolf", scale)
	arena.add_child(enemy)
	arena.enemies.append(enemy)
	return enemy

func _clear_enemies(arena: Node) -> void:
	for enemy in arena.enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	arena.enemies.clear()

func _has_node_named(root: Node, prefix: String) -> bool:
	if str(root.name).begins_with(prefix):
		return true
	for child in root.get_children():
		if _has_node_named(child, prefix):
			return true
	return false
