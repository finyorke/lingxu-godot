extends Node2D

signal run_ended(result)

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const ENEMY_SCENE := preload("res://Scenes/Enemies/Enemy.tscn")
const PROJECTILE_SCENE := preload("res://Scenes/Weapon/Projectile.tscn")
const HUD_STAT_DEFS := [
	{"key": "damage_pct", "label": "全伤", "icon": "fx_crit"},
	{"key": "metal_damage_pct", "label": "金伤", "icon": "icon_metal"},
	{"key": "wood_damage_pct", "label": "木伤", "icon": "icon_wood"},
	{"key": "water_damage_pct", "label": "水伤", "icon": "icon_water"},
	{"key": "fire_damage_pct", "label": "火伤", "icon": "icon_fire"},
	{"key": "earth_damage_pct", "label": "土伤", "icon": "icon_earth"},
	{"key": "crit_chance", "label": "暴击", "icon": "icon_crit"},
	{"key": "dodge", "label": "身法", "icon": "offer_frost_pendant"},
	{"key": "armor", "label": "护甲", "icon": "offer_thick_earth_armor"},
	{"key": "speed_pct", "label": "移速", "icon": "offer_swift_talisman"},
	{"key": "attack_speed", "label": "攻速", "icon": "offer_stat_attack_speed"},
	{"key": "range_pct", "label": "范围", "icon": "offer_stat_range"},
	{"key": "lifesteal", "label": "噬灵", "icon": "offer_bloodlust_jade"},
	{"key": "luck", "label": "气运", "icon": "offer_lucky_coin"}
]

var player: YunxiPlayer
var enemies: Array = []
var projectiles: Array = []
var pickups: Array = []
var weapon_cds: Array = []
var rng := RandomNumberGenerator.new()
var arena_radius := Vector2(1200, 700)
var spawn_timer := 0.0
var burst_cd := 0.0
var boss_index := 0
var market_open := false
var paused := false
var hitstop := 0.0
var shake_time := 0.0
var shake_power := 0.0
var camera: Camera2D
var hud_layer: CanvasLayer
var overlay_layer: CanvasLayer
var hp_bar: ProgressBar
var shield_bar: ProgressBar
var xp_bar: ProgressBar
var info_label: Label
var stats_label: Label
var weapon_label: Label
var hp_value_label: Label
var shield_value_label: Label
var xp_value_label: Label
var weapon_slot_buttons: Array = []
var stat_icon_buttons: Array = []
var message_label: Label

func _ready() -> void:
	rng.randomize()
	var spawn_cfg: Dictionary = ConfigDB.table("spawn").get("arena", {})
	arena_radius = Vector2(float(spawn_cfg.get("radius_x", 1200)), float(spawn_cfg.get("radius_y", 700)))
	_setup_world()
	_setup_player()
	_setup_hud()
	weapon_cds.resize(GameState.active_weapons.size())
	for i in range(weapon_cds.size()):
		weapon_cds[i] = rng.randf_range(0.05, 0.35)
	SignalsBus.hud_request_shake.connect(_on_shake)
	SignalsBus.hud_request_hitstop.connect(_on_hitstop)
	SignalsBus.player_levelup.connect(func(_level): _open_market("境界机缘"))
	SignalsBus.ascension_started.connect(_on_ascension)

func _setup_world() -> void:
	var bg := Sprite2D.new()
	bg.texture = AssetDB.tex("bg_arena")
	bg.z_index = -20
	if bg.texture != null:
		bg.scale = Vector2((arena_radius.x * 2.2) / bg.texture.get_width(), (arena_radius.y * 2.2) / bg.texture.get_height())
	add_child(bg)
	var line := Line2D.new()
	line.width = 5
	line.default_color = Color("#5fe0c8")
	line.closed = true
	line.z_index = -5
	for i in range(160):
		var a := float(i) / 160.0 * TAU
		line.add_point(Vector2(cos(a) * arena_radius.x, sin(a) * arena_radius.y))
	add_child(line)
	camera = Camera2D.new()
	camera.zoom = Vector2(0.72, 0.72)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()

func _setup_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector2(0, 90)
	player.died.connect(func(): _finish_run("陨落", "气血归零"))
	add_child(player)

func _setup_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(root)
	var top := HBoxContainer.new()
	top.anchor_left = 0.02
	top.anchor_top = 0.02
	top.anchor_right = 0.98
	top.anchor_bottom = 0.13
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)
	var bars := VBoxContainer.new()
	bars.custom_minimum_size = Vector2(520, 92)
	top.add_child(bars)
	hp_bar = _bar(Color("#f25050"))
	shield_bar = _bar(Color("#5aa9e0"))
	xp_bar = _bar(Color("#5fe0c8"))
	bars.add_child(hp_bar)
	hp_value_label = _bar_value_label(hp_bar)
	bars.add_child(shield_bar)
	shield_value_label = _bar_value_label(shield_bar)
	bars.add_child(xp_bar)
	xp_value_label = _bar_value_label(xp_bar)
	info_label = Label.new()
	info_label.custom_minimum_size = Vector2(460, 90)
	info_label.add_theme_font_size_override("font_size", 25)
	info_label.add_theme_color_override("font_color", Color("#eaf6ff"))
	top.add_child(info_label)
	var weapon_panel := PanelContainer.new()
	weapon_panel.custom_minimum_size = Vector2(370, 90)
	weapon_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.02, 0.04, 0.045, 0.72), Color("#5fe0c8"), 1, 6))
	top.add_child(weapon_panel)
	var weapon_slots := HBoxContainer.new()
	weapon_slots.add_theme_constant_override("separation", 10)
	weapon_panel.add_child(weapon_slots)
	weapon_slot_buttons.clear()
	for i in range(4):
		var slot := _hud_icon_button(Vector2(80, 80))
		weapon_slots.add_child(slot)
		weapon_slot_buttons.append(slot)
	var stat_panel := PanelContainer.new()
	stat_panel.anchor_left = 0.02
	stat_panel.anchor_top = 0.84
	stat_panel.anchor_right = 0.98
	stat_panel.anchor_bottom = 0.96
	stat_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.018, 0.032, 0.038, 0.76), Color("#5fe0c8"), 1, 6))
	root.add_child(stat_panel)
	var stat_slots := HBoxContainer.new()
	stat_slots.add_theme_constant_override("separation", 9)
	stat_panel.add_child(stat_slots)
	stat_icon_buttons.clear()
	for def in HUD_STAT_DEFS:
		var stat_button := _hud_icon_button(Vector2(52, 52))
		stat_slots.add_child(stat_button)
		stat_icon_buttons.append({"button": stat_button, "def": def})
	message_label = Label.new()
	message_label.anchor_left = 0.27
	message_label.anchor_top = 0.38
	message_label.anchor_right = 0.73
	message_label.anchor_bottom = 0.48
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 44)
	message_label.add_theme_color_override("font_color", Color("#e8b259"))
	root.add_child(message_label)
	overlay_layer = CanvasLayer.new()
	add_child(overlay_layer)

