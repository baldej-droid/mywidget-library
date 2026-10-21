extends RefCounted

const KEY = "api_demo_state_v1"
const DEFAULTS = {"count": 0, "name": "MyWidget", "accent": 0, "level": 50, "auto_save": false, "animate": true, "language": 0, "image": ""}

static func normalize(value: Variant) -> Dictionary:
	var state: Dictionary = DEFAULTS.duplicate(true)
	if value is not Dictionary:
		return state
	state.count = clampi(int(value.get("count", 0)), 0, 999999)
	state.name = str(value.get("name", "MyWidget")).substr(0, 48)
	state.accent = clampi(int(value.get("accent", 0)), 0, 2)
	state.level = clampi(int(value.get("level", 50)), 0, 100)
	state.level = int(round(state.level / 5.0)) * 5
	state.auto_save = value.get("auto_save", false) == true
	state.animate = value.get("animate", true) == true
	state.language = clampi(int(value.get("language", 0)), 0, 2)
	state.image = str(value.get("image", ""))
	return state

static func decode(value: Variant) -> Dictionary:
	if value == null:
		return normalize(null)
	if value is Dictionary:
		return normalize(value)
	# JavaObject resolves Java methods dynamically; has_method("toString") is false even when the call works.
	var text: String = value.toString() if value is Object else str(value)
	return normalize(JSON.parse_string(text))

