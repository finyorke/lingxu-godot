extends Node

const ELEMENTS := ["metal", "wood", "water", "fire", "earth"]
const ELEMENT_NAMES := {"metal": "金", "wood": "木", "water": "水", "fire": "火", "earth": "土"}
const STARTER_PRIORITY := ["metal", "fire", "earth", "water", "wood"]
const STARTER_BY_ELEMENT := {
	"metal": "guanri_sword",
	"fire": "fentian_talisman",
	"earth": "zhenyue_chu",
	"water": "hantan_sword",
	"wood": "shigu_sting"
}
const MULTI_ELEMENT_BONUS := {1: 1.0, 2: 1.16, 3: 1.32, 4: 1.50, 5: 1.65}
const COUNTERS := {"metal": "wood", "wood": "earth", "earth": "water", "water": "fire", "fire": "metal"}
const GENERATES := {"wood": "fire", "fire": "earth", "earth": "metal", "metal": "water", "water": "wood"}
const WEAPON_TIER_MAX := 4
const WEAPON_TIER_NAMES := {1: "凡品", 2: "灵品", 3: "法品", 4: "仙品"}
const WEAPON_TIER_COLORS := {
	1: "#7f9088",
	2: "#5fe0c8",
	3: "#e8b259",
	4: "#c8a2ff"
}
const SET_EFFECT_KEYS := {
	"execute_threshold": true,
	"execute_mult": true,
	"quake_radius": true
}

var rng := RandomNumberGenerator.new()
var active_roots: Array = ["metal", "fire", "earth"]
var sealed_roots: Array = ["wood", "water"]
var affinity_id := "five"
var stats := {}
var base_stats := {}
var active_weapons: Array = []
var weapon_reserve: Array = []
var bag: Array = []
var skill_stacks := {}
var level := 1
var xp := 0.0
var xp_to_next := 20.0
var realm := "lianqi"
var realm_name := "练气"
var applied_realms := {"lianqi": true}
var kills := 0
var combo := 0
var stones := 0
var run_time := 0.0

func _ready() -> void:
	rng.randomize()
	base_stats = ConfigDB.table("stats").duplicate(true)
	stats = base_stats.duplicate(true)
	_recalc_xp()

func root_name(element: String) -> String:
	return ELEMENT_NAMES.get(element, element)

func start_run(active: Array, sealed: Array, chosen_affinity: String) -> void:
	active_roots = active.duplicate()
	sealed_roots = sealed.duplicate()
	affinity_id = chosen_affinity
	stats = ConfigDB.table("stats").duplicate(true)
	active_weapons.clear()
	weapon_reserve.clear()
	bag.clear()
	skill_stacks.clear()
	level = 1
	xp = 0.0
	kills = 0
	combo = 0
	stones = 0
	run_time = 0.0
	realm = "lianqi"
	realm_name = "练气"
	applied_realms = {"lianqi": true}
	_apply_affinity_base()
	_fill_starting_weapons()
	_recalc_xp()
	SignalsBus.roots_chosen.emit(active_roots)

func _apply_affinity_base() -> void:
	if affinity_id == "five":
		for e in ELEMENTS:
			stats["%s_damage_pct" % e] = float(stats.get("%s_damage_pct" % e, 0.0)) + 0.08
	elif affinity_id.begins_with("single_"):
		var e := affinity_id.replace("single_", "")
		stats["%s_damage_pct" % e] = float(stats.get("%s_damage_pct" % e, 0.0)) + 0.35
	elif affinity_id.begins_with("dual_"):
		var parts := affinity_id.replace("dual_", "").split("_")
		for e in parts:
			stats["%s_damage_pct" % e] = float(stats.get("%s_damage_pct" % e, 0.0)) + 0.24

func _fill_starting_weapons() -> void:
	var ordered: Array = []
	for e in STARTER_PRIORITY:
		if active_roots.has(e):
			ordered.append(e)
	if ordered.is_empty():
		ordered = active_roots.duplicate()
	for e in ordered:
		if active_weapons.size() >= int(stats.get("weapon_slots", 4)):
			break
		_grant_starting_weapon(STARTER_BY_ELEMENT.get(e, "guanri_sword"))
	var idx := 0
	while active_weapons.size() < int(stats.get("weapon_slots", 4)) and not ordered.is_empty():
		_grant_starting_weapon(STARTER_BY_ELEMENT.get(ordered[idx % ordered.size()], "guanri_sword"))
		idx += 1

