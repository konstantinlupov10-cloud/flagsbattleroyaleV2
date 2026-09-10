extends StaticBody2D
class_name BlockerArc
## A second rotating wall arc, independent of GapRing, sweeping the ring at
## the SAME radius but the OPPOSITE rotational direction (confirmed design,
## reference image). It's solid across its whole span -- there's no special
## "is this over the gap right now" detection anywhere. Whenever its sweep
## happens to put it over the gap's current angular position, a flag trying
## to escape there simply collides with this arc instead of passing through,
## exactly like any other wall contact. Purely geometric, same as how
## GapRing's own gap works.
##
## Built the same way as GapRing's segments (see that file's doc comment for
## why a thin RectangleShape2D, not a zero-thickness SegmentShape2D) -- just
## a contiguous run of them spanning blocker_arc_width_degrees instead of a
## full circle with a hole in it.

const SEGMENTS_PER_DEGREE := 2.0  # matches GlowArc's visual density closely enough

## Seconds since the current round started -- drives the green -> light-blue
## -> green freeze window (see is_freezing_active()). Arena (and therefore
## this node) is built once and never rebuilt, so the timer is reset from
## GameManager's round-boundary signals rather than from _ready().
var _round_elapsed: float = 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = RoyaleSettings.flag_bounce
	physics_material_override = mat
	_build_segments()

	GameManager.tournament_started.connect(func(_t): _round_elapsed = 0.0)
	GameManager.qualifying_round_reset.connect(func(_p): _round_elapsed = 0.0)
	GameManager.last_flag_standing_started.connect(func(_f): _round_elapsed = 0.0)

## True during each light-blue window: none until first_delay, then a
## blue_seconds window, then interval_seconds green, then the next window,
## for up to max_windows windows, then green for the rest of the round.
## GlowArc reads this to recolor itself; Flag reads it to decide whether a
## contact freezes it.
func is_freezing_active() -> bool:
	var first: float = RoyaleSettings.blocker_freeze_first_delay_seconds
	if _round_elapsed < first:
		return false
	var blue: float = RoyaleSettings.blocker_freeze_blue_seconds
	var period: float = blue + RoyaleSettings.blocker_freeze_interval_seconds
	var since_first: float = _round_elapsed - first
	var window_index: int = int(since_first / period)
	if window_index >= RoyaleSettings.blocker_freeze_max_windows:
		return false
	return since_first - float(window_index) * period < blue

func _build_segments() -> void:
	var width_deg: float = RoyaleSettings.blocker_arc_width_degrees
	var radius: float = RoyaleSettings.ring_radius
	var thickness: float = RoyaleSettings.wall_thickness_px
	var segment_count: int = maxi(4, int(round(width_deg * SEGMENTS_PER_DEGREE)))
	var angle_step: float = deg_to_rad(width_deg) / float(segment_count)
	for i in range(segment_count):
		var a0: float = angle_step * i
		var a1: float = angle_step * (i + 1)
		var p0: Vector2 = Vector2(cos(a0), sin(a0)) * radius
		var p1: Vector2 = Vector2(cos(a1), sin(a1)) * radius
		var chord: Vector2 = p1 - p0
		var shape := RectangleShape2D.new()
		shape.size = Vector2(chord.length(), thickness)
		var coll := CollisionShape2D.new()
		coll.shape = shape
		coll.position = (p0 + p1) * 0.5
		coll.rotation = chord.angle()
		add_child(coll)

func _physics_process(delta: float) -> void:
	_round_elapsed += delta
	# Exactly opposite GapRing's own rotation -- negative of the same base
	# speed/multiplier, so the two arcs' relative sweep rate (how often they
	# actually cross paths) still scales down together with Last Flag
	# Standing's overall slowdown, same as the gap itself does.
	var speed: float = -RoyaleSettings.gap_rotation_speed_rad * GameManager.current_speed_multiplier()
	rotation += speed * delta
	constant_angular_velocity = speed
