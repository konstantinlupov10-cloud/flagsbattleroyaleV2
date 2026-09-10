extends RigidBody2D
class_name Flag
## A single competing flag, moving at a genuinely constant speed. Unlike the
## original flagsbattleroyale (which fought a continuous Vortex steering
## force with heavy damping) and unlike a naive "launch and let physics
## decide" approach (which a low-damping test confirmed still loses energy
## unpredictably in a chaotic multi-body system), speed magnitude is pinned
## every physics frame in _physics_process() -- collisions freely change
## direction, but a flag can never stall or run away with excess energy.
## This also means no separate anti-stall jitter system is needed at all.
## Flags are rectangular (native SVG aspect), not circular -- no shader.

@export var country_code: String = ""
@export var country_name: String = ""

var _departing: bool = false

## Set when this flag touches the blocker arc during its light-blue freeze
## window (see BlockerArc.is_freezing_active()). A frozen flag runs at
## RoyaleSettings.frozen_flag_speed_factor of normal speed for the rest of
## the round -- "the rest of the round" needs no explicit timer since every
## qualifying round spawns brand-new Flag instances, and Last Flag Standing
## is a single round. Touching the blocker arc again (any color) thaws it.
var _frozen: bool = false
## Frost visual: the flag's own pixels are never touched (confirmed via
## direct feedback -- it must keep its exact original colours). The cue is
## a Node2D holding a light-blue border hugging the flag's outer edge plus
## a row of neon-glowing icicles off the bottom, both drawn with the same
## manual-glow trick as GlowRing/GlowArc (bright core + wider dim copies).
## Built to the sprite's size in _fit_sprite_and_collision(), hidden until
## _frozen.
var _frost_icicles: Node2D

const BORDER_CORE_COLOR := Color(0.55, 0.85, 1.0, 0.95)
const BORDER_GLOW_COLOR := Color(0.4, 0.8, 1.0, 0.28)
const ICICLE_CORE_COLOR := Color(0.85, 0.96, 1.0, 0.97)
## Widest/dimmest first -- stacked behind the core for a soft cyan halo.
## `drop` starts each glow layer that many px BELOW the flag's bottom edge
## so its sideways bloom never washes onto the flag itself.
const ICICLE_GLOW_LAYERS: Array = [
	{"scale": 2.4, "drop": 5.0, "color": Color(0.35, 0.78, 1.0, 0.10)},
	{"scale": 1.7, "drop": 2.5, "color": Color(0.45, 0.85, 1.0, 0.22)},
]

func _ready() -> void:
	add_to_group("active_flags")
	gravity_scale = 0.0
	# Flags stay upright through every collision -- lock_rotation tells the
	# physics engine to never apply torque/angular velocity to the body at
	# all, rather than just damping it. This doesn't touch the depart()
	# tween's celebratory spin below, which sets `rotation` directly instead
	# of going through the physics layer.
	lock_rotation = true
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

	# body_entered fires for both flag-flag and flag-wall contacts alike --
	# AudioManager doesn't need to know which, just rate-limits whatever
	# comes in. max_contacts_reported only needs to be nonzero for the
	# signal to fire at all; the exact count doesn't matter since nothing
	# here reads get_colliding_bodies().
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

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
	var rendered: Vector2 = tex_size * scale_factor
	var shape: RectangleShape2D = $CollisionShape2D.shape
	shape.size = rendered
	_build_frost_overlay(rendered)

