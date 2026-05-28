extends Node

var tables := {}
var loaded := false

func _ready() -> void:
	load_all()

func load_all() -> void:
	tables.clear()
	var dir := DirAccess.open("res://Data")
	if dir == null:
		push_error("ConfigDB: cannot open res://Data")
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path := "res://Data/%s" % file_name
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("ConfigDB: cannot read %s" % path)
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed == null:
			push_error("ConfigDB: invalid JSON %s" % path)
			continue
		tables[file_name.get_basename()] = parsed
	loaded = true

func table(name: String) -> Variant:
	if not loaded:
		load_all()
	return tables.get(name, {})

func entry(table_name: String, id: String) -> Dictionary:
	var t = table(table_name)
	if typeof(t) != TYPE_DICTIONARY:
		return {}
	return t.get(id, {})

func keys(table_name: String) -> Array:
	var t = table(table_name)
	if typeof(t) != TYPE_DICTIONARY:
		return []
	var result: Array = []
	for k in t.keys():
		if not str(k).begins_with("_"):
			result.append(k)
	return result
