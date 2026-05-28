extends Node

const DISPLAY_FONT := preload("res://assets/fonts/MaShanZheng-Regular.ttf")
const ELEMENTS := ["metal", "wood", "water", "fire", "earth"]
const ROOT_INFO := {
	"metal": {"name": "金系御剑", "seal": "庚金剑印", "tag": "飞剑 / 贯穿 / 高频单体", "desc": "剑气凝霜，斩线破阵。", "icon": "icon_metal", "color": "#eaf6ff"},
	"wood": {"name": "木系毒蛊", "seal": "青木蛊印", "tag": "中毒 / 瘟疫 / 持续 AoE", "desc": "藤息入脉，疫雾缠身。", "icon": "icon_wood", "color": "#7ccb5a"},
	"water": {"name": "水系守护", "seal": "玄水寒印", "tag": "护盾 / 冰寒 / 减速", "desc": "寒潮护体，冰魄封敌。", "icon": "icon_water", "color": "#5aa9e0"},
	"fire": {"name": "火系焚天", "seal": "赤焰符印", "tag": "灼烧 / 爆发 / 斩杀", "desc": "业火临锋，一念燎原。", "icon": "icon_fire", "color": "#f27348"},
	"earth": {"name": "土系镇岳", "seal": "厚土岳印", "tag": "护甲 / 震荡 / 石化", "desc": "山河落印，镇邪成牢。", "icon": "icon_earth", "color": "#d9a441"}
}

var current_screen: Node
var sealed := {}
var root_buttons := {}
var root_card_views := {}
var preview_label: Label
var confirm_button: Button
var affinity_option: OptionButton

func _ready() -> void:
	_ensure_input_map()
	show_main_menu()

func _ensure_input_map() -> void:
	var defaults := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"dash": [KEY_SPACE],
		"sword_burst": [KEY_J],
		"skill_q": [KEY_Q],
		"skill_e": [KEY_E],
		"skill_r": [KEY_R],
		"pause": [KEY_ESCAPE]
	}
	for action in defaults.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			for code in defaults[action]:
				var ev := InputEventKey.new()
				ev.keycode = code
				InputMap.action_add_event(action, ev)
	if InputMap.action_get_events("sword_burst").size() < 2:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("sword_burst", mb)

func _clear() -> void:
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null

func show_main_menu() -> void:
	_clear()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	current_screen = root
	add_child(root)
	_add_background(root, "bg_menu", 0.82)
	_add_vignette(root, 0.48)
	var shell := _content_panel(root, Rect2(0.065, 0.055, 0.45, 0.875), Color(0.018, 0.032, 0.032, 0.64), Color(0.36, 0.88, 0.8, 0.34), 8)
	var panel: VBoxContainer = shell.get_node("Margin/Box")
	panel.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "御剑灵墟"
	_apply_display_font(title, 88, Color("#eaf6ff"), 4)
	panel.add_child(title)
	var sub := Label.new()
	sub.text = "末代御剑修士云栖 · 四法器自动斩妖 · 五行灵根构筑"
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color("#f4ecd8"))
	panel.add_child(sub)
	panel.add_child(_make_rule(Color("#5fe0c8"), 0.46))
	panel.add_child(_make_gap(8))
	var start := _menu_button("入墟历劫", "进入灵根抉择")
	start.pressed.connect(show_root_choice)
	panel.add_child(start)
	var cave := _menu_button("洞府修行", "查看本地存档与局外资源")
	cave.pressed.connect(_show_cave)
	panel.add_child(cave)
	var reset := _menu_button("重置道途", "清空本地测试存档")
	reset.pressed.connect(func():
		SaveSystem.reset_save()
		show_main_menu()
	)
	panel.add_child(reset)
	panel.add_child(_make_gap(12))
	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.06, 0.025, 0.68), Color("#e8b259"), 1, 6, 12))
	panel.add_child(stats_panel)
	var stats := Label.new()
	stats.text = "灵玉 %s    精魄 %s\n最佳 %.0fs    最高斩妖 %s" % [
		SaveSystem.meta.get("spirit_jade", 0),
		SaveSystem.meta.get("essence", 0),
		float(SaveSystem.meta.get("best_survive_time", 0.0)),
		SaveSystem.meta.get("best_kills", 0)
	]
	stats.add_theme_font_size_override("font_size", 22)
	stats.add_theme_color_override("font_color", Color("#e8b259"))
	stats_panel.add_child(stats)

