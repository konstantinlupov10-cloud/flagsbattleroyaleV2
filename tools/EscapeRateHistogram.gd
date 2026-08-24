extends Node2D
## Headless statistical harness for the rotating-gap arena's escape rate.
##
## Unlike flagsplinko's discs (which deliberately don't collide with each
## other, letting hundreds drop in independent parallel waves), v2's flags DO
## collide with each other -- the escape rate is a genuinely emergent
## property of the whole arena's chaotic multi-body dynamics, not something
## that can be sampled in independent batches. This runs full qualifying-
## phase simulations at high time_scale and records every escape timestamp.
##
## Run it with:
##   godot --headless --path C:/Git/flagsbattleroyalev2 res://tools/EscapeRateHistogram.tscn -- <runs> <time_scale> [flag_count] [qualifying_seconds]
##
## flag_count/qualifying_seconds default to the full roster/RoyaleSettings
## value if omitted -- pass small overrides (e.g. 30 flags, 20s window) for
## fast iteration while debugging, and only the full-scale defaults for a
## final confirmation run.
##
## A hard wall-clock watchdog force-quits and reports whatever partial data
## exists after WATCHDOG_SECONDS of real time, so a genuine hang or a
## mistuned slow run can never require manually killing the process.
##
## Tune RoyaleSettings.gap_width_degrees()/gap_rotation_speed_rad/ring_radius
## and flag bounce/damping against this, never by eye.

const FLAG_SCENE: PackedScene = preload("res://scenes/flag/Flag.tscn")
const ARENA_SCENE: PackedScene = preload("res://scenes/arena/Arena.tscn")

const DEFAULT_RUNS := 1
const DEFAULT_TIME_SCALE := 20.0
const DEFAULT_WATCHDOG_SECONDS := 45.0

var _target_runs: int = DEFAULT_RUNS
var _flag_count: int = -1  # -1 = full roster
var _qualifying_seconds_override: float = -1.0  # -1 = use RoyaleSettings default
var _watchdog_seconds: float = DEFAULT_WATCHDOG_SECONDS
var _current_run: int = 0
var _run_escape_times: Array = []   # seconds since this run's qualifying start
var _all_run_reports: Array = []    # one summary dict per completed run
var _run_start_ticks_msec: int = 0
var _arena: Arena
var _tunneling_warnings: int = 0
var _watchdog_start_msec: int = 0

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0].is_valid_int():
		_target_runs = maxi(args[0].to_int(), 1)
	var scale: float = DEFAULT_TIME_SCALE
	if args.size() >= 2 and args[1].is_valid_float():
		scale = maxf(args[1].to_float(), 0.1)
	if args.size() >= 3 and args[2].is_valid_int():
		_flag_count = maxi(args[2].to_int(), 2)
	if args.size() >= 4 and args[3].is_valid_float():
		_qualifying_seconds_override = maxf(args[3].to_float(), 1.0)
	if args.size() >= 5 and args[4].is_valid_float():
		_watchdog_seconds = maxf(args[4].to_float(), 5.0)
	Engine.time_scale = scale

	if _qualifying_seconds_override > 0.0:
		RoyaleSettings.qualifying_seconds = _qualifying_seconds_override

	GameManager.flag_qualified.connect(_on_flag_qualified)
	GameManager.qualifying_ended.connect(_on_qualifying_ended)

	_watchdog_start_msec = Time.get_ticks_msec()

	var effective_flags: int = _flag_count if _flag_count > 0 else FlagDatabase.roster_size()
	print("Escape rate histogram: %d run(s), time_scale %.1f, %d flags, %.1fs qualifying window" % [
		_target_runs, scale, effective_flags, RoyaleSettings.qualifying_seconds])
	print("gap_width=%.1f deg, gap_rotation=%.3f rad/s, ring_radius=%.1f, escape_margin=%.1f" % [
		RoyaleSettings.gap_width_degrees(), RoyaleSettings.gap_rotation_speed_rad,
		RoyaleSettings.ring_radius, RoyaleSettings.escape_margin_px])
	print("watchdog: force-quit after %.0fs real time" % _watchdog_seconds)
	_start_run()

