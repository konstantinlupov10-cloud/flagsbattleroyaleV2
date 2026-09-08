extends CanvasLayer
class_name StartScreen
## Shown once at launch, blocking the tournament from starting until the
## player clicks START -- previously GameManager.start_game() fired
## unconditionally from Main._ready(), so the very first tournament began
## before the player had seen anything, mid-load, with 250 flags already
## bouncing by the time the window was visible. Removes itself for good
## after the first click; every subsequent tournament (intermission -> next
## tournament) still loops on its own with no further gating, exactly as it
## did before this screen existed -- this only covers the very first start.
##
## Styled from Palette.gd directly rather than hardcoding matching hex/float
## colors into the .tscn like the rest of this project's UI does -- that
## duplication is exactly what made the recent blue->purple retheme require
## hunting down colors across half a dozen scene files. Doing it in script
## here means this one node never needs a matching manual edit again.
##
## Also preloads every flag texture while this screen sits idle waiting for
## a click -- confirmed via direct measurement that loading/rasterizing all
## ~207 SVGs cold takes ~650ms, and that cost was landing right at
## _spawn_flags() the moment the first round actually starts (a genuine
## ~700ms-2s main-thread stall measured directly on that exact frame).
## Godot's physics then has to catch up from that stall over the following
## real seconds (bounded by max_physics_steps_per_frame), which is what was
## surfacing as "collision sounds sound queued, then trickle out over a
## second or two" -- not an audio bug, a cold-cache stall at the worst
## possible moment. Warming the cache here, while the player is just looking
## at a static card with nothing moving, makes the same ~650ms cost
## genuinely invisible instead of landing mid-collision-chaos.

signal start_pressed

@onready var _root: Control = $Root
@onready var _card: PanelContainer = $Root/Card
@onready var _start_button: Button = $Root/Card/VBox/StartButton

func _ready() -> void:
	var dim: ColorRect = $Root/Dim
	dim.color = Palette.BG

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Palette.PANEL
	card_style.set_border_width_all(5)
	card_style.border_color = Palette.GOLD
	card_style.set_corner_radius_all(18)
	card_style.content_margin_left = 40.0
	card_style.content_margin_right = 40.0
	card_style.content_margin_top = 40.0
	card_style.content_margin_bottom = 40.0
	_card.add_theme_stylebox_override("panel", card_style)

	var button_normal := StyleBoxFlat.new()
	button_normal.bg_color = Palette.PANEL_EDGE
	button_normal.set_corner_radius_all(12)
	var button_hover := StyleBoxFlat.new()
	button_hover.bg_color = Palette.BLUE
	button_hover.set_corner_radius_all(12)
	_start_button.add_theme_stylebox_override("normal", button_normal)
	_start_button.add_theme_stylebox_override("hover", button_hover)
	_start_button.add_theme_stylebox_override("pressed", button_hover)
	_start_button.add_theme_color_override("font_color", Palette.TEXT)
	_start_button.add_theme_color_override("font_hover_color", Palette.TEXT)
	_start_button.add_theme_color_override("font_pressed_color", Palette.TEXT)

	$Root/Card/VBox/TitleLabel.add_theme_color_override("font_color", Palette.GOLD)
	$Root/Card/VBox/SubtitleLabel.add_theme_color_override("font_color", Palette.TEXT_DIM)

	_start_button.pressed.connect(_on_start_pressed)

	# Let this screen actually render/present once first, so the loading
	# work below has zero chance of delaying the player's first look at it.
	await get_tree().process_frame
	await get_tree().process_frame
	for entry in FlagDatabase.get_shuffled_roster():
		FlagDatabase.get_texture(entry.code)

func _on_start_pressed() -> void:
	# Guards against a double-click (or an accidental second signal
	# connection) firing GameManager.start_game() twice, which would try to
	# start a tournament that's already mid-flight.
	_start_button.disabled = true
	start_pressed.emit()
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
