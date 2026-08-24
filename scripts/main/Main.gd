extends Node2D
## Root scene: the only node that touches both GameManager and live scene
## nodes (flags/arena), following the sibling projects' "Main is the single
## bridge, everything else is a passive listener" discipline. Spawns and
## repositions flags in response to GameManager signals; escapes themselves
## are detected and reported directly by EscapeDetector, not through Main.

const ARENA_SCENE: PackedScene = preload("res://scenes/arena/Arena.tscn")
const GLOW_RING_SCENE: PackedScene = preload("res://scenes/arena/GlowRing.tscn")
const FLAG_SCENE: PackedScene = preload("res://scenes/flag/Flag.tscn")

## Concentric-ring packing: rings of evenly-spaced points, stepping outward
## by `spacing` between rings. Unlike the sunflower/phyllotaxis distribution
## originally ported from flagsbattleroyale (which only guarantees the
## AVERAGE nearest-neighbor spacing across the whole roster, not a minimum),
## this guarantees every point is at least `spacing` from its neighbors by
## construction. That distinction matters here: at the full 250-flag roster,
## the sunflower distribution's average spacing worked out to only ~47px --
## almost exactly the flag width -- so a meaningful fraction of pairs ended
## up closer than that purely by chance, and the physics engine's violent
## overlap-resolution impulse on frame one is what produced flags visibly
## glitching at the arena boundary right at spawn (confirmed via visual
## testing). A guaranteed minimum spacing removes that failure mode outright
## rather than just making it statistically rarer.
const SPAWN_MIN_RADIUS := 40.0
const SPAWN_MARGIN := 60.0
## Extra breathing room beyond the flag's own width, so neighboring flags
## clear each other with margin instead of spawning edge-to-edge.
const SPAWN_SPACING_FACTOR := 1.15

@onready var _flags_root: Node2D = $FlagsRoot

var _arena: Arena
var _flags_by_code: Dictionary = {}  # code -> Flag
## The flag currently frozen in place for a ROUND WINNER reveal, if any --
## needs explicit cleanup (queue_free) once the next round's flags spawn in,
## since it's no longer in _flags_by_code's "will get overwritten" path (its
## code has already permanently qualified, so it never appears in a future
## round's pool).
var _frozen_round_winner: Flag = null

func _ready() -> void:
	_arena = ARENA_SCENE.instantiate()
	add_child(_arena)
	move_child(_arena, 0)  # keep the arena drawn behind flags/UI

	# GlowRing draws the ring's neon outline itself (Arena's own GapRing is
	# now purely physics, invisible) -- see GlowRing.gd for why this needs
	# to be a separate node in its own SubViewport rather than just another
	# child here. Drawn right after Arena, still behind flags/UI.
	var glow_ring: GlowRing = GLOW_RING_SCENE.instantiate()
	add_child(glow_ring)
	move_child(glow_ring, 1)
	glow_ring.setup(_arena.gap_ring)

	GameManager.tournament_started.connect(_on_tournament_started)
	GameManager.qualifying_round_reset.connect(_on_qualifying_round_reset)
	GameManager.flag_qualified.connect(_on_flag_qualified)
	GameManager.last_flag_standing_started.connect(_on_last_flag_standing_started)
	GameManager.round_reset.connect(_on_round_reset)
	GameManager.champion_crowned.connect(_on_champion_crowned)
	GameManager.tournament_reset.connect(_on_tournament_reset)

	# The very first tournament waits for the player to click START ($StartScreen)
	# rather than firing the instant the scene loads -- every tournament after
	# that still loops on its own via GameManager's intermission timer, same
	# as before this screen existed. This only gates the first one.
	$StartScreen.start_pressed.connect(GameManager.start_game)

## Capacity of a ring layout at a given spacing -- summed across every ring
## from min_radius to max_radius, stepping by spacing. Used to find the
## largest spacing that still fits `count` points before actually placing
## them.
func _ring_capacity(spacing: float, min_radius: float, max_radius: float) -> int:
	var capacity := 0
	var r := min_radius
	while r <= max_radius:
		capacity += maxi(1, floori(TAU * r / spacing))
		r += spacing
	return capacity

