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

	var top_panel: Control = _find_node(arena, "HudTopPanel")
	var stat_panel: Control = _find_node(arena, "HudStatPanel")
	var weapon_panel: Control = _find_node(arena, "HudWeaponPanel")
	if top_panel == null:
		failures.append("HudTopPanel was not found")
	else:
		_check_max_size(top_panel, Vector2(860, 200), "top HUD panel", failures)
		if top_panel.find_children("*", "ProgressBar", true, false).size() != 3:
			failures.append("top HUD panel should keep three styled progress bars")
		if top_panel.find_children("*", "PanelContainer", true, false).size() < 6:
			failures.append("top HUD panel should split run info into compact info cells")
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

	arena._open_market("测试机缘")
	await process_frame
	var market_stat_panel: Control = _find_node(arena, "MarketStatPanel")
	if market_stat_panel == null:
		failures.append("MarketStatPanel was not found")
	else:
		_check_max_size(market_stat_panel, Vector2(220, 506), "market stat panel", failures)
		_check_slack(market_stat_panel, Vector2(96, 28), "market stat panel", failures)
		if market_stat_panel.find_children("*", "PanelContainer", true, false).size() < 14:
			failures.append("market stat panel should show the full icon-row stat list")
	var market_weapon_frame: Control = _find_node(arena, "MarketWeaponFrame")
	var market_item_frame: Control = _find_node(arena, "MarketItemFrame")
	var market_active_weapon_row: Control = _find_node(arena, "MarketActiveWeaponRow")
	var market_reserve_weapon_row: Control = _find_node(arena, "MarketReserveWeaponRow")
	var market_item_grid: GridContainer = _find_node(arena, "MarketItemSlotGrid")
	var market_continue_frame: Control = _find_node(arena, "MarketContinueFrame")
	var market_continue_button: Button = _find_node(arena, "MarketContinueButton")
	if market_weapon_frame == null:
		failures.append("MarketWeaponFrame was not found")
	else:
		_check_max_size(market_weapon_frame, Vector2(500, 200), "market weapon frame", failures)
	if market_item_frame == null:
		failures.append("MarketItemFrame was not found")
	else:
		_check_max_size(market_item_frame, Vector2(456, 200), "market item frame", failures)
	_check_vertical_label(arena, "MarketWeaponLabel", "装\n备", failures)
	_check_vertical_label(arena, "MarketReserveLabel", "备\n炼", failures)
	_check_vertical_label(arena, "MarketItemLabel", "道\n具", failures)
	var active_weapon_slots := _buttons_with_meta(market_active_weapon_row, "weapon_place", "active")
	if active_weapon_slots.size() != 4:
		failures.append("market active weapon row should show four equipment slots")
	_check_slot_minimum(active_weapon_slots, Vector2(56, 56), "market active weapon slots", failures)
	var reserve_weapon_slots := _buttons_with_meta(market_reserve_weapon_row, "weapon_place", "reserve")
	if reserve_weapon_slots.size() != 2:
		failures.append("market reserve weapon row should show two reserve slots")
	_check_slot_minimum(reserve_weapon_slots, Vector2(56, 56), "market reserve weapon slots", failures)
	if market_item_grid == null:
		failures.append("MarketItemSlotGrid was not found")
	else:
		if market_item_grid.columns != 5:
			failures.append("market item grid should use five columns")
		var item_slots := market_item_grid.find_children("*", "Button", true, false)
		if item_slots.size() != 5:
			failures.append("market item grid should show five starting item slots")
		_check_slot_minimum(item_slots, Vector2(56, 56), "market item slots", failures)
	if market_continue_frame == null:
		failures.append("MarketContinueFrame was not found")
	else:
		_check_max_size(market_continue_frame, Vector2(210, 142), "market continue frame", failures)
	if market_continue_button == null:
		failures.append("MarketContinueButton was not found")
	else:
		if not market_continue_button.disabled:
			failures.append("market continue button should be disabled until an offer is selected")
		if market_continue_button.custom_minimum_size.x < 154 or market_continue_button.custom_minimum_size.y < 92:
			failures.append("market continue button should be large enough to read")
		if not market_continue_button.has_theme_font_override("font"):
			failures.append("market continue button should use the display font")
		if market_item_frame != null and market_continue_button.global_position.x <= market_item_frame.global_position.x + market_item_frame.size.x:
			failures.append("market continue button should sit to the right of the item frame")

	if failures.is_empty():
		print("HUD LAYOUT OK: top, stat, and weapon panels remain compact.")
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

func _check_vertical_label(root_node: Node, node_name: String, expected_text: String, failures: Array) -> void:
	var label: Label = _find_node(root_node, node_name)
	if label == null:
		failures.append("%s was not found" % node_name)
	elif label.text != expected_text:
		failures.append("%s should render vertically, got %s" % [node_name, label.text])

func _buttons_with_meta(root_control: Control, meta_key: String, expected_value: String) -> Array:
	var buttons: Array = []
	if root_control == null:
		return buttons
	for child in root_control.find_children("*", "Button", true, false):
		if str(child.get_meta(meta_key, "")) == expected_value:
			buttons.append(child)
	return buttons

func _check_slot_minimum(buttons: Array, min_size: Vector2, label: String, failures: Array) -> void:
	for child in buttons:
		var button: Button = child
		if button.custom_minimum_size.x < min_size.x or button.custom_minimum_size.y < min_size.y:
			failures.append("%s should be at least %s, got %s" % [label, min_size, button.custom_minimum_size])

func _find_node(root_node: Node, node_name: String):
	if root_node.name == node_name:
		return root_node
	for child in root_node.get_children():
		var found = _find_node(child, node_name)
		if found != null:
			return found
	return null
