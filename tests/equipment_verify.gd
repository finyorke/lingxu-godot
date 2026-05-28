extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array = []
	var config: Node = root.get_node_or_null("ConfigDB")
	var game_state: Node = root.get_node_or_null("GameState")
	if config == null or game_state == null:
		push_error("autoloads were not available for equipment verification")
		quit(1)
		return
	config.call("load_all")
	var stats: Dictionary = config.call("table", "stats").duplicate(true)
	stats["weapon_slots"] = 1
	stats["weapon_reserve_slots"] = 2
	game_state.set("stats", stats)
	game_state.set("active_weapons", [])
	game_state.set("weapon_reserve", [])
	game_state.set("bag", [])
	game_state.set("affinity_id", "five")
	game_state.set("active_roots", ["metal", "fire", "earth"])

	if not bool(game_state.call("equip_weapon", "guanri_sword", 1)):
		failures.append("first weapon should enter the active slot")
	if not bool(game_state.call("equip_weapon", "hantan_sword", 1)):
		failures.append("second weapon should enter the reserve instead of replacing")
	var active_weapons: Array = game_state.get("active_weapons")
	var weapon_reserve: Array = game_state.get("weapon_reserve")
	if active_weapons.size() != 1 or str(active_weapons[0].get("id", "")) != "guanri_sword":
		failures.append("full active slots should not be replaced by a new weapon")
	if weapon_reserve.size() != 1 or str(weapon_reserve[0].get("id", "")) != "hantan_sword":
		failures.append("reserve should hold unequipped weapons")

	if not bool(game_state.call("equip_weapon", "guanri_sword", 1)):
		failures.append("matching same-tier weapon should merge")
	active_weapons = game_state.get("active_weapons")
	weapon_reserve = game_state.get("weapon_reserve")
	if int(active_weapons[0].get("tier", 1)) != 2:
		failures.append("two tier-1 guanri_sword copies should make one tier-2 copy")
	if weapon_reserve.size() != 1:
		failures.append("merge should consume the offered weapon without using reserve space")

	if not bool(game_state.call("equip_weapon", "fentian_talisman", 1)):
		failures.append("reserve should accept a second held weapon")
	if bool(game_state.call("can_accept_weapon", "zhenyue_chu", 1)):
		failures.append("new non-merge weapon should be blocked when active and reserve are full")
	if bool(game_state.call("equip_weapon", "zhenyue_chu", 1)):
		failures.append("blocked weapon acquisition should return false")
	active_weapons = game_state.get("active_weapons")
	if str(active_weapons[0].get("id", "")) != "guanri_sword":
		failures.append("blocked weapon acquisition should not replace active equipment")

	if not bool(game_state.call("can_accept_weapon", "guanri_sword", 2)):
		failures.append("mergeable weapons should remain selectable even when all slots are full")
	if not bool(game_state.call("equip_weapon", "guanri_sword", 2)):
		failures.append("tier-2 duplicate should merge despite full slots")
	active_weapons = game_state.get("active_weapons")
	if int(active_weapons[0].get("tier", 1)) != 3:
		failures.append("two tier-2 guanri_sword copies should make one tier-3 copy")

	stats = config.call("table", "stats").duplicate(true)
	stats["crit_chance"] = 0.0
	game_state.set("stats", stats)
	var t1_source: Dictionary = config.call("entry", "weapons", "guanri_sword")
	var t1 := t1_source.duplicate(true)
	t1["id"] = "guanri_sword"
	t1["tier"] = 1
	var t2 := t1.duplicate(true)
	t2["tier"] = 2
	var d1_result: Dictionary = game_state.call("calculate_weapon_damage", t1)
	var d2_result: Dictionary = game_state.call("calculate_weapon_damage", t2)
	var d1 := float(d1_result.get("amount", 0.0))
	var d2 := float(d2_result.get("amount", 0.0))
	if d1 <= 0.0 or abs((d2 / d1) - 1.7) > 0.01:
		failures.append("weapon tier damage multiplier should be 1.7x per tier")

	if failures.is_empty():
		print("EQUIPMENT OK: weapon reserve, merge gating, and tier damage verified.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
