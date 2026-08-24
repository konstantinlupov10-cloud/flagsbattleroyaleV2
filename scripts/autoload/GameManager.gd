extends Node
## Tournament state machine and pure signal source: it never touches scene
## nodes directly. Mirrors the sibling projects' GameManager discipline --
## Timer-driven phase transitions, notify_*() hooks called from a physics
## script (EscapeDetector), signals are the only way anything else finds out
## what happened.

enum TournamentState { QUALIFYING, LAST_FLAG_STANDING, CHAMPION_REVEAL, INTERMISSION }

signal tournament_started(total_flags: int)
signal qualifying_started(duration_seconds: float)
signal flag_qualified(code: String, country_name: String, qualify_rank: int, total_qualified: int)
signal qualifying_ended(total_qualified: int)
signal last_flag_standing_started(finalists: Array)
signal flag_eliminated(code: String, country_name: String, remaining: int, elimination_rank: int)
signal round_reset(remaining_codes: Array, round_multiplier: float)
signal champion_crowned(code: String, country_name: String, podium: Array)
signal intermission_started(seconds: float)
signal tournament_reset()

## Grace window after the qualifying timer expires, letting an escape that's
## already underway resolve before qualifying formally closes -- rather than
## GameManager needing visibility into a Flag's departure-tween state (which
## would break the "GameManager never touches scene nodes" discipline), it's
## just a short fixed window.
const QUALIFYING_CLOSE_GRACE_SECONDS := 1.5

var state: TournamentState = TournamentState.QUALIFYING

var _qualifying_timer: Timer
var _qualifying_grace_timer: Timer
var _intermission_timer: Timer

var _remaining_in_arena: Array = []  # codes still bouncing, qualifying phase
var _finalist_codes: Array = []      # codes still alive in the final
var _lfs_multiplier: float = 1.0

func _ready() -> void:
	_qualifying_timer = Timer.new()
	_qualifying_timer.one_shot = true
	_qualifying_timer.timeout.connect(_on_qualifying_timer_timeout)
	add_child(_qualifying_timer)

	_qualifying_grace_timer = Timer.new()
	_qualifying_grace_timer.one_shot = true
	_qualifying_grace_timer.timeout.connect(_end_qualifying)
	add_child(_qualifying_grace_timer)

	_intermission_timer = Timer.new()
	_intermission_timer.one_shot = true
	_intermission_timer.timeout.connect(_on_intermission_timeout)
	add_child(_intermission_timer)

## Called explicitly by Main, not auto-run in _ready() -- so headless tools
## sharing these autoloads (e.g. the escape-rate histogram) don't accidentally
## kick off a full tournament loop just by being run.
func start_game() -> void:
	_start_qualifying()

func current_speed_multiplier() -> float:
	return _lfs_multiplier if state == TournamentState.LAST_FLAG_STANDING else 1.0

func get_qualifying_time_left() -> float:
	return 0.0 if _qualifying_timer.is_stopped() else _qualifying_timer.time_left

func get_intermission_time_left() -> float:
	return 0.0 if _intermission_timer.is_stopped() else _intermission_timer.time_left

## Single physics->GameManager bridge. The phase alone decides whether an
## escape means qualifying or elimination -- Flag.gd and the escape detector
## never need to know which phase is active.
func notify_flag_escaped(code: String, country_name: String) -> void:
	match state:
		TournamentState.QUALIFYING:
			_handle_qualify(code, country_name)
		TournamentState.LAST_FLAG_STANDING:
			_handle_eliminate(code, country_name)

func _start_qualifying() -> void:
	state = TournamentState.QUALIFYING
	var roster: Array = FlagDatabase.get_shuffled_roster()
	TournamentLog.reset(roster)
	_remaining_in_arena = roster.map(func(entry): return entry.code)
	_lfs_multiplier = 1.0
	tournament_started.emit(roster.size())
	qualifying_started.emit(RoyaleSettings.qualifying_seconds)
	_qualifying_timer.start(RoyaleSettings.qualifying_seconds)

func _handle_qualify(code: String, country_name: String) -> void:
	_remaining_in_arena.erase(code)
	var rank: int = TournamentLog.record_qualifier(code, country_name)
	flag_qualified.emit(code, country_name, rank, TournamentLog.qualifier_count())

func _on_qualifying_timer_timeout() -> void:
	_qualifying_grace_timer.start(QUALIFYING_CLOSE_GRACE_SECONDS)

func _end_qualifying() -> void:
	if state != TournamentState.QUALIFYING:
		return
	var qualifiers: Array = TournamentLog.get_qualifiers_ranked()
	qualifying_ended.emit(qualifiers.size())
	if qualifiers.is_empty():
		# Defensive fallback -- should never trigger once escape-rate tuning
		# (tools/EscapeRateHistogram.gd) confirms a sane trickle rate.
		push_warning("GameManager: zero qualifiers, restarting qualifying")
		_start_qualifying()
		return
	_start_last_flag_standing(qualifiers)

func _start_last_flag_standing(qualifiers: Array) -> void:
	state = TournamentState.LAST_FLAG_STANDING
	_finalist_codes = qualifiers.map(func(entry): return entry.code)
	_lfs_multiplier = 1.0
	last_flag_standing_started.emit(qualifiers)

func _handle_eliminate(code: String, country_name: String) -> void:
	_finalist_codes.erase(code)
	var rank: int = TournamentLog.record_elimination(code, country_name)
	flag_eliminated.emit(code, country_name, _finalist_codes.size(), rank)
	if _finalist_codes.size() <= 1:
		_crown_champion()
		return
	_lfs_multiplier = maxf(
		_lfs_multiplier * (1.0 - RoyaleSettings.lfs_speed_multiplier_decay_per_elimination),
		RoyaleSettings.lfs_speed_multiplier_floor
	)
	round_reset.emit(_finalist_codes.duplicate(), _lfs_multiplier)

func _crown_champion() -> void:
	state = TournamentState.CHAMPION_REVEAL
	var champion_code: String = _finalist_codes[0] if not _finalist_codes.is_empty() else ""
	var champion_name: String = _lookup_qualifier_name(champion_code)
	TournamentLog.set_champion(champion_code, champion_name)
	var podium: Array = TournamentLog.get_podium()
	champion_crowned.emit(champion_code, champion_name, podium)
	_start_intermission()

func _lookup_qualifier_name(code: String) -> String:
	for entry in TournamentLog.get_qualifiers_ranked():
		if entry.code == code:
			return entry.name
	return code

func _start_intermission() -> void:
	state = TournamentState.INTERMISSION
	intermission_started.emit(RoyaleSettings.intermission_seconds)
	_intermission_timer.start(RoyaleSettings.intermission_seconds)

func _on_intermission_timeout() -> void:
	tournament_reset.emit()
	_start_qualifying()