func _show_cave() -> void:
	_clear()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	current_screen = root
	add_child(root)
	_add_background(root, "bg_menu", 0.5)
	_add_vignette(root, 0.48)
	var panel := _content_panel(root, Rect2(0.12, 0.12, 0.76, 0.74), Color(0.018, 0.032, 0.035, 0.76), Color("#5fe0c8"), 8)
	var box: VBoxContainer = panel.get_node("Margin/Box")
	box.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "洞府修行"
	_apply_display_font(title, 58, Color("#eaf6ff"), 3)
	box.add_child(title)
	box.add_child(_make_rule(Color("#5fe0c8"), 0.5))
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "测试版已记录灵玉、精魄、最佳存活、最高连斩等局外数据。本轮先实现可试玩闭环，洞府法宝强化已保留存档入口，后续可继续扩展永久法宝等级。"
	body.add_theme_font_size_override("font_size", 26)
	body.add_theme_color_override("font_color", Color("#f4ecd8"))
	box.add_child(body)
	var back := _menu_button("回宗门", "")
	back.pressed.connect(show_main_menu)
	box.add_child(back)

func show_root_choice() -> void:
	_clear()
	sealed.clear()
	root_buttons.clear()
	root_card_views.clear()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	current_screen = root
	add_child(root)
	_add_background(root, "bg_menu", 0.76)
	_add_vignette(root, 0.52)
	var title := Label.new()
	title.text = "灵根抉择"
	title.anchor_left = 0.08
	title.anchor_top = 0.045
	title.anchor_right = 0.92
	title.anchor_bottom = 0.14
	_apply_display_font(title, 70, Color("#eaf6ff"), 4)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "封印至多二道灵根，保留的五行将决定本局商店、Boss 掉落与法器构筑。"
	subtitle.anchor_left = 0.08
	subtitle.anchor_top = 0.132
	subtitle.anchor_right = 0.92
	subtitle.anchor_bottom = 0.18
	subtitle.add_theme_font_size_override("font_size", 23)
	subtitle.add_theme_color_override("font_color", Color("#d8f6ef"))
	root.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.anchor_left = 0.055
	grid.anchor_top = 0.19
	grid.anchor_right = 0.945
	grid.anchor_bottom = 0.56
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	root.add_child(grid)
	for e in ELEMENTS:
		grid.add_child(_root_card(e))

	var controls_panel := _content_panel(root, Rect2(0.08, 0.61, 0.42, 0.29), Color(0.018, 0.032, 0.035, 0.78), Color(0.36, 0.88, 0.8, 0.38), 8)
	var controls: VBoxContainer = controls_panel.get_node("Margin/Box")
	controls.add_theme_constant_override("separation", 13)
	var label := Label.new()
	label.text = "修行体质"
	_apply_display_font(label, 34, Color("#e8b259"), 2)
	controls.add_child(label)
	affinity_option = OptionButton.new()
	affinity_option.custom_minimum_size = Vector2(0, 48)
	affinity_option.add_theme_font_size_override("font_size", 21)
	affinity_option.add_theme_stylebox_override("normal", _panel_style(Color(0.016, 0.026, 0.03, 0.86), Color(0.36, 0.88, 0.8, 0.45), 1, 5, 10))
	_add_affinity("五行灵根：五行皆通，属性加成互转", "five")
	for e in ELEMENTS:
		_add_affinity("%s单灵根：本系大幅增伤，异系只吃基础" % GameState.root_name(e), "single_%s" % e)
	var duals := [["metal", "water"], ["water", "wood"], ["wood", "fire"], ["fire", "earth"], ["earth", "metal"]]
	for pair in duals:
		_add_affinity("%s%s双修：双系增伤并互转" % [GameState.root_name(pair[0]), GameState.root_name(pair[1])], "dual_%s_%s" % [pair[0], pair[1]])
	controls.add_child(affinity_option)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	controls.add_child(row)
	var back := _small_button("回宗门", Color("#8ea9a3"))
	back.pressed.connect(show_main_menu)
	row.add_child(back)
	var random_btn := _small_button("随机抉择", Color("#5fe0c8"))
	random_btn.pressed.connect(_random_roots)
	row.add_child(random_btn)
	confirm_button = _primary_button("确认入墟")
	confirm_button.pressed.connect(_confirm_roots)
	row.add_child(confirm_button)

	var preview_panel := _content_panel(root, Rect2(0.525, 0.61, 0.395, 0.29), Color(0.018, 0.032, 0.035, 0.78), Color("#e8b259"), 8)
	var preview_box: VBoxContainer = preview_panel.get_node("Margin/Box")
	var preview_title := Label.new()
	preview_title.text = "道途回响"
	_apply_display_font(preview_title, 32, Color("#e8b259"), 2)
	preview_box.add_child(preview_title)
	preview_label = Label.new()
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.add_theme_font_size_override("font_size", 22)
	preview_label.add_theme_color_override("font_color", Color("#eaf6ff"))
	preview_box.add_child(preview_label)

	_update_root_preview()

