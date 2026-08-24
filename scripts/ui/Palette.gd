extends RefCounted
class_name Palette
## Single source of truth for the UI look -- ported from flagsplinko's
## Palette.gd, trimmed to just what this project's leaderboard/strip need
## (no payout/slot ramp, this isn't Plinko).

const BG := Color("#0B1220")
const PANEL := Color("#131C42")
const PANEL_EDGE := Color("#233066")
const BLUE := Color("#3B82F6")
const CYAN := Color("#22D3EE")
const GOLD := Color("#FFC94A")
const TEXT := Color("#E8F0FF")
const TEXT_DIM := Color("#8FA3CC")

static func rank_color(rank: int) -> Color:
	match rank:
		1: return GOLD
		2: return Color("#CBD5E1")
		3: return Color("#D08A4E")
		_: return TEXT_DIM