## Lays out `count` points in concentric rings, shrinking the requested
## spacing (down to a hard floor) if the arena is too small to fit the full
## roster at full spacing -- guarantees every point still gets SOME minimum
## clearance rather than silently overlapping once the math doesn't fit.
##
## First figures out how many rings (and how many points per ring) `count`
## actually needs at this spacing -- using min_radius purely as a stand-in
## to size each ring's point capacity, NOT as where that ring ends up. Those
## rings then get spread evenly across the FULL [min_radius, max_radius]
## span rather than packed in tight starting from min_radius outward. That
## distinction only shows up once `count` is small (a late Last Flag
## Standing round, down to a handful of flags): the old inside-out packing
## always fit those few points in the first ring or two, which sits barely
## past the arena's dead center regardless of how big the arena actually
## is -- every post-elimination respawn looked like the remaining flags
## piling up in the middle and exploding outward (confirmed via direct
## report). Spreading whatever ring count was actually needed across the
## whole radius instead keeps every respawn using the entire arena no
## matter how few flags are left; for the full ~250-flag roster this comes
## out to essentially the same ring spacing as before, since needing many
## rings to fit that many points already spans close to the full range.
func _pack_positions(count: int, min_radius: float, max_radius: float, base_spacing: float) -> Array:
	var spacing := base_spacing
	while spacing > 4.0 and _ring_capacity(spacing, min_radius, max_radius) < count:
		spacing *= 0.95

	var ring_point_counts: Array[int] = []
	var sizing_r := min_radius
	var remaining := count
	while remaining > 0:
		var n_this_ring: int = mini(maxi(1, floori(TAU * sizing_r / spacing)), remaining)
		ring_point_counts.append(n_this_ring)
		remaining -= n_this_ring
		sizing_r += spacing

	var ring_count: int = ring_point_counts.size()
	var positions: Array = []
	var ring_phase := 0.0
	for ring_index in range(ring_count):
		var ring_radius: float = (min_radius + max_radius) * 0.5 if ring_count == 1 \
			else lerp(min_radius, max_radius, float(ring_index) / float(ring_count - 1))
		var n_this_ring: int = ring_point_counts[ring_index]
		for i in range(n_this_ring):
			var theta: float = (TAU * float(i) / float(n_this_ring)) + ring_phase
			positions.append(Vector2(cos(theta), sin(theta)) * ring_radius)
		ring_phase += 0.5  # stagger successive rings so points don't line up radially

	# Unreachable given the area math above for any realistic roster/arena
	# size, but never leave a flag without a valid spawn position.
	while positions.size() < count:
		var theta: float = randf() * TAU
		positions.append(Vector2(cos(theta), sin(theta)) * max_radius)
	return positions

## Shared by every "fill the arena with fresh Flag instances" moment --
## the very first spawn, each subsequent qualifying round (its pool is
## exclusively flags that were just ejected from the previous round and are
## already mid-departure-flight/freed, so there's nothing to reposition,
## only fresh instances to create), and the jump into Last Flag Standing.
## Entries are {code, name} dicts; overwrites _flags_by_code so a code's
## entry always points at whichever instance is actually currently alive.
##
## reset_physics_interpolation() after every direct position set below (here
## and in _on_round_reset) matters now that physics/common/physics_interpolation
## is on (see project.godot -- added specifically to fix visible per-frame
## jitter on fast-moving flags, most noticeable on diagonal motion, confirmed
## screenshots looked fine since a single frame has nothing to interpolate
## between). Without the reset, a teleported flag would visibly SLIDE from
## its old rendered position to the new one over one frame instead of
## appearing there instantly, since interpolation has no way to know "this
## wasn't real motion" otherwise.
func _spawn_flags(entries: Array, speed: float) -> void:
	var center: Vector2 = _arena.get_center_global()
	var count: int = entries.size()
	var max_radius: float = RoyaleSettings.ring_radius - SPAWN_MARGIN
	var spacing: float = RoyaleSettings.flag_width_px * SPAWN_SPACING_FACTOR
	var positions: Array = _pack_positions(count, SPAWN_MIN_RADIUS, max_radius, spacing)
	for i in range(count):
		var entry: Dictionary = entries[i]
		var flag: Flag = FLAG_SCENE.instantiate()
		_flags_root.add_child(flag)
		flag.setup(entry.code, entry.name, FlagDatabase.get_texture(entry.code))
		flag.global_position = center + positions[i]
		flag.reset_physics_interpolation()
		var launch_dir: float = randf() * TAU
		flag.launch(Vector2(cos(launch_dir), sin(launch_dir)) * speed)
		_flags_by_code[entry.code] = flag

