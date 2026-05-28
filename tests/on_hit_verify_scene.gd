extends Node

func _ready() -> void:
	call_deferred("_run_script_test")

func _run_script_test() -> void:
	var output: Array = []
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"tests/on_hit_verify.gd",
	])
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true, false)
	for chunk in output:
		var text := str(chunk)
		if not text.is_empty():
			print(text.strip_edges(false, true))
	if exit_code != 0:
		push_error("on_hit_verify.gd exited with code %d" % exit_code)
	get_tree().quit(exit_code)
