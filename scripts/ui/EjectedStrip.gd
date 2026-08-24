extends CanvasLayer
class_name EjectedStrip
## Bottom-of-screen strip showing the CURRENT round's ejected flags -- one
## icon per flag_round_ejected during qualifying, or per flag_eliminated
## during the final. Mirrors the progress bar's own scope exactly: the field
## clears every time a new round starts (qualifying_round_reset or
## last_flag_standing_started), same as the bar resets to N/N at that exact
## moment.
##
## Placement is fully predetermined per direct request, not delegated to any
## Container's auto-layout: for icon index i (0-based, in ejection order),
## column = i % columns, row_from_bottom = i / columns, and each icon's exact
## target (x, y) is computed directly from that -- the Nth flag always lands
## at the same coordinates regardless of animation timing or how the field
## itself is laid out. Fill order is bottom row first, left to right, then
## the row above it, left to right, and so on (confirmed via a precise 2x2
## example: flag 1->(row2,col1), flag 2->(row2,col2), flag 3->(row1,col1),
## flag 4->(row1,col2), i.e. bottom row completes before the next row up
## starts). Two earlier approaches were tried and abandoned for this exact
## scoping: a GridContainer with a 180deg scale flip (worked for final
## placement, but its pivot recentered on every row added, visibly shifting
## already-placed icons -- confirmed via direct feedback showing a jittery
## diagonal "staircase"), and a GridContainer + ScrollContainer with
## auto-scroll-to-bottom (fill order was right but positions were still at
## the mercy of two different Containers' layout passes, not a single
## predictable formula). Direct positioning has neither problem: an icon's
## coordinates are set once, when it's created, and never recomputed or
## touched again by anything else.
##
## Deliberately no bordered/background panel here (unlike Leaderboard) --
## icons sit directly on the dark canvas background, per direct request. A
## thin progress bar + "X / Y FLAGS" count above the field gives the same
## "how far along is this round" read that a bordered panel would otherwise
## imply, without the visual weight of a boxed card.

const ICON_ASPECT := 0.667  # matches the ~3:2 landscape aspect most flag SVGs use
const H_SPACING := 6.0
const V_SPACING := 6.0
const FLY_IN_DISTANCE_PX := 70.0
const FLY_IN_SECONDS := 0.45

@onready var _field: Control = $Root/VBox/Field
@onready var _count_label: Label = $Root/VBox/CountLabel
@onready var _bar_fill: Control = $Root/VBox/BarTrack/BarFill

## Size of the current round's pool, and how many of them haven't been
## ejected yet -- drives the "X / Y FLAGS" label and the progress bar. Reset
## every time a round (qualifying or the final) starts.
var _round_total: int = 0
var _round_remaining: int = 0
## How many icons have been placed so far THIS round -- this index is what
## the (row, column) formula in _add_icon() is computed from. Reset
## alongside the field itself every time a round starts.
var _icon_count: int = 0

func _ready() -> void:
	GameManager.tournament_started.connect(_on_tournament_started)
	GameManager.qualifying_round_reset.connect(_on_qualifying_round_reset)
	GameManager.flag_round_ejected.connect(_on_flag_round_ejected)
	GameManager.flag_qualified.connect(_on_flag_qualified)
	GameManager.last_flag_standing_started.connect(_on_last_flag_standing_started)
	GameManager.flag_eliminated.connect(_on_flag_eliminated)
	_update_progress()

func _on_qualifying_round_reset(pool_entries: Array) -> void:
	_clear_field()
	_round_total = pool_entries.size()
	_round_remaining = pool_entries.size()
	_update_progress()

func _on_flag_round_ejected(code: String, _country_name: String) -> void:
	_round_remaining = maxi(0, _round_remaining - 1)
	_update_progress()
	_add_icon(code)

## The round's winner never itself gets a flag_round_ejected event (it's the
## one flag that ISN'T ejected) -- the second-to-last ejection already
## brought _round_remaining down to 2, not 1, so this snaps it the rest of
## the way to reflect "only the winner is left" right when that's decided.
## It doesn't get an icon here either -- it qualified, it wasn't ejected.
func _on_flag_qualified(_code: String, _country_name: String, _rank: int, _total: int) -> void:
	_round_remaining = 1
	_update_progress()

func _on_last_flag_standing_started(qualifiers: Array) -> void:
	_clear_field()
	_round_total = qualifiers.size()
	_round_remaining = qualifiers.size()
	_update_progress()

func _update_progress() -> void:
	_count_label.text = "%d / %d FLAGS" % [_round_remaining, _round_total]
	var ratio: float = float(_round_remaining) / float(_round_total) if _round_total > 0 else 0.0
	_bar_fill.anchor_right = clampf(ratio, 0.0, 1.0)

func _on_flag_eliminated(code: String, _country_name: String, _remaining: int, _rank: int) -> void:
	_round_remaining = maxi(0, _round_remaining - 1)
	_update_progress()
	_add_icon(code)

## Places the (icon_count)th icon at its predetermined (row, column) slot --
## column = index % columns, row counted from the BOTTOM = index / columns
## (integer division). It then flies in downward while fading in, distinct
## from the actual Flag physics object's own departure flight in the arena
## -- purely a UI polish detail on this static entry, unrelated to game
## state. Nothing else ever touches this icon's position again after this.
##
## The bottom reference for row_from_bottom=0 is NOT _field.size.y (the
## field's full available height, which is generous enough to fit ~14 rows
## regardless of how many flags a round could ever actually produce) -- that
## left a large empty gap between the progress bar and wherever icons
## actually started appearing (confirmed via direct feedback). Instead it's
## the height of a matrix sized to _round_total's actual maximum possible
## row count, top-aligned flush with the field's own top edge (right under
## the bar). row_from_bottom=0 still sits at the BOTTOM of that (now
## appropriately-sized) matrix, same fill order as before -- only the
## matrix's total height, and therefore how far down from the bar it
## extends, changed.
func _add_icon(code: String) -> void:
	var w: float = RoyaleSettings.roster_strip_icon_width
	var h: float = w * ICON_ASPECT
	var columns: int = RoyaleSettings.roster_strip_columns

	var index: int = _icon_count
	_icon_count += 1
	var col: int = index % columns
	var row_from_bottom: int = index / columns

	var max_rows: int = maxi(1, ceili(float(maxi(_round_total, 1)) / float(columns)))
	var matrix_height: float = max_rows * h + maxi(0, max_rows - 1) * V_SPACING

	var target_x: float = col * (w + H_SPACING)
	var target_y: float = matrix_height - h - row_from_bottom * (h + V_SPACING)

	var icon := TextureRect.new()
	icon.size = Vector2(w, h)
	icon.texture = FlagDatabase.get_texture(code)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate.a = 0.0
	icon.position = Vector2(target_x, target_y - FLY_IN_DISTANCE_PX)
	_field.add_child(icon)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(icon, "modulate:a", 1.0, FLY_IN_SECONDS)
	tween.tween_property(icon, "position", Vector2(target_x, target_y), FLY_IN_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _clear_field() -> void:
	for child in _field.get_children():
		child.queue_free()
	_icon_count = 0

func _on_tournament_started(total_flags: int) -> void:
	_clear_field()
	_round_total = total_flags
	_round_remaining = total_flags
	_update_progress()
