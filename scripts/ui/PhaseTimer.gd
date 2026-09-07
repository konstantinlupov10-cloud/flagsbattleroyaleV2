extends CanvasLayer
class_name PhaseTimer
## Always-visible countdown sitting just under the leaderboard panel, styled
## as a neon glow so it stands out (confirmed via direct request) rather
## than the small subtle white text it started as. Shows how much longer
## qualifying has before it closes, or how long until the next tournament
## during intermission. Reads GameManager.state/get_*_time_left() directly
## every frame rather than listening for a signal per tick (there isn't
## one) -- same "passive listener, no state of its own" discipline as the
## rest of this project's UI, just polling instead of subscribing since a
## countdown is inherently a per-frame value, not a discrete event.
##
## The glow itself is the same manual-layered-text technique as GlowRing.gd
## uses for the arena ring -- see that file's doc comment for why: Godot's
## Glow post-process was already tried and abandoned there for producing
## uneven, blobby results on thin/small shapes, and text glyphs are exactly
## that. Four stacked Label copies at the same position, widening
## font_outline_size and dropping alpha outward from a crisp bright core,
## approximates the same soft halo with zero blur/post-process step.
##
## Added specifically because qualifying_seconds defaults to a real 30
## minutes with otherwise zero on-screen indication anything is progressing
## at all -- without this, a genuinely-still-qualifying game was
## indistinguishable from a stuck one during manual testing, and looked like
## it was the cause of "ejected flags never appear" / "no new round starts"
## reports that were actually just qualifying still legitimately in
## progress (confirmed via a full headless run of the state machine).
##
## Shows a static "FINAL ROUND" label (no countdown -- the final has no timer
## at all by design, runs to exactly one survivor) during LAST_FLAG_STANDING.
## Hidden entirely during CHAMPION_REVEAL -- the reveal is its own discrete
## beat, not something a phase label applies to.

@onready var _root: Control = $Root
@onready var _layers: Array[Label] = [$Root/Glow3, $Root/Glow2, $Root/Glow1, $Root/Core]

func _process(_delta: float) -> void:
	match GameManager.state:
		GameManager.TournamentState.QUALIFYING:
			_show("QUALIFYING %s" % _format(GameManager.get_qualifying_time_left()))
		GameManager.TournamentState.INTERMISSION:
			_show("NEXT TOURNAMENT %s" % _format(GameManager.get_intermission_time_left()))
		GameManager.TournamentState.LAST_FLAG_STANDING:
			_show("FINAL ROUND")
		_:
			_root.visible = false

func _show(text: String) -> void:
	_root.visible = true
	for layer in _layers:
		layer.text = text

func _format(seconds: float) -> String:
	var total: int = maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [total / 60, total % 60]
