extends Node
## Music playback + rate-limited flag-collision SFX. Deliberately not the
## full sibling-project AudioManager pattern (elimination/round/champion
## stingers) yet -- this only wires what's actually been requested so far:
## a looping background track and a "clack" on every flag-flag/flag-wall
## collision. Extend the same way when the rest gets requested.

## RigidBody2D.body_entered fires once per body per NEW contact, but a dense
## 250-flag arena produces far more of those per second than is pleasant to
## actually hear layered on top of each other -- confirmed by ear, not
## guessed at. Capping playback to roughly this many per second keeps the
## clack readable as "lots of collisions happening" rather than turning into
## a wall of noise; not tied to any particular collision, just whichever one
## happens to be the first to ask after the cooldown clears.
const MAX_COLLISION_SFX_PER_SECOND := 7.0
const MIN_COLLISION_SFX_INTERVAL := 1.0 / MAX_COLLISION_SFX_PER_SECOND
const COLLISION_SFX_POOL_SIZE := 4

## Guards against a completely different failure mode than the rate cap
## above: a main-thread stall (confirmed via direct measurement -- e.g. the
## very first flag spawn loading ~207 SVG textures cold took 700ms-2s)
## makes Godot's physics fall behind real wall-clock time, then catch up
## over the following real seconds (bounded by
## physics/common/max_physics_steps_per_frame). Every body_entered signal
## fired during that catch-up is a perfectly real collision, so the rate
## cap alone still lets some through -- they just land audibly LATE,
## trickling out over the next second or two even once the screen looks
## calm again (confirmed via direct report).
##
## FIRST attempt at this compared Engine.get_physics_frames() against a
## fixed startup baseline -- broke collision audio entirely (confirmed via
## direct report). The bug: once physics falls behind real time even once,
## it stays at that same fixed number of ticks behind forever after (it
## proceeds at normal speed from wherever it fell behind, it doesn't run
## extra-fast to fully re-close the gap against the ORIGINAL baseline) --
## so that "lag" reading only ever goes up, never resets, and permanently
## exceeded the threshold after the very first stall.
##
## This version tracks whether a stall happened RECENTLY instead of a
## cumulative-since-startup drift: _process() watches for an abnormally
## long rendered frame and opens a short suppression window after one,
## self-clearing on its own once the window passes with no further stalls --
## nothing to permanently drift.
const STALL_FRAME_THRESHOLD_SEC := 0.1
const STALL_SUPPRESS_WINDOW_SEC := 1.0

## -60% perceived volume, expressed as the dB drop that actually produces a
## 0.4x amplitude multiplier (20*log10(0.4)) -- dB is logarithmic, so a flat
## "-60" here would be a far more drastic cut than "60% quieter" implies.
const MUSIC_VOLUME_DB := -7.96

## A blunt "punch" impact, not the brighter 8-bit "hit" blip used originally --
## confirmed via direct feedback that the first attempt didn't read as blunt
## enough. From Kenney's CC0 Impact Sounds pack (https://kenney.nl/assets/impact-sounds),
## purpose-made foley impact hits rather than chiptune UI blips.
const SFX_COLLISION_THUD: AudioStream = preload("res://assets/audio/sfx/collision_thud.ogg")
const MUSIC_BACKGROUND: AudioStreamWAV = preload("res://assets/audio/music/background_loop.wav")

var _music_player: AudioStreamPlayer
## AudioStreamPlayer2D, not the flat AudioStreamPlayer used originally --
## confirmed via direct feedback that the non-positional version made every
## clack sound identical and disconnected from wherever the actual collision
## was happening on screen. Positioning each play at the real contact point
## (see Flag.gd's _on_body_entered) ties the sound to something the player
## can actually see happen, panning left/right with it.
var _collision_sfx_pool: Array[AudioStreamPlayer2D] = []
var _collision_sfx_pool_index: int = 0
var _last_collision_sfx_time_sec: float = -INF

## Real-time timestamp (Time.get_ticks_msec()-based) until which collision
## sounds are suppressed -- set a STALL_SUPPRESS_WINDOW_SEC into the future
## every time _process() notices an abnormally long frame, so it keeps
## sliding forward through a whole run of stuttery frames and only actually
## lapses once things have been smooth for a full window.
var _collision_sound_suppressed_until: float = -INF

func _process(delta: float) -> void:
	if delta > STALL_FRAME_THRESHOLD_SEC:
		_collision_sound_suppressed_until = (Time.get_ticks_msec() / 1000.0) + STALL_SUPPRESS_WINDOW_SEC

func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = MUSIC_BACKGROUND
	_music_player.volume_db = MUSIC_VOLUME_DB
	# Restarting on `finished` rather than relying on AudioStreamWAV's
	# sample-accurate loop_begin/loop_end fields -- those need to be hand-set
	# in exact PCM sample-frame counts to loop the whole file correctly, easy
	# to get subtly wrong without ever throwing an error. A manual restart
	# has a few milliseconds of scheduling gap between one playback ending
	# and the next starting, imperceptible for a background loop, and is
	# correct regardless of the source file's format/encoding.
	_music_player.finished.connect(_music_player.play)
	add_child(_music_player)
	_music_player.play()

	for i in range(COLLISION_SFX_POOL_SIZE):
		var p := AudioStreamPlayer2D.new()
		add_child(p)
		_collision_sfx_pool.append(p)

## Called by any Flag on every body_entered (flag-flag or flag-wall alike --
## RigidBody2D doesn't distinguish, and neither does the sound), passing the
## world-space point the collision happened at so playback can be positioned
## there. Silently drops the request -- rather than queueing it -- for
## either of two different reasons: the ordinary rate cap (a missed clack in
## a split second already full of them is inaudible anyway), or a stall
## having happened recently enough that this collision is likely part of
## the backlog catching up rather than something happening right now (a
## missed clack for a moment that's already passed is worse than inaudible,
## it's actively confusing -- see the suppression-window comment above).
func notify_flag_collision(world_position: Vector2) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _collision_sound_suppressed_until:
		return
	if now - _last_collision_sfx_time_sec < MIN_COLLISION_SFX_INTERVAL:
		return
	_last_collision_sfx_time_sec = now
	var player: AudioStreamPlayer2D = _collision_sfx_pool[_collision_sfx_pool_index]
	_collision_sfx_pool_index = (_collision_sfx_pool_index + 1) % _collision_sfx_pool.size()
	player.global_position = world_position
	player.stream = SFX_COLLISION_THUD
	player.play()