func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(500, 24)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 3
	fill.corner_radius_bottom_left = 3
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.04, 0.04, 0.74)
	bg.border_color = Color("#5fe0c8")
	bg.set_border_width_all(1)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b

func _bar_value_label(bar: ProgressBar) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#fff8e8"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)
	return label

func _hud_icon_button(size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.text = ""
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_HELP
	b.add_theme_stylebox_override("normal", _stylebox(Color(0.03, 0.055, 0.06, 0.9), Color(0.35, 0.88, 0.82, 0.34), 1, 5))
	b.add_theme_stylebox_override("hover", _stylebox(Color(0.05, 0.09, 0.1, 0.96), Color("#e8b259"), 2, 5))
	b.add_theme_stylebox_override("pressed", _stylebox(Color(0.08, 0.1, 0.09, 0.98), Color("#e8b259"), 2, 5))
	return b

func _stylebox(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("pause") and not market_open:
		paused = not paused
		message_label.text = "暂停" if paused else ""
	if paused or market_open:
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	GameState.run_time += delta
	burst_cd = max(0.0, burst_cd - delta)
	player.tick(delta, arena_radius)
	camera.global_position = player.global_position + _shake_offset()
	_update_enemies(delta)
	_update_weapons(delta)
	_update_projectiles(delta)
	_update_pickups(delta)
	_update_spawning(delta)
	_update_bosses()
	_update_burst()
	_update_hud()
	if GameState.run_time >= 720.0:
		_finish_run("道成", "撑过十二分钟")

func _update_enemies(delta: float) -> void:
	enemies = enemies.filter(func(e): return is_instance_valid(e))
	for enemy in enemies:
		enemy.tick(delta, player)

func _update_weapons(delta: float) -> void:
	while weapon_cds.size() < GameState.active_weapons.size():
		weapon_cds.append(0.0)
	for i in range(GameState.active_weapons.size()):
		var weapon: Dictionary = GameState.active_weapons[i]
		weapon_cds[i] = max(0.0, float(weapon_cds[i]) - delta)
		if weapon_cds[i] <= 0.0:
			_fire_weapon(weapon)
			var interval := float(weapon.get("cooldown", 1.0))
			interval /= 1.0 + max(-0.75, float(GameState.stats.get("attack_speed", 0.0)))
			interval *= 1.0 - clamp(float(GameState.stats.get("attack_interval_pct", 0.0)), -0.5, 0.5)
			weapon_cds[i] = max(0.12, interval)

func _fire_weapon(weapon: Dictionary) -> void:
	var klass := str(weapon.get("class", "flying_sword"))
	if klass == "shield":
		var shield_gain := 10.0
		for effect in weapon.get("on_hit", []):
			if str(effect.get("effect", "")) == "grant_shield":
				var scale_eng := float(effect.get("scale_eng", 1.0))
				var tier_mult := 1.0 + 0.22 * float(int(weapon.get("tier", 1)) - 1)
				shield_gain += (8.0 + float(GameState.stats.get("engineering", 0.0))) * scale_eng * tier_mult
		_add_player_shield(shield_gain)
		_spawn_fx(player.global_position, "fx_water", 0.25)
		return
	if klass == "orbit" or klass == "aura":
		var range := float(weapon.get("range", 180)) * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
		for enemy in enemies:
			if player.global_position.distance_squared_to(enemy.global_position) <= range * range:
				_hit_enemy(weapon, enemy)
		_spawn_fx(player.global_position, "fx_%s" % weapon.get("element", "metal"), 0.2)
		return
	var target := _select_target(weapon)
	if target == null:
		return
	if klass == "area":
		var radius := float(weapon.get("radius", 110)) * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
		for enemy in enemies:
			if enemy.global_position.distance_squared_to(target.global_position) <= radius * radius:
				_hit_enemy(weapon, enemy)
		_spawn_fx(target.global_position, "fx_%s" % weapon.get("element", "metal"), 0.32)
		return
	var projectile: LingxuProjectile = PROJECTILE_SCENE.instantiate()
	projectile.setup(weapon, player.global_position, target.global_position)
	add_child(projectile)
	projectiles.append(projectile)

func _select_target(weapon: Dictionary) -> LingxuEnemy:
	var max_range := float(weapon.get("range", 360)) * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
	if max_range >= 9000:
		max_range = 99999
	var candidates: Array = []
	for enemy in enemies:
		var d2 := player.global_position.distance_squared_to(enemy.global_position)
		if d2 <= max_range * max_range:
			candidates.append({"enemy": enemy, "d2": d2})
	if candidates.is_empty():
		return null
	var lock := str(weapon.get("lock", "nearest"))
	if lock == "farthest":
		candidates.sort_custom(func(a, b): return a["d2"] > b["d2"])
	elif lock == "densest":
		candidates.sort_custom(func(a, b): return _nearby_count(a["enemy"].global_position, 140) > _nearby_count(b["enemy"].global_position, 140))
	else:
		candidates.sort_custom(func(a, b): return a["d2"] < b["d2"])
	return candidates[0]["enemy"]

func _nearby_count(pos: Vector2, radius: float) -> int:
	var count := 0
	var r2 := radius * radius
	for enemy in enemies:
		if pos.distance_squared_to(enemy.global_position) <= r2:
			count += 1
	return count

func _hit_enemy(weapon: Dictionary, enemy: LingxuEnemy, hit_pos := Vector2.ZERO, allow_secondary := true) -> Dictionary:
	if enemy == null or not is_instance_valid(enemy):
		return {}
	var target_pos := enemy.global_position if hit_pos == Vector2.ZERO else hit_pos
	var result := GameState.calculate_weapon_damage(weapon, enemy)
	enemy.take_damage(float(result["amount"]), bool(result["is_crit"]), str(result["element"]))
	player.heal_from_lifesteal(float(result["amount"]))
	_apply_weapon_on_hit(weapon, enemy, target_pos, result, allow_secondary)
	SignalsBus.hud_request_hitstop.emit(0.02)
	return result

func _apply_weapon_on_hit(weapon: Dictionary, enemy: LingxuEnemy, hit_pos: Vector2, result: Dictionary, allow_secondary := true) -> void:
	var effects: Array = weapon.get("on_hit", [])
	if effects.is_empty():
		return
	var element := str(result.get("element", weapon.get("element", "metal")))
	for effect in effects:
		var kind := str(effect.get("effect", ""))
		match kind:
			"poison", "bleed", "ignite":
				if is_instance_valid(enemy):
					enemy.add_dot(kind, element, float(effect.get("dps", 3.0)), float(effect.get("dur", 2.5)), bool(effect.get("stack", false)))
			"slow":
				if is_instance_valid(enemy):
					enemy.apply_slow(float(effect.get("value", 0.22)), float(effect.get("dur", 1.5)))
			"chill_stack":
				if is_instance_valid(enemy):
					enemy.add_chill_stack(int(effect.get("stacks", 5)), float(effect.get("freeze_dur", 0.8)))
			"freeze":
				if is_instance_valid(enemy):
					enemy.apply_freeze(float(effect.get("dur", 1.0)))
			"petrify":
				if is_instance_valid(enemy):
					enemy.apply_petrify(float(effect.get("dur", 1.0)))
			"root":
				if is_instance_valid(enemy):
					enemy.apply_root(float(effect.get("dur", 0.6)))
			"stagger":
				if is_instance_valid(enemy):
					enemy.apply_root(float(effect.get("dur", 0.22)))
			"blind":
				if is_instance_valid(enemy):
					enemy.apply_slow(0.35, float(effect.get("dur", 1.2)))
			"vulnerable", "execute_setup":
				if is_instance_valid(enemy):
					enemy.apply_vulnerable(float(effect.get("value", 0.14)), float(effect.get("dur", 2.0)))
			"ignore_armor":
				if is_instance_valid(enemy):
					enemy.apply_vulnerable(float(effect.get("value", 0.12)), float(effect.get("dur", 2.2)))
				_spawn_fx(hit_pos, "fx_crit", 0.16)
			"knockback":
				if is_instance_valid(enemy):
					enemy.apply_knockback(player.global_position, float(effect.get("value", 20.0)))
			"pull":
				if is_instance_valid(enemy):
					enemy.apply_pull(player.global_position, float(effect.get("value", 18.0)))
			"quake":
				if allow_secondary:
					var radius := float(effect.get("radius", GameState.stats.get("quake_radius", weapon.get("radius", 120))))
					_secondary_aoe(weapon, hit_pos, radius, 0.38, element, false, true)
					_spawn_fx(hit_pos, "fx_earth", 0.22)
			"explode":
				if allow_secondary:
					var radius := float(effect.get("radius", weapon.get("radius", 115))) * 0.85
					_secondary_aoe(weapon, hit_pos, radius, float(effect.get("damage_mult", 0.42)), element, true, false)
					_spawn_fx(hit_pos, "fx_fire", 0.22)
			"ignite_nova":
				if allow_secondary:
					_secondary_status_wave("ignite", element, hit_pos, float(effect.get("radius", 230.0)), float(effect.get("dps", 6.0)), float(effect.get("dur", 3.0)), true)
					_spawn_fx(hit_pos, "fx_fire", 0.34)
			"poison_burst":
				if allow_secondary:
					_secondary_status_wave("poison", element, hit_pos, float(effect.get("radius", 210.0)), float(effect.get("dps", 7.0)), float(effect.get("dur", 4.0)), true)
					_spawn_fx(hit_pos, "fx_wood", 0.34)
			"shield_splash":
				_add_player_shield(float(effect.get("value", 1.0)) + float(GameState.stats.get("engineering", 0.0)) * 0.15)
			"armor_up":
				_add_player_shield(2.0 + float(effect.get("value", 1.0)) * 2.0)
			"taunt":
				if is_instance_valid(enemy):
					enemy.apply_root(float(effect.get("dur", 0.35)))
			"split_chance":
				if allow_secondary and rng.randf() < float(effect.get("value", 0.1)):
					var split_target := _find_split_target(hit_pos, enemy, float(effect.get("radius", 260.0)))
					if split_target != null:
						var split_weapon := _make_secondary_weapon(weapon, 0.45, element)
						_hit_enemy(split_weapon, split_target, split_target.global_position, false)
						_spawn_fx(split_target.global_position, "fx_slash", 0.16)
			_:
				pass

func _secondary_aoe(source_weapon: Dictionary, center: Vector2, radius: float, damage_mult: float, element: String, ignite_targets := false, knock_targets := false) -> void:
	var secondary_weapon := _make_secondary_weapon(source_weapon, damage_mult, element)
	var radius_sq := radius * radius
	var hits := 0
	for other in enemies:
		if hits >= 6:
			break
		if other == null or not is_instance_valid(other):
			continue
		if center.distance_squared_to(other.global_position) > radius_sq:
			continue
		_hit_enemy(secondary_weapon, other, center, false)
		if ignite_targets:
			other.add_dot("ignite", element, 3.0, 2.0, true)
		if knock_targets:
			other.apply_knockback(center, 16.0)
		hits += 1

func _secondary_status_wave(effect: String, element: String, center: Vector2, radius: float, dps: float, duration: float, stackable := true) -> void:
	var radius_sq := radius * radius
	for other in enemies:
		if other == null or not is_instance_valid(other):
			continue
		if center.distance_squared_to(other.global_position) <= radius_sq:
			other.add_dot(effect, element, dps, duration, stackable)

func _make_secondary_weapon(source_weapon: Dictionary, damage_mult: float, element: String) -> Dictionary:
	var secondary_weapon := source_weapon.duplicate(true)
	secondary_weapon["base_damage"] = max(1.0, float(source_weapon.get("base_damage", 1.0)) * damage_mult)
	secondary_weapon["element"] = element
	secondary_weapon["on_hit"] = []
	return secondary_weapon

func _add_player_shield(amount: float) -> void:
	if amount <= 0.0:
		return
	player.shield = min(float(GameState.stats.get("max_qi_shield", 60)), player.shield + amount)

func _find_split_target(center: Vector2, source_enemy: LingxuEnemy, radius: float) -> LingxuEnemy:
	var best: LingxuEnemy = null
	var best_d2 := radius * radius
	for other in enemies:
		if other == null or other == source_enemy or not is_instance_valid(other):
			continue
		var d2 := center.distance_squared_to(other.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = other
	return best

func _update_projectiles(delta: float) -> void:
	projectiles = projectiles.filter(func(p): return is_instance_valid(p))
	for projectile in projectiles:
		projectile.tick(delta, enemies, player)

func _update_pickups(delta: float) -> void:
	var keep: Array = []
	var radius := float(GameState.stats.get("pickup_radius", 60)) + float(GameState.stats.get("harvesting", 0.0))
	for p in pickups:
		var node: Node2D = p["node"]
		if not is_instance_valid(node):
			continue
		var d := node.global_position.distance_to(player.global_position)
		if d < radius:
			if p["type"] == "qi":
				GameState.gain_xp(float(p["amount"]))
				SignalsBus.qi_collected.emit(p["amount"])
			else:
				GameState.stones += int(p["amount"])
				SignalsBus.stone_collected.emit(p["amount"])
			node.queue_free()
		else:
			if d < radius * 3.0:
				node.global_position = node.global_position.lerp(player.global_position, delta * 4.0)
			keep.append(p)
	pickups = keep

func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	var wave := _current_wave()
	var cap := int(wave.get("cap", 80))
	if enemies.size() >= cap:
		spawn_timer = 0.5
		return
	var pack: Array = wave.get("pack", [2, 4])
	var count := rng.randi_range(int(pack[0]), int(pack[1]))
	for i in range(count):
		_spawn_enemy(str(wave.get("enemy", "xie_wolf")))
	spawn_timer = max(0.16, float(wave.get("interval", 1.0)) * (1.0 - min(0.45, GameState.run_time / 1600.0)))

func _current_wave() -> Dictionary:
	var waves: Array = ConfigDB.table("spawn").get("waves", [])
	for wave in waves:
		if GameState.run_time >= float(wave.get("from", 0)) and GameState.run_time < float(wave.get("to", 99999)):
			return wave
	return waves.back() if not waves.is_empty() else {"enemy": "xie_wolf", "interval": 1.0, "pack": [2, 4], "cap": 80}

func _spawn_enemy(id: String, boss := false) -> void:
	var enemy: LingxuEnemy = ENEMY_SCENE.instantiate()
	var angle := rng.randf() * TAU
	var pos := Vector2(cos(angle) * arena_radius.x * rng.randf_range(0.86, 1.0), sin(angle) * arena_radius.y * rng.randf_range(0.86, 1.0))
	enemy.position = pos
	var scale := 1.0 + GameState.run_time / 720.0 * 1.2
	if boss:
		scale *= 1.2
	enemy.setup(id, scale)
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemies.append(enemy)
	if boss:
		_spawn_fx(enemy.global_position, "fx_warning", 0.55)
		SignalsBus.boss_spawned.emit(id)

func _update_bosses() -> void:
	var boss_times: Array = ConfigDB.table("spawn").get("boss_times", [180, 360, 540, 720])
	if boss_index >= boss_times.size():
		return
	if GameState.run_time >= float(boss_times[boss_index]):
		var id := "sword_demon" if boss_index == boss_times.size() - 1 else "serpent_boss"
		_spawn_enemy(id, true)
		message_label.text = "妖将现世：%s" % ConfigDB.entry("enemies", id).get("name", id)
		var tween := create_tween()
		tween.tween_interval(2.0)
		tween.tween_callback(func(): message_label.text = "")
		boss_index += 1

func _update_burst() -> void:
	var auto := bool(SaveSystem.settings.get("auto_burst", false))
	if (Input.is_action_just_pressed("sword_burst") or auto) and burst_cd <= 0.0:
		burst_cd = float(GameState.stats.get("burst_cooldown", 8.0))
		var burst_weapon := {"name": "御剑·聚剑斩", "element": "metal", "class": "burst", "base_damage": 34, "cooldown": 8.0, "scale": {"sword": 1.2, "spell": 0.2, "eng": 0.5}, "tier": 1, "art_id": "fx_slash"}
		var range := 260.0 * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
		for enemy in enemies:
			if player.global_position.distance_squared_to(enemy.global_position) <= range * range:
				var result := GameState.calculate_weapon_damage(burst_weapon, enemy)
				enemy.take_damage(float(result["amount"]) * float(GameState.stats.get("burst_mult", 0.9)), true, "metal")
		_spawn_fx(player.global_position + player.facing * 80.0, "fx_slash", 0.42)
		SignalsBus.hud_request_shake.emit(12.0, 0.22)
		SignalsBus.hud_request_hitstop.emit(0.05)

func _on_enemy_died(enemy: LingxuEnemy, xp_amount: float) -> void:
	GameState.kills += 1
	GameState.combo += 1
	_spawn_pickup(enemy.global_position, "qi", xp_amount)
	if rng.randf() < 0.25 + float(GameState.stats.get("luck", 0.0)) * 0.01:
		_spawn_pickup(enemy.global_position + Vector2(rng.randf_range(-18, 18), rng.randf_range(-18, 18)), "stone", rng.randi_range(1, 3))
	SignalsBus.enemy_died.emit(enemy, enemy.global_position)
	if bool(enemy.data.get("is_boss", false)):
		_open_market("妖将机缘")

func _spawn_pickup(pos: Vector2, kind: String, amount: float) -> void:
	var s := Sprite2D.new()
	s.texture = AssetDB.tex("pickup_qi" if kind == "qi" else "pickup_stone")
	s.scale = Vector2(0.065, 0.065)
	s.global_position = pos
	add_child(s)
	pickups.append({"node": s, "type": kind, "amount": amount})

func _spawn_fx(pos: Vector2, id: String, duration: float) -> void:
	var fx := Sprite2D.new()
	fx.texture = AssetDB.tex(id)
	fx.global_position = pos
	fx.scale = Vector2(0.18, 0.18)
	fx.modulate = Color(1, 1, 1, 0.85)
	add_child(fx)
	var tween := create_tween()
	tween.tween_property(fx, "scale", Vector2(0.42, 0.42), duration)
	tween.parallel().tween_property(fx, "modulate:a", 0.0, duration)
	tween.tween_callback(fx.queue_free)

func _open_market(reason: String) -> void:
	if market_open:
		return
	market_open = true
	overlay_layer.queue_free()
	overlay_layer = CanvasLayer.new()
	add_child(overlay_layer)
	var root := ColorRect.new()
	root.color = Color(0.02, 0.03, 0.03, 0.82)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_layer.add_child(root)
	var box := VBoxContainer.new()
	box.anchor_left = 0.08
	box.anchor_top = 0.09
	box.anchor_right = 0.92
	box.anchor_bottom = 0.91
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)
	var title := Label.new()
	title.text = "%s · 四选一" % reason
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("#e8b259"))
	box.add_child(title)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	box.add_child(cards)
	var offers := _roll_offers(4)
	for offer in offers:
		cards.add_child(_offer_button(offer))
	SignalsBus.market_offered.emit(offers)

func _roll_offers(count: int) -> Array:
	var result: Array = []
	var pool: Array = []
	for id in GameState.filtered_ids("weapons"):
		var w := ConfigDB.entry("weapons", id)
		if bool(w.get("legendary", false)) and GameState.realm != "huashen":
			continue
		pool.append({"kind": "weapon", "id": id, "name": w.get("name", id), "summary": "%s法器 · %s伤害 %.0f" % [GameState.root_name(w.get("element", "")), w.get("class", ""), float(w.get("base_damage", 0))], "art_id": _offer_art_id(id), "data": w})
	for id in GameState.filtered_ids("items"):
		var item := ConfigDB.entry("items", id)
		pool.append({"kind": "item", "id": id, "name": item.get("name", id), "summary": item.get("summary", ""), "art_id": _offer_art_id(id), "data": item})
	for id in GameState.filtered_ids("skills"):
		var skill := ConfigDB.entry("skills", id)
		pool.append({"kind": "skill", "id": id, "name": skill.get("name", id), "summary": skill.get("summary", ""), "art_id": _offer_art_id(id), "data": skill})
	pool.shuffle()
	var seen := {}
	for offer in pool:
		if result.size() >= count:
			break
		if seen.has(offer["id"]):
			continue
		seen[offer["id"]] = true
		result.append(offer)
	return result

func _offer_button(offer: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(320, 426)
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _stylebox(Color(0.026, 0.04, 0.045, 0.96), Color(0.38, 0.9, 0.82, 0.38), 1, 6))
	b.add_theme_stylebox_override("hover", _stylebox(Color(0.045, 0.072, 0.076, 0.98), Color("#e8b259"), 2, 6))
	b.add_theme_stylebox_override("pressed", _stylebox(Color(0.055, 0.066, 0.055, 0.98), Color("#e8b259"), 2, 6))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	b.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var art_panel := PanelContainer.new()
	art_panel.custom_minimum_size = Vector2(0, 154)
	art_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.012, 0.025, 0.028, 0.98), _element_color(str(offer.get("data", {}).get("element", ""))), 2, 5))
	box.add_child(art_panel)
	var art := TextureRect.new()
	art.texture = AssetDB.tex(str(offer.get("art_id", "pickup_qi")))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_panel.add_child(art)
	var name := Label.new()
	name.text = str(offer["name"])
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_size_override("font_size", 25)
	name.add_theme_color_override("font_color", Color("#fff8e8"))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	var kind := Label.new()
	kind.text = "%s · %s" % [_kind_name(str(offer["kind"])), _offer_school_name(offer)]
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_font_size_override("font_size", 17)
	kind.add_theme_color_override("font_color", Color("#e8b259"))
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(kind)
	var summary := Label.new()
	summary.text = str(offer.get("summary", ""))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size = Vector2(0, 42)
	summary.add_theme_font_size_override("font_size", 15)
	summary.add_theme_color_override("font_color", Color("#cfe5e0"))
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(summary)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rows)
	for row in _offer_effect_rows(offer).slice(0, 4):
		rows.add_child(_effect_row_control(row))
	b.pressed.connect(func(): _choose_offer(offer))
	return b

