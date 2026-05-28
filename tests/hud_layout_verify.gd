extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array = []
	root.size = Vector2i(1920, 1080)
	var config: Node = root.get_node_or_null("ConfigDB")
	var asset_db: Node = root.get_node_or_null("AssetDB")
	var game_state: Node = root.get_node_or_null("GameState")
	if config == null or asset_db == null or game_state == null:
		push_error("autoloads were not available for HUD layout verification")
		quit(1)
		return
	config.call("load_all")
	asset_db.call("load_manifest")
	game_state.call("start_run", ["metal", "wood", "water", "fire", "earth"], [], "five")

	var arena = load("res://Scenes/Arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	await process_frame

	var stat_panel: Control = _find_node(arena, "HudStatPanel")
	var weapon_panel: Control = _find_node(arena, "HudWeaponPanel")
	if stat_panel == null:
		failures.append("HudStatPanel was not found")
	else:
		_check_max_size(stat_panel, Vector2(196, 530), "stat panel", failures)
		_check_slack(stat_panel, Vector2(96, 48), "stat panel", failures)
	if weapon_panel == null:
		failures.append("HudWeaponPanel was not found")
	else:
		_check_max_size(weapon_panel, Vector2(386, 112), "weapon panel", failures)
		_check_slack(weapon_panel, Vector2(32, 34), "weapon panel", failures)

	if failures.is_empty():
		print("HUD LAYOUT OK: stat and weapon panels remain compact.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_max_size(control: Control, max_size: Vector2, label: String, failures: Array) -> void:
	if control.size.x > max_size.x or control.size.y > max_size.y:
		failures.append("%s is too large: %s, max %s" % [label, control.size, max_size])

func _check_slack(control: Control, max_slack: Vector2, label: String, failures: Array) -> void:
	if control.get_child_count() == 0 or not control.get_child(0) is Control:
		failures.append("%s has no measurable content child" % label)
		return
	var child: Control = control.get_child(0)
	var slack := control.size - child.get_combined_minimum_size()
	if slack.x > max_slack.x or slack.y > max_slack.y:
		failures.append("%s has too much empty space: %s, max %s" % [label, slack, max_slack])

func _find_node(root_node: Node, node_name: String):
	if root_node.name == node_name:
		return root_node
	for child in root_node.get_children():
		var found = _find_node(child, node_name)
		if found != null:
			return found
	return null