func _build_frost_overlay(rendered: Vector2) -> void:
	var hw: float = rendered.x * 0.5
	var hh: float = rendered.y * 0.5

	_frost_icicles = Node2D.new()
	_frost_icicles.visible = false
	add_child(_frost_icicles)

	# Light-blue border hugging the flag's outer edge (offset 1px out so it
	# frames rather than eats into the flag) -- a dim wider glow copy under a
	# brighter core, both closed rectangles.
	var b := hw + 1.0
	var bh := hh + 1.0
	var rect := PackedVector2Array([
		Vector2(-b, -bh), Vector2(b, -bh), Vector2(b, bh), Vector2(-b, bh), Vector2(-b, -bh)])
	for spec in [{"w": 6.0, "c": BORDER_GLOW_COLOR}, {"w": 2.5, "c": BORDER_CORE_COLOR}]:
		var border := Line2D.new()
		border.points = rect
		border.width = spec.w
		border.default_color = spec.c
		border.antialiased = true
		border.joint_mode = Line2D.LINE_JOINT_ROUND
		_frost_icicles.add_child(border)

	# One tapered spike per icicle: a Line2D from just inside the flag's
	# bottom edge down to a sharp point (width_curve tapers to 0), plus a
	# couple of wider, dimmer copies behind it for the cyan neon halo.
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(0.68, 0.5))
	taper.add_point(Vector2(1.0, 0.0))

	var count := 5
	for t in range(count):
		var span: float = rendered.x / float(count)
		var cx: float = -hw + span * (t + 0.5) + randf_range(-span * 0.12, span * 0.12)
		var base_w: float = span * randf_range(0.5, 0.72)
		# Longer toward the middle -- meltwater pools there and drips most.
		var mid_bias: float = 0.6 + 0.85 * sin(PI * (float(t) + 0.5) / float(count))
		var length: float = hh * randf_range(0.9, 1.5) * mid_bias
		var tip := Vector2(cx + randf_range(-base_w, base_w) * 0.18, hh + length)
		for layer in ICICLE_GLOW_LAYERS:
			_frost_icicles.add_child(_make_icicle(
				Vector2(cx, hh + layer.drop), tip, base_w * layer.scale, layer.color, taper))
		_frost_icicles.add_child(_make_icicle(Vector2(cx, hh), tip, base_w, ICICLE_CORE_COLOR, taper))

func _make_icicle(from: Vector2, to: Vector2, width: float, color: Color, taper: Curve) -> Line2D:
	var ln := Line2D.new()
	ln.points = PackedVector2Array([from, to])
	ln.width = width
	ln.width_curve = taper
	ln.default_color = color
	ln.antialiased = true
	ln.begin_cap_mode = Line2D.LINE_CAP_NONE
	ln.end_cap_mode = Line2D.LINE_CAP_NONE
	return ln

## Gives this flag an initial direction -- speed magnitude doesn't matter
## here since _physics_process() pins it every frame regardless, but the
## direction persists until the first collision changes it.
func launch(velocity: Vector2) -> void:
	linear_velocity = velocity

func is_departing() -> bool:
	return _departing

## departing flags already have their collision layer/mask cleared in
## depart(), so this can only fire for a genuine in-arena bounce -- no
## _departing guard needed. Reports the midpoint between the two colliding
## bodies (falling back to this flag's own position for a non-Node2D body,
## not that any exist on the relevant collision layers) so AudioManager can
## play the clack positioned where the hit actually happened on screen.
func _on_body_entered(body: Node) -> void:
	var contact_point: Vector2 = global_position
	if body is Node2D:
		contact_point = (global_position + (body as Node2D).global_position) * 0.5
	AudioManager.notify_flag_collision(contact_point)

	if body is BlockerArc:
		# The arc's current colour decides the outcome of a contact:
		#  - blue (freezing window): freezes a normal flag; a frozen flag
		#    just bounces, it does NOT thaw while the arc is still blue
		#    (confirmed via direct feedback).
		#  - green: thaws a frozen flag; does nothing to a normal one.
		if (body as BlockerArc).is_freezing_active():
			_set_frozen(true)
		else:
			_set_frozen(false)

func _set_frozen(value: bool) -> void:
	if _frozen == value:
		return
	_frozen = value
	if _frost_icicles:
		_frost_icicles.visible = value

