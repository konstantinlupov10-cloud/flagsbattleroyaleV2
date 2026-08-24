extends CanvasLayer
class_name Leaderboard
## Top-of-screen "QUALIFIED FOR FINAL" board -- ported from flagsplinko's
## Leaderboard.gd (same pagination/auto-flip/crossfade pattern), reading
## TournamentLog.get_qualifiers_ranked() instead of ScoreBoard.get_ranked().
## Pure passive listener, like every other UI piece in this project -- never
## touches GameManager, only reacts to its signals.
##
## Unlike flagsplinko's ScoreBoard (which changes continuously while a round
## plays, so Leaderboard only re-reads it once per scheduled page flip), the
## qualifier list here only grows on discrete flag_qualified events -- so this
## also repopulates the currently-visible page immediately on each one, not
## just at the next flip, so a viewer sees a new qualifier appear right away
## instead of waiting up to leaderboard_page_seconds for it to show up.

const ROW_SCENE: PackedScene = preload("res://scenes/ui/LeaderboardRow.tscn")

@onready var _page_a: VBoxContainer = $Panel/VBox/Rows/PageA
@onready var _page_b: VBoxContainer = $Panel/VBox/Rows/PageB
@onready var _dots_root: HBoxContainer = $Panel/VBox/Dots

var _rows_a: Array[LeaderboardRow] = []
var _rows_b: Array[LeaderboardRow] = []
var _dots: Array[Panel] = []
var _active_is_a: bool = true
var _current_page: int = 0
var _page_timer: float = 0.0

func _ready() -> void:
	var page_size: int = RoyaleSettings.leaderboard_page_size
	for i in range(page_size):
		var ra: LeaderboardRow = ROW_SCENE.instantiate()
		_page_a.add_child(ra)
		_rows_a.append(ra)
		var rb: LeaderboardRow = ROW_SCENE.instantiate()
		_page_b.add_child(rb)
		_rows_b.append(rb)
	_page_b.modulate.a = 0.0

	for child in _dots_root.get_children():
		if child is Panel:
			_dots.append(child)

	GameManager.tournament_started.connect(_on_tournament_started)
	GameManager.flag_qualified.connect(_on_flag_qualified)
	_populate(_rows_a, 0)
	_update_dots()

func _on_tournament_started(_total_flags: int) -> void:
	_current_page = 0
	_page_timer = 0.0
	_active_is_a = true
	_page_a.modulate.a = 1.0
	_page_a.position.x = 0.0
	_page_b.modulate.a = 0.0
	_populate(_rows_a, 0)
	_update_dots()

func _on_flag_qualified(_code: String, _country_name: String, _rank: int, _total: int) -> void:
	var active_rows: Array[LeaderboardRow] = _rows_a if _active_is_a else _rows_b
	_populate(active_rows, _current_page)
	_update_dots()  # a new qualifier can add a page; keep the dot count in sync

func _process(delta: float) -> void:
	var total_pages: int = _page_count()
	if total_pages <= 1:
		return
	_page_timer += delta
	if _page_timer >= RoyaleSettings.leaderboard_page_seconds:
		_page_timer = 0.0
		_flip_page()

func _page_count() -> int:
	var entries: int = mini(RoyaleSettings.leaderboard_max_entries, TournamentLog.qualifier_count())
	return maxi(1, int(ceil(float(entries) / float(RoyaleSettings.leaderboard_page_size))))

func _flip_page() -> void:
	_current_page = (_current_page + 1) % _page_count()

	var outgoing: VBoxContainer = _page_a if _active_is_a else _page_b
	var incoming: VBoxContainer = _page_b if _active_is_a else _page_a
	var incoming_rows: Array[LeaderboardRow] = _rows_b if _active_is_a else _rows_a
	_active_is_a = not _active_is_a

	_populate(incoming_rows, _current_page)

	var slide: float = outgoing.size.x

	incoming.modulate.a = 0.0
	incoming.position.x = slide

	var t: float = RoyaleSettings.leaderboard_transition_seconds
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(outgoing, "modulate:a", 0.0, t)
	tween.tween_property(outgoing, "position:x", -slide, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(incoming, "modulate:a", 1.0, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(incoming, "position:x", 0.0, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_update_dots()

func _populate(rows: Array[LeaderboardRow], page: int) -> void:
	var ranked: Array = TournamentLog.get_qualifiers_ranked()
	var start: int = page * RoyaleSettings.leaderboard_page_size
	for i in range(rows.size()):
		var idx: int = start + i
		if idx < ranked.size():
			var e: Dictionary = ranked[idx]
			rows[i].visible = true
			rows[i].update(idx + 1, e["code"], e["name"])
		else:
			rows[i].visible = false

func _update_dots() -> void:
	var total_pages: int = _page_count()
	# No pagination affordance at all until it's actually needed -- the first
	# leaderboard_page_size (5) qualifiers fit on a single page with nothing
	# to flip between, so showing dots (or flipping pages) before that point
	# is just noise. _process() already skips flipping when total_pages<=1;
	# this hides the dots row entirely for the same condition.
	_dots_root.visible = total_pages > 1
	for i in range(_dots.size()):
		if i >= total_pages:
			_dots[i].visible = false
			continue
		_dots[i].visible = true
		var active: bool = i == _current_page
		_dots[i].modulate = Color(Palette.CYAN, 1.0) if active else Color(Palette.TEXT_DIM, 0.4)
		_dots[i].scale = Vector2(1.3, 1.3) if active else Vector2.ONE
