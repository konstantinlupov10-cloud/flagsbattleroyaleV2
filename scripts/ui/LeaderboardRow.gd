extends PanelContainer
class_name LeaderboardRow
## A single "QUALIFIED FOR FINAL" entry, styled as its own rounded card --
## ported from flagsplinko's LeaderboardRow.gd, dropped the points/score
## column (qualify order IS the rank here, there's no separate stat to show)
## and the circular-crop shader on the flag icon (flags stay rectangular
## throughout this project, no flag_disc.gdshader anywhere).
##
## Every row uses the same uniform styling regardless of rank -- no gold/
## silver/bronze medal tint for #1-3, per direct request. Qualification order
## isn't a placement here (that's what the podium/champion reveal is for at
## the end of the final); it's simply the order flags happened to escape the
## qualifying arena in, so ranks 1-3 don't deserve special treatment relative
## to #4, #50, or #150.

@onready var _rank_label: Label = $HBox/RankLabel
@onready var _flag_icon: TextureRect = $HBox/FlagIcon
@onready var _name_label: Label = $HBox/NameLabel

func update(rank: int, code: String, country_name: String) -> void:
	_rank_label.text = "#%d" % rank
	_flag_icon.texture = FlagDatabase.get_texture(code)
	_name_label.text = country_name
	_rank_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.PANEL_EDGE, 0.4)
	box.border_width_left = 4
	box.border_color = Palette.CYAN
	box.set_corner_radius_all(12)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", box)