func _process(_delta: float) -> void:
	var elapsed_real: float = float(Time.get_ticks_msec() - _watchdog_start_msec) / 1000.0
	if elapsed_real > _watchdog_seconds:
		print("\n!!! WATCHDOG TRIGGERED after %.1fs real time -- reporting partial data !!!" % elapsed_real)
		_report()

func _start_run() -> void:
	_run_escape_times.clear()
	_run_start_ticks_msec = Time.get_ticks_msec()
	if _arena:
		_arena.queue_free()
	for flag in get_tree().get_nodes_in_group("active_flags"):
		flag.queue_free()

	_arena = ARENA_SCENE.instantiate()
	add_child(_arena)
	_arena.escape_detector.tunneling_detected.connect(_on_tunneling_detected)
	call_deferred("_spawn_and_start")

## Sunflower/phyllotaxis distribution, ported from flagsbattleroyale's
## Main.gd -- guarantees no two flags spawn overlapping (each index maps to a
## distinct position), unlike independent random placement, which produced a
## catastrophic de-penetration impulse (overshoot in the billions of pixels)
## when two flags happened to spawn on top of each other.
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))

func _sunflower_point(index: int, count: int, min_radius: float, max_radius: float) -> Vector2:
	var t: float = (float(index) + 0.5) / float(count)
	var r: float = sqrt(lerp(min_radius * min_radius, max_radius * max_radius, t))
	var theta: float = float(index) * GOLDEN_ANGLE
	return Vector2(cos(theta), sin(theta)) * r

func _spawn_and_start() -> void:
	var roster: Array = FlagDatabase.get_shuffled_roster()
	if _flag_count > 0:
		roster = roster.slice(0, _flag_count)
	var center: Vector2 = _arena.get_center_global()
	var count: int = roster.size()
	for i in range(count):
		var entry = roster[i]
		var flag: Flag = FLAG_SCENE.instantiate()
		add_child(flag)
		flag.setup(entry.code, entry.name, null)
		var offset: Vector2 = _sunflower_point(i, count, 40.0, RoyaleSettings.ring_radius - 60.0)
		flag.global_position = center + offset
		var launch_dir: float = randf() * TAU
		flag.launch(Vector2(cos(launch_dir), sin(launch_dir)) * RoyaleSettings.relaunch_speed_base)
	GameManager.start_game()

func _on_tunneling_detected(_code: String) -> void:
	_tunneling_warnings += 1

func _on_flag_qualified(_code: String, _name: String, _rank: int, _total: int) -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _run_start_ticks_msec) / 1000.0
	_run_escape_times.append(elapsed)

func _on_qualifying_ended(total_qualified: int) -> void:
	_all_run_reports.append({
		"total_qualified": total_qualified,
		"escape_times": _run_escape_times.duplicate(),
	})
	_current_run += 1
	if _current_run >= _target_runs:
		_report()
	else:
		_start_run()

func _report() -> void:
	print("")
	print("run  qualified  escapes/min (mean)  longest gap (s)  shortest gap (s)")
	print("----------------------------------------------------------------------")
	var grand_total_qualified: int = 0
	for i in range(_all_run_reports.size()):
		var report: Dictionary = _all_run_reports[i]
		var times: Array = report.escape_times
		var per_min: float = float(times.size()) / (RoyaleSettings.qualifying_seconds / 60.0)
		var longest_gap: float = 0.0
		var shortest_gap: float = INF
		for j in range(1, times.size()):
			var gap: float = times[j] - times[j - 1]
			longest_gap = maxf(longest_gap, gap)
			shortest_gap = minf(shortest_gap, gap)
		if times.size() < 2:
			shortest_gap = 0.0
		print("%3d  %9d  %18.2f  %15.1f  %17.1f" % [
			i + 1, report.total_qualified, per_min, longest_gap,
			0.0 if shortest_gap == INF else shortest_gap])
		grand_total_qualified += report.total_qualified
	print("----------------------------------------------------------------------")
	if not _all_run_reports.is_empty():
		print("mean qualifiers per run: %.1f" % (float(grand_total_qualified) / float(_all_run_reports.size())))
	print("tunneling warnings     : %d" % _tunneling_warnings)
	print("")
	get_tree().quit()
