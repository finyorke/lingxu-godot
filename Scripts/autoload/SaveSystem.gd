extends Node

const SAVE_PATH := "user://save.json"

var meta := {}
var settings := {}

func _ready() -> void:
	load_save()

func load_save() -> void:
	meta = ConfigDB.table("meta").duplicate(true)
	settings = meta.get("settings", {}).duplicate(true)
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		meta.merge(parsed, true)
		settings = meta.get("settings", {}).duplicate(true)

func save() -> void:
	meta["settings"] = settings
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(meta, "\t"))

func reset_save() -> void:
	meta = ConfigDB.table("meta").duplicate(true)
	settings = meta.get("settings", {}).duplicate(true)
	save()

func record_run(run_stats: Dictionary) -> void:
	meta["runs_completed"] = int(meta.get("runs_completed", 0)) + 1
	meta["best_survive_time"] = max(float(meta.get("best_survive_time", 0.0)), float(run_stats.get("time", 0.0)))
	meta["best_kills"] = max(int(meta.get("best_kills", 0)), int(run_stats.get("kills", 0)))
	meta["best_combo"] = max(int(meta.get("best_combo", 0)), int(run_stats.get("combo", 0)))
	meta["spirit_jade"] = int(meta.get("spirit_jade", 0)) + int(run_stats.get("jade", 0))
	meta["essence"] = int(meta.get("essence", 0)) + int(run_stats.get("essence", 0))
	save()
