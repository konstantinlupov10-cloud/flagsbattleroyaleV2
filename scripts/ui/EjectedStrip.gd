extends CanvasLayer
class_name EjectedStrip
## Bottom-of-screen strip of flags ejected (eliminated) during the current
## tournament's Last Flag Standing final -- the icon grid fills in as
## flag_eliminated fires, cleared at the start of each new tournament. Pure
## passive listener, same discipline as Leaderboard.gd: never touches
## GameManager, only reacts to its signals.
##
## Qualifying-phase departures don't get an ICON here -- "ejected" still
## specifically means eliminated from the final, not merely having been
## ejected from a qualifying round (those flags recycle into the next round,
## and the eventual round winner shows up on the Leaderboard instead).
##
## The progress bar/count is scoped to whatever's CURRENTLY playing out --
## the current qualifying round's pool, or (once the final starts) the
## finalist field -- not a whole-tournament tally. It starts at that pool's
## full size ("250 / 250" for round one) and decrements on every ejection
## within that round, then resets to the NEXT round's (smaller) pool size
## once one starts, repeating all the way through qualifying and into the
## final, correctly reaching 1 at the champion. An earlier version tried to
## track "how many of the original 250 are still anywhere in the
## tournament" instead, which stayed flat at "250 / 250" the whole
## qualifying phase (wrong -- confirmed via direct feedback: it should
## visibly count down round by round) and needed an awkward snap-to-finalist-
## count hack at the start of the final to avoid double-counting qualifiers.
## Scoping it to "the round in progress" is simpler AND matches what was
## actually wanted.
##
## Deliberately no bordered/background panel here (unlike Leaderboard) --
## icons sit directly on the dark canvas background, per direct request. A
## thin progress bar + "X / Y FLAGS" count above the grid gives the same
## "how far along is this round" read that a bordered panel would otherwise
## imply, without the visual weight of a boxed card.

const ICON_ASPECT := 0.667  # matches the ~3:2 landscape aspect most flag SVGs use
const FLY_IN_DISTANCE_PX := 40.0
const FLY_IN_SECONDS := 0.35

@onready var _grid: GridContainer = $Root/VBox/Scroll/Grid
@onready var _count_label: Label = $Root/VBox/CountLabel
@onready var _bar_fill: Control = $Root/VBox/BarTrack/BarFill

## Size of the current round's pool, and how many of them haven't been
## ejected yet -- drives the "X / Y FLAGS" label and the progress bar. Reset
## every time a round (qualifying or the final) starts.
var _round_total: int = 0
var _round_remaining: int = 0

func _ready() -> void:
	_grid.columns = RoyaleSettings.roster_strip_columns
	GameManager.tournament_started.connect(_on_tournament_started)
	GameManager.qualifying_round_reset.connect(_on_qualifying_round_reset)
	GameManager.flag_round_ejected.connect(_on_flag_round_ejected)
	GameManager.flag_qualified.connect(_on_flag_qualified)
	GameManager.last_flag_standing_started.connect(_on_last_flag_standing_started)
	GameManager.flag_eliminated.connect(_on_flag_eliminated)
	_update_progress()

func _on_qualifying_round_reset(pool_entries: Array) -> void:
	_round_total = pool_entries.size()
	_round_remaining = pool_entries.size()
	_update_progress()

func _on_flag_round_ejected(_code: String, _country_name: String) -> void:
	_round_remaining = maxi(0, _round_remaining - 1)
	_update_progress()

## The round's winner never itself gets a flag_round_ejected event (it's the
## one flag that ISN'T ejected) -- the second-to-last ejection already
## brought _round_remaining down to 2, not 1, so this snaps it the rest of
## the way to reflect "only the winner is left" right when that's decided.
func _on_flag_qualified(_code: String, _country_name: String, _rank: int, _total: int) -> void:
	_round_remaining = 1
	_update_progress()

func _on_last_flag_standing_started(qualifiers: Array) -> void:
	_round_total = qualifiers.size()
	_round_remaining = qualifiers.size()
	_update_progress()

func _update_progress() -> void:
	_count_label.text = "%d / %d FLAGS" % [_round_remaining, _round_total]
	var ratio: float = float(_round_remaining) / float(_round_total) if _round_total > 0 else 0.0
	_bar_fill.anchor_right = clampf(ratio, 0.0, 1.0)

## Each new icon flies in downward while fading in, distinct from the actual
## Flag physics object's own departure flight in the arena -- purely a UI
## polish detail on this static grid entry, unrelated to game state.
##
## GridContainer positions its DIRECT children itself every time it re-sorts
## (e.g. when a sibling cell is added later), which would fight/reset a tween
## running directly on a grid child. Wrapping the actual animated TextureRect
## inside a plain Control "cell" sidesteps that entirely: the Control is what
## GridContainer manages and lands in its final position immediately (so grid
## layout is correct from frame one), while the TextureRect inside it is a
## grandchild GridContainer never touches, free to tween its own local
## position/modulate with zero risk of the container clobbering it mid-flight.
func _on_flag_eliminated(code: String, _country_name: String, _remaining: int, _rank: int) -> void:
	_round_remaining = maxi(0, _round_remaining - 1)
	_update_progress()

	var w: float = RoyaleSettings.roster_strip_icon_width
	var cell_size := Vector2(w, w * ICON_ASPECT)

	var cell := Control.new()
	cell.custom_minimum_size = cell_size
	_grid.add_child(cell)

	var icon := TextureRect.new()
	icon.size = cell_size
	icon.texture = FlagDatabase.get_texture(code)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate.a = 0.0
	icon.position = Vector2(0.0, -FLY_IN_DISTANCE_PX)
	cell.add_child(icon)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(icon, "modulate:a", 1.0, FLY_IN_SECONDS)
	tween.tween_property(icon, "position", Vector2.ZERO, FLY_IN_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_tournament_started(total_flags: int) -> void:
	for child in _grid.get_children():
		child.queue_free()
	_round_total = total_flags
	_round_remaining = total_flags
	_update_progress()
