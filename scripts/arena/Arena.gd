extends Node2D
class_name Arena

@onready var _gap_ring: GapRing = $GapRing
@onready var escape_detector: EscapeDetector = $EscapeDetector
@onready var _outline: Line2D = $GapRing/Outline

func _ready() -> void:
	global_position = Vector2(RoyaleSettings.board_center_x, RoyaleSettings.board_center_y)
	escape_detector.setup(global_position, _gap_ring)
	_build_outline()

func get_center_global() -> Vector2:
	return global_position

## Visual ring matching GapRing's own rotation for free (Outline is a child
## of GapRing), with the gap segments simply left undrawn -- a break in the
## line rather than a separate "gap" visual element to keep in sync.
func _build_outline() -> void:
	var count: int = RoyaleSettings.ring_segment_count
	var gap_count: int = RoyaleSettings.gap_segment_count
	var radius: float = RoyaleSettings.ring_radius
	var angle_step: float = TAU / float(count)
	var points := PackedVector2Array()
	for i in range(gap_count, count + 1):
		var a: float = angle_step * i
		points.append(Vector2(cos(a), sin(a)) * radius)
	_outline.points = points