func _offer_art_id(id: String) -> String:
	return "offer_%s" % id

func _offer_school_name(offer: Dictionary) -> String:
	var data: Dictionary = offer.get("data", {})
	var element = data.get("element", data.get("school", null))
	if element == null or str(element) == "common":
		return "通用"
	return GameState.root_name(str(element))

func _offer_effect_rows(offer: Dictionary) -> Array:
	var rows: Array = []
	var data: Dictionary = offer.get("data", {})
	match str(offer.get("kind", "")):
		"weapon":
			var element := str(data.get("element", ""))
			var klass := str(data.get("class", ""))
			if klass == "shield":
				rows.append(_effect_row("max_qi_shield", "护盾生成", "+%.0f" % max(10.0, float(data.get("base_damage", 0.0)) + 10.0), element))
			else:
				rows.append(_effect_row("%s_damage_pct" % element, "%s伤害" % GameState.root_name(element), "%.0f" % float(data.get("base_damage", 0.0)), element))
			rows.append(_effect_row("attack_speed", "冷却", "%.2fs" % float(data.get("cooldown", 0.0)), element))
			if float(data.get("range", 0.0)) > 0.0:
				rows.append(_effect_row("range_pct", "射程", "%.0f" % float(data.get("range", 0.0)), element))
			for effect in data.get("on_hit", []):
				rows.append(_on_hit_row(effect, element))
		"item":
			for key in data.get("effects", {}).keys():
				rows.append(_stat_effect_row(str(key), data["effects"][key], false))
			for key in data.get("cost_effects", {}).keys():
				rows.append(_stat_effect_row(str(key), data["cost_effects"][key], true))
		"skill":
			for key in data.get("effects", {}).keys():
				rows.append(_stat_effect_row(str(key), data["effects"][key], false))
	return rows

