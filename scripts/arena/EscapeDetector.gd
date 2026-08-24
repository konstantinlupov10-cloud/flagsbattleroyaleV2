extends Node2D
class_name EscapeDetector
## Centralized escape detection over group("active_flags") -- one script
## driving the check for every flag each physics frame, not per-flag polling.
## Tying detection to _gap_ring.rotation directly (rather than separately
## tracked bookkeeping) means detection and the physical wall can never desync.

## Fired when a flag is found outside the ring radius but NOT within the
## gap's angular window. In an isolated low-body-count test this is rare and
## worth investigating; at full roster scale (250 flags densely colliding),
## some rate of this is an accepted, permanent safety net rather than a bug
## to chase to zero -- CCD_MODE_CAST_SHAPE has known limitations under heavy
## simultaneous multi-body contact that no amount of margin/tolerance tuning
## fully eliminates. The position/velocity correction below runs regardless;
## this signal is for aggregate-rate statistics (see tools/EscapeRateHistogram.gd),
## not per-event logging -- deliberately no push_warning() here, since that
## was itself materially slowing down high-load test runs.
signal tunneling_detected(code: String)

var _center: Vector2
var _gap_ring: GapRing

func setup(center: Vector2, gap_ring: GapRing) -> void:
	_center = center
	_gap_ring = gap_ring

func _physics_process(_delta: float) -> void:
	# GapRing._build_segments() disables segment indices [0, gap_segment_count)
	# specifically -- i.e. the physical gap spans local angle [0, gap_width),
	# NOT a window centered on 0. Detection must match that exact placement.
	var gap_width: float = deg_to_rad(RoyaleSettings.gap_width_degrees())
	for flag in get_tree().get_nodes_in_group("active_flags"):
		var offset: Vector2 = flag.global_position - _center
		# Defensive backstop against a corrupted position, checked BEFORE
		# calling .normalized() anywhere below. is_finite() alone isn't
		# enough: a position that's individually finite but astronomically
		# large (from a residual physics explosion) can still overflow to
		# infinity inside normalize()'s own internal squaring, which
		# is_finite() on the un-squared offset can't catch. A generous
		# magnitude sanity bound catches both cases in one check.
		if not offset.is_finite() or offset.length() > RoyaleSettings.ring_radius * 10.0:
			flag.depart(false)
			continue
		if offset.length() <= RoyaleSettings.ring_radius + RoyaleSettings.escape_margin_px:
			continue
		var local_angle: float = fposmod(offset.angle() - _gap_ring.rotation, TAU)
		var tolerance: float = deg_to_rad(RoyaleSettings.gap_edge_tolerance_degrees)
		if local_angle < gap_width + tolerance or local_angle > TAU - tolerance:
			GameManager.notify_flag_escaped(flag.country_code, flag.country_name)
			flag.depart(true)
		else:
			# Permanent safety net, not a rare-case guard -- see the signal's
			# doc comment above. Silent correction, no per-event logging.
			tunneling_detected.emit(flag.country_code)
			# Lands clearly inside the wall's own INNER face (ring_radius -
			# wall_thickness_px/2), not just barely inside ring_radius
			# itself. The previous ring_radius-5.0 target (445, with the
			# wall spanning 430-470) sat INSIDE the wall's own physical
			# footprint -- at the speeds/tunneling rates this project runs
			# at now, a flag correcting there over and over reads as
			# permanently glued to the boundary line rather than as a
			# clean "back inside the arena" correction (confirmed via
			# direct feedback -- what looked like flags spawning on the
			# ring line was actually this).
			flag.global_position = _center + offset.normalized() * \
				(RoyaleSettings.ring_radius - RoyaleSettings.wall_thickness_px * 0.5 - 20.0)
			# Without this, physics interpolation (see project.godot) would
			# visibly slide the flag from its pre-correction position to
			# this teleported one over one frame instead of correcting it
			# instantly.
			flag.reset_physics_interpolation()
			flag.linear_velocity = flag.linear_velocity.bounce(offset.normalized())
