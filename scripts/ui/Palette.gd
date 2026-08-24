extends RefCounted
class_name Palette
## Single source of truth for the UI look -- ported from flagsplinko's
## Palette.gd, trimmed to just what this project's leaderboard/strip need
## (no payout/slot ramp, this isn't Plinko).

const BG := Color("#12091F")
const PANEL := Color("#1E1142")
const PANEL_EDGE := Color("#3B2166")
const BLUE := Color("#8B5CF6")
const CYAN := Color("#E879F9")
const GOLD := Color("#FFC94A")
const TEXT := Color("#F0E8FF")
const TEXT_DIM := Color("#A896CC")

static func rank_color(rank: int) -> Color:
	match rank:
		1: return GOLD
		2: return Color("#D8CCE6")
		3: return Color("#D08A4E")
		_: return TEXT_DIM
