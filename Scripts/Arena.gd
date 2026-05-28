extends Node2D

signal run_ended(result)

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const ENEMY_SCENE := preload("res://Scenes/Enemies/Enemy.tscn")
const PROJECTILE_SCENE := preload("res://Scenes/Weapon/Projectile.tscn")

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
	bars.add_child(shield_bar)
	bars.add_child(xp_bar)
	info_label = Label.new()
	info_label.custom_minimum_size = Vector2(460, 90)
	info_label.add_theme_font_size_override("font_size", 25)
	info_label.add_theme_color_override("font_color", Color("#eaf6ff"))
	top.add_child(info_label)
	weapon_label = Label.new()
	weapon_label.custom_minimum_size = Vector2(520, 90)
	weapon_label.add_theme_font_size_override("font_size", 21)
	weapon_label.add_theme_color_override("font_color", Color("#f4ecd8"))
	top.add_child(weapon_label)
	stats_label = Label.new()
	stats_label.anchor_left = 0.02
	stats_label.anchor_top = 0.82
	stats_label.anchor_right = 0.98
	stats_label.anchor_bottom = 0.98
	stats_label.add_theme_font_size_override("font_size", 20)
	stats_label.add_theme_color_override("font_color", Color("#eaf6ff"))
	root.add_child(stats_label)
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
		player.shield = min(float(GameState.stats.get("max_qi_shield", 60)), player.shield + 10.0 + float(GameState.stats.get("engineering", 0.0)))
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

func _hit_enemy(weapon: Dictionary, enemy: LingxuEnemy) -> void:
	var result := GameState.calculate_weapon_damage(weapon, enemy)
	enemy.take_damage(float(result["amount"]), bool(result["is_crit"]), str(result["element"]))
	player.heal_from_lifesteal(float(result["amount"]))
	SignalsBus.hud_request_hitstop.emit(0.02)

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
	for offer in _roll_offers(4):
		cards.add_child(_offer_button(offer))
	SignalsBus.market_offered.emit(cards)

func _roll_offers(count: int) -> Array:
	var result: Array = []
	var pool: Array = []
	for id in GameState.filtered_ids("weapons"):
		var w := ConfigDB.entry("weapons", id)
		if bool(w.get("legendary", false)) and GameState.realm != "huashen":
			continue
		pool.append({"kind": "weapon", "id": id, "name": w.get("name", id), "summary": "%s法器 · %s伤害 %.0f" % [GameState.root_name(w.get("element", "")), w.get("class", ""), float(w.get("base_damage", 0))], "art_id": w.get("art_id", "icon_metal")})
	for id in GameState.filtered_ids("items"):
		var item := ConfigDB.entry("items", id)
		pool.append({"kind": "item", "id": id, "name": item.get("name", id), "summary": item.get("summary", ""), "art_id": item.get("art_id", "pickup_qi")})
	for id in GameState.filtered_ids("skills"):
		var skill := ConfigDB.entry("skills", id)
		pool.append({"kind": "skill", "id": id, "name": skill.get("name", id), "summary": skill.get("summary", ""), "art_id": skill.get("art_id", "fx_slash")})
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
	b.custom_minimum_size = Vector2(410, 360)
	b.text = "%s\n\n%s\n\n%s" % [offer["name"], _kind_name(offer["kind"]), offer["summary"]]
	b.icon = AssetDB.tex(str(offer.get("art_id", "pickup_qi")))
	b.expand_icon = true
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func(): _choose_offer(offer))
	return b

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
	var w_lines := []
	for i in range(GameState.active_weapons.size()):
		var w: Dictionary = GameState.active_weapons[i]
		w_lines.append("%d.%s %s T%d" % [i + 1, GameState.root_name(w.get("element", "")), w.get("name", ""), int(w.get("tier", 1))])
	weapon_label.text = "四法器槽 · 多系倍率 %.0f%%\n%s" % [GameState.multi_element_multiplier() * 100.0, "\n".join(w_lines)]
	stats_label.text = "气血 %.0f/%.0f  护盾 %.0f/%.0f  全伤 %.0f%%  金/木/水/火/土 %.0f/%.0f/%.0f/%.0f/%.0f%%  暴击 %.0f%%  闪避 %.0f%%  护甲 %.0f  移速 %.0f%%  攻速 %.0f%%  范围 %.0f%%  吸血 %.0f%%  气运 %.0f  背包 %d/%d" % [
		player.hp,
		float(GameState.stats.get("max_hp", 110)),
		player.shield,
		float(GameState.stats.get("max_qi_shield", 60)),
		float(GameState.stats.get("damage_pct", 0.0)) * 100.0,
		float(GameState.stats.get("metal_damage_pct", 0.0)) * 100.0,
		float(GameState.stats.get("wood_damage_pct", 0.0)) * 100.0,
		float(GameState.stats.get("water_damage_pct", 0.0)) * 100.0,
		float(GameState.stats.get("fire_damage_pct", 0.0)) * 100.0,
		float(GameState.stats.get("earth_damage_pct", 0.0)) * 100.0,
		float(GameState.stats.get("crit_chance", 0.0)) * 100.0,
		float(GameState.stats.get("dodge", 0.0)) * 100.0,
		float(GameState.stats.get("armor", 0.0)),
		(1.0 + float(GameState.stats.get("speed_pct", 0.0))) * 100.0,
		float(GameState.stats.get("attack_speed", 0.0)) * 100.0,
		float(GameState.stats.get("range_pct", 0.0)) * 100.0,
		float(GameState.stats.get("lifesteal", 0.0)) * 100.0,
		float(GameState.stats.get("luck", 0.0)),
		GameState.bag.size(),
		int(GameState.stats.get("bag_capacity", 5))
	]

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
