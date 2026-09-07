extends Node2D
class_name Arena
## The physical arena: wall collision (GapRing, BlockerArc) and escape
## detection only -- purely functional, no visible rendering of its own.
## Both arcs' neon outlines are drawn entirely by GlowRing/GlowArc (see
## those scripts), which read gap_ring's/blocker_arc's rotation directly
## every frame to stay in sync with the collision geometry they're drawing
## on top of.

@onready var gap_ring: GapRing = $GapRing
@onready var blocker_arc: BlockerArc = $BlockerArc
@onready var escape_detector: EscapeDetector = $EscapeDetector

func _ready() -> void:
	global_position = Vector2(RoyaleSettings.board_center_x, RoyaleSettings.board_center_y)
	escape_detector.setup(global_position, gap_ring)

func get_center_global() -> Vector2:
	return global_position
