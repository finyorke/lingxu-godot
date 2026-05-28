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
		push_error("autoloads were not available for on-hit verification")
		quit(1)
		return
	config.call("load_all")
	asset_db.call("load_manifest")
	game_state.call("start_run", ["metal", "wood", "water", "fire", "earth"], [], "five")
	game_state.call("add_item", "execute_jade")
	game_state.call("add_item", "execute_jade")
	var stats: Dictionary = game_state.get("stats")
	if abs(float(stats.get("execute_threshold", 0.0)) - 0.25) > 0.001:
		failures.append("execute_threshold should use set/max semantics")
	if abs(float(stats.get("execute_mult", 0.0)) - 1.75) > 0.001:
		failures.append("execute_mult should use set/max semantics")

	var arena = load("res://Scenes/Arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena._open_market("测试机缘")
	await process_frame
	if not arena.market_open or arena.market_offers.size() != 4:
		failures.append("choice market should render four offers")
	var continue_button := _find_button_by_text(arena.overlay_layer, "继续历练")
	if continue_button == null or not continue_button.disabled:
		failures.append("choice market should require an offer before continuing")
	var selected_offer: Dictionary = {}
	for offer in arena.market_offers:
		if arena._offer_block_reason(offer).is_empty():
			selected_offer = offer
			break
	if selected_offer.is_empty():
		failures.append("choice market should provide at least one selectable offer")
	else:
		arena._choose_offer(selected_offer)
		await process_frame
		if not arena.market_open or not arena.market_choice_completed:
			failures.append("choice market should stay open after selecting an offer")
		if str(arena.market_selected_offer_id) != str(selected_offer.get("id", "")):
			failures.append("choice market should remember the selected offer")
		continue_button = _find_button_by_text(arena.overlay_layer, "继续历练")
		if continue_button == null or continue_button.disabled:
			failures.append("choice market continue button should enable after selecting an offer")
		else:
			continue_button.emit_signal("pressed")
			await process_frame
			if arena.market_open:
				failures.append("choice market continue button should resume the run")
	game_state.stones = 50
	arena._open_spirit_shop()
	await process_frame
	if not arena.market_open or arena.market_mode != "spirit_shop" or arena.market_offers.size() != 4:
		failures.append("timed spirit shop should render four purchasable offers")
	arena._refresh_spirit_shop()
	if game_state.stones >= 50:
		failures.append("spirit shop refresh should spend stones")
	arena._close_market()
	await process_frame

	var poison_enemy = _spawn_test_enemy(arena, Vector2(220, 0), 8.0)
	arena._hit_enemy(_entry("weapons", "shigu_sting").duplicate(true), poison_enemy, poison_enemy.global_position, true)
	if poison_enemy.dots.is_empty() or str(poison_enemy.dots[0].get("effect", "")) != "poison":
		failures.append("shigu_sting did not apply poison DoT")
	var poison_hp: float = poison_enemy.hp
	poison_enemy.tick(0.5, arena.player)
	if poison_enemy.hp >= poison_hp:
		failures.append("poison DoT did not tick damage")

	var fire_enemy = _spawn_test_enemy(arena, Vector2(250, 50), 8.0)
	arena._hit_enemy(_entry("weapons", "ember_sword").duplicate(true), fire_enemy, fire_enemy.global_position, true)
	if fire_enemy.dots.is_empty() or str(fire_enemy.dots[0].get("effect", "")) != "ignite":
		failures.append("ember_sword did not apply ignite DoT")

	var frost_enemy = _spawn_test_enemy(arena, Vector2(280, -40), 10.0)
	var frost: Dictionary = _entry("weapons", "frost_needle").duplicate(true)
	for i in range(5):
		arena._hit_enemy(frost, frost_enemy, frost_enemy.global_position, true)
	if frost_enemy.freeze_timer <= 0.0:
		failures.append("frost_needle 5 chill stacks did not freeze")

	var knock_enemy = _spawn_test_enemy(arena, Vector2(180, 0), 10.0)
	var before: Vector2 = knock_enemy.global_position
	arena._hit_enemy(_entry("weapons", "zhenyue_chu").duplicate(true), knock_enemy, knock_enemy.global_position, true)
	knock_enemy.tick(0.16, arena.player)
	if knock_enemy.global_position.distance_to(before) < 8.0:
		failures.append("zhenyue_chu knockback did not move enemy")

	var exec_enemy = _spawn_test_enemy(arena, Vector2(320, 0), 10.0)
	exec_enemy.hp = exec_enemy.max_hp * 0.20
	var execute_result: Dictionary = arena._hit_enemy(_entry("weapons", "ember_sword").duplicate(true), exec_enemy, exec_enemy.global_position, true)
	if not bool(execute_result.get("is_crit", false)):
		failures.append("execute_jade did not force fire crit below threshold")

	stats["crit_chance"] = 0.0
	game_state.set("stats", stats)
	var projectile_enemy = _spawn_test_enemy(arena, Vector2(360, 30), 20.0)
	var projectile = load("res://Scenes/Weapon/Projectile.tscn").instantiate()
	arena.add_child(projectile)
	var projectile_weapon: Dictionary = _entry("weapons", "liuguang_blade").duplicate(true)
	projectile.setup(projectile_weapon, projectile_enemy.global_position, projectile_enemy.global_position)
	var fx_parent := current_scene if current_scene != null else root
	var fx_texture: Texture2D = asset_db.call("tex", "fx_metal")
	var fx_count_before := _count_sprites_with_texture(fx_parent, fx_texture)
	projectile.tick(0.0, [projectile_enemy], arena.player)
	await process_frame
	await create_timer(0.25).timeout
	await process_frame
	if _count_sprites_with_texture(fx_parent, fx_texture) > fx_count_before:
		failures.append("projectile hit FX lingered after projectile freed")

	var boss_data: Dictionary = _entry("enemies", "serpent_boss")
	if str(boss_data.get("sprite", "")) != "serpent_boss":
		failures.append("serpent_boss still points at the wrong sprite id")
	if not FileAccess.file_exists("res://assets/enemies/serpent_boss.png"):
		failures.append("missing serpent_boss.png asset")

	if failures.is_empty():
		print("ON_HIT OK: poison, ignite, freeze, knockback, execute, and serpent boss asset verified.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _entry(table_name: String, id: String) -> Dictionary:
	return config.call("entry", table_name, id)

func _spawn_test_enemy(arena: Node, pos: Vector2, scale: float):
	var enemy = ENEMY_SCENE.instantiate()
	enemy.position = pos
	enemy.setup("xie_wolf", scale)
	arena.add_child(enemy)
	arena.enemies.append(enemy)
	return enemy

func _count_sprites_with_texture(root: Node, texture: Texture2D) -> int:
	var count := 0
	for child in root.get_children():
		if child is Sprite2D:
			var sprite := child as Sprite2D
			if sprite.texture == texture:
				count += 1
		count += _count_sprites_with_texture(child, texture)
	return count

func _find_button_by_text(root: Node, text: String) -> Button:
	for child in root.get_children():
		if child is Button and child.text == text:
			return child as Button
		var found: Button = _find_button_by_text(child, text)
		if found != null:
			return found
	return null
