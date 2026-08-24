extends Node2D
class_name Arena
## The physical arena: wall collision (GapRing) and escape detection only --
## purely functional, no visible rendering of its own. The ring's neon
## outline is drawn entirely by GlowRing (see scripts/arena/GlowRing.gd), a
## separate node in its own glow-enabled SubViewport, so that Godot's Glow
## (a whole-viewport post-process) can never touch flag sprites regardless
## of their own texture colors -- an HDR-color/threshold approach tuned on a
## SHARED environment can only ever reduce the chance of flag bleed, not
## structurally guarantee it (confirmed request for a real guarantee).
## GlowRing reads gap_ring's rotation directly every frame to stay in sync
## with the wall it's drawing on top of.

@onready var gap_ring: GapRing = $GapRing
@onready var escape_detector: EscapeDetector = $EscapeDetector

func _ready() -> void:
	global_position = Vector2(RoyaleSettings.board_center_x, RoyaleSettings.board_center_y)
	escape_detector.setup(global_position, gap_ring)

func get_center_global() -> Vector2:
	return global_position
