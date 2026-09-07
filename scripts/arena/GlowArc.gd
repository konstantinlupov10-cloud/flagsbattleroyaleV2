extends Node2D
class_name GlowArc
## Draws BlockerArc's neon outline via the same manual-layered-line
## technique GlowRing.gd uses for the main ring (see that file's doc
## comment for the full reasoning: Godot's Glow post-process was tried and
## abandoned there for producing uneven, blobby results on a thin curve
## across a large mostly-empty canvas, so several stacked Line2D copies --
## progressively wider and dimmer outward from a bright core -- stand in
## for it with no blur/post-process step at all). Neon GREEN specifically
## (confirmed via direct request), distinct from the main ring's blue-violet,
## so the two read as clearly separate moving elements.

const OUTLINE_POINTS_PER_DEGREE := 4.0

## Same shape as GlowRing.LAYERS (width/alpha progression), hued around
## #39ff14 (a saturated "electric" neon green). Pushed noticeably punchier
## than the first pass at this per direct follow-up feedback ("stand out
## more") -- every layer's alpha roughly doubled so the halo actually reads
## at normal (not zoomed-in) viewing distance, and the core is a near-white
## hot spark rather than a mid-tone green, for the high-contrast "electric"
## look real neon/arc-flash visuals have at their brightest point. The green
## itself stays fully saturated one layer out from that spark, so the arc
## still reads as green overall rather than washing white -- only the very
## center spikes past it. Outermost/dimmest first, innermost/brightest last.
const LAYERS: Array = [
	{"width": 32.0, "color": Color(0.22, 1.0, 0.08, 0.12)},
	{"width": 22.0, "color": Color(0.22, 1.0, 0.08, 0.22)},
	{"width": 14.0, "color": Color(0.22, 1.0, 0.08, 0.4)},
	{"width": 8.0, "color": Color(0.22, 1.0, 0.08, 0.8)},
	{"width": 3.0, "color": Color(0.88, 1.0, 0.82, 1.0)},
]

var _lines: Array = []
var _source_arc: BlockerArc

func setup(source_arc: BlockerArc) -> void:
	_source_arc = source_arc

func _ready() -> void:
	var points: PackedVector2Array = _compute_points()
	var center := Vector2(RoyaleSettings.board_center_x, RoyaleSettings.board_center_y)
	for layer in LAYERS:
		var line := Line2D.new()
		line.points = points
		line.width = layer.width
		line.default_color = layer.color
		line.antialiased = true
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.position = center
		add_child(line)
		_lines.append(line)

## Only spans blocker_arc_width_degrees (not the full circle like GlowRing) --
## same points-per-degree density, just over a shorter arc.
func _compute_points() -> PackedVector2Array:
	var radius: float = RoyaleSettings.ring_radius
	var width_deg: float = RoyaleSettings.blocker_arc_width_degrees
	var total_points: int = maxi(2, int(round(width_deg * OUTLINE_POINTS_PER_DEGREE)))
	var angle_step: float = deg_to_rad(width_deg) / float(total_points)
	var points := PackedVector2Array()
	for i in range(total_points + 1):
		var a: float = angle_step * i
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points

func _process(_delta: float) -> void:
	if _source_arc:
		for line in _lines:
			line.rotation = _source_arc.rotation
