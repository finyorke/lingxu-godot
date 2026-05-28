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
		"res://assets/enemies/enemies_sheet.png",
		"res://assets/enemies/sword_demon.png",
		"res://assets/weapons/weapon_icons.png",
		"res://assets/fx/combat_fx.png",
		"res://assets/fonts/NotoSansCJKsc-Regular.otf"
	]
	for path in required_assets:
		if not FileAccess.file_exists(path):
			failures.append("missing asset %s" % path)
	if not ResourceLoader.exists("res://Scenes/Main.tscn"):
		failures.append("main scene missing")
	if failures.is_empty():
		print("SMOKE OK: data, CJK font, generated assets, and main scene are present.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
