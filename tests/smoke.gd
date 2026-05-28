extends SceneTree

func _init() -> void:
	var failures: Array = []
	var config = load("res://Scripts/autoload/ConfigDB.gd").new()
	root.add_child(config)
	config.load_all()
	var weapons: Dictionary = config.table("weapons")
	var items: Dictionary = config.table("items")
	var enemies: Dictionary = config.table("enemies")
	if weapons.size() < 35:
		failures.append("expected 35 weapons, got %d" % weapons.size())
	if items.size() < 15:
		failures.append("expected 15 items, got %d" % items.size())
	if not enemies.has("sword_demon"):
		failures.append("missing final boss sword_demon")
	var required_assets := [
		"res://assets/backgrounds/main_menu.png",
		"res://assets/backgrounds/arena.png",
		"res://assets/sprites/yunxi.png",
		"res://assets/sprites/yunxi_walk_24.png",
		"res://assets/enemies/enemies_sheet.png",
		"res://assets/enemies/serpent_boss.png",
		"res://assets/enemies/sword_demon.png",
		"res://assets/weapons/weapon_icons.png",
		"res://assets/weapons/icon_wood.png",
		"res://assets/ui/offer_icons.png",
		"res://assets/ui/offer_stat_attack_speed.png",
		"res://assets/ui/offer_stat_engineering.png",
		"res://assets/ui/offer_stat_range.png",
		"res://assets/ui/offer_stat_spell_power.png",
		"res://assets/fx/combat_fx.png",
		"res://assets/fonts/NotoSansCJKsc-Regular.otf",
		"res://assets/fonts/MaShanZheng-Regular.ttf"
	]
	for path in required_assets:
		if not FileAccess.file_exists(path):
			failures.append("missing asset %s" % path)
	if not ResourceLoader.exists("res://Scenes/Main.tscn"):
		failures.append("main scene missing")
	var asset_db = load("res://Scripts/autoload/AssetDB.gd").new()
	root.add_child(asset_db)
	asset_db.load_manifest()
	for id in ["offer_guanri_sword", "offer_hantan_sword", "offer_turtle_charm", "offer_stat_attack_speed", "offer_blood_return"]:
		if not asset_db.manifest.has(id):
			failures.append("missing market offer icon manifest entry %s" % id)
	var standalone_icons := {
		"icon_wood": {"path": "res://assets/weapons/icon_wood.png", "min_width": 300, "min_height": 500},
		"offer_stat_spell_power": {"path": "res://assets/ui/offer_stat_spell_power.png", "min_width": 128, "min_height": 128},
		"offer_stat_engineering": {"path": "res://assets/ui/offer_stat_engineering.png", "min_width": 128, "min_height": 128},
		"offer_stat_range": {"path": "res://assets/ui/offer_stat_range.png", "min_width": 128, "min_height": 128},
		"offer_stat_attack_speed": {"path": "res://assets/ui/offer_stat_attack_speed.png", "min_width": 512, "min_height": 512},
	}
	for id in standalone_icons:
		var expected: Dictionary = standalone_icons[id]
		var info: Dictionary = asset_db.manifest.get(id, {})
		if str(info.get("path", "")) != str(expected["path"]):
			failures.append("%s must use standalone icon %s" % [id, expected["path"]])
		if info.has("region"):
			failures.append("%s must not use an atlas region" % id)
		var tex: Texture2D = asset_db.tex(id)
		if tex == null or tex.get_width() < int(expected["min_width"]) or tex.get_height() < int(expected["min_height"]):
			failures.append("%s texture did not load at expected standalone dimensions" % id)
	var display_font: Font = load("res://assets/fonts/MaShanZheng-Regular.ttf")
	var body_font: Font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	if not body_font.has_char(0x00b7):
		failures.append("NotoSansCJKsc-Regular.otf must contain the middle dot glyph")
	var font_util = load("res://Scripts/FontUtil.gd")
	font_util.ensure_fallback(display_font, body_font)
	if not _font_has_fallback(display_font, body_font.resource_path):
		failures.append("display font must fall back to NotoSansCJKsc-Regular.otf")
	var yunxi_motion_info: Dictionary = asset_db.manifest.get("char_yunxi_walk_24", {})
	if int(yunxi_motion_info.get("frames", 0)) < 20:
		failures.append("char_yunxi_walk_24 must provide at least 20 continuous animation frames")
	var yunxi_motion_grid: Array = yunxi_motion_info.get("grid", [])
	if yunxi_motion_grid.size() != 2 or int(yunxi_motion_grid[0]) != 6 or int(yunxi_motion_grid[1]) != 4:
		failures.append("char_yunxi_walk_24 must use the expected 6x4 frame grid")
	var yunxi_motion_tex: Texture2D = asset_db.tex("char_yunxi_walk_24")
	if yunxi_motion_tex == null or yunxi_motion_tex.get_width() != 1536 or yunxi_motion_tex.get_height() != 1024:
		failures.append("char_yunxi_walk_24 texture did not load at the expected 1536x1024 sheet size")
	var yunxi_motion_image := Image.new()
	var yunxi_motion_file := FileAccess.open("res://assets/sprites/yunxi_walk_24.png", FileAccess.READ)
	var yunxi_motion_error := ERR_FILE_CANT_OPEN
	if yunxi_motion_file != null:
		yunxi_motion_error = yunxi_motion_image.load_png_from_buffer(yunxi_motion_file.get_buffer(yunxi_motion_file.get_length()))
	if yunxi_motion_error != OK or yunxi_motion_image.is_empty():
		failures.append("char_yunxi_walk_24 source image could not be inspected")
	else:
		var cell_size := 256
		var frame_0 := yunxi_motion_image.get_region(Rect2i(0, 0, cell_size, cell_size))
		var frame_6 := yunxi_motion_image.get_region(Rect2i(0, cell_size, cell_size, cell_size))
		var frame_12 := yunxi_motion_image.get_region(Rect2i(0, cell_size * 2, cell_size, cell_size))
		if _frame_diff(frame_0, frame_6) < 1200.0:
			failures.append("char_yunxi_walk_24 frame 6 is too similar to frame 0")
		if _frame_diff(frame_0, frame_12) < 1200.0:
			failures.append("char_yunxi_walk_24 frame 12 must be a distinct opposite walk pose")
	if failures.is_empty():
		print("SMOKE OK: data, CJK font, generated assets, and main scene are present.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _font_has_fallback(font: Font, fallback_path: String) -> bool:
	for fallback: Font in font.get_fallbacks():
		if fallback.resource_path == fallback_path:
			return true
	return false

func _frame_diff(a: Image, b: Image) -> float:
	var total := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
	return total
