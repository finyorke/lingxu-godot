extends Node

const ELEMENTS := ["metal", "wood", "water", "fire", "earth"]
const ROOT_INFO := {
	"metal": {"name": "金·御剑", "tag": "飞剑·贯穿·高频单体", "color": "#eaf6ff"},
	"wood": {"name": "木·毒蛊", "tag": "中毒·瘟疫·持续 AoE", "color": "#7ccb5a"},
	"water": {"name": "水·守护", "tag": "护盾·冰寒·减速", "color": "#5aa9e0"},
	"fire": {"name": "火·焚天", "tag": "灼烧·爆发·斩杀", "color": "#f27348"},
	"earth": {"name": "土·镇岳", "tag": "护甲·震荡·石化·召唤", "color": "#d9a441"}
}

var current_screen: Node
var sealed := {}
var root_buttons := {}
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
	_add_background(root, "bg_menu", 0.72)
	var panel := VBoxContainer.new()
	panel.anchor_left = 0.07
	panel.anchor_top = 0.09
	panel.anchor_right = 0.48
	panel.anchor_bottom = 0.94
	panel.add_theme_constant_override("separation", 18)
	root.add_child(panel)
	var title := Label.new()
	title.text = "御剑灵墟"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color("#eaf6ff"))
	panel.add_child(title)
	var sub := Label.new()
	sub.text = "末代御剑修士云栖 · 四法器自动斩妖 · 五行灵根构筑"
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color("#f4ecd8"))
	panel.add_child(sub)
	panel.add_child(_make_gap(20))
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
	var stats := Label.new()
	stats.text = "灵玉 %s  精魄 %s  最佳 %.0fs  最高斩妖 %s" % [
		SaveSystem.meta.get("spirit_jade", 0),
		SaveSystem.meta.get("essence", 0),
		float(SaveSystem.meta.get("best_survive_time", 0.0)),
		SaveSystem.meta.get("best_kills", 0)
	]
	stats.add_theme_font_size_override("font_size", 22)
	stats.add_theme_color_override("font_color", Color("#e8b259"))
	panel.add_child(stats)

func _show_cave() -> void:
	_clear()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	current_screen = root
	add_child(root)
	_add_background(root, "bg_menu", 0.5)
	var box := VBoxContainer.new()
	box.anchor_left = 0.12
	box.anchor_top = 0.12
	box.anchor_right = 0.88
	box.anchor_bottom = 0.86
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	var title := Label.new()
	title.text = "洞府修行"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("#eaf6ff"))
	box.add_child(title)
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
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	current_screen = root
	add_child(root)
	_add_background(root, "bg_menu", 0.55)
	var title := Label.new()
	title.text = "灵根抉择"
	title.anchor_left = 0.08
	title.anchor_top = 0.06
	title.anchor_right = 0.92
	title.anchor_bottom = 0.14
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color("#eaf6ff"))
	root.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.anchor_left = 0.08
	grid.anchor_top = 0.18
	grid.anchor_right = 0.92
	grid.anchor_bottom = 0.49
	grid.add_theme_constant_override("h_separation", 12)
	root.add_child(grid)
	for e in ELEMENTS:
		var info: Dictionary = ROOT_INFO[e]
		var button := Button.new()
		button.custom_minimum_size = Vector2(300, 250)
		button.toggle_mode = true
		button.text = "%s\n%s\n点击封印" % [info["name"], info["tag"]]
		button.add_theme_font_size_override("font_size", 24)
		button.add_theme_color_override("font_color", Color(info["color"]))
		button.pressed.connect(func(element: String = e): _toggle_root(element))
		root_buttons[e] = button
		grid.add_child(button)
	var controls := VBoxContainer.new()
	controls.anchor_left = 0.08
	controls.anchor_top = 0.54
	controls.anchor_right = 0.92
	controls.anchor_bottom = 0.93
	controls.add_theme_constant_override("separation", 16)
	root.add_child(controls)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	controls.add_child(row)
	var label := Label.new()
	label.text = "修行体质"
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color("#f4ecd8"))
	row.add_child(label)
	affinity_option = OptionButton.new()
	affinity_option.custom_minimum_size = Vector2(390, 42)
	_add_affinity("五行灵根：五行皆通，属性加成互转", "five")
	for e in ELEMENTS:
		_add_affinity("%s单灵根：本系大幅增伤，异系只吃基础" % GameState.root_name(e), "single_%s" % e)
	var duals := [["metal", "water"], ["water", "wood"], ["wood", "fire"], ["fire", "earth"], ["earth", "metal"]]
	for pair in duals:
		_add_affinity("%s%s双修：双系增伤并互转" % [GameState.root_name(pair[0]), GameState.root_name(pair[1])], "dual_%s_%s" % [pair[0], pair[1]])
	row.add_child(affinity_option)
	var random_btn := Button.new()
	random_btn.text = "随机抉择"
	random_btn.custom_minimum_size = Vector2(170, 42)
	random_btn.pressed.connect(_random_roots)
	row.add_child(random_btn)
	confirm_button = Button.new()
	confirm_button.text = "确认 · 入墟"
	confirm_button.custom_minimum_size = Vector2(180, 42)
	confirm_button.pressed.connect(_confirm_roots)
	row.add_child(confirm_button)
	preview_label = Label.new()
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.add_theme_font_size_override("font_size", 25)
	preview_label.add_theme_color_override("font_color", Color("#eaf6ff"))
	controls.add_child(preview_label)
	var back := Button.new()
	back.text = "回宗门"
	back.custom_minimum_size = Vector2(160, 42)
	back.pressed.connect(show_main_menu)
	controls.add_child(back)
	_update_root_preview()

func _add_affinity(text: String, id: String) -> void:
	affinity_option.add_item(text)
	affinity_option.set_item_metadata(affinity_option.item_count - 1, id)

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
		var info: Dictionary = ROOT_INFO[e]
		b.text = "%s\n%s\n%s" % [info["name"], info["tag"], "已封印" if sealed.has(e) else "本局可用"]
		b.modulate = Color(0.55, 0.55, 0.55, 1.0) if sealed.has(e) else Color.WHITE
	var active := _active_roots()
	var active_names := []
	for e in active:
		active_names.append(GameState.root_name(e))
	GameState.active_roots = active
	var lines := GameState.synergy_lines()
	preview_label.text = "可封印 0-2 道；当前封印 %d，道途：%s\n商店与 Boss 掉落只围绕未封灵根，中性/通用卡照常出现。\n%s\n多属性法器伤害倍率：1系100%% / 2系116%% / 3系132%% / 4系150%%。" % [
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
	var box := VBoxContainer.new()
	box.anchor_left = 0.14
	box.anchor_top = 0.15
	box.anchor_right = 0.86
	box.anchor_bottom = 0.88
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)
	var title := Label.new()
	title.text = result.get("title", "历劫结算")
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color("#e8b259"))
	box.add_child(title)
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

func _menu_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(280, 54)
	b.add_theme_font_size_override("font_size", 28)
	return b

func _make_gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(1, height)
	return c