func _grant_starting_weapon(weapon_id: String) -> void:
	var weapon := _make_weapon_instance(weapon_id, 1)
	if weapon.is_empty():
		return
	active_weapons.append(weapon)
	SignalsBus.weapon_changed.emit(active_weapons.size() - 1, weapon)

func _make_weapon_instance(weapon_id: String, tier := 1) -> Dictionary:
	var weapon := ConfigDB.entry("weapons", weapon_id).duplicate(true)
	if weapon.is_empty():
		return {}
	weapon["id"] = weapon_id
	weapon["tier"] = clampi(int(tier), 1, WEAPON_TIER_MAX)
	return weapon

func equip_weapon(weapon_id: String, tier := 1) -> bool:
	var weapon := _make_weapon_instance(weapon_id, tier)
	if weapon.is_empty():
		return false
	return acquire_weapon(weapon)

func acquire_weapon(weapon: Dictionary) -> bool:
	if weapon.is_empty():
		return false
	var weapon_id := str(weapon.get("id", ""))
	var tier := clampi(int(weapon.get("tier", 1)), 1, WEAPON_TIER_MAX)
	weapon["tier"] = tier
	var match := weapon_merge_target(weapon_id, tier)
	if not match.is_empty():
		_upgrade_weapon_at(str(match["place"]), int(match["index"]))
		return true
	if active_weapons.size() < int(stats.get("weapon_slots", 4)):
		active_weapons.append(weapon)
		SignalsBus.weapon_changed.emit(active_weapons.size() - 1, weapon)
		return true
	if weapon_reserve.size() < weapon_reserve_capacity():
		weapon_reserve.append(weapon)
		return true
	return false

func can_accept_weapon(weapon_id: String, tier := 1) -> bool:
	if not weapon_merge_target(weapon_id, tier).is_empty():
		return true
	return active_weapons.size() < int(stats.get("weapon_slots", 4)) or weapon_reserve.size() < weapon_reserve_capacity()

func weapon_sell_value(weapon: Dictionary) -> int:
	var tier := clampi(int(weapon.get("tier", 1)), 1, WEAPON_TIER_MAX)
	return 6 + (tier - 1) * 5

func sell_weapon_at(place: String, index: int) -> bool:
	var weapon := weapon_at(place, index)
	if weapon.is_empty():
		return false
	var value := weapon_sell_value(weapon)
	if not remove_weapon_at(place, index):
		return false
	stones += value
	return true

func weapon_at(place: String, index: int) -> Dictionary:
	if place == "active":
		if index >= 0 and index < active_weapons.size():
			return active_weapons[index]
	elif place == "reserve":
		if index >= 0 and index < weapon_reserve.size():
			return weapon_reserve[index]
	return {}

func remove_weapon_at(place: String, index: int) -> bool:
	if place == "active":
		if index < 0 or index >= active_weapons.size():
			return false
		active_weapons.remove_at(index)
		SignalsBus.weapon_changed.emit(index, {})
		return true
	if place == "reserve":
		if index < 0 or index >= weapon_reserve.size():
			return false
		weapon_reserve.remove_at(index)
		return true
	return false

func move_weapon(from_place: String, from_index: int, to_place: String, to_index: int) -> bool:
	if from_place == to_place and from_index == to_index:
		return false
	var weapon := weapon_at(from_place, from_index)
	if weapon.is_empty():
		return false
	if from_place == "active" and to_place == "active":
		if to_index < 0 or to_index >= active_weapons.size():
			return false
		var target: Dictionary = active_weapons[to_index]
		active_weapons[to_index] = weapon
		active_weapons[from_index] = target
		SignalsBus.weapon_changed.emit(from_index, active_weapons[from_index])
		SignalsBus.weapon_changed.emit(to_index, active_weapons[to_index])
		return true
	if from_place == "reserve" and to_place == "reserve":
		if to_index < 0 or to_index >= weapon_reserve.size():
			return false
		var target: Dictionary = weapon_reserve[to_index]
		weapon_reserve[to_index] = weapon
		weapon_reserve[from_index] = target
		return true
	if from_place == "active" and to_place == "reserve":
		if to_index >= 0 and to_index < weapon_reserve.size():
			var target: Dictionary = weapon_reserve[to_index]
			weapon_reserve[to_index] = weapon
			active_weapons[from_index] = target
			SignalsBus.weapon_changed.emit(from_index, target)
			return true
		if weapon_reserve.size() >= weapon_reserve_capacity():
			return false
		active_weapons.remove_at(from_index)
		weapon_reserve.append(weapon)
		SignalsBus.weapon_changed.emit(from_index, {})
		return true
	if from_place == "reserve" and to_place == "active":
		if to_index >= 0 and to_index < active_weapons.size():
			var target: Dictionary = active_weapons[to_index]
			active_weapons[to_index] = weapon
			weapon_reserve[from_index] = target
			SignalsBus.weapon_changed.emit(to_index, weapon)
			return true
		if active_weapons.size() >= int(stats.get("weapon_slots", 4)):
			return false
		weapon_reserve.remove_at(from_index)
		active_weapons.append(weapon)
		SignalsBus.weapon_changed.emit(active_weapons.size() - 1, weapon)
		return true
	return false