func _add_affinity(text: String, id: String) -> void:
	affinity_option.add_item(text)
	affinity_option.set_item_metadata(affinity_option.item_count - 1, id)

func _root_card(element: String) -> Button:
	var info: Dictionary = ROOT_INFO[element]
	var accent := Color(str(info["color"]))
	var button := Button.new()
	button.custom_minimum_size = Vector2(310, 342)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _root_card_style(element, false, false))
	button.add_theme_stylebox_override("hover", _root_card_style(element, false, true))
	button.add_theme_stylebox_override("pressed", _root_card_style(element, false, true))
	button.pressed.connect(func(element_id: String = element): _toggle_root(element_id))
	root_buttons[element] = button

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	button.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var seal := Label.new()
	seal.text = str(info["seal"])
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal.add_theme_font_size_override("font_size", 18)
	seal.add_theme_color_override("font_color", Color("#cfe5e0"))
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(seal)

	var icon := TextureRect.new()
	icon.texture = AssetDB.tex(str(info["icon"]))
	icon.custom_minimum_size = Vector2(0, 126)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1.05, 1.05, 1.05, 1.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var title := Label.new()
	title.text = str(info["name"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_display_font(title, 34, accent, 2)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	var tag := Label.new()
	tag.text = str(info["tag"])
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", Color("#fff8e8"))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tag)

	var desc := Label.new()
	desc.text = str(info["desc"])
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 17)
	desc.add_theme_color_override("font_color", Color("#cfe5e0"))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)

	var status := Label.new()
	status.text = "本局可用"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 22)
	status.add_theme_color_override("font_color", Color("#5fe0c8"))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(status)

	var seal_mark := Label.new()
	seal_mark.text = "封"
	seal_mark.anchor_left = 0.68
	seal_mark.anchor_top = 0.12
	seal_mark.anchor_right = 1.02
	seal_mark.anchor_bottom = 0.52
	seal_mark.rotation = -0.18
	seal_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_display_font(seal_mark, 96, Color(0.95, 0.2, 0.16, 0.8), 3)
	seal_mark.visible = false
	seal_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(seal_mark)

	root_card_views[element] = {"status": status, "seal_mark": seal_mark}
	return button

func _root_card_style(element: String, is_sealed: bool, hover: bool) -> StyleBoxFlat:
	var accent := Color(str(ROOT_INFO[element]["color"]))
	var bg_alpha := 0.1 if is_sealed else 0.2
	if hover and not is_sealed:
		bg_alpha = 0.3
	var border_alpha := 0.3 if is_sealed else (0.78 if hover else 0.5)
	var bg := Color(0.012, 0.024, 0.026, 0.9)
	bg = bg.lerp(accent, bg_alpha)
	var box := _panel_style(bg, Color(accent.r, accent.g, accent.b, border_alpha), 2 if hover else 1, 8, 10)
	box.shadow_color = Color(accent.r, accent.g, accent.b, 0.22 if hover else 0.1)
	box.shadow_size = 12 if hover else 6
	return box

