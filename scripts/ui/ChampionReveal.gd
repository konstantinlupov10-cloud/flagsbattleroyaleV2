extends CanvasLayer
class_name ChampionReveal
## Full-screen celebration card, reused for two distinct moments (confirmed
## via direct request):
##  - "ROUND WINNER" -- EVERY qualifying round's sole survivor, not just the
##    tournament champion. GameManager._record_round_winner() fires
##    flag_qualified the instant a round narrows to exactly one un-ejected
##    flag -- that flag didn't need to escape itself, staying in as the only
##    one left is sufficient.
##  - "TOURNAMENT WINNER" -- the actual tournament winner at the end of Last
##    Flag Standing, same trigger condition (exactly one flag left) applied
##    to the whole final instead of a single qualifying round, with a longer
##    display duration befitting the bigger moment.

## Matches GameManager.ROUND_ADVANCE_DELAY_SECONDS -- the reveal's own
## display duration and the actual delay before the next round's flags
## spawn are two independent timers by construction (this one is UI-only,
## that one is game-state), so keeping them numerically in sync is what
## prevents the reveal disappearing early/lingering after gameplay has
## already moved on underneath it.
const ROUND_WINNER_DISPLAY_SECONDS := 3.0
## No fixed display duration for the champion case -- unlike a round winner
## (which just needs to clear out of the way before the next round's flags
## spawn underneath it), the tournament winner reveal is meant to stay up
## for the ENTIRE intermission, only clearing on tournament_started (confirmed
## via direct request: it was disappearing mid-intermission before this).

@onready var _root: Control = $Root
@onready var _rays: Control = $Root/Rays
@onready var _title_label: Label = $Root/Card/TitleLabel
@onready var _flag_icon: TextureRect = $Root/Card/FlagPanel/FlagIcon
@onready var _name_label: Label = $Root/Card/NameLabel
@onready var _next_tournament_label: Label = $Root/Card/NextTournamentLabel

var _hide_tween: Tween
## True only for the champion/tournament-winner reveal -- gates both the
## persistent (no auto-hide) behavior and the live "next tournament in..."
## countdown, neither of which apply to a plain round winner.
var _is_champion_reveal: bool = false

func _ready() -> void:
	_root.visible = false
	GameManager.flag_qualified.connect(_on_flag_qualified)
	GameManager.champion_crowned.connect(_on_champion_crowned)
	GameManager.tournament_started.connect(_on_tournament_started)

func _on_flag_qualified(code: String, country_name: String, _rank: int, _total: int) -> void:
	_show_reveal("ROUND WINNER", code, country_name, false)

func _on_champion_crowned(code: String, country_name: String, _podium: Array) -> void:
	_show_reveal("TOURNAMENT WINNER", code, country_name, true)

func _show_reveal(title: String, code: String, country_name: String, is_champion: bool) -> void:
	_title_label.text = title
	_flag_icon.texture = FlagDatabase.get_texture(code)
	_name_label.text = country_name
	_is_champion_reveal = is_champion
	_next_tournament_label.visible = is_champion
	_root.visible = true
	_root.modulate.a = 0.0
	_root.scale = Vector2(0.7, 0.7)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_root, "modulate:a", 1.0, 0.3)
	tween.tween_property(_root, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# A qualifying phase fast enough to produce back-to-back round winners
	# would otherwise queue up hide callbacks behind a stale display timer --
	# each new reveal restarts its own display clock instead.
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	if is_champion:
		return  # stays up until _on_tournament_started hides it
	_hide_tween = create_tween()
	_hide_tween.tween_interval(ROUND_WINNER_DISPLAY_SECONDS)
	_hide_tween.tween_callback(func(): _root.visible = false)

func _on_tournament_started(_total_flags: int) -> void:
	_root.visible = false

func _process(delta: float) -> void:
	if not _root.visible:
		return
	_rays.rotation += delta * 0.15
	if _is_champion_reveal and GameManager.state == GameManager.TournamentState.INTERMISSION:
		var seconds_left: int = maxi(0, int(ceil(GameManager.get_intermission_time_left())))
		_next_tournament_label.text = "Next tournament in %d seconds" % seconds_left
