extends RigidBody2D
class_name Flag
## A single competing flag, moving at a genuinely constant speed. Unlike the
## original flagsbattleroyale (which fought a continuous Vortex steering
## force with heavy damping) and unlike a naive "launch and let physics
## decide" approach (which a low-damping test confirmed still loses energy
## unpredictably in a chaotic multi-body system), speed magnitude is pinned
## every physics frame in _integrate_forces() -- collisions freely change
## direction, but a flag can never stall or run away with excess energy.
## This also means no separate anti-stall jitter system is needed at all.
## Flags are rectangular (native SVG aspect), not circular -- no shader.

@export var country_code: String = ""
@export var country_name: String = ""

var _departing: bool = false

func _ready() -> void:
	add_to_group("active_flags")
	gravity_scale = 0.0
	angular_damp = RoyaleSettings.flag_angular_damp
	# The boundary wall segments have real (if thin) thickness now, but a
	# fast-moving flag colliding in a dense chaotic system can still cross
	# one within a single physics tick without continuous collision detection.
	# CAST_SHAPE (not the cheaper CAST_RAY) is required: flags have real
	# extent, so a corner/edge can tunnel at a grazing angle even when a
	# ray-cast from the center wouldn't.
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var mat := PhysicsMaterial.new()
	mat.friction = RoyaleSettings.flag_friction
	mat.bounce = RoyaleSettings.flag_bounce
	physics_material_override = mat

## Assigns identity + texture and sizes the sprite/collision shape to match.
## texture may be null (headless physics testing, no visuals needed).
func setup(code: String, display_name: String, texture: Texture2D) -> void:
	country_code = code
	country_name = display_name
	if texture == null:
		return
	var sprite: Sprite2D = $Sprite2D
	sprite.texture = texture
	_fit_sprite_and_collision(texture)

func _fit_sprite_and_collision(texture: Texture2D) -> void:
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale_factor: float = RoyaleSettings.flag_width_px / tex_size.x
	$Sprite2D.scale = Vector2(scale_factor, scale_factor)
	$Shadow.scale = Vector2(scale_factor, scale_factor)
	var shape: RectangleShape2D = $CollisionShape2D.shape
	shape.size = tex_size * scale_factor

## Gives this flag an initial direction -- speed magnitude doesn't matter
## here since _integrate_forces() pins it every frame regardless, but the
## direction persists until the first collision changes it.
func launch(velocity: Vector2) -> void:
	linear_velocity = velocity

func is_departing() -> bool:
	return _departing

## The correct hook for touching velocity (not _process/_physics_process).
## Direction is whatever collisions/the solver produced this step; magnitude
## is always pinned to the current target speed, which itself tracks
## GameManager's round multiplier -- so this one mechanism gives both
## "never stalls" and "Last Flag Standing gradually slows down" for free.
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _departing:
		return
	var target_speed: float = RoyaleSettings.relaunch_speed_base * GameManager.current_speed_multiplier()
	var v: Vector2 = state.linear_velocity
	if v.length() > 0.01:
		state.linear_velocity = v.normalized() * target_speed
	else:
		# Degenerate zero-velocity edge case (shouldn't happen from a nonzero
		# launch, but a flag pinned exactly still by a solver quirk should
		# still get moving rather than staying frozen forever).
		var dir: float = randf() * TAU
		state.linear_velocity = Vector2(cos(dir), sin(dir)) * target_speed

## Called by EscapeDetector once this flag has passed through the gap. The
## meaning (qualified vs. eliminated) is entirely GameManager's phase-based
## interpretation -- this script has no idea which one just happened.
## `flourish` gates the celebratory ring-burst FX (wired in a later
## milestone); duration is the shrink/spin flourish length either way.
func depart(flourish: bool, duration: float = 0.45) -> void:
	if _departing:
		return
	_departing = true
	remove_from_group("active_flags")
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, false)
	# A flag that arrives here with an already-corrupted (NaN/Inf) transform
	# -- from the same class of instability EscapeDetector's finite-position
	# guard catches -- crashes on freeze/tween below (Godot's internal
	# affine_invert hits a zero-determinant matrix). Snap to a known-good
	# transform first so this cleanup path is always safe to run.
	if not global_position.is_finite() or not scale.is_finite():
		global_position = Vector2.ZERO
		scale = Vector2.ONE
		rotation = 0.0
	freeze = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ZERO, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "rotation", rotation + TAU * 2.0, duration)
	tween.chain().tween_callback(queue_free)