func can_merge_weapon_at(place: String, index: int) -> bool:
	return not weapon_manual_merge_target(place, index).is_empty()

func weapon_manual_merge_target(place: String, index: int) -> Dictionary:
	var weapon := weapon_at(place, index)
	if weapon.is_empty():
		return {}
	var weapon_id := str(weapon.get("id", ""))
	var tier := clampi(int(weapon.get("tier", 1)), 1, WEAPON_TIER_MAX)
	if tier >= WEAPON_TIER_MAX:
		return {}
	if place == "reserve":
		for i in range(active_weapons.size()):
			var active: Dictionary = active_weapons[i]
			if str(active.get("id", "")) == weapon_id and int(active.get("tier", 1)) == tier:
				return {"place": "active", "index": i}
	for i in range(active_weapons.size()):
		if place == "active" and i == index:
			continue
		var active: Dictionary = active_weapons[i]
		if str(active.get("id", "")) == weapon_id and int(active.get("tier", 1)) == tier:
			return {"place": "active", "index": i}
	for i in range(weapon_reserve.size()):
		if place == "reserve" and i == index:
			continue
		var reserve_weapon: Dictionary = weapon_reserve[i]
		if str(reserve_weapon.get("id", "")) == weapon_id and int(reserve_weapon.get("tier", 1)) == tier:
			return {"place": "reserve", "index": i}
	return {}

func merge_weapon_at(place: String, index: int) -> bool:
	var weapon := weapon_at(place, index)
	if weapon.is_empty():
		return false
	var tier := clampi(int(weapon.get("tier", 1)), 1, WEAPON_TIER_MAX)
	if tier >= WEAPON_TIER_MAX:
		return false
	var match := weapon_manual_merge_target(place, index)
	if match.is_empty():
		return false
	var target_place := place
	var target_index := index
	var consume_place := str(match["place"])
	var consume_index := int(match["index"])
	if place == "reserve" and consume_place == "active":
		target_place = "active"
		target_index = consume_index
		consume_place = "reserve"
		consume_index = index
	_upgrade_weapon_at(target_place, target_index)
	remove_weapon_at(consume_place, consume_index)
	return true

func weapon_merge_target(weapon_id: String, tier := 1) -> Dictionary:
	var normalized_tier := clampi(int(tier), 1, WEAPON_TIER_MAX)
	if normalized_tier >= WEAPON_TIER_MAX:
		return {}
	return _find_merge_match(weapon_id, normalized_tier)

func weapon_reserve_capacity() -> int:
	return max(0, int(stats.get("weapon_reserve_slots", 2)))

func _find_merge_match(weapon_id: String, tier: int) -> Dictionary:
	for i in range(active_weapons.size()):
		var weapon: Dictionary = active_weapons[i]
		if str(weapon.get("id", "")) == weapon_id and int(weapon.get("tier", 1)) == tier:
			return {"place": "active", "index": i}
	for i in range(weapon_reserve.size()):
		var weapon: Dictionary = weapon_reserve[i]
		if str(weapon.get("id", "")) == weapon_id and int(weapon.get("tier", 1)) == tier:
			return {"place": "reserve", "index": i}
	return {}