func _on_tournament_started(_total_flags: int) -> void:
	_spawn_flags(FlagDatabase.get_shuffled_roster(), RoyaleSettings.relaunch_speed_base)

## Every code in this pool was just ejected from the previous round (already
## departed/freed) except on the very first round, which never reaches this
## handler at all -- tournament_started's own spawn covers that one.
func _on_qualifying_round_reset(pool_entries: Array) -> void:
	_clear_frozen_round_winner()
	_spawn_flags(pool_entries, RoyaleSettings.relaunch_speed_base)

## A qualifying round's winner never itself escaped through the gap (that's
## exactly why it won: everyone else did, this one didn't) -- so unlike
## every other departure, nothing has told this flag to leave yet. It's
## still live and bouncing in the arena at this exact moment.
##
## Freezing it in place (same treatment as the champion at the very end)
## rather than calling depart() -- departing disables the flag's collision
## and sends it flying off in a straight line same as any other exit, which
## looked broken during the ROUND WINNER reveal specifically: the reveal
## shows for a few real seconds (see GameManager.ROUND_ADVANCE_DELAY_SECONDS),
## long enough for that flight to visibly cross clean through the arena,
## ignoring the ring boundary since collisions are already off -- confirmed
## via direct feedback. It gets cleaned up (queue_free) once the next round's
## flags spawn in, via _clear_frozen_round_winner().
func _on_flag_qualified(code: String, _country_name: String, _rank: int, _total: int) -> void:
	if _flags_by_code.has(code):
		var flag: Flag = _flags_by_code[code]
		if is_instance_valid(flag) and not flag.is_departing():
			flag.freeze = true
			flag.linear_velocity = Vector2.ZERO
			_frozen_round_winner = flag

func _clear_frozen_round_winner() -> void:
	if _frozen_round_winner != null and is_instance_valid(_frozen_round_winner):
		_frozen_round_winner.queue_free()
	_frozen_round_winner = null

## The qualifiers that just closed out the qualifying arena already departed
## it (each one's Flag node is mid-flight toward the leaderboard, or already
## freed once it crossed the boundary) -- nothing spawns them back in on its
## own. Fresh Flag instances for the final, same spawn approach as
## _on_tournament_started but over just the qualifier roster, replacing each
## code's now-stale (already-departed/freed) entry in _flags_by_code. Without
## this, the first elimination's round_reset would try to reposition those
## stale freed references and crash.
func _on_last_flag_standing_started(qualifiers: Array) -> void:
	_clear_frozen_round_winner()
	_spawn_flags(qualifiers, RoyaleSettings.relaunch_speed_base)

## Last Flag Standing: after every elimination, all remaining flags reset to
## fresh positions and relaunch at the new (slower) round speed -- confirmed
## requirement, not optional polish.
func _on_round_reset(remaining_codes: Array, multiplier: float) -> void:
	var center: Vector2 = _arena.get_center_global()
	var count: int = remaining_codes.size()
	var max_radius: float = RoyaleSettings.ring_radius - SPAWN_MARGIN
	var spacing: float = RoyaleSettings.flag_width_px * SPAWN_SPACING_FACTOR
	var positions: Array = _pack_positions(count, SPAWN_MIN_RADIUS, max_radius, spacing)
	var speed: float = RoyaleSettings.relaunch_speed_base * multiplier
	for i in range(count):
		var code: String = remaining_codes[i]
		if not _flags_by_code.has(code):
			continue
		var flag: Flag = _flags_by_code[code]
		flag.global_position = center + positions[i]
		flag.reset_physics_interpolation()
		var launch_dir: float = randf() * TAU
		flag.launch(Vector2(cos(launch_dir), sin(launch_dir)) * speed)

## The champion is the one flag that never had depart() called on it (it
## won, it didn't escape) -- freeze it in place for the reveal instead of
## letting it keep bouncing alone.
func _on_champion_crowned(code: String, _country_name: String, _podium: Array) -> void:
	if _flags_by_code.has(code):
		var flag: Flag = _flags_by_code[code]
		flag.freeze = true
		flag.linear_velocity = Vector2.ZERO

func _on_tournament_reset() -> void:
	for flag in _flags_by_code.values():
		if is_instance_valid(flag):
			flag.queue_free()
	_flags_by_code.clear()
	_frozen_round_winner = null
