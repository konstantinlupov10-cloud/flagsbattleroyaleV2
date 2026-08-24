extends CanvasLayer
class_name PhaseTimer
## Small always-visible countdown sitting just under the leaderboard panel --
## subtle white semi-transparent text, not meant to compete visually with the
## panel above it. Shows how much longer qualifying has before it closes, or
## how long until the next tournament during intermission. Reads
## GameManager.state/get_*_time_left()
## directly every frame rather than listening for a signal per tick (there
## isn't one) -- same "passive listener, no state of its own" discipline as
## the rest of this project's UI, just polling instead of subscribing since
## a countdown is inherently a per-frame value, not a discrete event.
##
## Added specifically because qualifying_seconds defaults to a real 30
## minutes with otherwise zero on-screen indication anything is progressing
## at all -- without this, a genuinely-still-qualifying game was
## indistinguishable from a stuck one during manual testing, and looked like
## it was the cause of "ejected flags never appear" / "no new round starts"
## reports that were actually just qualifying still legitimately in
## progress (confirmed via a full headless run of the state machine).
##
## Hidden entirely during LAST_FLAG_STANDING/CHAMPION_REVEAL -- the final has
## no timer at all by design (runs to exactly one survivor), and the reveal
## is its own discrete beat, not something a countdown applies to.

@onready var _label: Label = $Label

func _process(_delta: float) -> void:
	match GameManager.state:
		GameManager.TournamentState.QUALIFYING:
			_label.visible = true
			_label.text = "QUALIFYING %s" % _format(GameManager.get_qualifying_time_left())
		GameManager.TournamentState.INTERMISSION:
			_label.visible = true
			_label.text = "NEXT TOURNAMENT %s" % _format(GameManager.get_intermission_time_left())
		_:
			_label.visible = false

func _format(seconds: float) -> String:
	var total: int = maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [total / 60, total % 60]