func _upgrade_weapon_at(place: String, index: int) -> void:
	if place == "active":
		if index < 0 or index >= active_weapons.size():
			return
		var weapon: Dictionary = active_weapons[index]
		weapon["tier"] = min(WEAPON_TIER_MAX, int(weapon.get("tier", 1)) + 1)
		active_weapons[index] = weapon
		SignalsBus.weapon_changed.emit(index, weapon)
	elif place == "reserve":
		if index < 0 or index >= weapon_reserve.size():
			return
		var weapon: Dictionary = weapon_reserve[index]
		weapon["tier"] = min(WEAPON_TIER_MAX, int(weapon.get("tier", 1)) + 1)
		weapon_reserve[index] = weapon

func weapon_tier_name(tier: int) -> String:
	return str(WEAPON_TIER_NAMES.get(clampi(tier, 1, WEAPON_TIER_MAX), "凡品"))

func weapon_tier_color(tier: int) -> Color:
	return Color(str(WEAPON_TIER_COLORS.get(clampi(tier, 1, WEAPON_TIER_MAX), "#7f9088")))

func weapon_tier_multiplier(tier: int) -> float:
	return pow(1.7, float(clampi(tier, 1, WEAPON_TIER_MAX) - 1))

func bag_used_slots() -> int:
	var used := 0
	for b in bag:
		used += int(b.get("slots", 1))
	return used

func can_accept_item(item_id: String) -> bool:
	var item := ConfigDB.entry("items", item_id)
	if item.is_empty():
		return false
	var need := int(item.get("slots", 1))
	return bag_used_slots() + need <= int(stats.get("bag_capacity", 5))

func add_item(item_id: String) -> bool:
	var item := ConfigDB.entry("items", item_id).duplicate(true)
	if item.is_empty():
		return false
	var need := int(item.get("slots", 1))
	if bag_used_slots() + need > int(stats.get("bag_capacity", 5)):
		return false
	item["id"] = item_id
	bag.append(item)
	_apply_effects(item.get("effects", {}))
	_apply_effects(item.get("cost_effects", {}))
	return true

func item_sell_value(item: Dictionary) -> int:
	return max(3, 3 + int(item.get("slots", 1)) * 2)

func sell_item_at(index: int) -> bool:
	if index < 0 or index >= bag.size():
		return false
	var item: Dictionary = bag[index]
	var value := item_sell_value(item)
	bag.remove_at(index)
	_rebuild_stats_from_sources()
	stones += value
	return true

func apply_skill(skill_id: String) -> bool:
	var skill := ConfigDB.entry("skills", skill_id)
	if skill.is_empty():
		return false
	var current := int(skill_stacks.get(skill_id, 0))
	if current >= int(skill.get("max_stacks", 1)):
		return false
	skill_stacks[skill_id] = current + 1
	_apply_effects(skill.get("effects", {}))
	return true

func _apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var value = effects[key]
		if typeof(value) == TYPE_BOOL:
			stats[key] = value
		elif SET_EFFECT_KEYS.has(key):
			stats[key] = max(float(stats.get(key, 0.0)), float(value))
		else:
			stats[key] = float(stats.get(key, 0.0)) + float(value)
		SignalsBus.stat_changed.emit(key, stats[key])

func _rebuild_stats_from_sources() -> void:
	stats = ConfigDB.table("stats").duplicate(true)
	_apply_affinity_base()
	var realms: Array = ConfigDB.table("realms").get("realms", [])
	for realm_def in realms:
		var realm_id := str(realm_def.get("id", ""))
		if applied_realms.has(realm_id):
			_apply_effects(realm_def.get("bonus", {}))
	for skill_id in skill_stacks.keys():
		var skill := ConfigDB.entry("skills", str(skill_id))
		if skill.is_empty():
			continue
		for _i in range(int(skill_stacks[skill_id])):
			_apply_effects(skill.get("effects", {}))
	for item in bag:
		_apply_effects(item.get("effects", {}))
		_apply_effects(item.get("cost_effects", {}))

func weapon_element_count() -> int:
	var seen := {}
	for weapon in active_weapons:
		seen[weapon.get("element", "metal")] = true
	return max(1, seen.size())

func multi_element_multiplier() -> float:
	return float(MULTI_ELEMENT_BONUS.get(weapon_element_count(), 1.0))

func root_affinity_multiplier(element: String) -> float:
	if affinity_id == "five":
		return 1.08
	if affinity_id == "single_%s" % element:
		return 1.35
	if affinity_id.begins_with("single_"):
		return 1.0
	if affinity_id.begins_with("dual_"):
		var parts := affinity_id.replace("dual_", "").split("_")
		return 1.24 if parts.has(element) else 1.0
	return 1.0

