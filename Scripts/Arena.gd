extends Node2D

signal run_ended(result)

const FontUtil := preload("res://Scripts/FontUtil.gd")
const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const ENEMY_SCENE := preload("res://Scenes/Enemies/Enemy.tscn")
const PROJECTILE_SCENE := preload("res://Scenes/Weapon/Projectile.tscn")
const DISPLAY_FONT := preload("res://assets/fonts/MaShanZheng-Regular.ttf")
const BODY_FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
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
const OFFER_CARD_SIZE := Vector2(320, 492)
const OFFER_EFFECT_ROW_LIMIT := 4
const WEAPON_FEEDBACK_Z := 18
const WEAPON_HIT_FEEDBACK_DURATION := 0.22
const WEAPON_CAST_FEEDBACK_DURATION := 0.34

var player: YunxiPlayer
var enemies: Array = []
var projectiles: Array = []
var enemy_projectiles: Array = []
var enemy_area_attacks: Array = []
var pending_spawns: Array = []
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
var detail_layer: CanvasLayer
var hp_bar: ProgressBar
var shield_bar: ProgressBar
var xp_bar: ProgressBar
var info_label: Label
var stats_label: Label
var weapon_label: Label
var hp_value_label: Label
var shield_value_label: Label
var xp_value_label: Label
var bag_title_label: Label
var item_panel: PanelContainer
var weapon_slot_buttons: Array = []
var weapon_reserve_buttons: Array = []
var item_slot_buttons: Array = []
var stat_rows: Array = []
var message_label: Label
var market_notice_label: Label
var market_mode := "choice"
var market_reason := ""
var market_offers: Array = []
var market_notice_text := ""
var market_choice_completed := false
var market_selected_offer_id := ""
var next_spirit_shop_time := 60.0
var weapon_drag_source := {}
var suppress_next_weapon_detail := false

func _ready() -> void:
	FontUtil.ensure_fallback(DISPLAY_FONT, BODY_FONT)
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
	var stat_panel := PanelContainer.new()
	stat_panel.name = "HudStatPanel"
	stat_panel.anchor_left = 1.0
	stat_panel.anchor_top = 0.0
	stat_panel.anchor_right = 1.0
	stat_panel.anchor_bottom = 0.0
	stat_panel.offset_left = -220
	stat_panel.offset_top = 150
	stat_panel.offset_right = -28
	stat_panel.offset_bottom = 670
	stat_panel.add_theme_stylebox_override("panel", _compact_stylebox(Color(0.018, 0.032, 0.038, 0.76), Color("#5fe0c8"), 1, 6, 5, 4))
	root.add_child(stat_panel)
	var stat_box := VBoxContainer.new()
	stat_box.add_theme_constant_override("separation", 3)
	stat_panel.add_child(stat_box)
	var stat_title := Label.new()
	stat_title.text = "数值"
	stat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_title.add_theme_font_size_override("font_size", 15)
	stat_title.add_theme_color_override("font_color", Color("#e8b259"))
	stat_box.add_child(stat_title)
	stat_rows.clear()
	for def in HUD_STAT_DEFS:
		var stat_entry := _stat_row_control(def)
		var stat_def: Dictionary = def.duplicate(true)
		var panel: PanelContainer = stat_entry["panel"]
		panel.gui_input.connect(func(event): _on_stat_gui_input(event, stat_def))
		stat_box.add_child(stat_entry["panel"])
		stat_rows.append(stat_entry)
	var weapon_panel := PanelContainer.new()
	weapon_panel.name = "HudWeaponPanel"
	weapon_panel.anchor_left = 1.0
	weapon_panel.anchor_top = 0.0
	weapon_panel.anchor_right = 1.0
	weapon_panel.anchor_bottom = 0.0
	weapon_panel.offset_left = -410
	weapon_panel.offset_top = 24
	weapon_panel.offset_right = -28
	weapon_panel.offset_bottom = 132
	weapon_panel.add_theme_stylebox_override("panel", _compact_stylebox(Color(0.02, 0.04, 0.045, 0.72), Color("#5fe0c8"), 1, 6, 6, 5))
	root.add_child(weapon_panel)
	var weapon_box := VBoxContainer.new()
	weapon_box.add_theme_constant_override("separation", 5)
	weapon_panel.add_child(weapon_box)
	var weapon_title := Label.new()
	weapon_title.text = "装备"
	weapon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_title.add_theme_font_size_override("font_size", 16)
	weapon_title.add_theme_color_override("font_color", Color("#e8b259"))
	weapon_box.add_child(weapon_title)
	var weapon_slots := HBoxContainer.new()
	weapon_slots.add_theme_constant_override("separation", 6)
	weapon_box.add_child(weapon_slots)
	weapon_slot_buttons.clear()
	for i in range(4):
		var slot := _hud_icon_button(Vector2(48, 48))
		var slot_index := i
		slot.pressed.connect(func(): _show_weapon_detail("active", slot_index))
		slot.gui_input.connect(func(event): _on_weapon_slot_gui_input(event, "active", slot_index))
		weapon_slots.add_child(slot)
		weapon_slot_buttons.append(slot)
	var reserve_label := Label.new()
	reserve_label.text = "备炼"
	reserve_label.add_theme_font_size_override("font_size", 14)
	reserve_label.add_theme_color_override("font_color", Color("#c8a2ff"))
	weapon_slots.add_child(reserve_label)
	var reserve_slots := HBoxContainer.new()
	reserve_slots.add_theme_constant_override("separation", 6)
	weapon_slots.add_child(reserve_slots)
	weapon_reserve_buttons.clear()
	for i in range(GameState.weapon_reserve_capacity()):
		var slot := _hud_icon_button(Vector2(48, 48))
		var slot_index := i
		slot.pressed.connect(func(): _show_weapon_detail("reserve", slot_index))
		slot.gui_input.connect(func(event): _on_weapon_slot_gui_input(event, "reserve", slot_index))
		reserve_slots.add_child(slot)
		weapon_reserve_buttons.append(slot)
	item_panel = PanelContainer.new()
	item_panel.anchor_left = 0.02
	item_panel.anchor_top = 1.0
	item_panel.anchor_right = 0.02
	item_panel.anchor_bottom = 1.0
	item_panel.offset_top = -112
	item_panel.offset_right = 270
	item_panel.offset_bottom = -28
	item_panel.add_theme_stylebox_override("panel", _compact_stylebox(Color(0.035, 0.027, 0.042, 0.72), Color("#c8a2ff"), 1, 6, 7, 5))
	root.add_child(item_panel)
	var item_box := VBoxContainer.new()
	item_box.add_theme_constant_override("separation", 6)
	item_panel.add_child(item_box)
	bag_title_label = Label.new()
	bag_title_label.text = "道具"
	bag_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_title_label.add_theme_font_size_override("font_size", 16)
	bag_title_label.add_theme_color_override("font_color", Color("#e8b259"))
	item_box.add_child(bag_title_label)
	var item_slots := GridContainer.new()
	item_slots.columns = 5
	item_slots.add_theme_constant_override("h_separation", 6)
	item_slots.add_theme_constant_override("v_separation", 6)
	item_box.add_child(item_slots)
	item_slot_buttons.clear()
	var max_bag_slots: int = int(max(int(GameState.stats.get("bag_capacity", 5)), int(GameState.stats.get("bag_capacity_max", 10))))
	for i in range(max_bag_slots):
		var slot := _hud_icon_button(Vector2(42, 42))
		var slot_index := i
		slot.pressed.connect(func(): _show_item_detail(slot_index))
		item_slots.add_child(slot)
		item_slot_buttons.append(slot)
	message_label = Label.new()
	message_label.anchor_left = 0.27
	message_label.anchor_top = 0.38
	message_label.anchor_right = 0.73
	message_label.anchor_bottom = 0.48
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_display_font(message_label, 54, Color("#e8b259"), 3)
	root.add_child(message_label)
	overlay_layer = CanvasLayer.new()
	add_child(overlay_layer)
	detail_layer = CanvasLayer.new()
	detail_layer.layer = 20
	add_child(detail_layer)

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
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", _stylebox(Color(0.03, 0.055, 0.06, 0.9), Color(0.35, 0.88, 0.82, 0.34), 1, 5))
	b.add_theme_stylebox_override("hover", _stylebox(Color(0.05, 0.09, 0.1, 0.96), Color("#e8b259"), 2, 5))
	b.add_theme_stylebox_override("pressed", _stylebox(Color(0.08, 0.1, 0.09, 0.98), Color("#e8b259"), 2, 5))
	return b

