extends RefCounted

static func ensure_fallback(font: Font, fallback_font: Font) -> void:
	var fallbacks := font.get_fallbacks()
	for existing: Font in fallbacks:
		if existing == fallback_font or existing.resource_path == fallback_font.resource_path:
			return
	fallbacks.append(fallback_font)
	font.set_fallbacks(fallbacks)
