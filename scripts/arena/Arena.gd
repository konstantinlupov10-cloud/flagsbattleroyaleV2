extends Node2D
class_name Arena

@onready var _gap_ring: GapRing = $GapRing
@onready var escape_detector: EscapeDetector = $EscapeDetector
@onready var _outline: Line2D = $GapRing/Outline

func _ready() -> void:
	global_position = Vector2(RoyaleSettings.board_center_x, RoyaleSettings.board_center_y)
	escape_detector.setup(global_position, _gap_ring)
	_build_outline()
	# Godot's Glow only blooms pixels whose color exceeds the environment's
	# glow_hdr_threshold (1.5, see Main.tscn's Environment) -- pushed well
	# clear of that, not just barely over it. A first attempt at a lower
	# threshold (1.05) still bled onto flag sprites: legitimate full-white
	# pixels (very common in flag art -- Japan's field, Nordic cross flags,
	# stripes) sit at exactly 1.0, and Godot's soft-knee bloom ramp still
	# contributes some glow to content just under the threshold, not only
	# content strictly over it (confirmed via visual testing -- flags visibly
	# glowed too). A wide margin between normal (<=1.0) and this line's color
	# is what keeps the glow exclusive to the ring.
	_outline.default_color = Color(3.2, 3.8, 4.6, 1.0)
	_outline.width = 6.0

func get_center_global() -> Vector2:
	return global_position

## Visual ring matching GapRing's own rotation for free (Outline is a child
## of GapRing), with the gap simply left undrawn -- a break in the line
## rather than a separate "gap" visual element to keep in sync.
##
## Deliberately NOT one point per physical wall segment (ring_segment_count =
## 72, i.e. one point every 5deg) -- that number is tuned for gap-width game
## design (see RoyaleSettings.gap_segment_count's comment), not visual
## smoothness, and drawing the outline at that same low resolution produced a
## visibly faceted/jagged curve once zoomed in (confirmed via visual
## testing: a 5deg chord at this radius is a real, noticeable straight
## segment, not a smooth arc). OUTLINE_POINTS_PER_DEGREE is independent and
## purely cosmetic -- free to tune without touching wall/gap physics at all.
const OUTLINE_POINTS_PER_DEGREE := 2.0

func _build_outline() -> void:
	var radius: float = RoyaleSettings.ring_radius
	var gap_width_deg: float = RoyaleSettings.gap_width_degrees()
	var total_points: int = int(360.0 * OUTLINE_POINTS_PER_DEGREE)
	var angle_step: float = TAU / float(total_points)
	var gap_step_count: int = int(round(gap_width_deg * OUTLINE_POINTS_PER_DEGREE))
	var points := PackedVector2Array()
	for i in range(gap_step_count, total_points + 1):
		var a: float = angle_step * i
		points.append(Vector2(cos(a), sin(a)) * radius)
	_outline.points = points
