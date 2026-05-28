extends SceneTree

const ENEMY_SCENE := preload("res://Scenes/Enemies/Enemy.tscn")

var config: Node
var asset_db: Node
var game_state: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array = []
	config = root.get_node_or_null("ConfigDB")
	asset_db = root.get_node_or_null("AssetDB")
	game_state = root.get_node_or_null("GameState")
	if config == null or asset_db == null or game_state == null:
		push_error("autoloads were not available for weapon feedback verification")
		quit(1)
		return
	config.call("load_all")
	asset_db.call("load_manifest")
	game_state.call("start_run", ["metal", "wood", "water", "fire", "earth"], [], "five")
	var stats: Dictionary = game_state.get("stats")
	stats["crit_chance"] = 0.0
	game_state.set("stats", stats)

	var arena = load("res://Scenes/Arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame

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

	_clear_enemies(arena)
	stats = game_state.get("stats")
	stats["fire_execute"] = true
	stats["execute_threshold"] = 1.0
	stats["execute_mult"] = 1.0
	game_state.set("stats", stats)
	var crit_enemy := _spawn_test_enemy(arena, Vector2(210, -60), 20.0)
	var crit_result: Dictionary = arena._hit_enemy(_weapon("ember_sword"), crit_enemy, crit_enemy.global_position, true)
	if not bool(crit_result.get("is_crit", false)):
		failures.append("forced fire execute did not produce a critical hit")
	if not _has_node_named(arena, "CriticalBurstRing"):
		failures.append("critical hit did not create burst ring feedback")
	if not _has_node_named(arena, "CriticalCrossSlash"):
		failures.append("critical hit did not create cross-slash feedback")
	if not _has_node_named(arena, "CriticalHitText"):
		failures.append("critical hit did not create floating text feedback")

	if failures.is_empty():
		print("WEAPON FEEDBACK OK: source badges, class-specific attacks, and critical hit feedback verified.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_fire_feedback(arena: Node, failures: Array, weapon_id: String, target_pos: Vector2, expected_prefix: String) -> void:
	_clear_enemies(arena)
	_spawn_test_enemy(arena, target_pos, 20.0)
	arena._fire_weapon(_weapon(weapon_id), -1)
	if not _has_node_named(arena, expected_prefix):
		failures.append("%s did not create %s feedback" % [weapon_id, expected_prefix])

func _weapon(id: String) -> Dictionary:
	var weapon: Dictionary = config.call("entry", "weapons", id).duplicate(true)
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
