extends Node
## Tournament state machine and pure signal source: it never touches scene
## nodes directly. Mirrors the sibling projects' GameManager discipline --
## Timer-driven phase transitions, notify_*() hooks called from a physics
## script (EscapeDetector), signals are the only way anything else finds out
## what happened.

enum TournamentState { QUALIFYING, LAST_FLAG_STANDING, CHAMPION_REVEAL, INTERMISSION }

signal tournament_started(total_flags: int)
signal qualifying_started(duration_seconds: float)
## A new qualifying round's pool (everyone except flags that have already
## permanently qualified in an earlier round) -- NOT fired for the very
## first round, which rides tournament_started instead (Main.gd's existing
## spawn path already handles that one).
signal qualifying_round_reset(pool_entries: Array)
## A flag was ejected from the CURRENT qualifying round without winning it --
## it rejoins the pool for the next round, so this is explicitly NOT a
## qualification. Distinguishing this from flag_qualified is what lets
## Leaderboard.gd/EjectedStrip.gd tell "still in contention" apart from
## "permanently secured a spot".
signal flag_round_ejected(code: String, country_name: String)
## Fired once per qualifying round, for whichever flag is left un-ejected --
## that flag doesn't need to have escaped itself (see _record_round_winner()).
signal flag_qualified(code: String, country_name: String, qualify_rank: int, total_qualified: int)
signal qualifying_ended(total_qualified: int)
signal last_flag_standing_started(finalists: Array)
signal flag_eliminated(code: String, country_name: String, remaining: int, elimination_rank: int)
signal round_reset(remaining_codes: Array, round_multiplier: float)
signal champion_crowned(code: String, country_name: String, podium: Array)
signal intermission_started(seconds: float)
signal tournament_reset()

var state: TournamentState = TournamentState.QUALIFYING

var _qualifying_timer: Timer
var _intermission_timer: Timer
var _round_advance_timer: Timer

## How long a round's ROUND WINNER reveal gets to actually be seen before
## the next round's flags start spawning/bouncing underneath it. Advancing
## immediately (the original behavior) meant the reveal card and the next
## round's arena activity began in the exact same instant -- confirmed via
## direct feedback that they visibly overlapped.
const ROUND_ADVANCE_DELAY_SECONDS := 3.0

## Each qualifying round is its own miniature last-flag-standing contest:
## every code in _round_pool bounces in the arena until only one remains
## un-ejected -- that survivor permanently qualifies (recorded in
## TournamentLog, never re-enters the pool), while every other flag ejected
## THIS round goes right back into the pool for the next round. This repeats
## for as many rounds as fit inside qualifying_seconds. Confirmed design --
## replaces the earlier "any escape individually qualifies, arena never
## resets" model, which didn't match the original "whatever flag is last
## qualifies" framing at all.
var _round_pool: Array = []
var _code_to_name: Dictionary = {}
## Set once the qualifying timer fires. The CURRENT round is always allowed
## to run to completion rather than being cut off mid-round (confirmed
## choice) -- this flag just means "don't start ANOTHER round after this
## one resolves; end qualifying instead."
var _qualifying_closing: bool = false

var _finalist_codes: Array = []
var _lfs_multiplier: float = 1.0

func _ready() -> void:
	_qualifying_timer = Timer.new()
	_qualifying_timer.one_shot = true
	_qualifying_timer.timeout.connect(_on_qualifying_timer_timeout)
	add_child(_qualifying_timer)

	_intermission_timer = Timer.new()
	_intermission_timer.one_shot = true
	_intermission_timer.timeout.connect(_on_intermission_timeout)
	add_child(_intermission_timer)

	_round_advance_timer = Timer.new()
	_round_advance_timer.one_shot = true
	_round_advance_timer.timeout.connect(_on_round_advance_timeout)
	add_child(_round_advance_timer)

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
## escape means "ejected from this qualifying round" or "eliminated from the
## final" -- Flag.gd and the escape detector never need to know which phase
## is active.
func notify_flag_escaped(code: String, country_name: String) -> void:
	match state:
		TournamentState.QUALIFYING:
			_handle_round_ejection(code, country_name)
		TournamentState.LAST_FLAG_STANDING:
			_handle_eliminate(code, country_name)

