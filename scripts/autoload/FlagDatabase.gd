extends Node
## Loads the curated country roster and exposes flag textures by code.

const COUNTRIES_PATH := "res://data/countries.json"
const TEXTURE_DIR := "res://assets/flags/textures/"

var _roster: Array = []
var _texture_cache: Dictionary = {}

func _ready() -> void:
	_load_roster()

func _load_roster() -> void:
	var file := FileAccess.open(COUNTRIES_PATH, FileAccess.READ)
	if file == null:
		push_error("FlagDatabase: could not open %s" % COUNTRIES_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("FlagDatabase: countries.json did not parse to an array")
		return
	_roster = parsed

## Returns a shuffled copy of the full roster: [{code: String, name: String}, ...]
func get_shuffled_roster() -> Array:
	var copy := _roster.duplicate(true)
	copy.shuffle()
	return copy

func roster_size() -> int:
	return _roster.size()

func get_texture(code: String) -> Texture2D:
	if _texture_cache.has(code):
		return _texture_cache[code]
	var path := "%s%s.svg" % [TEXTURE_DIR, code]
	if not ResourceLoader.exists(path):
		push_warning("FlagDatabase: missing texture for code '%s'" % code)
		return null
	var tex: Texture2D = load(path)
	_texture_cache[code] = tex
	return tex