func converted_element_bonus(element: String) -> float:
	var direct := float(stats.get("%s_damage_pct" % element, 0.0))
	var conversion := 0.0
	if affinity_id == "five":
		conversion = 0.30 + float(stats.get("root_conversion_bonus", 0.0))
		var other_total := 0.0
		for e in ELEMENTS:
			if e != element:
				other_total += float(stats.get("%s_damage_pct" % e, 0.0))
		return direct + other_total * conversion
	if affinity_id.begins_with("dual_"):
		var parts := affinity_id.replace("dual_", "").split("_")
		if parts.has(element):
			for e in parts:
				if e != element:
					direct += float(stats.get("%s_damage_pct" % e, 0.0)) * 0.35
	return direct

func calculate_weapon_damage(weapon: Dictionary, target: Node = null) -> Dictionary:
	var scale: Dictionary = weapon.get("scale", {})
	var raw := float(weapon.get("base_damage", 1.0))
	raw += float(stats.get("sword_power", 0.0)) * float(scale.get("sword", 0.0))
	raw += float(stats.get("spell_power", 0.0)) * float(scale.get("spell", 0.0))
	raw += float(stats.get("engineering", 0.0)) * float(scale.get("eng", 0.0))
	raw *= 1.0 + max(-0.85, float(stats.get("damage_pct", 0.0)))
	var element := str(weapon.get("element", "metal"))
	raw *= root_affinity_multiplier(element)
	raw *= 1.0 + converted_element_bonus(element) + float(stats.get("element_pct", 0.0))
	raw *= multi_element_multiplier()
	raw *= weapon_tier_multiplier(int(weapon.get("tier", 1)))
	var crit_chance := float(stats.get("crit_chance", 0.05))
	for effect in weapon.get("on_hit", []):
		var kind := str(effect.get("effect", ""))
		if kind == "crit_bonus":
			crit_chance += float(effect.get("value", 0.0))
		elif kind == "ignore_armor":
			raw *= 1.12
	var is_crit: bool = rng.randf() < clamp(crit_chance, 0.0, 0.95)
	if element == "fire" and target != null and target.has_method("hp_ratio"):
		if target.hp_ratio() <= float(stats.get("execute_threshold", -1.0)) and bool(stats.get("fire_execute", false)):
			is_crit = true
			raw *= float(stats.get("execute_mult", 1.0))
	if is_crit:
		raw *= float(stats.get("crit_mult", 1.85))
	return {"amount": max(1.0, raw), "is_crit": is_crit, "element": element}

func gain_xp(amount: float) -> bool:
	xp += amount * float(stats.get("qi_gain", 1.0))
	var leveled := false
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		_recalc_xp()
		_update_realm()
		leveled = true
		SignalsBus.player_levelup.emit(level)
	return leveled

func _recalc_xp() -> void:
	xp_to_next = float(stats.get("xp_curve_a", 12)) + float(stats.get("xp_curve_b", 8)) * pow(level, 1.12) + float(stats.get("xp_curve_c", 0))

func _update_realm() -> void:
	var realms: Array = ConfigDB.table("realms").get("realms", [])
	for r in realms:
		var id := str(r.get("id", ""))
		if level >= int(r.get("min_level", 1)) and not applied_realms.has(id):
			applied_realms[id] = true
			realm = id
			realm_name = str(r.get("name", realm_name))
			_apply_effects(r.get("bonus", {}))
			SignalsBus.ascension_started.emit(realm_name)

func synergy_lines() -> Array:
	var lines: Array = []
	for a in active_roots:
		var b = GENERATES.get(a, "")
		if active_roots.has(b):
			lines.append("%s生%s：2+2 装配触发相生连招" % [root_name(a), root_name(b)])
	if lines.is_empty():
		lines.append("当前组合无相生连招，适合纯色专精")
	return lines

func filtered_ids(table_name: String) -> Array:
	var result: Array = []
	var table = ConfigDB.table(table_name)
	for id in table.keys():
		if str(id).begins_with("_"):
			continue
		var entry: Dictionary = table[id]
		var element = entry.get("element", entry.get("school", null))
		if element == null or element == "common" or active_roots.has(element):
			result.append(id)
	return result