func _apply_display_font(control: Control, size: int, color: Color, outline_size := 0) -> void:
	control.add_theme_font_override("font", DISPLAY_FONT)
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	if outline_size > 0:
		control.add_theme_constant_override("outline_size", outline_size)
		control.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.035, 0.92))

func _content_panel(parent: Control, rect: Rect2, bg: Color, border: Color, radius := 8) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = rect.position.x
	panel.anchor_top = rect.position.y
	panel.anchor_right = rect.position.x + rect.size.x
	panel.anchor_bottom = rect.position.y + rect.size.y
	panel.add_theme_stylebox_override("panel", _panel_style(bg, border, 1, radius, 18))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	return panel

func _panel_style(bg: Color, border: Color, border_width: int, radius: int, margin := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	box.shadow_color = Color(0, 0, 0, 0.34)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 2)
	return box

func _make_rule(color: Color, alpha: float) -> ColorRect:
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(1, 2)
	rule.color = Color(color.r, color.g, color.b, alpha)
	return rule

func _primary_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 58)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_display_font(button, 34, Color("#fff8e8"), 2)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.12, 0.075, 0.02, 0.86), Color("#e8b259"), 2, 7, 10))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.2, 0.12, 0.035, 0.95), Color("#fff4b8"), 2, 7, 10))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.25, 0.16, 0.045, 0.98), Color("#5fe0c8"), 2, 7, 10))
	return button

func _small_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(170, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_display_font(button, 28, Color("#eaf6ff"), 1)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.018, 0.032, 0.035, 0.78), Color(accent.r, accent.g, accent.b, 0.52), 1, 6, 8))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.035, 0.06, 0.062, 0.9), accent, 2, 6, 8))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.07, 0.065, 0.03, 0.95), Color("#e8b259"), 2, 6, 8))
	return button

func _toggle_root(element: String) -> void:
	if sealed.has(element):
		sealed.erase(element)
	elif sealed.size() < 2:
		sealed[element] = true
	else:
		root_buttons[element].button_pressed = false
	_update_root_preview()

func _random_roots() -> void:
	sealed.clear()
	var candidates := ELEMENTS.duplicate()
	candidates.shuffle()
	var count := randi_range(0, 2)
	for i in range(count):
		sealed[candidates[i]] = true
	for e in ELEMENTS:
		root_buttons[e].button_pressed = sealed.has(e)
	_update_root_preview()

func _active_roots() -> Array:
	var active: Array = []
	for e in ELEMENTS:
		if not sealed.has(e):
			active.append(e)
	return active

func _update_root_preview() -> void:
	for e in ELEMENTS:
		var b: Button = root_buttons[e]
		var view: Dictionary = root_card_views.get(e, {})
		var is_sealed := sealed.has(e)
		b.button_pressed = is_sealed
		b.modulate = Color(0.46, 0.5, 0.5, 1.0) if is_sealed else Color.WHITE
		b.add_theme_stylebox_override("normal", _root_card_style(e, is_sealed, false))
		b.add_theme_stylebox_override("hover", _root_card_style(e, is_sealed, true))
		b.add_theme_stylebox_override("pressed", _root_card_style(e, is_sealed, true))
		if view.has("status"):
			var status: Label = view["status"]
			status.text = "已封印" if is_sealed else "本局可用"
			status.add_theme_color_override("font_color", Color("#f27348") if is_sealed else Color("#5fe0c8"))
		if view.has("seal_mark"):
			var seal_mark: Label = view["seal_mark"]
			seal_mark.visible = is_sealed
	var active := _active_roots()
	var active_names := []
	for e in active:
		active_names.append(GameState.root_name(e))
	GameState.active_roots = active
	var lines := GameState.synergy_lines()
	preview_label.text = "封印：%d / 2    道途：%s\n商店与 Boss 掉落只围绕未封灵根，中性/通用卡照常出现。\n%s\n多属性法器伤害倍率：1系100%% / 2系116%% / 3系132%% / 4系150%%。" % [
		sealed.size(),
		" / ".join(active_names),
		"\n".join(lines)
	]

