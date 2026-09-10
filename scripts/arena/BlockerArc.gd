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

enum State { GREEN, FREEZING, FIRE }

## The colour cycle reads GREEN -> BLUE -> GREEN -> RED and repeats. The
## very first GREEN lasts blocker_arc_first_green_seconds; after that the
## block below repeats forever: GREEN phases last blocker_arc_green_seconds,
## the BLUE phase blocker_arc_freezing_seconds, the RED phase
## blocker_arc_fire_seconds. The block starts at BLUE because the long
## initial GREEN already served as the first GREEN of the sequence.
const _BLOCK: Array = [State.FREEZING, State.GREEN, State.FIRE, State.GREEN]

## Seconds since the current round started -- drives the colour cycle (see
## current_state()). Arena (and therefore this node) is built once and never
## rebuilt, so the timer is reset from GameManager's round-boundary signals
## rather than from _ready().
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

## Which colour the arc is right now. GlowArc reads this to recolour
## itself; Flag reads it on contact to decide a state change.
func current_state() -> State:
	var first: float = RoyaleSettings.blocker_arc_first_green_seconds
	if _round_elapsed < first:
		return State.GREEN
	var green: float = RoyaleSettings.blocker_arc_green_seconds
	var freezing: float = RoyaleSettings.blocker_arc_freezing_seconds
	var fire: float = RoyaleSettings.blocker_arc_fire_seconds
	var durations: Array = [freezing, green, fire, green]  # matches _BLOCK
	var block_len: float = freezing + green + fire + green
	var t: float = fmod(_round_elapsed - first, block_len)
	var acc: float = 0.0
	for i in range(_BLOCK.size()):
		acc += durations[i]
		if t < acc:
			return _BLOCK[i]
	return State.GREEN  # unreachable

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