func _effect_row(key: String, label: String, value: String, element := "") -> Dictionary:
	return {"key": key, "label": label, "value": value, "icon": _effect_icon_id(key, element), "color": _effect_color(key, element)}

func _stat_effect_row(key: String, value, cost := false) -> Dictionary:
	var text := _effect_value_text(key, value)
	if cost and not text.begins_with("-") and text != "启用":
		if text.begins_with("+"):
			text = text.substr(1)
		text = "+" + text
	var row := _effect_row(key, _effect_label(key), text)
	if cost:
		row["label"] = "代价 · %s" % row["label"]
		row["color"] = Color("#f27348")
	return row

func _on_hit_row(effect: Dictionary, element: String) -> Dictionary:
	var kind := str(effect.get("effect", ""))
	match kind:
		"poison":
			return _effect_row("poison", "中毒", "%.0f/s %.1fs" % [float(effect.get("dps", 0.0)), float(effect.get("dur", 0.0))], "wood")
		"bleed":
			return _effect_row("bleed", "流血", "%.0f/s %.1fs" % [float(effect.get("dps", 0.0)), float(effect.get("dur", 0.0))], "metal")
		"ignite":
			return _effect_row("ignite", "灼烧", "%.0f/s %.1fs" % [float(effect.get("dps", 0.0)), float(effect.get("dur", 0.0))], "fire")
		"slow":
			return _effect_row("slow", "减速", "-%.0f%% %.1fs" % [float(effect.get("value", 0.0)) * 100.0, float(effect.get("dur", 0.0))], "water")
		"chill_stack":
			return _effect_row("chill_stack", "寒意", "叠层", "water")
		"freeze":
			return _effect_row("freeze", "冻结", "触发", "water")
		"grant_shield", "shield_splash":
			return _effect_row("max_qi_shield", "护盾", "+%.0f" % float(effect.get("value", effect.get("scale_eng", 1.0))), "water")
		"crit_bonus":
			return _effect_row("crit_chance", "暴击", "+%.0f%%" % (float(effect.get("value", 0.0)) * 100.0), element)
		"knockback", "pull":
			return _effect_row("range_pct", "控场", "%.0f" % float(effect.get("value", 0.0)), element)
		"split_chance":
			return _effect_row("sword_split_chance", "分裂", "+%.0f%%" % (float(effect.get("value", 0.0)) * 100.0), "metal")
		"quake", "explode", "ignite_nova", "poison_burst":
			return _effect_row(kind, "范围爆发", "触发", element)
		"armor_up":
			return _effect_row("armor", "护甲", "+%.0f" % float(effect.get("value", 1.0)), "earth")
		"vulnerable", "execute_setup", "ignore_armor":
			return _effect_row("crit_chance", "破绽", "触发", element)
		_:
			return _effect_row(kind, _effect_label(kind), "触发", element)