func _stat_row_control(def: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 30)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_theme_stylebox_override("panel", _compact_stylebox(Color(0.03, 0.055, 0.06, 0.74), Color(0.35, 0.88, 0.82, 0.28), 1, 5, 4, 3))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	panel.add_child(line)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)
	var label := Label.new()
	label.text = str(def.get("label", ""))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("#cfe5e0"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)
	var value := Label.new()
	value.custom_minimum_size = Vector2(46, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", Color("#eaf6ff"))
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(value)
	return {"panel": panel, "icon": icon, "label": label, "value": value, "def": def}

func _set_weapon_button_style(button: Button, tier: int, empty := false) -> void:
	if empty:
		button.add_theme_stylebox_override("normal", _stylebox(Color(0.03, 0.055, 0.06, 0.9), Color(0.35, 0.88, 0.82, 0.34), 1, 5))
		button.add_theme_stylebox_override("hover", _stylebox(Color(0.05, 0.09, 0.1, 0.96), Color("#e8b259"), 2, 5))
		button.add_theme_stylebox_override("pressed", _stylebox(Color(0.08, 0.1, 0.09, 0.98), Color("#e8b259"), 2, 5))
		return
	var tier_color := GameState.weapon_tier_color(tier)
	button.add_theme_stylebox_override("normal", _stylebox(Color(tier_color.r, tier_color.g, tier_color.b, 0.18), Color(tier_color.r, tier_color.g, tier_color.b, 0.74), 2, 5))
	button.add_theme_stylebox_override("hover", _stylebox(Color(tier_color.r, tier_color.g, tier_color.b, 0.28), Color("#fff4b8"), 2, 5))
	button.add_theme_stylebox_override("pressed", _stylebox(Color(tier_color.r, tier_color.g, tier_color.b, 0.34), Color("#e8b259"), 2, 5))

func _set_item_button_style(button: Button, item: Dictionary, empty := false) -> void:
	if empty:
		button.add_theme_stylebox_override("normal", _stylebox(Color(0.035, 0.027, 0.042, 0.78), Color(0.78, 0.64, 1.0, 0.26), 1, 5))
		button.add_theme_stylebox_override("hover", _stylebox(Color(0.05, 0.04, 0.065, 0.92), Color("#e8b259"), 2, 5))
		button.add_theme_stylebox_override("pressed", _stylebox(Color(0.07, 0.055, 0.08, 0.95), Color("#e8b259"), 2, 5))
		return
	var element_value = item.get("element", null)
	var element := "" if element_value == null else str(element_value)
	var item_color := _element_color(element)
	button.add_theme_stylebox_override("normal", _stylebox(Color(item_color.r, item_color.g, item_color.b, 0.16), Color(item_color.r, item_color.g, item_color.b, 0.62), 2, 5))
	button.add_theme_stylebox_override("hover", _stylebox(Color(item_color.r, item_color.g, item_color.b, 0.25), Color("#fff4b8"), 2, 5))
	button.add_theme_stylebox_override("pressed", _stylebox(Color(item_color.r, item_color.g, item_color.b, 0.32), Color("#e8b259"), 2, 5))

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
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = 7
	box.shadow_offset = Vector2(0, 2)
	return box

func _compact_stylebox(bg: Color, border: Color, border_width: int, radius: int, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	box.shadow_color = Color(0, 0, 0, 0.24)
	box.shadow_size = 5
	box.shadow_offset = Vector2(0, 2)
	return box

func _apply_display_font(control: Control, size: int, color: Color, outline_size := 0) -> void:
	control.add_theme_font_override("font", DISPLAY_FONT)
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	if outline_size > 0:
		control.add_theme_constant_override("outline_size", outline_size)
		control.add_theme_color_override("font_outline_color", Color(0.02, 0.035, 0.032, 0.92))

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
	if GameState.run_time >= next_spirit_shop_time:
		next_spirit_shop_time += 60.0
		_open_spirit_shop()
		return
	burst_cd = max(0.0, burst_cd - delta)
	player.tick(delta, arena_radius)
	camera.global_position = player.global_position + _shake_offset()
	_update_enemies(delta)
	_update_enemy_projectiles(delta)
	_update_enemy_area_attacks(delta)
	_update_weapons(delta)
	_update_projectiles(delta)
	_update_pickups(delta)
	_update_spawn_warnings(delta)
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
			_fire_weapon(weapon, i)
			var interval := float(weapon.get("cooldown", 1.0))
			interval /= 1.0 + max(-0.75, float(GameState.stats.get("attack_speed", 0.0)))
			interval *= 1.0 - clamp(float(GameState.stats.get("attack_interval_pct", 0.0)), -0.5, 0.5)
			weapon_cds[i] = max(0.12, interval)

func _reset_weapon_cooldowns() -> void:
	weapon_cds.resize(GameState.active_weapons.size())
	for i in range(weapon_cds.size()):
		weapon_cds[i] = rng.randf_range(0.05, 0.35)

func _fire_weapon(weapon: Dictionary, slot_index := -1) -> void:
	var klass := str(weapon.get("class", "flying_sword"))
	var origin := _weapon_origin(slot_index)
	if klass == "shield":
		_play_weapon_release(weapon, slot_index, player.global_position)
		var shield_gain := 10.0
		for effect in weapon.get("on_hit", []):
			if str(effect.get("effect", "")) == "grant_shield":
				var scale_eng := float(effect.get("scale_eng", 1.0))
				var tier_mult := GameState.weapon_tier_multiplier(int(weapon.get("tier", 1)))
				shield_gain += (8.0 + float(GameState.stats.get("engineering", 0.0))) * scale_eng * tier_mult
		_add_player_shield(shield_gain)
		_spawn_shield_feedback(weapon, player.global_position, shield_gain)
		return
	if klass == "orbit" or klass == "aura":
		_play_weapon_release(weapon, slot_index, player.global_position + player.facing * 80.0)
		var hit_range := float(weapon.get("range", 180)) * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
		var hit_limit := -1
		if klass == "orbit":
			hit_limit = max(2, int(weapon.get("tier", 1)) + 2)
		_spawn_orbit_feedback(weapon, player.global_position, hit_range, klass)
		for enemy in _enemies_in_radius(player.global_position, hit_range, hit_limit, true):
			_hit_enemy(weapon, enemy)
		return
	var target := _select_target(weapon)
	if target == null:
		return
	var target_pos := target.global_position
	_play_weapon_release(weapon, slot_index, target_pos)
	if klass == "area":
		var radius := float(weapon.get("radius", 110)) * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
		_spawn_area_feedback(weapon, target_pos, radius, "area")
		_hit_area_weapon(weapon, target_pos, radius)
		return
	if klass == "talisman":
		var radius := float(weapon.get("radius", 88)) * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
		_spawn_area_feedback(weapon, target_pos, radius, "talisman")
		_hit_area_weapon(weapon, target_pos, radius, 5)
		return
	if klass == "dash_blade":
		_spawn_line_feedback(weapon, origin, target_pos, 34.0, "dash")
		_hit_line_weapon(weapon, origin, target_pos, 42.0, int(weapon.get("pierce", 1)) + 1)
		return
	if klass == "hammer":
		var radius := float(weapon.get("radius", 86)) * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
		_spawn_slam_feedback(weapon, origin, target_pos, radius)
		_hit_area_weapon(weapon, target_pos, radius, 4)
		return
	if klass == "spike":
		_spawn_spike_feedback(weapon, origin, target_pos)
		_hit_line_weapon(weapon, origin, target_pos, 34.0, int(weapon.get("pierce", 2)) + 1)
		return
	if klass == "needle":
		_spawn_fan_feedback(weapon, origin, target_pos, 4, 0.12)
		_fire_spread_projectiles(weapon, origin, target_pos, 4, 0.12, 0.46, {"hit_radius": 12.0, "visual_scale": 0.085, "proj_speed": float(weapon.get("proj_speed", 720.0)) * 1.08})
		return
	if klass == "thorn":
		_spawn_fan_feedback(weapon, origin, target_pos, 3, 0.20)
		_fire_spread_projectiles(weapon, origin, target_pos, 3, 0.20, 0.68, {"hit_radius": 16.0, "visual_scale": 0.105})
		return
	if klass == "summon":
		_spawn_summon_feedback(weapon, origin, target.global_position)
		_fire_summon_projectiles(weapon, origin, target)
		return
	var projectile: LingxuProjectile = PROJECTILE_SCENE.instantiate()
	projectile.setup(weapon, origin, target_pos)
	add_child(projectile)
	projectiles.append(projectile)

func _play_weapon_release(weapon: Dictionary, slot_index: int, target_pos: Vector2) -> void:
	if player != null and player.has_method("trigger_weapon_attack"):
		player.trigger_weapon_attack(weapon, slot_index, target_pos)

func _weapon_origin(slot_index: int) -> Vector2:
	if player != null and player.has_method("weapon_muzzle_global_position"):
		return player.weapon_muzzle_global_position(slot_index)
	return player.global_position

func _spawn_weapon_projectile(weapon: Dictionary, origin: Vector2, target_pos: Vector2, angle_offset := 0.0) -> void:
	var aim := target_pos - origin
	if aim.length_squared() < 4.0:
		aim = player.facing if player != null else Vector2.RIGHT
	if aim.length_squared() < 0.01:
		aim = Vector2.RIGHT
	var projectile: LingxuProjectile = PROJECTILE_SCENE.instantiate()
	projectile.setup(weapon, origin, origin + aim.rotated(angle_offset))
	add_child(projectile)
	projectiles.append(projectile)

func _hit_area_weapon(weapon: Dictionary, center: Vector2, radius: float, max_hits := -1) -> void:
	for enemy in _enemies_in_radius(center, radius, max_hits, true):
		_hit_enemy(weapon, enemy, center)

func _hit_line_weapon(weapon: Dictionary, origin: Vector2, target_pos: Vector2, width: float, max_hits: int) -> void:
	var dir: Vector2 = target_pos - origin
	var length: float = dir.length()
	if length < 4.0:
		return
	var dir_norm: Vector2 = dir / length
	var candidates: Array = []
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var rel: Vector2 = enemy.global_position - origin
		var along: float = rel.dot(dir_norm)
		if along < -12.0 or along > length + 72.0:
			continue
		var closest: Vector2 = origin + dir_norm * along
		var hit_width: float = width + float(enemy.radius)
		if enemy.global_position.distance_squared_to(closest) <= hit_width * hit_width:
			candidates.append({"enemy": enemy, "along": along})
	candidates.sort_custom(func(a, b): return float(a["along"]) < float(b["along"]))
	var hits := 0
	for candidate in candidates:
		if max_hits > 0 and hits >= max_hits:
			break
		var enemy: LingxuEnemy = candidate["enemy"]
		_hit_enemy(weapon, enemy, enemy.global_position)
		hits += 1

func _fire_spread_projectiles(weapon: Dictionary, origin: Vector2, target_pos: Vector2, count: int, spread: float, damage_mult: float, overrides := {}) -> void:
	var middle := float(count - 1) * 0.5
	for i in range(count):
		var shot := _weapon_variant(weapon, damage_mult, overrides)
		var offset := (float(i) - middle) * spread
		_spawn_weapon_projectile(shot, origin, target_pos, offset)

func _fire_summon_projectiles(weapon: Dictionary, origin: Vector2, primary: LingxuEnemy) -> void:
	var count := 2 + clampi(int(weapon.get("tier", 1)), 1, 4)
	var hit_range := float(weapon.get("range", 420)) * (1.0 + float(GameState.stats.get("range_pct", 0.0)))
	var targets := _enemies_in_radius(player.global_position, hit_range, count, true)
	for i in range(count):
		var target_pos := primary.global_position
		if not targets.is_empty():
			var summon_target: LingxuEnemy = targets[i % targets.size()]
			target_pos = summon_target.global_position
		var angle := float(i) / float(count) * TAU
		var shot_origin := origin + Vector2.RIGHT.rotated(angle) * 22.0
		_spawn_summon_gate_feedback(weapon, shot_origin, target_pos, i)
		var shot := _weapon_variant(weapon, 0.42, {"hit_radius": 15.0, "visual_scale": 0.095, "proj_speed": float(weapon.get("proj_speed", 560.0)) * rng.randf_range(0.92, 1.12)})
		_spawn_weapon_projectile(shot, shot_origin, target_pos)

func _weapon_variant(weapon: Dictionary, damage_mult: float, overrides := {}) -> Dictionary:
	var variant := weapon.duplicate(true)
	variant["base_damage"] = max(1.0, float(weapon.get("base_damage", 1.0)) * damage_mult)
	for key in overrides.keys():
		variant[key] = overrides[key]
	return variant

func _enemies_in_radius(center: Vector2, radius: float, max_hits := -1, nearest_first := false) -> Array:
	var candidates: Array = []
	var radius_sq := radius * radius
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var d2 := center.distance_squared_to(enemy.global_position)
		if d2 <= radius_sq:
			candidates.append({"enemy": enemy, "d2": d2})
	if nearest_first:
		candidates.sort_custom(func(a, b): return float(a["d2"]) < float(b["d2"]))
	var result: Array = []
	for candidate in candidates:
		if max_hits > 0 and result.size() >= max_hits:
			break
		result.append(candidate["enemy"])
	return result

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
	var is_crit := bool(result.get("is_crit", false))
	enemy.take_damage(float(result["amount"]), is_crit, str(result["element"]))
	player.heal_from_lifesteal(float(result["amount"]))
	_apply_weapon_on_hit(weapon, enemy, target_pos, result, allow_secondary)
	_spawn_weapon_hit_feedback(weapon, target_pos, result, not allow_secondary)
	SignalsBus.hud_request_hitstop.emit(0.045 if is_crit else 0.02)
	if is_crit:
		SignalsBus.hud_request_shake.emit(6.0 if allow_secondary else 3.5, 0.09 if allow_secondary else 0.06)
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
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"slow":
				if is_instance_valid(enemy):
					enemy.apply_slow(float(effect.get("value", 0.22)), float(effect.get("dur", 1.5)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"chill_stack":
				if is_instance_valid(enemy):
					enemy.add_chill_stack(int(effect.get("stacks", 5)), float(effect.get("freeze_dur", 0.8)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"freeze":
				if is_instance_valid(enemy):
					enemy.apply_freeze(float(effect.get("dur", 1.0)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"petrify":
				if is_instance_valid(enemy):
					enemy.apply_petrify(float(effect.get("dur", 1.0)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"root":
				if is_instance_valid(enemy):
					enemy.apply_root(float(effect.get("dur", 0.6)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"stagger":
				if is_instance_valid(enemy):
					enemy.apply_root(float(effect.get("dur", 0.22)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"blind":
				if is_instance_valid(enemy):
					enemy.apply_slow(0.35, float(effect.get("dur", 1.2)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"vulnerable", "execute_setup":
				if is_instance_valid(enemy):
					enemy.apply_vulnerable(float(effect.get("value", 0.14)), float(effect.get("dur", 2.0)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"ignore_armor":
				if is_instance_valid(enemy):
					enemy.apply_vulnerable(float(effect.get("value", 0.12)), float(effect.get("dur", 2.2)))
				_spawn_fx(hit_pos, "fx_crit", 0.16)
			"knockback":
				if is_instance_valid(enemy):
					enemy.apply_knockback(player.global_position, float(effect.get("value", 20.0)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"pull":
				if is_instance_valid(enemy):
					enemy.apply_pull(player.global_position, float(effect.get("value", 18.0)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"quake":
				if allow_secondary:
					var radius := float(effect.get("radius", GameState.stats.get("quake_radius", weapon.get("radius", 120))))
					_spawn_area_feedback(weapon, hit_pos, radius, "quake")
					_secondary_aoe(weapon, hit_pos, radius, 0.38, element, false, true)
			"explode":
				if allow_secondary:
					var radius := float(effect.get("radius", weapon.get("radius", 115))) * 0.85
					_spawn_area_feedback(weapon, hit_pos, radius, "explode")
					_secondary_aoe(weapon, hit_pos, radius, float(effect.get("damage_mult", 0.42)), element, true, false)
			"ignite_nova":
				if allow_secondary:
					var radius := float(effect.get("radius", 230.0))
					_spawn_area_feedback(weapon, hit_pos, radius, "nova")
					_secondary_status_wave("ignite", element, hit_pos, radius, float(effect.get("dps", 6.0)), float(effect.get("dur", 3.0)), true)
			"poison_burst":
				if allow_secondary:
					var radius := float(effect.get("radius", 210.0))
					_spawn_area_feedback(weapon, hit_pos, radius, "poison_burst")
					_secondary_status_wave("poison", element, hit_pos, radius, float(effect.get("dps", 7.0)), float(effect.get("dur", 4.0)), true)
			"shield_splash":
				_add_player_shield(float(effect.get("value", 1.0)) + float(GameState.stats.get("engineering", 0.0)) * 0.15)
				_spawn_shield_feedback(weapon, player.global_position, float(effect.get("value", 1.0)))
			"armor_up":
				_add_player_shield(2.0 + float(effect.get("value", 1.0)) * 2.0)
				_spawn_shield_feedback(weapon, player.global_position, float(effect.get("value", 1.0)))
			"taunt":
				if is_instance_valid(enemy):
					enemy.apply_root(float(effect.get("dur", 0.35)))
					_spawn_status_feedback(weapon, hit_pos, kind, element)
			"split_chance":
				if allow_secondary and rng.randf() < float(effect.get("value", 0.1)):
					var split_target := _find_split_target(hit_pos, enemy, float(effect.get("radius", 260.0)))
					if split_target != null:
						var split_weapon := _make_secondary_weapon(weapon, 0.45, element)
						_spawn_line_feedback(weapon, hit_pos, split_target.global_position, 8.0, "split")
						_hit_enemy(split_weapon, split_target, split_target.global_position, false)
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

func spawn_enemy_projectile(origin: Vector2, target_pos: Vector2, projectile_data: Dictionary) -> void:
	var dir := target_pos - origin
	if dir.length_squared() < 4.0:
		dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
	var speed := float(projectile_data.get("speed", 280.0))
	var node := Node2D.new()
	node.name = "EnemyProjectile"
	node.global_position = origin
	node.z_index = 6
	var sprite := Sprite2D.new()
	sprite.texture = AssetDB.tex(str(projectile_data.get("art_id", "fx_fire")))
	sprite.scale = Vector2.ONE * float(projectile_data.get("visual_scale", 0.11))
	sprite.rotation = dir.angle()
	var element := str(projectile_data.get("element", "fire"))
	var tint := AssetDB.color_for_element(element)
	sprite.modulate = Color(tint.r, tint.g, tint.b, 0.94)
	node.add_child(sprite)
	add_child(node)
	enemy_projectiles.append({
		"node": node,
		"velocity": dir.normalized() * speed,
		"ttl": float(projectile_data.get("ttl", 3.2)),
		"radius": float(projectile_data.get("radius", 14.0)),
		"damage": float(projectile_data.get("damage", 7.0)),
		"element": element
	})

func _update_enemy_projectiles(delta: float) -> void:
	var keep: Array = []
	for projectile in enemy_projectiles:
		var node: Node2D = projectile.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		var velocity: Vector2 = projectile.get("velocity", Vector2.ZERO)
		node.position += velocity * delta
		node.rotation = velocity.angle()
		projectile["ttl"] = float(projectile.get("ttl", 0.0)) - delta
		var radius := float(projectile.get("radius", 14.0))
		if player != null and is_instance_valid(player):
			var hit_radius := radius + float(GameState.stats.get("body_radius", 22.0))
			if node.global_position.distance_squared_to(player.global_position) <= hit_radius * hit_radius:
				player.receive_damage(float(projectile.get("damage", 7.0)))
				_spawn_fx(node.global_position, "fx_%s" % str(projectile.get("element", "fire")), 0.18)
				node.queue_free()
				continue
		if float(projectile["ttl"]) <= 0.0:
			node.queue_free()
			continue
		keep.append(projectile)
	enemy_projectiles = keep

func queue_enemy_area_attack(center: Vector2, radius: float, delay: float, damage: float, element := "earth") -> void:
	var marker := _make_warning_marker(center, radius, AssetDB.color_for_element(element))
	marker["duration"] = max(0.05, delay)
	marker["time"] = max(0.05, delay)
	marker["damage"] = damage
	marker["element"] = element
	marker["flash_count"] = 3.0
	enemy_area_attacks.append(marker)

func _update_enemy_area_attacks(delta: float) -> void:
	var keep: Array = []
	for attack in enemy_area_attacks:
		attack["time"] = float(attack.get("time", 0.0)) - delta
		_animate_warning_marker(attack)
		if float(attack["time"]) > 0.0:
			keep.append(attack)
			continue
		var marker: Node2D = attack.get("node", null)
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
		var center: Vector2 = attack.get("pos", Vector2.ZERO)
		var radius := float(attack.get("radius", 70.0))
		if player != null and is_instance_valid(player):
			var body_radius := float(GameState.stats.get("body_radius", 22.0))
			if center.distance_squared_to(player.global_position) <= (radius + body_radius) * (radius + body_radius):
				player.receive_damage(float(attack.get("damage", 10.0)))
		_spawn_fx(center, "fx_%s" % str(attack.get("element", "earth")), 0.26)
	enemy_area_attacks = keep

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
	var pressure := enemies.size() + pending_spawns.size()
	if pressure >= cap:
		spawn_timer = 0.5
		return
	var pack: Array = wave.get("pack", [2, 4])
	var count: int = mini(rng.randi_range(int(pack[0]), int(pack[1])), cap - pressure)
	for i in range(count):
		var enemy_id := _pick_wave_enemy(wave)
		var mode := _pick_spawn_mode(wave)
		_queue_enemy_spawn(enemy_id, false, mode, _spawn_warning_delay(wave, mode))
	spawn_timer = max(0.16, float(wave.get("interval", 1.0)) * (1.0 - min(0.45, GameState.run_time / 1600.0)))

func _current_wave() -> Dictionary:
	var waves: Array = ConfigDB.table("spawn").get("waves", [])
	for wave in waves:
		if GameState.run_time >= float(wave.get("from", 0)) and GameState.run_time < float(wave.get("to", 99999)):
			return wave
	return waves.back() if not waves.is_empty() else {"enemy": "xie_wolf", "interval": 1.0, "pack": [2, 4], "cap": 80}

func _pick_wave_enemy(wave: Dictionary) -> String:
	var pool: Array = wave.get("pool", [])
	if pool.is_empty():
		return str(wave.get("enemy", "xie_wolf"))
	var total := 0.0
	for entry in pool:
		total += max(0.0, float(entry.get("weight", 1.0)))
	if total <= 0.0:
		return str(pool[0].get("enemy", "xie_wolf"))
	var roll := rng.randf() * total
	for entry in pool:
		roll -= max(0.0, float(entry.get("weight", 1.0)))
		if roll <= 0.0:
			return str(entry.get("enemy", "xie_wolf"))
	return str(pool.back().get("enemy", "xie_wolf"))

func _pick_spawn_mode(wave: Dictionary, boss := false) -> String:
	if boss:
		return "inner"
	var near_chance: float = clamp(float(wave.get("near_player_chance", 0.0)), 0.0, 0.8)
	var inner_chance: float = clamp(float(wave.get("inner_chance", 0.0)), 0.0, 0.9 - near_chance)
	var roll := rng.randf()
	if roll < near_chance:
		return "near_player"
	if roll < near_chance + inner_chance:
		return "inner"
	return "edge"

func _spawn_warning_delay(wave: Dictionary, mode: String) -> float:
	if mode == "edge":
		return float(wave.get("edge_warning", 0.0))
	return float(wave.get("warning", 1.15))

func _spawn_enemy(id: String, boss := false) -> void:
	_spawn_enemy_at(id, _choose_spawn_position(_pick_spawn_mode({}, boss), boss), boss)

func _queue_enemy_spawn(id: String, boss := false, mode := "edge", delay := 0.0) -> void:
	var pos := _choose_spawn_position(mode, boss)
	if delay <= 0.0:
		_spawn_enemy_at(id, pos, boss)
		return
	var enemy_data := ConfigDB.entry("enemies", id)
	var element := str(enemy_data.get("hex_element", "fire"))
	var color := AssetDB.color_for_element(element)
	var marker := _make_warning_marker(pos, max(56.0, float(enemy_data.get("radius", 22.0)) * (2.2 if boss else 1.9)), color)
	marker["id"] = id
	marker["boss"] = boss
	marker["duration"] = delay
	marker["time"] = delay
	marker["flash_count"] = 5.0 if boss else 4.0
	pending_spawns.append(marker)

func _update_spawn_warnings(delta: float) -> void:
	var keep: Array = []
	for spawn in pending_spawns:
		spawn["time"] = float(spawn.get("time", 0.0)) - delta
		_animate_warning_marker(spawn)
		if float(spawn["time"]) > 0.0:
			keep.append(spawn)
			continue
		var marker: Node2D = spawn.get("node", null)
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
		_spawn_enemy_at(str(spawn.get("id", "xie_wolf")), spawn.get("pos", Vector2.ZERO), bool(spawn.get("boss", false)))
	pending_spawns = keep

func _choose_spawn_position(mode: String, boss := false) -> Vector2:
	match mode:
		"inner":
			return _random_inner_spawn_position(boss)
		"near_player":
			return _random_near_player_spawn_position()
		_:
			return _random_edge_spawn_position()

func _random_edge_spawn_position() -> Vector2:
	var angle := rng.randf() * TAU
	return Vector2(cos(angle) * arena_radius.x * rng.randf_range(0.86, 1.0), sin(angle) * arena_radius.y * rng.randf_range(0.86, 1.0))

func _random_inner_spawn_position(boss := false) -> Vector2:
	var min_distance := 340.0 if boss else 240.0
	for i in range(18):
		var pos := _random_point_in_arena(92.0 if boss else 72.0)
		if player == null or not is_instance_valid(player) or pos.distance_to(player.global_position) >= min_distance:
			return pos
	var fallback_dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
	var origin := Vector2.ZERO if player == null or not is_instance_valid(player) else player.global_position
	return _clamp_point_to_arena(origin + fallback_dir * min_distance, 72.0)

func _random_near_player_spawn_position() -> Vector2:
	var origin := Vector2.ZERO if player == null or not is_instance_valid(player) else player.global_position
	var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
	return _clamp_point_to_arena(origin + dir * rng.randf_range(260.0, 430.0), 80.0)

func _random_point_in_arena(margin := 64.0) -> Vector2:
	var angle := rng.randf() * TAU
	var r := sqrt(rng.randf())
	return Vector2(cos(angle) * max(32.0, arena_radius.x - margin) * r, sin(angle) * max(32.0, arena_radius.y - margin) * r)

func _clamp_point_to_arena(pos: Vector2, margin := 32.0) -> Vector2:
	var radius := Vector2(max(32.0, arena_radius.x - margin), max(32.0, arena_radius.y - margin))
	var metric := (pos.x * pos.x) / (radius.x * radius.x) + (pos.y * pos.y) / (radius.y * radius.y)
	if metric > 1.0:
		return pos / sqrt(metric)
	return pos

func _spawn_enemy_at(id: String, pos: Vector2, boss := false) -> void:
	var enemy: LingxuEnemy = ENEMY_SCENE.instantiate()
	enemy.position = _clamp_point_to_arena(pos, 24.0)
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
		_queue_enemy_spawn(id, true, "inner", 1.8)
		message_label.text = "妖气凝聚：%s" % ConfigDB.entry("enemies", id).get("name", id)
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

func _make_warning_marker(pos: Vector2, radius: float, color: Color) -> Dictionary:
	var marker := Node2D.new()
	marker.name = "WarningCircle"
	marker.global_position = pos
	marker.z_index = -2
	var glow := Sprite2D.new()
	glow.texture = AssetDB.tex("fx_warning")
	glow.scale = Vector2.ONE * clamp(radius / 260.0, 0.18, 0.85)
	glow.modulate = Color(color.r, color.g, color.b, 0.18)
	marker.add_child(glow)
	var ring := Line2D.new()
	ring.width = 5
	ring.closed = true
	ring.default_color = Color(color.r, color.g, color.b, 0.82)
	for i in range(72):
		var a := float(i) / 72.0 * TAU
		ring.add_point(Vector2(cos(a) * radius, sin(a) * radius))
	marker.add_child(ring)
	add_child(marker)
	return {
		"node": marker,
		"ring": ring,
		"glow": glow,
		"pos": pos,
		"radius": radius,
		"color": color,
		"duration": 1.0,
		"time": 1.0,
		"flash_count": 4.0
	}

func _animate_warning_marker(marker_data: Dictionary) -> void:
	var marker: Node2D = marker_data.get("node", null)
	if marker == null or not is_instance_valid(marker):
		return
	var duration: float = max(0.05, float(marker_data.get("duration", 1.0)))
	var time_left: float = max(0.0, float(marker_data.get("time", 0.0)))
	var elapsed: float = duration - time_left
	var flash_count := float(marker_data.get("flash_count", 4.0))
	var pulse := 0.25 + 0.75 * absf(sin((elapsed / duration) * flash_count * PI))
	var color: Color = marker_data.get("color", Color("#f27348"))
	var ring: Line2D = marker_data.get("ring", null)
	if ring != null and is_instance_valid(ring):
		ring.default_color = Color(color.r, color.g, color.b, lerpf(0.16, 0.88, pulse))
	var glow: Sprite2D = marker_data.get("glow", null)
	if glow != null and is_instance_valid(glow):
		glow.modulate = Color(color.r, color.g, color.b, lerpf(0.06, 0.25, pulse))
	marker.scale = Vector2.ONE * (1.0 + pulse * 0.045)

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

func _spawn_weapon_hit_feedback(weapon: Dictionary, pos: Vector2, result: Dictionary, secondary := false) -> void:
	var element := str(result.get("element", weapon.get("element", "metal")))
	var color := AssetDB.color_for_element(element)
	var is_crit := bool(result.get("is_crit", false))
	var root := _feedback_root("WeaponHit_%s" % str(weapon.get("id", weapon.get("name", "weapon"))), pos, WEAPON_FEEDBACK_Z + 2)
	var duration := WEAPON_HIT_FEEDBACK_DURATION * (0.72 if secondary else 1.0)
	var start_scale := 0.78 if secondary else 1.0
	var end_scale := 1.14 if secondary else 1.36
	var fx_scale := 0.11 if secondary else 0.15
	var fx_alpha := 0.72
	var ring_radius := 14.0 if secondary else 21.0
	var ring_width := 2.0 if secondary else 3.5
	var ring_color := color
	var ring_steps := 30
	if is_crit:
		duration = max(duration * 1.35, 0.36 if secondary else 0.44)
		start_scale = 0.88 if secondary else 1.08
		end_scale = 1.34 if secondary else 1.62
		fx_scale = 0.14 if secondary else 0.2
		fx_alpha = 0.86
		ring_radius = 18.0 if secondary else 28.0
		ring_width = 3.0 if secondary else 5.0
		ring_color = Color("#fff4b8").lerp(color, 0.25)
		ring_steps = 36
	root.scale = Vector2.ONE * start_scale
	_add_feedback_fx(root, _weapon_feedback_fx_id(weapon, is_crit), Vector2.ZERO, fx_scale, fx_alpha)
	_add_feedback_ring(root, ring_radius, ring_color, ring_width, "SourceRing", ring_steps)
	var icon := _add_feedback_icon(root, weapon, Vector2(0, -20.0 if secondary else -27.0), 0.034 if secondary else 0.048, 0.9)
	icon.rotation = -0.18
	_add_hit_class_mark(root, str(weapon.get("class", "flying_sword")), color, secondary)
	if is_crit:
		_add_critical_hit_animation(root, color, secondary)
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector2.ONE * end_scale, duration)
	tween.parallel().tween_property(root, "modulate:a", 0.0, duration)
	tween.tween_callback(root.queue_free)

func _spawn_status_feedback(weapon: Dictionary, pos: Vector2, kind: String, element: String) -> void:
	var color := _effect_feedback_color(kind, element)
	var root := _feedback_root("WeaponStatus_%s_%s" % [kind, str(weapon.get("id", ""))], pos + Vector2(0, -18), WEAPON_FEEDBACK_Z + 3)
	_add_feedback_fx(root, _effect_feedback_fx_id(kind, element), Vector2.ZERO, 0.095, 0.58)
	_add_feedback_icon(root, weapon, Vector2(16, -10), 0.026, 0.82)
	_add_feedback_ring(root, 12.0, color, 2.0, "StatusRing", 24)
	var tween := create_tween()
	tween.tween_property(root, "position", root.position + Vector2(0, -22), 0.3)
	tween.parallel().tween_property(root, "modulate:a", 0.0, 0.3)
	tween.tween_callback(root.queue_free)

func _spawn_line_feedback(weapon: Dictionary, origin: Vector2, target_pos: Vector2, width: float, style: String) -> void:
	var aim := target_pos - origin
	if aim.length_squared() < 4.0:
		return
	var element := str(weapon.get("element", "metal"))
	var color := AssetDB.color_for_element(element)
	var duration := 0.2 if style == "split" else WEAPON_CAST_FEEDBACK_DURATION
	var line := _add_world_line("WeaponPath_%s_%s" % [style, str(weapon.get("id", ""))], origin, target_pos, color, width, 0.58, duration)
	if style == "dash":
		var side := Vector2(-aim.y, aim.x).normalized()
		_add_world_line("WeaponPath_dash_edge", origin + side * 13.0, target_pos + side * 13.0, color.lerp(Color.WHITE, 0.28), max(2.0, width * 0.24), 0.38, duration)
		_add_world_line("WeaponPath_dash_edge", origin - side * 13.0, target_pos - side * 13.0, color.lerp(Color.WHITE, 0.28), max(2.0, width * 0.24), 0.38, duration)
	elif style == "split":
		line.width = max(3.0, width)
	var icon := _world_feedback_icon(weapon, origin, 0.048, WEAPON_FEEDBACK_Z + 2)
	icon.rotation = aim.angle()
	var tween := create_tween()
	tween.tween_property(icon, "global_position", target_pos, duration * 0.82)
	tween.parallel().tween_property(icon, "scale", Vector2.ONE * 0.028, duration * 0.82)
	tween.parallel().tween_property(icon, "modulate:a", 0.0, duration * 0.82)
	tween.tween_callback(icon.queue_free)

func _spawn_fan_feedback(weapon: Dictionary, origin: Vector2, target_pos: Vector2, count: int, spread: float) -> void:
	var aim := target_pos - origin
	if aim.length_squared() < 4.0:
		return
	var middle := float(count - 1) * 0.5
	for i in range(count):
		var offset := (float(i) - middle) * spread
		var endpoint := origin + aim.rotated(offset)
		_spawn_line_feedback(weapon, origin, endpoint, 5.0, "fan")

func _spawn_area_feedback(weapon: Dictionary, center: Vector2, radius: float, style: String) -> void:
	var element := str(weapon.get("element", "metal"))
	var color := AssetDB.color_for_element(element)
	var root := _feedback_root("WeaponArea_%s_%s" % [style, str(weapon.get("id", ""))], center, WEAPON_FEEDBACK_Z)
	root.scale = Vector2.ONE * 0.16
	var ring_width := 5.0 if style in ["explode", "quake", "nova", "poison_burst"] else 4.0
	_add_feedback_ring(root, radius, color, ring_width, "AreaRing", 72)
	if style == "talisman":
		_add_feedback_square(root, radius * 0.62, color, 3.0)
	elif style == "quake":
		_add_feedback_spokes(root, radius, color, 8, 2.5)
	elif style == "explode" or style == "nova":
		_add_feedback_spokes(root, radius * 0.82, color.lerp(Color.WHITE, 0.2), 12, 3.0)
	elif style == "poison_burst":
		_add_feedback_spores(root, radius, color)
	else:
		_add_feedback_spokes(root, radius * 0.72, color, 5, 2.0)
	_add_feedback_fx(root, _weapon_feedback_fx_id(weapon, false), Vector2.ZERO, clamp(radius / 760.0, 0.11, 0.24), 0.64)
	_add_feedback_icon(root, weapon, Vector2(0, -min(radius * 0.34, 44.0)), 0.055, 0.92)
	var duration := 0.46 if style in ["explode", "quake", "nova", "poison_burst"] else WEAPON_CAST_FEEDBACK_DURATION
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector2.ONE, duration)
	tween.parallel().tween_property(root, "modulate:a", 0.0, duration)
	tween.tween_callback(root.queue_free)

func _spawn_orbit_feedback(weapon: Dictionary, center: Vector2, radius: float, klass: String) -> void:
	var element := str(weapon.get("element", "metal"))
	var color := AssetDB.color_for_element(element)
	var root := _feedback_root("WeaponOrbit_%s_%s" % [klass, str(weapon.get("id", ""))], center, WEAPON_FEEDBACK_Z)
	_add_feedback_ring(root, radius, color, 4.0, "OrbitRing", 96)
	if klass == "aura":
		_add_feedback_ring(root, radius * 0.68, color.lerp(Color.WHITE, 0.18), 2.4, "AuraInnerRing", 80)
		_add_feedback_fx(root, _weapon_feedback_fx_id(weapon, false), Vector2.ZERO, clamp(radius / 720.0, 0.12, 0.26), 0.46)
	else:
		for i in range(3):
			var angle := float(i) / 3.0 * TAU + rng.randf_range(-0.18, 0.18)
			var icon := _add_feedback_icon(root, weapon, Vector2(cos(angle), sin(angle)) * radius, 0.038, 0.86)
			icon.rotation = angle + PI * 0.5
	var tween := create_tween()
	tween.tween_property(root, "rotation", root.rotation + (TAU * (0.35 if klass == "aura" else 0.75)), WEAPON_CAST_FEEDBACK_DURATION)
	tween.parallel().tween_property(root, "scale", Vector2.ONE * (1.12 if klass == "aura" else 1.02), WEAPON_CAST_FEEDBACK_DURATION)
	tween.parallel().tween_property(root, "modulate:a", 0.0, WEAPON_CAST_FEEDBACK_DURATION)
	tween.tween_callback(root.queue_free)

func _spawn_shield_feedback(weapon: Dictionary, center: Vector2, amount: float) -> void:
	var color := AssetDB.color_for_element(str(weapon.get("element", "water"))).lerp(Color.WHITE, 0.16)
	var root := _feedback_root("WeaponShield_%s" % str(weapon.get("id", "")), center, WEAPON_FEEDBACK_Z + 1)
	var radius: float = 62.0 + minf(amount, 80.0) * 0.16
	root.scale = Vector2.ONE * 0.7
	_add_feedback_ring(root, radius, color, 5.0, "ShieldRing", 72)
	_add_feedback_ring(root, radius * 0.68, color, 2.4, "ShieldInnerRing", 64)
	_add_feedback_icon(root, weapon, Vector2(0, -radius * 0.34), 0.064, 0.94)
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector2.ONE * 1.12, 0.38)
	tween.parallel().tween_property(root, "modulate:a", 0.0, 0.38)
	tween.tween_callback(root.queue_free)

func _spawn_slam_feedback(weapon: Dictionary, origin: Vector2, target_pos: Vector2, radius: float) -> void:
	_spawn_line_feedback(weapon, origin, target_pos, 12.0, "slam")
	_spawn_area_feedback(weapon, target_pos, radius, "quake")

func _spawn_spike_feedback(weapon: Dictionary, origin: Vector2, target_pos: Vector2) -> void:
	var aim := target_pos - origin
	if aim.length_squared() < 4.0:
		return
	var dir := aim.normalized()
	var color := AssetDB.color_for_element(str(weapon.get("element", "earth")))
	_spawn_line_feedback(weapon, origin, target_pos, 8.0, "spike")
	for i in range(4):
		var t := (float(i) + 0.65) / 4.6
		var pos := origin.lerp(target_pos, t)
		var spike := Polygon2D.new()
		spike.name = "WeaponSpike_%s" % str(weapon.get("id", ""))
		var points := PackedVector2Array()
		points.append(Vector2(0, -20))
		points.append(Vector2(-8, 8))
		points.append(Vector2(8, 8))
		spike.polygon = points
		spike.color = Color(color.r, color.g, color.b, 0.66)
		spike.global_position = pos
		spike.rotation = dir.angle() + PI * 0.5
		spike.z_index = WEAPON_FEEDBACK_Z
		add_child(spike)
		spike.scale = Vector2.ONE * 0.28
		var tween := create_tween()
		tween.tween_property(spike, "scale", Vector2.ONE, 0.16)
		tween.parallel().tween_property(spike, "modulate:a", 0.0, 0.32)
		tween.tween_callback(spike.queue_free)

func _spawn_summon_feedback(weapon: Dictionary, origin: Vector2, target_pos: Vector2) -> void:
	_spawn_area_feedback(weapon, origin, 42.0, "talisman")
	_spawn_line_feedback(weapon, origin, target_pos, 6.0, "summon")

func _spawn_summon_gate_feedback(weapon: Dictionary, origin: Vector2, target_pos: Vector2, index: int) -> void:
	var color := AssetDB.color_for_element(str(weapon.get("element", "metal")))
	var root := _feedback_root("WeaponSummonGate_%d_%s" % [index, str(weapon.get("id", ""))], origin, WEAPON_FEEDBACK_Z + 1)
	_add_feedback_ring(root, 16.0, color, 2.4, "SummonGateRing", 28)
	_add_feedback_icon(root, weapon, Vector2.ZERO, 0.028, 0.76)
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector2.ONE * 1.7, 0.24)
	tween.parallel().tween_property(root, "modulate:a", 0.0, 0.24)
	tween.tween_callback(root.queue_free)
	_add_world_line("WeaponSummonThread_%s" % str(weapon.get("id", "")), origin, target_pos, color, 3.0, 0.28, 0.2)

func _feedback_root(node_name: String, pos: Vector2, z_value: int) -> Node2D:
	var root := Node2D.new()
	root.name = node_name
	root.global_position = pos
	root.z_index = z_value
	add_child(root)
	return root

func _add_feedback_icon(parent: Node, weapon: Dictionary, pos: Vector2, scale_value: float, alpha: float) -> Sprite2D:
	var icon := Sprite2D.new()
	icon.name = "SourceWeaponIcon"
	icon.texture = AssetDB.tex(str(weapon.get("art_id", "icon_%s" % str(weapon.get("element", "metal")))))
	icon.position = pos
	icon.scale = Vector2.ONE * scale_value
	icon.modulate = Color(1, 1, 1, alpha)
	icon.z_index = 4
	parent.add_child(icon)
	return icon

func _world_feedback_icon(weapon: Dictionary, pos: Vector2, scale_value: float, z_value: int) -> Sprite2D:
	var icon := Sprite2D.new()
	icon.name = "TravelingWeaponIcon_%s" % str(weapon.get("id", ""))
	icon.texture = AssetDB.tex(str(weapon.get("art_id", "icon_%s" % str(weapon.get("element", "metal")))))
	icon.global_position = pos
	icon.scale = Vector2.ONE * scale_value
	icon.modulate = Color(1, 1, 1, 0.92)
	icon.z_index = z_value
	add_child(icon)
	return icon

func _add_feedback_fx(parent: Node, fx_id: String, pos: Vector2, scale_value: float, alpha: float) -> Sprite2D:
	var fx := Sprite2D.new()
	fx.name = "FeedbackFx"
	fx.texture = AssetDB.tex(fx_id)
	fx.position = pos
	fx.scale = Vector2.ONE * scale_value
	fx.modulate = Color(1, 1, 1, alpha)
	fx.z_index = 1
	parent.add_child(fx)
	return fx

func _add_feedback_ring(parent: Node, radius: float, color: Color, width: float, node_name: String, steps: int) -> Line2D:
	var ring := Line2D.new()
	ring.name = node_name
	ring.closed = true
	ring.width = width
	ring.default_color = Color(color.r, color.g, color.b, color.a if color.a < 1.0 else 0.64)
	ring.z_index = 2
	for point in _circle_points(radius, steps):
		ring.add_point(point)
	parent.add_child(ring)
	return ring

func _add_feedback_square(parent: Node, radius: float, color: Color, width: float) -> void:
	var square := Line2D.new()
	square.name = "TalismanSquare"
	square.closed = true
	square.width = width
	square.default_color = Color(color.r, color.g, color.b, 0.58)
	square.z_index = 3
	square.add_point(Vector2(-radius, -radius) * 0.6)
	square.add_point(Vector2(radius, -radius) * 0.6)
	square.add_point(Vector2(radius, radius) * 0.6)
	square.add_point(Vector2(-radius, radius) * 0.6)
	square.rotation = PI * 0.25
	parent.add_child(square)

func _add_feedback_spokes(parent: Node, radius: float, color: Color, count: int, width: float) -> void:
	for i in range(count):
		var angle := float(i) / float(count) * TAU
		var spoke := Line2D.new()
		spoke.name = "FeedbackSpoke"
		spoke.width = width
		spoke.default_color = Color(color.r, color.g, color.b, 0.48)
		spoke.add_point(Vector2.ZERO)
		spoke.add_point(Vector2(cos(angle), sin(angle)) * radius)
		spoke.z_index = 1
		parent.add_child(spoke)

func _add_feedback_spores(parent: Node, radius: float, color: Color) -> void:
	for i in range(8):
		var angle := float(i) / 8.0 * TAU + rng.randf_range(-0.16, 0.16)
		var spore := Sprite2D.new()
		spore.name = "PoisonSpore"
		spore.texture = AssetDB.tex("fx_wood")
		spore.position = Vector2(cos(angle), sin(angle)) * radius * rng.randf_range(0.26, 0.82)
		spore.scale = Vector2.ONE * rng.randf_range(0.035, 0.065)
		spore.modulate = Color(color.r, color.g, color.b, 0.55)
		spore.z_index = 2
		parent.add_child(spore)

func _add_hit_class_mark(parent: Node, klass: String, color: Color, secondary: bool) -> void:
	var alpha := 0.42 if secondary else 0.64
	match klass:
		"dash_blade", "flying_sword":
			var slash := Line2D.new()
			slash.name = "HitSlashMark"
			slash.width = 4.0 if secondary else 6.0
			slash.default_color = Color(color.r, color.g, color.b, alpha)
			slash.add_point(Vector2(-18, 8))
			slash.add_point(Vector2(18, -8))
			slash.z_index = 3
			parent.add_child(slash)
		"hammer", "spike":
			_add_feedback_spokes(parent, 24.0 if secondary else 34.0, color, 6, 2.4)
		"needle", "thorn":
			for i in range(3):
				var dart := Line2D.new()
				dart.name = "HitDartMark"
				dart.width = 2.0
				dart.default_color = Color(color.r, color.g, color.b, alpha)
				var y := -8.0 + float(i) * 8.0
				dart.add_point(Vector2(-14, y))
				dart.add_point(Vector2(14, y - 8.0))
				dart.z_index = 3
				parent.add_child(dart)
		"area", "talisman", "aura":
			_add_feedback_ring(parent, 25.0 if secondary else 34.0, color, 2.0, "HitPulseMark", 32)
		"summon":
			_add_feedback_square(parent, 25.0 if secondary else 34.0, color, 2.0)
		"shield", "orbit":
			_add_feedback_ring(parent, 20.0 if secondary else 28.0, color, 2.2, "HitGuardMark", 32)
		_:
			pass

func _add_critical_hit_animation(parent: Node, color: Color, secondary: bool) -> void:
	var gold := Color("#fff4b8")
	var burst_color := gold.lerp(color, 0.18)
	var ring_radius := 31.0 if secondary else 45.0
	var outer := _add_feedback_ring(parent, ring_radius, burst_color, 3.0 if secondary else 5.0, "CriticalBurstRing", 56)
	outer.default_color = Color(burst_color.r, burst_color.g, burst_color.b, 0.88)
	var inner := _add_feedback_ring(parent, ring_radius * 0.56, gold.lerp(Color.WHITE, 0.28), 2.0 if secondary else 3.0, "CriticalInnerFlash", 44)
	inner.default_color = Color(1.0, 0.96, 0.72, 0.72)
	for i in range(2):
		var slash := Line2D.new()
		slash.name = "CriticalCrossSlash"
		slash.width = 5.0 if secondary else 8.0
		slash.default_color = Color(1.0, 0.95, 0.64, 0.78)
		slash.add_point(Vector2(-ring_radius * 0.66, 0.0))
		slash.add_point(Vector2(ring_radius * 0.66, 0.0))
		slash.rotation = PI * 0.25 + float(i) * PI * 0.5
		slash.z_index = 5
		parent.add_child(slash)
	var spark_count: int = 8 if secondary else 12
	for i in range(spark_count):
		var angle := float(i) / float(spark_count) * TAU
		var spark := Line2D.new()
		spark.name = "CriticalSpark"
		spark.width = 2.0 if secondary else 3.0
		spark.default_color = Color(1.0, 0.94, 0.52, 0.72)
		var dir := Vector2(cos(angle), sin(angle))
		spark.add_point(dir * ring_radius * 0.38)
		spark.add_point(dir * ring_radius * 0.88)
		spark.z_index = 4
		parent.add_child(spark)
	var label := Label.new()
	label.name = "CriticalHitText"
	label.text = "暴击"
	label.size = Vector2(82, 42) if secondary else Vector2(108, 52)
	label.pivot_offset = label.size * 0.5
	label.position = Vector2(-label.size.x * 0.5, -72.0 if secondary else -88.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 8
	_apply_display_font(label, 28 if secondary else 38, Color("#fff4b8"), 4)
	label.modulate = Color(1, 1, 1, 0.96)
	parent.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - (16.0 if secondary else 24.0), 0.24 if secondary else 0.32)
	tween.parallel().tween_property(label, "scale", Vector2.ONE * (1.15 if secondary else 1.22), 0.14)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.32 if secondary else 0.42)

func _add_world_line(node_name: String, origin: Vector2, target_pos: Vector2, color: Color, width: float, alpha: float, duration: float) -> Line2D:
	var line := Line2D.new()
	line.name = node_name
	line.z_index = WEAPON_FEEDBACK_Z - 1
	line.width = width
	line.default_color = Color(color.r, color.g, color.b, alpha)
	line.add_point(to_local(origin))
	line.add_point(to_local(target_pos))
	add_child(line)
	var tween := create_tween()
	tween.tween_property(line, "width", max(1.0, width * 0.35), duration)
	tween.parallel().tween_property(line, "modulate:a", 0.0, duration)
	tween.tween_callback(line.queue_free)
	return line

func _circle_points(radius: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(steps):
		var angle := float(i) / float(steps) * TAU
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points

func _weapon_feedback_fx_id(weapon: Dictionary, is_crit: bool) -> String:
	if is_crit:
		return "fx_crit"
	match str(weapon.get("class", "flying_sword")):
		"dash_blade", "flying_sword", "needle", "thorn", "summon":
			return "fx_slash"
		_:
			return "fx_%s" % str(weapon.get("element", "metal"))

func _effect_feedback_fx_id(kind: String, element: String) -> String:
	match kind:
		"poison", "root", "taunt":
			return "fx_wood"
		"ignite":
			return "fx_fire"
		"bleed", "vulnerable", "execute_setup", "ignore_armor":
			return "fx_crit"
		"slow", "chill_stack", "freeze", "pull":
			return "fx_water"
		"stagger", "petrify", "blind", "knockback":
			return "fx_earth"
		_:
			return "fx_%s" % element

func _effect_feedback_color(kind: String, element: String) -> Color:
	match kind:
		"poison", "root", "taunt":
			return AssetDB.color_for_element("wood")
		"ignite":
			return AssetDB.color_for_element("fire")
		"slow", "chill_stack", "freeze", "pull":
			return AssetDB.color_for_element("water")
		"stagger", "petrify", "blind", "knockback":
			return AssetDB.color_for_element("earth")
		"bleed", "vulnerable", "execute_setup", "ignore_armor":
			return Color("#e8b259")
		_:
			return AssetDB.color_for_element(element)

func _open_market(reason: String) -> void:
	if market_open:
		return
	market_open = true
	market_mode = "choice"
	market_reason = reason
	market_notice_text = "择一道机缘，整备完成后继续历练。"
	market_choice_completed = false
	market_selected_offer_id = ""
	market_offers = _roll_offers(4, false)
	_render_market()

func _open_spirit_shop() -> void:
	if market_open:
		return
	market_open = true
	market_mode = "spirit_shop"
	market_reason = "云游商会"
	market_notice_text = "可用拾取的灵石购买法器、道具和数值提升。"
	market_choice_completed = false
	market_selected_offer_id = ""
	market_offers = _roll_offers(4, true)
	_render_market()

func _render_market() -> void:
	overlay_layer.queue_free()
	overlay_layer = CanvasLayer.new()
	add_child(overlay_layer)
	var root := ColorRect.new()
	root.color = Color(0.02, 0.03, 0.03, 0.82)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_layer.add_child(root)
	var frame := PanelContainer.new()
	frame.anchor_left = 0.06
	frame.anchor_top = 0.07
	frame.anchor_right = 0.94
	frame.anchor_bottom = 0.93
	frame.add_theme_stylebox_override("panel", _stylebox(Color(0.012, 0.024, 0.028, 0.92), Color("#e8b259"), 2, 8))
	root.add_child(frame)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	frame.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var title := Label.new()
	if market_mode == "spirit_shop":
		title.text = "%s · 灵石购物" % market_reason
	else:
		title.text = "%s · 已择定" % market_reason if market_choice_completed else "%s · 四选一" % market_reason
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_display_font(title, 46, Color("#e8b259"), 3)
	header.add_child(title)
	var stone_label := Label.new()
	stone_label.text = "灵石 %d" % GameState.stones
	stone_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stone_label.add_theme_font_size_override("font_size", 22)
	stone_label.add_theme_color_override("font_color", Color("#fff4b8"))
	header.add_child(stone_label)
	if market_mode == "spirit_shop":
		var refresh := Button.new()
		refresh.text = "刷新 %d" % _reroll_cost()
		refresh.custom_minimum_size = Vector2(112, 44)
		refresh.focus_mode = Control.FOCUS_NONE
		refresh.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		refresh.pressed.connect(_refresh_spirit_shop)
		header.add_child(refresh)
		var close := Button.new()
		close.text = "离开"
		close.custom_minimum_size = Vector2(86, 44)
		close.focus_mode = Control.FOCUS_NONE
		close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		close.pressed.connect(_close_market)
		header.add_child(close)
	else:
		var proceed := Button.new()
		proceed.text = "继续历练"
		proceed.custom_minimum_size = Vector2(116, 44)
		proceed.focus_mode = Control.FOCUS_NONE
		proceed.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		proceed.disabled = not market_choice_completed
		proceed.tooltip_text = "先择一道机缘" if proceed.disabled else "关闭机缘界面，继续战斗"
		proceed.pressed.connect(_close_market)
		header.add_child(proceed)
	market_notice_label = Label.new()
	market_notice_label.text = market_notice_text
	market_notice_label.custom_minimum_size = Vector2(0, 24)
	market_notice_label.add_theme_font_size_override("font_size", 17)
	market_notice_label.add_theme_color_override("font_color", Color("#cfe5e0"))
	box.add_child(market_notice_label)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var offer_area := HBoxContainer.new()
	offer_area.add_theme_constant_override("separation", 14)
	box.add_child(offer_area)
	offer_area.add_child(cards)
	for offer in market_offers:
		cards.add_child(_offer_button(offer))
	offer_area.add_child(_market_stat_panel())
	box.add_child(_market_inventory_panel())
	SignalsBus.market_offered.emit(market_offers)

func _close_market() -> void:
	market_open = false
	market_notice_text = ""
	market_choice_completed = false
	market_selected_offer_id = ""
	_clear_detail()
	overlay_layer.queue_free()
	overlay_layer = CanvasLayer.new()
	add_child(overlay_layer)
	_update_hud()

func _refresh_spirit_shop() -> void:
	var cost := _reroll_cost()
	if GameState.stones < cost:
		_show_notice("灵石不足，无法刷新")
		return
	GameState.stones -= cost
	market_notice_text = "已刷新商品。"
	market_offers = _roll_offers(4, true)
	_render_market()

func _reroll_cost() -> int:
	return int(ConfigDB.table("market").get("reroll_cost", 8))

func _roll_offers(count: int, paid_shop := false) -> Array:
	var result: Array = []
	var pool: Array = []
	for id in GameState.filtered_ids("weapons"):
		var w := ConfigDB.entry("weapons", id)
		if bool(w.get("legendary", false)) and GameState.realm != "huashen":
			continue
		var data := w.duplicate(true)
		var tier := GameState.WEAPON_TIER_MAX if bool(data.get("legendary", false)) else _roll_weapon_tier()
		data["id"] = id
		data["tier"] = tier
		var tier_mult := GameState.weapon_tier_multiplier(tier)
		var weapon_offer := {"kind": "weapon", "id": id, "tier": tier, "name": data.get("name", id), "summary": "%s法器 · %s伤害 %.0f" % [GameState.root_name(data.get("element", "")), data.get("class", ""), float(data.get("base_damage", 0)) * tier_mult], "art_id": _offer_art_id(id), "data": data}
		if paid_shop:
			weapon_offer["price"] = _offer_price(weapon_offer)
		pool.append(weapon_offer)
	for id in GameState.filtered_ids("items"):
		var item := ConfigDB.entry("items", id)
		var item_offer := {"kind": "item", "id": id, "name": item.get("name", id), "summary": item.get("summary", ""), "art_id": _offer_art_id(id), "data": item}
		if paid_shop:
			item_offer["price"] = _offer_price(item_offer)
		pool.append(item_offer)
	for id in GameState.filtered_ids("skills"):
		var skill := ConfigDB.entry("skills", id)
		var skill_offer := {"kind": "skill", "id": id, "name": skill.get("name", id), "summary": skill.get("summary", ""), "art_id": _offer_art_id(id), "data": skill}
		if paid_shop:
			skill_offer["price"] = _offer_price(skill_offer)
		pool.append(skill_offer)
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

func _roll_weapon_tier() -> int:
	var weights := {1: 68.0, 2: 24.0, 3: 7.0, 4: 1.0}
	match GameState.realm:
		"zhuji":
			weights = {1: 58.0, 2: 30.0, 3: 10.0, 4: 2.0}
		"jindan":
			weights = {1: 44.0, 2: 34.0, 3: 17.0, 4: 5.0}
		"yuanying":
			weights = {1: 32.0, 2: 36.0, 3: 23.0, 4: 9.0}
		"huashen":
			weights = {1: 22.0, 2: 34.0, 3: 28.0, 4: 16.0}
	var luck: float = max(0.0, float(GameState.stats.get("luck", 0.0)))
	weights[3] = float(weights[3]) + luck * 0.18
	weights[4] = float(weights[4]) + luck * 0.08
	var total := 0.0
	for weight in weights.values():
		total += float(weight)
	var roll := rng.randf() * total
	var running := 0.0
	for tier in [1, 2, 3, 4]:
		running += float(weights[tier])
		if roll <= running:
			return tier
	return 1

func _offer_button(offer: Dictionary) -> Button:
	var kind_id := str(offer.get("kind", ""))
	var data: Dictionary = offer.get("data", {})
	var tier := int(offer.get("tier", data.get("tier", 1)))
	var tier_color := GameState.weapon_tier_color(tier)
	var merge_target := {}
	if kind_id == "weapon":
		merge_target = GameState.weapon_merge_target(str(offer.get("id", "")), tier)
	var block_reason := _offer_block_reason(offer)
	var normal_bg := Color(0.026, 0.04, 0.045, 0.96)
	var normal_border := Color(0.38, 0.9, 0.82, 0.38)
	if kind_id == "weapon":
		normal_bg = normal_bg.lerp(tier_color, 0.18)
		normal_border = Color(tier_color.r, tier_color.g, tier_color.b, 0.82)
	var choice_completed := market_mode == "choice" and market_choice_completed
	var selected := choice_completed and str(offer.get("id", "")) == market_selected_offer_id
	if selected:
		normal_bg = normal_bg.lerp(Color("#e8b259"), 0.18)
		normal_border = Color("#ffe9a8")
	var b := Button.new()
	b.custom_minimum_size = OFFER_CARD_SIZE
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _stylebox(normal_bg, normal_border, 2 if kind_id == "weapon" else 1, 6))
	b.add_theme_stylebox_override("hover", _stylebox(Color(0.045, 0.072, 0.076, 0.98).lerp(tier_color, 0.15 if kind_id == "weapon" else 0.0), Color("#e8b259"), 2, 6))
	b.add_theme_stylebox_override("pressed", _stylebox(Color(0.055, 0.066, 0.055, 0.98), Color("#e8b259"), 2, 6))
	if selected:
		b.add_theme_stylebox_override("disabled", _stylebox(normal_bg, Color("#ffe9a8"), 3, 6))
	else:
		b.add_theme_stylebox_override("disabled", _stylebox(Color(0.02, 0.024, 0.026, 0.82), Color(0.36, 0.38, 0.38, 0.42), 1, 6))
	b.disabled = choice_completed
	if choice_completed:
		b.tooltip_text = "已选择此机缘" if selected else "本次机缘已择定"
		if not selected:
			b.modulate = Color(0.58, 0.62, 0.62, 1.0)
	elif not block_reason.is_empty():
		b.modulate = Color(0.76, 0.78, 0.75, 1.0)
		b.tooltip_text = block_reason
	elif kind_id == "weapon" and not merge_target.is_empty():
		b.tooltip_text = "选择后合成已有同名同品法器，不占用空槽"
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
	art_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.012, 0.025, 0.028, 0.98), _element_color(str(data.get("element", ""))), 2, 5))
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
	_apply_display_font(name, 31, tier_color if kind_id == "weapon" else Color("#fff8e8"), 2)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	var kind := Label.new()
	if kind_id == "weapon":
		if merge_target.is_empty():
			kind.text = "%s · %s · %s" % [_kind_name(kind_id), GameState.weapon_tier_name(tier), _offer_school_name(offer)]
		else:
			kind.text = "%s · 升至%s · %s" % [_kind_name(kind_id), GameState.weapon_tier_name(tier + 1), _offer_school_name(offer)]
	else:
		kind.text = "%s · %s" % [_kind_name(kind_id), _offer_school_name(offer)]
	if market_mode == "spirit_shop":
		kind.text = "%s · %d灵石" % [kind.text, int(offer.get("price", _offer_price(offer)))]
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
	for row in _offer_effect_rows(offer).slice(0, OFFER_EFFECT_ROW_LIMIT):
		rows.add_child(_effect_row_control(row))
	b.pressed.connect(func(): _choose_offer(offer))
	return b

func _offer_price(offer: Dictionary) -> int:
	match str(offer.get("kind", "")):
		"weapon":
			var tier := int(offer.get("tier", offer.get("data", {}).get("tier", 1)))
			return 10 + tier * 8
		"item":
			var data: Dictionary = offer.get("data", {})
			return 6 + int(data.get("slots", 1)) * 4
		"skill":
			return 12
	return 8

func _offer_block_reason(offer: Dictionary) -> String:
	if market_mode == "spirit_shop" and GameState.stones < int(offer.get("price", _offer_price(offer))):
		return "灵石不足，不能购买"
	match str(offer.get("kind", "")):
		"weapon":
			if not GameState.can_accept_weapon(str(offer.get("id", "")), int(offer.get("tier", 1))):
				return "法器槽与备炼栏已满，且没有同名同品可合成。可先合并、出售或拖拽调整。"
		"item":
			if not GameState.can_accept_item(str(offer.get("id", ""))):
				return "道具栏已满，出售道具后才可获得。"
		"skill":
			var data: Dictionary = offer.get("data", {})
			if int(GameState.skill_stacks.get(str(offer.get("id", "")), 0)) >= int(data.get("max_stacks", 1)):
				return "该数值提升已达上限。"
	return ""

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
			var tier := int(data.get("tier", 1))
			var merge_target := GameState.weapon_merge_target(str(data.get("id", offer.get("id", ""))), tier)
			if not merge_target.is_empty():
				var upgrade_row := _effect_row("weapon_tier", "选择后", "升至%s" % GameState.weapon_tier_name(tier + 1), element)
				upgrade_row["color"] = GameState.weapon_tier_color(tier + 1)
				rows.append(upgrade_row)
			var tier_row := _effect_row("weapon_tier", "品阶", GameState.weapon_tier_name(tier), element)
			tier_row["color"] = GameState.weapon_tier_color(tier)
			rows.append(tier_row)
			if klass == "shield":
				rows.append(_effect_row("max_qi_shield", "护盾生成", "+%.0f" % max(10.0, float(data.get("base_damage", 0.0)) + 10.0), element))
			else:
				var shown_damage := float(data.get("base_damage", 0.0)) * GameState.weapon_tier_multiplier(tier)
				rows.append(_effect_row("%s_damage_pct" % element, "%s伤害" % GameState.root_name(element), "%.0f" % shown_damage, element))
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
			return "数值"
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
	if market_mode == "choice" and market_choice_completed:
		_show_notice("本次机缘已择定，整备完成后继续历练")
		return
	var block_reason := _offer_block_reason(offer)
	if not block_reason.is_empty():
		_show_notice(block_reason)
		return
	if market_mode == "spirit_shop":
		_buy_shop_offer(offer)
		return
	var accepted := true
	match offer["kind"]:
		"weapon":
			accepted = GameState.equip_weapon(str(offer["id"]), int(offer.get("tier", 1)))
			if accepted:
				_reset_weapon_cooldowns()
		"item":
			accepted = GameState.add_item(str(offer["id"]))
		"skill":
			accepted = GameState.apply_skill(str(offer["id"]))
	if not accepted:
		_show_notice("槽位已满或数值已达上限")
		return
	SignalsBus.market_choice.emit(offer["id"])
	market_choice_completed = true
	market_selected_offer_id = str(offer.get("id", ""))
	market_notice_text = "已得%s，可整备法器与法宝。" % str(offer.get("name", offer.get("id", "")))
	_render_market()
	_update_hud()

func _buy_shop_offer(offer: Dictionary) -> void:
	var price := int(offer.get("price", _offer_price(offer)))
	if GameState.stones < price:
		_show_notice("灵石不足，不能购买")
		return
	var accepted := true
	match offer["kind"]:
		"weapon":
			accepted = GameState.equip_weapon(str(offer["id"]), int(offer.get("tier", 1)))
			if accepted:
				_reset_weapon_cooldowns()
		"item":
			accepted = GameState.add_item(str(offer["id"]))
		"skill":
			accepted = GameState.apply_skill(str(offer["id"]))
	if not accepted:
		_show_notice("槽位已满或数值已达上限，先整理后再购买")
		return
	GameState.stones -= price
	SignalsBus.market_choice.emit(offer["id"])
	market_notice_text = "购买了 %s。" % str(offer.get("name", offer.get("id", "")))
	market_offers = _roll_offers(4, true)
	_render_market()
	_update_hud()

func _show_notice(text: String) -> void:
	market_notice_text = text
	if is_instance_valid(market_notice_label):
		market_notice_label.text = text
	message_label.text = text
	var tween := create_tween()
	tween.tween_interval(1.3)
	tween.tween_callback(func():
		if message_label.text == text:
			message_label.text = ""
	)

func _market_inventory_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 138)
	panel.add_theme_stylebox_override("panel", _stylebox(Color(0.018, 0.031, 0.035, 0.9), Color(0.35, 0.88, 0.82, 0.32), 1, 6))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	margin.add_child(columns)
	columns.add_child(_market_weapon_column())
	columns.add_child(_market_item_column())
	return panel

func _market_column(title_text: String, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#e8b259"))
	box.add_child(title)
	return box

func _market_weapon_column() -> VBoxContainer:
	var box := _market_column("装备 / 备炼", 340)
	var active := HBoxContainer.new()
	active.add_theme_constant_override("separation", 6)
	box.add_child(active)
	for i in range(4):
		active.add_child(_market_weapon_slot_button("active", i, Vector2(42, 42)))
	var reserve_line := HBoxContainer.new()
	reserve_line.add_theme_constant_override("separation", 6)
	box.add_child(reserve_line)
	var reserve_label := Label.new()
	reserve_label.text = "备炼"
	reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reserve_label.add_theme_font_size_override("font_size", 13)
	reserve_label.add_theme_color_override("font_color", Color("#c8a2ff"))
	reserve_line.add_child(reserve_label)
	for i in range(GameState.weapon_reserve_capacity()):
		reserve_line.add_child(_market_weapon_slot_button("reserve", i, Vector2(42, 42)))
	return box

func _market_weapon_slot_button(place: String, index: int, size: Vector2) -> Button:
	var slot := _hud_icon_button(size)
	slot.set_meta("weapon_place", place)
	slot.set_meta("weapon_index", index)
	if place == "active" and index < GameState.active_weapons.size():
		var w: Dictionary = GameState.active_weapons[index]
		slot.icon = AssetDB.tex(_offer_art_id(str(w.get("id", ""))))
		slot.tooltip_text = _weapon_tooltip(index, w)
		_set_weapon_button_style(slot, int(w.get("tier", 1)))
	elif place == "reserve" and index < GameState.weapon_reserve.size():
		var w: Dictionary = GameState.weapon_reserve[index]
		slot.icon = AssetDB.tex(_offer_art_id(str(w.get("id", ""))))
		slot.tooltip_text = _weapon_tooltip(index, w, true)
		_set_weapon_button_style(slot, int(w.get("tier", 1)))
	else:
		slot.icon = AssetDB.tex("pickup_qi")
		slot.tooltip_text = "空法器槽" if place == "active" else "空备炼栏"
		_set_weapon_button_style(slot, 1, true)
	slot.pressed.connect(func(): _show_weapon_detail(place, index))
	slot.gui_input.connect(func(event): _on_weapon_slot_gui_input(event, place, index))
	return slot

func _market_item_column() -> VBoxContainer:
	var box := _market_column("道具 %d/%d" % [GameState.bag_used_slots(), int(GameState.stats.get("bag_capacity", 5))], 300)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	box.add_child(row)
	for i in range(int(GameState.stats.get("bag_capacity", 5))):
		var slot := _hud_icon_button(Vector2(36, 36))
		if i < GameState.bag.size():
			var item: Dictionary = GameState.bag[i]
			slot.icon = AssetDB.tex(_offer_art_id(str(item.get("id", ""))))
			slot.tooltip_text = _item_tooltip(i, item)
			_set_item_button_style(slot, item)
		else:
			slot.icon = AssetDB.tex("pickup_stone")
			slot.tooltip_text = "空道具格"
			_set_item_button_style(slot, {}, true)
		var slot_index := i
		slot.pressed.connect(func(): _show_item_detail(slot_index))
		row.add_child(slot)
	return box

func _market_stat_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "MarketStatPanel"
	panel.custom_minimum_size = Vector2(196, OFFER_CARD_SIZE.y)
	panel.add_theme_stylebox_override("panel", _compact_stylebox(Color(0.018, 0.032, 0.038, 0.84), Color("#5fe0c8"), 1, 6, 5, 4))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var title := Label.new()
	title.text = "角色数值"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("#e8b259"))
	box.add_child(title)
	for def in HUD_STAT_DEFS:
		var stat_entry := _stat_row_control(def)
		_refresh_stat_entry(stat_entry)
		var stat_def: Dictionary = def.duplicate(true)
		var row_panel: PanelContainer = stat_entry["panel"]
		row_panel.gui_input.connect(func(event): _on_stat_gui_input(event, stat_def))
		box.add_child(row_panel)
	return panel

func _clear_detail() -> void:
	if is_instance_valid(detail_layer):
		detail_layer.queue_free()
	detail_layer = CanvasLayer.new()
	detail_layer.layer = 20
	add_child(detail_layer)

func _show_detail(title_text: String, lines: Array, actions: Array) -> void:
	_clear_detail()
	var root := ColorRect.new()
	root.color = Color(0.0, 0.0, 0.0, 0.36)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_layer.add_child(root)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.32
	panel.anchor_top = 0.18
	panel.anchor_right = 0.68
	panel.anchor_bottom = 0.78
	panel.add_theme_stylebox_override("panel", _stylebox(Color(0.012, 0.024, 0.028, 0.96), Color("#e8b259"), 2, 8))
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = title_text
	_apply_display_font(title, 34, Color("#e8b259"), 2)
	box.add_child(title)
	var body := Label.new()
	body.text = "\n".join(lines)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color("#eaf6ff"))
	box.add_child(body)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	box.add_child(action_row)
	for action in actions:
		var button := Button.new()
		button.text = str(action.get("label", ""))
		button.custom_minimum_size = Vector2(112, 42)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.disabled = bool(action.get("disabled", false))
		var callback: Callable = action.get("callback", Callable())
		if callback.is_valid():
			button.pressed.connect(callback)
		action_row.add_child(button)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(92, 42)
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_clear_detail)
	action_row.add_child(close)

func _show_weapon_detail(place: String, index: int) -> void:
	if suppress_next_weapon_detail:
		suppress_next_weapon_detail = false
		return
	var weapon := GameState.weapon_at(place, index)
	if weapon.is_empty():
		_show_notice("这个槽位为空")
		return
	var tier := int(weapon.get("tier", 1))
	var title := "%s · %s" % [str(weapon.get("name", "")), GameState.weapon_tier_name(tier)]
	var lines := _weapon_tooltip(index, weapon, place == "reserve").split("\n")
	lines.append("出售：+%d灵石" % GameState.weapon_sell_value(weapon))
	if tier >= GameState.WEAPON_TIER_MAX:
		lines.append("已达满品，不能继续合并升级。")
	elif GameState.can_merge_weapon_at(place, index):
		lines.append("已有同名同品法器，可合并升至%s。" % GameState.weapon_tier_name(tier + 1))
	else:
		lines.append("需要另一件同名同品法器才能合并升级。")
	if place == "active" and GameState.weapon_reserve.size() >= GameState.weapon_reserve_capacity():
		lines.append("备炼栏满时，可拖拽到指定备炼槽交换。")
	if place == "reserve" and GameState.active_weapons.size() >= int(GameState.stats.get("weapon_slots", 4)):
		lines.append("主装备栏满时，可拖拽到指定主槽交换。")
	var actions: Array = []
	actions.append({
		"label": "合并升级",
		"disabled": not GameState.can_merge_weapon_at(place, index),
		"callback": func():
			if GameState.merge_weapon_at(place, index):
				_after_inventory_action("法器已合并升级")
	})
	if place == "active":
		actions.append({
			"label": "移至备炼",
			"disabled": GameState.weapon_reserve.size() >= GameState.weapon_reserve_capacity(),
			"callback": func():
				if GameState.move_weapon("active", index, "reserve", GameState.weapon_reserve.size()):
					_after_inventory_action("已移至备炼栏")
		})
	else:
		actions.append({
			"label": "装入主槽",
			"disabled": GameState.active_weapons.size() >= int(GameState.stats.get("weapon_slots", 4)),
			"callback": func():
				if GameState.move_weapon("reserve", index, "active", GameState.active_weapons.size()):
					_after_inventory_action("已装入主装备栏")
		})
	actions.append({
		"label": "出售",
		"callback": func():
			if GameState.sell_weapon_at(place, index):
				_after_inventory_action("已出售法器")
	})
	_show_detail(title, lines, actions)

func _show_item_detail(index: int) -> void:
	if index < 0 or index >= GameState.bag.size():
		_show_notice("这个道具格为空")
		return
	var item: Dictionary = GameState.bag[index]
	var title := str(item.get("name", "道具"))
	var lines := _item_tooltip(index, item).split("\n")
	lines.append("出售：+%d灵石" % GameState.item_sell_value(item))
	var actions: Array = [{
		"label": "出售",
		"callback": func():
			if GameState.sell_item_at(index):
				_after_inventory_action("已出售道具")
	}]
	_show_detail(title, lines, actions)

func _on_stat_gui_input(event: InputEvent, def: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_show_stat_detail(def)

func _show_stat_detail(def: Dictionary) -> void:
	var title := str(def.get("label", "数值"))
	var lines := [_stat_tooltip(def), "云游商会和境界机缘会刷出可提升数值的商品。"]
	_show_detail(title, lines, [])

func _on_weapon_slot_gui_input(event: InputEvent, place: String, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not GameState.weapon_at(place, index).is_empty():
				weapon_drag_source = {"place": place, "index": index}
		else:
			if weapon_drag_source.is_empty():
				return
			var target := _weapon_slot_at_position(event.global_position)
			if not target.is_empty() and (str(target["place"]) != str(weapon_drag_source["place"]) or int(target["index"]) != int(weapon_drag_source["index"])):
				if GameState.move_weapon(str(weapon_drag_source["place"]), int(weapon_drag_source["index"]), str(target["place"]), int(target["index"])):
					suppress_next_weapon_detail = true
					_after_inventory_action("已调整法器槽位")
				else:
					_show_notice("目标槽位不可用")
			weapon_drag_source = {}

func _weapon_slot_at_position(pos: Vector2) -> Dictionary:
	for i in range(weapon_slot_buttons.size()):
		var button: Button = weapon_slot_buttons[i]
		if button.visible and button.get_global_rect().has_point(pos):
			return {"place": "active", "index": i}
	for i in range(weapon_reserve_buttons.size()):
		var button: Button = weapon_reserve_buttons[i]
		if button.visible and button.get_global_rect().has_point(pos):
			return {"place": "reserve", "index": i}
	if market_open and is_instance_valid(overlay_layer):
		for button in overlay_layer.find_children("*", "Button", true, false):
			if not button.has_meta("weapon_place"):
				continue
			var weapon_button: Button = button
			if weapon_button.visible and weapon_button.get_global_rect().has_point(pos):
				return {"place": str(weapon_button.get_meta("weapon_place")), "index": int(weapon_button.get_meta("weapon_index"))}
	return {}

func _after_inventory_action(text: String) -> void:
	_clear_detail()
	if player != null:
		player.hp = min(player.hp, float(GameState.stats.get("max_hp", 110)))
		player.shield = min(player.shield, float(GameState.stats.get("max_qi_shield", 60)))
	_reset_weapon_cooldowns()
	_update_hud()
	if market_open:
		_render_market()
	_show_notice(text)

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
			_set_weapon_button_style(slot, int(w.get("tier", 1)))
		else:
			slot.icon = AssetDB.tex("pickup_qi")
			slot.tooltip_text = "空法器槽"
			_set_weapon_button_style(slot, 1, true)
	for i in range(weapon_reserve_buttons.size()):
		var slot: Button = weapon_reserve_buttons[i]
		if i < GameState.weapon_reserve.size():
			var w: Dictionary = GameState.weapon_reserve[i]
			slot.icon = AssetDB.tex(_offer_art_id(str(w.get("id", ""))))
			slot.tooltip_text = _weapon_tooltip(i, w, true)
			_set_weapon_button_style(slot, int(w.get("tier", 1)))
		else:
			slot.icon = AssetDB.tex("pickup_qi")
			slot.tooltip_text = "空备炼栏"
			_set_weapon_button_style(slot, 1, true)
	var bag_capacity := int(GameState.stats.get("bag_capacity", 5))
	var used_slots := _bag_used_slots()
	item_panel.offset_top = -158 if bag_capacity > 5 else -112
	bag_title_label.text = "道具 %d/%d" % [used_slots, bag_capacity]
	for i in range(item_slot_buttons.size()):
		var slot: Button = item_slot_buttons[i]
		slot.visible = i < bag_capacity
		if not slot.visible:
			continue
		if i < GameState.bag.size():
			var item: Dictionary = GameState.bag[i]
			slot.icon = AssetDB.tex(_offer_art_id(str(item.get("id", ""))))
			slot.tooltip_text = _item_tooltip(i, item)
			_set_item_button_style(slot, item)
		else:
			slot.icon = AssetDB.tex("pickup_stone")
			slot.tooltip_text = "空道具格"
			_set_item_button_style(slot, {}, true)
	for entry in stat_rows:
		_refresh_stat_entry(entry)

func _refresh_stat_entry(entry: Dictionary) -> void:
	var panel: PanelContainer = entry["panel"]
	var icon: TextureRect = entry["icon"]
	var value: Label = entry["value"]
	var def: Dictionary = entry["def"]
	icon.texture = AssetDB.tex(str(def["icon"]))
	value.text = _hud_stat_value(def)
	panel.tooltip_text = _stat_tooltip(def)

func _weapon_tooltip(index: int, weapon: Dictionary, reserve := false) -> String:
	var element := str(weapon.get("element", ""))
	var tier := int(weapon.get("tier", 1))
	var lines := [
		"%s%d. %s · %s" % ["备炼" if reserve else "", index + 1, str(weapon.get("name", "")), GameState.weapon_tier_name(tier)],
		"%s · %s" % [GameState.root_name(element), str(weapon.get("class", ""))],
		"伤害 %.0f  冷却 %.2fs  射程 %.0f" % [float(weapon.get("base_damage", 0.0)) * GameState.weapon_tier_multiplier(tier), float(weapon.get("cooldown", 0.0)), float(weapon.get("range", 0.0))]
	]
	for effect in weapon.get("on_hit", []):
		var row := _on_hit_row(effect, element)
		lines.append("%s %s" % [row.get("label", ""), row.get("value", "")])
	return "\n".join(lines)

func _bag_used_slots() -> int:
	return GameState.bag_used_slots()

func _item_tooltip(index: int, item: Dictionary) -> String:
	var element_value = item.get("element", null)
	var element := "" if element_value == null else str(element_value)
	var school := "通用" if element == "" else GameState.root_name(element)
	var lines := [
		"%d. %s" % [index + 1, str(item.get("name", ""))],
		"法宝 · %s · 占%d格" % [school, int(item.get("slots", 1))]
	]
	var summary := str(item.get("summary", ""))
	if not summary.is_empty():
		lines.append(summary)
	for key in item.get("effects", {}).keys():
		var row := _stat_effect_row(str(key), item["effects"][key], false)
		lines.append("%s %s" % [row.get("label", ""), row.get("value", "")])
	for key in item.get("cost_effects", {}).keys():
		var row := _stat_effect_row(str(key), item["cost_effects"][key], true)
		lines.append("%s %s" % [row.get("label", ""), row.get("value", "")])
	return "\n".join(lines)

func _hud_stat_value(def: Dictionary) -> String:
	var key := str(def["key"])
	var current = GameState.stats.get(key, 0.0)
	if key == "speed_pct":
		return "%.0f%%" % ((1.0 + float(current)) * 100.0)
	return _effect_value_text(key, current)

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
		extra = "\n法宝背包 %d/%d\n备炼栏 %d/%d" % [GameState.bag.size(), int(GameState.stats.get("bag_capacity", 5)), GameState.weapon_reserve.size(), GameState.weapon_reserve_capacity()]
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
