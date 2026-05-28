extends Node

var manifest := {}
var cache := {}
var fallback_cache := {}

func _ready() -> void:
	load_manifest()

func load_manifest() -> void:
	var file := FileAccess.open("res://assets/MANIFEST.json", FileAccess.READ)
	if file == null:
		push_error("AssetDB: missing assets/MANIFEST.json")
		manifest = {}
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed.get("assets", {})
	else:
		manifest = {}

func tex(id: String) -> Texture2D:
	if cache.has(id):
		return cache[id]
	if manifest.is_empty():
		load_manifest()
	var info: Dictionary = manifest.get(id, {})
	if info.has("path"):
		var path := str(info["path"])
		if ResourceLoader.exists(path):
			var base_tex: Texture2D = load(path)
			if info.has("region"):
				var region_arr: Array = info["region"]
				var atlas := AtlasTexture.new()
				atlas.atlas = base_tex
				atlas.region = Rect2(region_arr[0], region_arr[1], region_arr[2], region_arr[3])
				cache[id] = atlas
				return atlas
			cache[id] = base_tex
			return base_tex
	var fallback := _make_fallback(id)
	cache[id] = fallback
	return fallback

func color_for_element(element: String) -> Color:
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

func _make_fallback(id: String) -> Texture2D:
	if fallback_cache.has(id):
		return fallback_cache[id]
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var hue := float(abs(id.hash()) % 360) / 360.0
	var base := Color.from_hsv(hue, 0.55, 0.78)
	img.fill(Color(0, 0, 0, 0))
	for y in range(96):
		for x in range(96):
			var dx := x - 48
			var dy := y - 48
			if dx * dx + dy * dy < 1900:
				img.set_pixel(x, y, base)
	var tex := ImageTexture.create_from_image(img)
	fallback_cache[id] = tex
	return tex
