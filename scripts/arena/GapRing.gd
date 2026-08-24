extends StaticBody2D
class_name GapRing
## The rotating boundary wall: RoyaleSettings.ring_segment_count thin
## RectangleShape2D children arranged in a circle (chord-aligned, one per
## segment), with gap_segment_count of them disabled to form the escaping
## gap. The whole ring rotates as a single Transform2D update (`rotation`),
## not a per-frame shape rebuild -- cheap, and avoids the class of bug a
## rebuilt CollisionPolygon2D could hit mid-frame.
##
## Originally built from SegmentShape2D (a true zero-thickness line), which
## is what the BUILD_SOLIDS/BUILD_SEGMENTS trap that bit the original
## flagsbattleroyale's CollisionPolygon2D doesn't apply to. But a
## zero-thickness segment turned out to have its own problem, found via the
## escape-rate harness: CCD_MODE_CAST_SHAPE against a truly zero-width shape
## produced a degenerate/undefined contact normal under some approach
## angles, which propagated NaN position/velocity into the flag and cascaded
## into a runaway error loop. A thin RectangleShape2D (real, if small,
## thickness) gives the physics engine a well-defined contact normal to
## resolve against instead.

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	# Without an explicit override, a StaticBody2D collides at the engine's
	# default bounce (0.0) -- which can dominate however Godot combines the
	# two sides' bounce values, silently making wall collisions far less
	# elastic than flag_bounce alone would suggest. Matching it here removes
	# that ambiguity outright: both sides agree on full elastic restitution,
	# so a wall bounce is a true mirror reflection with no directional bias.
	# See RoyaleSettings.flag_bounce's comment for the full reasoning -- this
	# was the actual cause of flags gradually converging into a perimeter
	# "orbit" over time, not the flag-side physics.
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = RoyaleSettings.flag_bounce
	physics_material_override = mat
	_build_segments()

func _build_segments() -> void:
	var count: int = RoyaleSettings.ring_segment_count
	var gap_count: int = RoyaleSettings.gap_segment_count
	var radius: float = RoyaleSettings.ring_radius
	var thickness: float = RoyaleSettings.wall_thickness_px
	var angle_step: float = TAU / float(count)
	for i in range(count):
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
		coll.disabled = i < gap_count
		add_child(coll)

func _physics_process(delta: float) -> void:
	var speed: float = RoyaleSettings.gap_rotation_speed_rad * GameManager.current_speed_multiplier()
	rotation += speed * delta
	# Tells the physics solver the wall itself is moving, so contact impulses
	# against it are computed correctly -- setting `rotation` alone moves the
	# shape but not the solver's notion of the wall's own velocity.
	constant_angular_velocity = speed