## Deliberately _physics_process(), not _integrate_forces(). _integrate_forces
## runs BEFORE the physics server resolves this step's collisions, so
## state.linear_velocity/get_contact_count() there both describe the PREVIOUS
## frame -- a flag in sustained contact (resting against the wall under crowd
## pressure, or wedged against neighbors) shows contact_count > 0 on every
## single frame, which (in an earlier version of this function that skipped
## renormalization during contact) permanently blocked the speed top-up and
## left flags parked at whatever near-zero velocity the solver settled them
## to: visually, a ring of barely-moving flags clustered at the perimeter.
## _physics_process() runs AFTER the physics step completes, so
## linear_velocity here already reflects this frame's fully-resolved bounce --
## setting it directly never fights the solver mid-resolution, so no
## contact-count check is needed at all: direction is always whatever the
## solver just produced, magnitude is always pinned to the current target
## speed (tracks GameManager's round multiplier for the Last Flag Standing
## slowdown).
##
## Getting a true mirror reflection off the wall (angle in = angle out, no
## directional bias) depends on both sides of that contact combining to full
## elastic restitution -- see flag_bounce's comment in RoyaleSettings.gd and
## GapRing.gd's matching physics_material_override for why that has to be set
## explicitly on the wall too, not just on the flag.
func _physics_process(_delta: float) -> void:
	if freeze:
		return
	if _departing:
		_check_departure_bounds()
		return
	var target_speed: float = RoyaleSettings.relaunch_speed_base * GameManager.current_speed_multiplier()
	if _frozen:
		target_speed *= RoyaleSettings.frozen_flag_speed_factor
	var v: Vector2 = linear_velocity
	if v.length() > 0.01:
		linear_velocity = v.normalized() * target_speed
	else:
		# Degenerate zero-velocity edge case (shouldn't happen from a nonzero
		# launch, but a flag pinned exactly still by a solver quirk should
		# still get moving rather than staying frozen forever).
		var a: float = randf() * TAU
		linear_velocity = Vector2(cos(a), sin(a)) * target_speed

## Once departing, a flag has no more collisions to worry about (its layers
## are fully cleared in depart(), below) and there's no gravity or friction,
## so ordinary Newtonian motion keeps it coasting in a dead-straight line at
## its exact exit velocity with zero extra code needed -- direction is
## whatever it was actually moving at the moment it escaped, not redirected
## toward some fixed point (confirmed via visual testing: aiming every
## departure at one shared spot made them all visibly curve inward toward
## it, which read as an odd funnel rather than flags naturally continuing on
## their way out). This just watches for that straight line crossing into
## the top/bottom UI panels -- or fully off either side of the screen, which
## has no UI to catch it, so it just vanishes quietly there too -- and
## removes the flag right at that boundary rather than playing any further
## animation.
func _check_departure_bounds() -> void:
	var pos: Vector2 = global_position
	if pos.y <= RoyaleSettings.departure_vanish_top_y or pos.y >= RoyaleSettings.departure_vanish_bottom_y \
		or pos.x <= 0.0 or pos.x >= 1080.0:
		queue_free()

## Called by EscapeDetector once this flag has passed through the gap. The
## meaning (qualified vs. eliminated) is entirely GameManager's phase-based
## interpretation -- this script has no idea which one just happened, and
## doesn't need to: Leaderboard.gd and EjectedStrip.gd each listen to
## GameManager's own flag_qualified/flag_eliminated signals directly, fully
## decoupled from this flag's physical flight path.
##
## `flourish` distinguishes a genuine escape from EscapeDetector's defensive
## cleanup path for an already-corrupted (NaN/Inf) flag -- flying a flag from
## a garbage position isn't meaningful, so that case (and any flag that
## somehow still has a non-finite position/velocity despite flourish=true)
## skips straight to immediate removal instead.
func depart(flourish: bool) -> void:
	if _departing:
		return
	_departing = true
	remove_from_group("active_flags")
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, false)
	if not flourish or not global_position.is_finite() or not linear_velocity.is_finite():
		queue_free()
		return
	# No further action needed here -- collisions are already fully disabled
	# above and there's no gravity/friction, so plain physics carries the
	# flag onward in a straight line at its current velocity from this point;
	# _check_departure_bounds() above removes it once that line crosses into
	# a UI panel or off either side of the screen.