func _confirm_roots() -> void:
	var active := _active_roots()
	var sealed_arr := []
	for e in ELEMENTS:
		if sealed.has(e):
			sealed_arr.append(e)
	var affinity := str(affinity_option.get_item_metadata(affinity_option.selected))
	GameState.start_run(active, sealed_arr, affinity)
	_start_arena()

func _start_arena() -> void:
	_clear()
	var arena_scene = load("res://Scenes/Arena.tscn")
	current_screen = arena_scene.instantiate()
	current_screen.run_ended.connect(_on_run_ended)
	add_child(current_screen)

func _on_run_ended(result: Dictionary) -> void:
	SaveSystem.record_run(result)
	show_result(result)

func show_result(result: Dictionary) -> void:
	_clear()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	current_screen = root
	add_child(root)
	_add_background(root, "bg_menu", 0.55)
	_add_vignette(root, 0.48)
	var panel := _content_panel(root, Rect2(0.14, 0.15, 0.72, 0.73), Color(0.018, 0.032, 0.035, 0.78), Color("#e8b259"), 8)
	var box: VBoxContainer = panel.get_node("Margin/Box")
	box.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = result.get("title", "历劫结算")
	_apply_display_font(title, 66, Color("#e8b259"), 3)
	box.add_child(title)
	box.add_child(_make_rule(Color("#e8b259"), 0.5))
	var body := Label.new()
	body.add_theme_font_size_override("font_size", 28)
	body.add_theme_color_override("font_color", Color("#f4ecd8"))
	body.text = "存活 %.0fs  境界 %s  斩妖 %d  最高连斩 %d\n灵玉 +%d  精魄 +%d  本局灵根 %s" % [
		float(result.get("time", 0.0)),
		result.get("realm", "练气"),
		int(result.get("kills", 0)),
		int(result.get("combo", 0)),
		int(result.get("jade", 0)),
		int(result.get("essence", 0)),
		" / ".join(result.get("roots", []))
	]
	box.add_child(body)
	var again := _menu_button("入下一劫", "")
	again.pressed.connect(show_root_choice)
	box.add_child(again)
	var menu := _menu_button("回宗门", "")
	menu.pressed.connect(show_main_menu)
	box.add_child(menu)

func _add_background(parent: Control, id: String, alpha: float) -> void:
	var bg := TextureRect.new()
	bg.texture = AssetDB.tex(id)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(1, 1, 1, alpha)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.07, 0.06, 0.42)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(shade)

func _add_vignette(parent: Control, alpha: float) -> void:
	var top := ColorRect.new()
	top.color = Color(0.0, 0.0, 0.0, alpha)
	top.anchor_left = 0.0
	top.anchor_top = 0.0
	top.anchor_right = 1.0
	top.anchor_bottom = 0.08
	parent.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = Color(0.0, 0.0, 0.0, alpha * 0.82)
	bottom.anchor_left = 0.0
	bottom.anchor_top = 0.92
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	parent.add_child(bottom)

func _menu_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(340, 62)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_display_font(b, 34, Color("#eaf6ff"), 2)
	b.add_theme_stylebox_override("normal", _panel_style(Color(0.016, 0.026, 0.03, 0.78), Color(0.36, 0.88, 0.8, 0.45), 1, 6, 10))
	b.add_theme_stylebox_override("hover", _panel_style(Color(0.035, 0.06, 0.062, 0.94), Color("#e8b259"), 2, 6, 10))
	b.add_theme_stylebox_override("pressed", _panel_style(Color(0.07, 0.065, 0.03, 0.98), Color("#fff4b8"), 2, 6, 10))
	return b

func _make_gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(1, height)
	return c