func _effect_row_control(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 30)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color: Color = row.get("color", Color("#5fe0c8"))
	panel.add_theme_stylebox_override("panel", _stylebox(Color(color.r, color.g, color.b, 0.12), Color(color.r, color.g, color.b, 0.32), 1, 4))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.texture = AssetDB.tex(str(row.get("icon", "pickup_qi")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)
	var label := Label.new()
	label.text = str(row.get("label", ""))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("#eaf6ff"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)
	var value := Label.new()
	value.text = str(row.get("value", ""))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", color)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(value)
	return panel

func _kind_name(kind: String) -> String:
	match kind:
		"weapon":
			return "法器"
		"item":
			return "法宝"
		"skill":
			return "心法"
		_:
			return kind

func _effect_label(key: String) -> String:
	match key:
		"sword_power":
			return "剑意"
		"spell_power":
			return "法力"
		"engineering":
			return "御器"
		"damage_pct":
			return "全伤"
		"element_pct":
			return "元素"
		"metal_damage_pct":
			return "金伤"
		"wood_damage_pct":
			return "木伤"
		"water_damage_pct":
			return "水伤"
		"fire_damage_pct":
			return "火伤"
		"earth_damage_pct":
			return "土伤"
		"crit_chance":
			return "暴击"
		"crit_mult":
			return "暴伤"
		"dodge":
			return "身法"
		"armor":
			return "护甲"
		"speed_pct":
			return "移速"
		"attack_speed":
			return "攻速"
		"range_pct":
			return "范围"
		"lifesteal":
			return "噬灵"
		"luck":
			return "气运"
		"harvesting":
			return "摄物"
		"max_hp":
			return "气血"
		"hp_regen":
			return "回气"
		"max_qi_shield":
			return "护盾"
		"qi_shield_delay":
			return "回盾延迟"
		"sword_split_chance":
			return "分裂"
		"poison_contagion":
			return "毒扩散"
		"fire_execute":
			return "斩杀"
		"execute_threshold":
			return "斩杀线"
		"execute_mult":
			return "斩杀倍率"
		"melee_quake_wave":
			return "震荡"
		"quake_radius":
			return "震荡范围"
		"root_conversion_bonus":
			return "互济"
		_:
			return key

func _effect_value_text(key: String, value) -> String:
	if typeof(value) == TYPE_BOOL:
		return "启用" if bool(value) else "关闭"
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return str(value)
	var amount := float(value)
	if _is_percent_key(key):
		return _signed_number(amount * 100.0, 0) + "%"
	if key == "qi_shield_delay":
		return _signed_number(amount, 1) + "s"
	if abs(amount) < 1.0 and not is_zero_approx(amount):
		return _signed_number(amount * 100.0, 0) + "%"
	if is_equal_approx(amount, round(amount)):
		return _signed_number(amount, 0)
	return _signed_number(amount, 1)

func _is_percent_key(key: String) -> bool:
	return key.ends_with("_pct") or key in ["crit_chance", "crit_mult", "dodge", "attack_speed", "lifesteal", "sword_split_chance", "execute_threshold", "execute_mult", "root_conversion_bonus"]

func _signed_number(amount: float, decimals: int) -> String:
	var absolute: float = abs(amount)
	var body := ""
	match decimals:
		0:
			body = str(int(round(absolute)))
		1:
			body = "%.1f" % absolute
		_:
			body = "%.2f" % absolute
	if amount > 0.0:
		return "+" + body
	if amount < 0.0:
		return "-" + body
	return body

func _effect_icon_id(key: String, element := "") -> String:
	if key.find("shield") >= 0 or key == "max_qi_shield":
		return "icon_shield"
	if key.find("crit") >= 0 or key.find("execute") >= 0:
		return "icon_crit"
	if key.find("speed") >= 0:
		return "offer_stat_attack_speed"
	if key.find("range") >= 0 or key == "harvesting":
		return "offer_stat_range"
	if key.find("hp") >= 0 or key == "lifesteal":
		return "offer_blood_return"
	if key == "armor":
		return "offer_thick_earth_armor"
	if key == "luck":
		return "offer_lucky_coin"
	if key.find("poison") >= 0:
		return "icon_wood"
	if key.find("ignite") >= 0 or key.find("fire") >= 0:
		return "icon_fire"
	if key.find("water") >= 0 or key.find("slow") >= 0 or key.find("chill") >= 0 or key.find("freeze") >= 0:
		return "icon_water"
	if key.find("earth") >= 0 or key.find("quake") >= 0:
		return "icon_earth"
	if key.find("wood") >= 0:
		return "icon_wood"
	if key.find("metal") >= 0 or key.find("sword") >= 0 or key.find("bleed") >= 0:
		return "icon_metal"
	match element:
		"metal", "wood", "water", "fire", "earth":
			return "icon_%s" % element
		_:
			return "pickup_qi"

func _effect_color(key: String, element := "") -> Color:
	if key.find("shield") >= 0 or key == "max_qi_shield":
		return Color("#5aa9e0")
	if key.find("crit") >= 0 or key.find("fire") >= 0 or key.find("ignite") >= 0:
		return Color("#f27348")
	if key.find("poison") >= 0 or key.find("wood") >= 0:
		return Color("#7ccb5a")
	if key.find("water") >= 0 or key.find("slow") >= 0 or key.find("freeze") >= 0:
		return Color("#5aa9e0")
	if key.find("earth") >= 0 or key == "armor" or key.find("quake") >= 0:
		return Color("#d9a441")
	if key.find("metal") >= 0 or key.find("sword") >= 0 or key.find("bleed") >= 0:
		return Color("#eaf6ff")
	return _element_color(element)

func _element_color(element: String) -> Color:
	match element:
		"metal":
			return Color("#eaf6ff")
		"wood":
			return Color("#7ccb5a")
		"water":
			return Color("#5aa9e0")
		"fire":
			return Color("#f27348")
		"earth":
			return Color("#d9a441")
		_:
			return Color("#5fe0c8")

func _choose_offer(offer: Dictionary) -> void:
	match offer["kind"]:
		"weapon":
			GameState.equip_weapon(str(offer["id"]))
		"item":
			if not GameState.add_item(str(offer["id"])):
				GameState.stones += 6
		"skill":
			GameState.apply_skill(str(offer["id"]))
	SignalsBus.market_choice.emit(offer["id"])
	market_open = false
	overlay_layer.queue_free()
	overlay_layer = CanvasLayer.new()
	add_child(overlay_layer)
	_update_hud()

func _on_ascension(realm_name: String) -> void:
	message_label.text = "渡劫成功 · %s" % realm_name
	_spawn_fx(player.global_position, "fx_ascend", 0.8)
	player.hp = float(GameState.stats.get("max_hp", 110))
	player.shield = float(GameState.stats.get("max_qi_shield", 60))
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_callback(func():
		message_label.text = ""
		_open_market("机缘大开")
	)

func _update_hud() -> void:
	hp_bar.max_value = float(GameState.stats.get("max_hp", 110))
	hp_bar.value = player.hp
	shield_bar.max_value = float(GameState.stats.get("max_qi_shield", 60))
	shield_bar.value = player.shield
	xp_bar.max_value = GameState.xp_to_next
	xp_bar.value = GameState.xp
	hp_value_label.text = "气血 %.0f / %.0f" % [player.hp, float(GameState.stats.get("max_hp", 110))]
	shield_value_label.text = "护盾 %.0f / %.0f" % [player.shield, float(GameState.stats.get("max_qi_shield", 60))]
	xp_value_label.text = "Lv.%d  灵气 %.0f / %.0f" % [GameState.level, GameState.xp, GameState.xp_to_next]
	var roots := []
	for e in GameState.active_roots:
		roots.append(GameState.root_name(e))
	info_label.text = "%02d:%02d  %s Lv.%d\n斩妖 %d  灵石 %d  聚剑 %.1fs\n灵根 %s" % [
		int(GameState.run_time / 60.0),
		int(GameState.run_time) % 60,
		GameState.realm_name,
		GameState.level,
		GameState.kills,
		GameState.stones,
		burst_cd,
		"".join(roots)
	]
	for i in range(weapon_slot_buttons.size()):
		var slot: Button = weapon_slot_buttons[i]
		if i < GameState.active_weapons.size():
			var w: Dictionary = GameState.active_weapons[i]
			slot.icon = AssetDB.tex(_offer_art_id(str(w.get("id", ""))))
			slot.tooltip_text = _weapon_tooltip(i, w)
		else:
			slot.icon = AssetDB.tex("pickup_qi")
			slot.tooltip_text = "空法器槽"
	for entry in stat_icon_buttons:
		var button: Button = entry["button"]
		var def: Dictionary = entry["def"]
		button.icon = AssetDB.tex(str(def["icon"]))
		button.tooltip_text = _stat_tooltip(def)

func _weapon_tooltip(index: int, weapon: Dictionary) -> String:
	var element := str(weapon.get("element", ""))
	var lines := [
		"%d. %s T%d" % [index + 1, str(weapon.get("name", "")), int(weapon.get("tier", 1))],
		"%s · %s" % [GameState.root_name(element), str(weapon.get("class", ""))],
		"伤害 %.0f  冷却 %.2fs  射程 %.0f" % [float(weapon.get("base_damage", 0.0)), float(weapon.get("cooldown", 0.0)), float(weapon.get("range", 0.0))]
	]
	for effect in weapon.get("on_hit", []):
		var row := _on_hit_row(effect, element)
		lines.append("%s %s" % [row.get("label", ""), row.get("value", "")])
	return "\n".join(lines)

func _stat_tooltip(def: Dictionary) -> String:
	var key := str(def["key"])
	var label := str(def["label"])
	var current = GameState.stats.get(key, 0.0)
	var value := _effect_value_text(key, current)
	if key == "speed_pct":
		value = "%.0f%%" % ((1.0 + float(current)) * 100.0)
	var extra := ""
	if key == "damage_pct":
		extra = "\n多系倍率 %.0f%%" % (GameState.multi_element_multiplier() * 100.0)
	elif key == "lifesteal":
		extra = "\n背包 %d/%d" % [GameState.bag.size(), int(GameState.stats.get("bag_capacity", 5))]
	return "%s：%s%s" % [label, value, extra]

func _finish_run(title: String, _reason: String) -> void:
	var roots := []
	for e in GameState.active_roots:
		roots.append(GameState.root_name(e))
	var result := {
		"title": title,
		"time": GameState.run_time,
		"realm": GameState.realm_name,
		"kills": GameState.kills,
		"combo": GameState.combo,
		"jade": int(GameState.kills / 14) + (18 if title == "道成" else 4),
		"essence": boss_index,
		"roots": roots
	}
	SignalsBus.run_ended.emit(result, result)
	run_ended.emit(result)

func _on_shake(intensity: float, duration: float) -> void:
	if not bool(SaveSystem.settings.get("screen_shake", true)):
		return
	shake_power = max(shake_power, intensity)
	shake_time = max(shake_time, duration)

func _shake_offset() -> Vector2:
	if shake_time <= 0.0:
		return Vector2.ZERO
	shake_time -= get_physics_process_delta_time()
	return Vector2(rng.randf_range(-shake_power, shake_power), rng.randf_range(-shake_power, shake_power))

func _on_hitstop(duration: float) -> void:
	hitstop = max(hitstop, duration)
