extends Node
## Pure data: tracks qualification and elimination order for the current
## tournament. Order IS rank for both lists -- no sorting needed, since
## qualification/elimination order is itself the ranking criterion. Mirrors
## ScoreBoard.gd's "pure data, no scene refs, no signals" shape from the
## sibling flagsplinko project; read directly by UI (e.g. Leaderboard.gd),
## written to only by GameManager.

var _qualifiers: Array = []   # [{code, name}, ...] in qualification order
var _eliminations: Array = [] # [{code, name}, ...] in elimination order
var _champion: Dictionary = {}

func reset(_roster: Array) -> void:
	_qualifiers.clear()
	_eliminations.clear()
	_champion = {}

func record_qualifier(code: String, name: String) -> int:
	_qualifiers.append({"code": code, "name": name})
	return _qualifiers.size()

func record_elimination(code: String, name: String) -> int:
	_eliminations.append({"code": code, "name": name})
	return _eliminations.size()

func set_champion(code: String, name: String) -> void:
	_champion = {"code": code, "name": name}

func get_qualifiers_ranked() -> Array:
	return _qualifiers

func qualifier_count() -> int:
	return _qualifiers.size()

## Returns [{code,name,rank=1} champion, {code,name,rank=2} silver, {code,name,rank=3} bronze].
## Silver = last flag eliminated before the champion, bronze = second-to-last.
## Returns fewer than 3 entries gracefully if the final had under 3 finalists.
func get_podium() -> Array:
	var podium: Array = []
	if not _champion.is_empty():
		podium.append({"code": _champion.code, "name": _champion.name, "rank": 1})
	var count: int = _eliminations.size()
	if count >= 1:
		var silver: Dictionary = _eliminations[count - 1]
		podium.append({"code": silver.code, "name": silver.name, "rank": 2})
	if count >= 2:
		var bronze: Dictionary = _eliminations[count - 2]
		podium.append({"code": bronze.code, "name": bronze.name, "rank": 3})
	return podium
