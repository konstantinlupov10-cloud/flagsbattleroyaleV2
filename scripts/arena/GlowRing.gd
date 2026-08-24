extends Node2D
class_name GlowRing
## Draws the ring's neon look via several STACKED copies of the same curve,
## progressively wider and dimmer outward from a bright, sharp core --
## classic manual "glow" technique, drawn outermost-first so the bright
## core paints on top.
##
## NOT Godot's built-in Glow post-process (a SubViewport + glow-enabled
## Environment, composited via a full-screen Sprite2D). That approach was
## tried first and abandoned after actually rendering and inspecting real
## screenshots (not just reasoning about settings): even restricted to the
## tightest blur levels, it produced large, uneven, blobby bright patches
## scattered across the WHOLE canvas, not a halo confined to the ring's
## curve -- confirmed by disabling glow_enabled entirely and watching the
## exact same blobs disappear along with it. They were never "flags
## leaking through the isolation" in the sense of flag pixels themselves
## being glow-processed; the SubViewport's own glow rendering was already
## blobby and uneven on its own, and that got composited on top of
## everything via the full-screen Sprite2D regardless of how isolated the
## SOURCE content was. Godot's multi-pass downsample blur just isn't
## predictable for "one thin curved line across a large mostly-empty
## canvas" the way it is for typical glowing 3D scenes.
##
## Manual layered lines have no blur/spread step at all, so there's nothing
## that COULD bleed onto anything else -- every pixel drawn is exactly and
## only where a Line2D says it is, fully predictable, and trivially cheap
## (a handful of Line2D draws, no render-to-texture, no post-process pass).

const OUTLINE_POINTS_PER_DEGREE := 4.0

## (width_px, color) pairs, outermost/dimmest first, innermost/brightest
## last.
const LAYERS: Array = [
	{"width": 26.0, "color": Color(0.4, 0.75, 1.0, 0.05)},
	{"width": 18.0, "color": Color(0.5, 0.8, 1.0, 0.10)},
	{"width": 12.0, "color": Color(0.6, 0.85, 1.0, 0.20)},
	{"width": 8.0, "color": Color(0.75, 0.92, 1.0, 0.45)},
	{"width": 4.0, "color": Color(0.95, 0.98, 1.0, 1.0)},
]

var _lines: Array = []
var _source_gap_ring: GapRing

func setup(source_gap_ring: GapRing) -> void:
	_source_gap_ring = source_gap_ring

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

## Same points formula the old single-line Outline used -- deliberately NOT
## one point per physical wall segment (ring_segment_count, tuned for
## gap-width game design, not visual smoothness).
func _compute_points() -> PackedVector2Array:
	var radius: float = RoyaleSettings.ring_radius
	var gap_width_deg: float = RoyaleSettings.gap_width_degrees()
	var total_points: int = int(360.0 * OUTLINE_POINTS_PER_DEGREE)
	var angle_step: float = TAU / float(total_points)
	var gap_step_count: int = int(round(gap_width_deg * OUTLINE_POINTS_PER_DEGREE))
	var points := PackedVector2Array()
	for i in range(gap_step_count, total_points + 1):
		var a: float = angle_step * i
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points

func _process(_delta: float) -> void:
	if _source_gap_ring:
		for line in _lines:
			line.rotation = _source_gap_ring.rotation
