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

var rng := RandomNumberGenerator.new()
var active_roots: Array = ["metal", "fire", "earth"]
var sealed_roots: Array = ["wood", "water"]
var affinity_id := "five"
var stats := {}
var base_stats := {}
var active_weapons: Array = []
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
		equip_weapon(STARTER_BY_ELEMENT.get(e, "guanri_sword"))
	var idx := 0
	while active_weapons.size() < int(stats.get("weapon_slots", 4)) and not ordered.is_empty():
		equip_weapon(STARTER_BY_ELEMENT.get(ordered[idx % ordered.size()], "guanri_sword"))
		idx += 1

func equip_weapon(weapon_id: String) -> void:
	var weapon := ConfigDB.entry("weapons", weapon_id).duplicate(true)
	if weapon.is_empty():
		return
	weapon["id"] = weapon_id
	weapon["tier"] = int(weapon.get("tier", 1))
	if active_weapons.size() < int(stats.get("weapon_slots", 4)):
		active_weapons.append(weapon)
		SignalsBus.weapon_changed.emit(active_weapons.size() - 1, weapon)
		return
	var replace_idx := 0
	var lowest := 999999.0
	for i in range(active_weapons.size()):
		var score := float(active_weapons[i].get("base_damage", 0)) * float(active_weapons[i].get("tier", 1))
		if score < lowest:
			lowest = score
			replace_idx = i
	active_weapons[replace_idx] = weapon
	SignalsBus.weapon_changed.emit(replace_idx, weapon)

func add_item(item_id: String) -> bool:
	var item := ConfigDB.entry("items", item_id).duplicate(true)
	if item.is_empty():
		return false
	var used := 0
	for b in bag:
		used += int(b.get("slots", 1))
	var need := int(item.get("slots", 1))
	if used + need > int(stats.get("bag_capacity", 5)):
		return false
	item["id"] = item_id
	bag.append(item)
	_apply_effects(item.get("effects", {}))
	_apply_effects(item.get("cost_effects", {}))
	return true

func apply_skill(skill_id: String) -> void:
	var skill := ConfigDB.entry("skills", skill_id)
	if skill.is_empty():
		return
	var current := int(skill_stacks.get(skill_id, 0))
	if current >= int(skill.get("max_stacks", 1)):
		return
	skill_stacks[skill_id] = current + 1
	_apply_effects(skill.get("effects", {}))

func _apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var value = effects[key]
		if typeof(value) == TYPE_BOOL:
			stats[key] = value
		else:
			stats[key] = float(stats.get(key, 0.0)) + float(value)
		SignalsBus.stat_changed.emit(key, stats[key])

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
	raw *= 1.0 + 0.22 * float(int(weapon.get("tier", 1)) - 1)
	var is_crit: bool = rng.randf() < clamp(float(stats.get("crit_chance", 0.05)), 0.0, 0.95)
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
