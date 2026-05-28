extends SceneTree

const ENEMY_SCENE := preload("res://Scenes/Enemies/Enemy.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array = []
	var config: Node = root.get_node_or_null("ConfigDB")
	var asset_db: Node = root.get_node_or_null("AssetDB")
	var game_state: Node = root.get_node_or_null("GameState")
	if config == null or asset_db == null or game_state == null:
		push_error("autoloads were not available for enemy spawning verification")
		quit(1)
		return
	config.call("load_all")
	asset_db.call("load_manifest")
	game_state.call("start_run", ["metal", "wood", "water", "fire", "earth"], [], "five")

	var enemy_table: Dictionary = config.call("table", "enemies")
	for id in ["wind_wolf", "shadow_stalker", "ember_wisp", "venom_priest", "stone_warden"]:
		if not enemy_table.has(id):
			failures.append("missing enemy archetype %s" % id)
		elif not enemy_table[id].has("abilities"):
			failures.append("%s should declare reusable abilities" % id)

	var spawn_table: Dictionary = config.call("table", "spawn")
	var waves: Array = spawn_table.get("waves", [])
	if waves.size() < 6:
		failures.append("spawn table should split the run into at least six mixed waves")
	for wave in waves:
		if not wave.has("pool") or not wave.has("inner_chance") or not wave.has("warning"):
			failures.append("wave %s-%s missing pool/inner warning fields" % [wave.get("from", "?"), wave.get("to", "?")])

	var arena = load("res://Scenes/Arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.spawn_timer = 999.0

	var existing_count: int = arena.enemies.size()
	arena._queue_enemy_spawn("ember_wisp", false, "inner", 0.05)
	if arena.pending_spawns.is_empty():
		failures.append("inner spawn should create a warning marker before the enemy appears")
	arena._update_spawn_warnings(0.06)
	await process_frame
	if arena.enemies.size() <= existing_count or not _has_enemy(arena, "ember_wisp"):
		failures.append("warning spawn did not resolve into the requested enemy")

	var ranged = _spawn_test_enemy(arena, "miasma_toad", arena.player.global_position + Vector2(410, 0), 1.0)
	_force_ability_ready(ranged)
	var projectile_count: int = arena.enemy_projectiles.size()
	ranged.tick(0.10, arena.player)
	ranged.tick(0.50, arena.player)
	if arena.enemy_projectiles.size() <= projectile_count:
		failures.append("ranged enemy ability did not create hostile projectiles")

	var puppet = _spawn_test_enemy(arena, "iron_puppet", arena.player.global_position + Vector2(118, 0), 1.0)
	_force_ability_ready(puppet)
	var area_count: int = arena.enemy_area_attacks.size()
	puppet.tick(0.10, arena.player)
	if arena.enemy_area_attacks.size() <= area_count:
		failures.append("slam enemy ability did not create a telegraphed area attack")

	var charger = _spawn_test_enemy(arena, "wind_wolf", arena.player.global_position + Vector2(280, 0), 1.0)
	_force_ability_ready(charger)
	var before_charge: Vector2 = charger.global_position
	charger.tick(0.10, arena.player)
	charger.tick(0.30, arena.player)
	charger.tick(0.20, arena.player)
	if charger.global_position.distance_to(before_charge) < 20.0:
		failures.append("charge enemy ability did not move during dash phase")

	arena.queue_free()
	await process_frame
	if failures.is_empty():
		print("ENEMY SPAWNING OK: weighted waves, warning spawns, ranged shots, slams, and charges verified.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _spawn_test_enemy(arena: Node, id: String, pos: Vector2, scale: float):
	var enemy = ENEMY_SCENE.instantiate()
	enemy.position = pos
	enemy.setup(id, scale)
	arena.add_child(enemy)
	arena.enemies.append(enemy)
	return enemy

func _force_ability_ready(enemy) -> void:
	for key in enemy.ability_cds.keys():
		enemy.ability_cds[key] = 0.0

func _has_enemy(arena: Node, id: String) -> bool:
	for enemy in arena.enemies:
		if is_instance_valid(enemy) and str(enemy.enemy_id) == id:
			return true
	return false