func _start_qualifying() -> void:
	state = TournamentState.QUALIFYING
	var roster: Array = FlagDatabase.get_shuffled_roster()
	TournamentLog.reset(roster)
	_code_to_name.clear()
	for entry in roster:
		_code_to_name[entry.code] = entry.name
	_qualifying_closing = false
	_lfs_multiplier = 1.0
	_round_pool = _code_to_name.keys()
	tournament_started.emit(roster.size())
	qualifying_started.emit(RoyaleSettings.qualifying_seconds)
	_qualifying_timer.start(RoyaleSettings.qualifying_seconds)
	# Degenerate: an empty/near-empty roster (only ever happens with a tiny
	# headless-test override, never the real 250) resolves immediately
	# rather than waiting on a round nobody can eject anybody from.
	if _round_pool.size() == 1:
		_record_round_winner(_round_pool[0])

## A flag escaped the arena during a qualifying round without being the last
## one left -- ejected from this round, but not disqualified from the
## tournament: it rejoins the pool the next round starts with.
func _handle_round_ejection(code: String, country_name: String) -> void:
	_round_pool.erase(code)
	if _round_pool.size() > 1:
		flag_round_ejected.emit(code, country_name)
		return
	# Exactly one flag left un-ejected: that's the round's winner. It didn't
	# need to escape itself -- staying in as the only one left is sufficient
	# (confirmed via direct request) -- Main.gd is responsible for sending
	# that flag on its way visually, since nothing here calls depart() on it.
	_record_round_winner(_round_pool[0])

func _record_round_winner(winner_code: String) -> void:
	var winner_name: String = _code_to_name.get(winner_code, winner_code)
	var rank: int = TournamentLog.record_qualifier(winner_code, winner_name)
	flag_qualified.emit(winner_code, winner_name, rank, TournamentLog.qualifier_count())
	_round_advance_timer.start(ROUND_ADVANCE_DELAY_SECONDS)

func _on_round_advance_timeout() -> void:
	if _qualifying_closing:
		_end_qualifying()
		return
	_start_next_qualifying_round()

func _start_next_qualifying_round() -> void:
	var qualified: Dictionary = {}
	for entry in TournamentLog.get_qualifiers_ranked():
		qualified[entry.code] = true
	var pool: Array = []
	for code in _code_to_name.keys():
		if not qualified.has(code):
			pool.append(code)
	_round_pool = pool
	# Everyone else has already individually won a round in an earlier pass
	# through the roster -- nothing left to fight over.
	if _round_pool.size() <= 1:
		if _round_pool.size() == 1:
			_record_round_winner(_round_pool[0])
		return
	var pool_entries: Array = []
	for code in _round_pool:
		pool_entries.append({"code": code, "name": _code_to_name[code]})
	qualifying_round_reset.emit(pool_entries)

func _on_qualifying_timer_timeout() -> void:
	# Let whatever round is currently in progress run to completion --
	# confirmed choice over cutting it off mid-round, which would leave an
	# undefined "what happens to the flags still bouncing" state. This just
	# stops another round from starting once the current one resolves;
	# _record_round_winner() checks it at exactly that moment.
	_qualifying_closing = true

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
	# A single qualifier needs no fight at all -- crown it immediately,
	# matching the same "last one left doesn't need to escape" principle
	# applied everywhere else in this state machine. Without this, a lone
	# finalist just bounces alone until IT eventually wanders through the
	# gap on its own, at which point _handle_eliminate() treats that as an
	# elimination and empties _finalist_codes entirely -- confirmed via a
	# headless test producing a "champion_crowned" with a blank code/name.
	# A short qualifying window genuinely can close after just one round
	# now (each round can take a while to resolve with the full roster), so
	# this isn't a rare edge case to shrug off.
	if _finalist_codes.size() <= 1:
		_crown_champion()

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
