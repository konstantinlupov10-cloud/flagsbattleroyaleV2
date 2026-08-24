extends Node
## Central tunables for arena geometry, the rotating gap, pacing, and UI.
## Autoload singleton so any script can read `RoyaleSettings.xxx` directly.
## Mirrors the PlinkoSettings/RoundSettings pattern from the sibling projects.

# ---------------------------------------------------------------------------
# Arena geometry
# ---------------------------------------------------------------------------

## Center of the circular arena on the 1080x1920 portrait canvas. Leaderboard
## sits above, the roster strip sits below.
@export var board_center_x: float = 540.0
@export var board_center_y: float = 980.0
@export var ring_radius: float = 480.0

## Thickness for each boundary wall segment. A true zero-thickness
## SegmentShape2D was tried first and produced degenerate/NaN contact
## normals under CCD_MODE_CAST_SHAPE (see GapRing.gd); a thin 10px rectangle
## fixed that but still let a meaningful fraction of contacts tunnel through
## under full-roster-scale simultaneous multi-body pileup pressure at the
## wall (a known class of physics-engine limitation under dense contact
## loads, not something margin/tolerance tuning alone fully closes). A much
## thicker wall gives both discrete detection and the CCD sweep far more
## margin to catch a fast body before it fully crosses.
@export var wall_thickness_px: float = 40.0

## The rotating boundary wall is built from this many equal segments, with
## gap_segment_count of them left disabled to form the escaping gap. Kept as
## two separate tunables (not just an angle) so the physical segment geometry
## and the "feel" knob stay the same number -- see GapRing.gd.
@export var ring_segment_count: int = 72
## 5 segments * 5deg = 25deg opening -- widened from an initial 15deg after
## full-scale testing showed only ~8 qualifiers per 30-min window, too sparse
## for good stream pacing. Tune against tools/EscapeRateHistogram.gd.
@export var gap_segment_count: int = 5

## How far past the ring radius (the wall's CENTERLINE, not its outer
## surface) a flag must be before it counts as having escaped. Must exceed
## half of wall_thickness_px (the wall's actual outer surface sits at
## ring_radius + wall_thickness_px/2) with real margin to spare, or a flag
## merely resting against the wall's own outer face would border on
## triggering detection. Tune against tools/EscapeRateHistogram.gd.
@export var escape_margin_px: float = 45.0

## With the full roster, many flags converge on the gap as the arena's only
## weak point, and crowd pressure right at that pinch-point can legitimately
## shove a flag past the gap's exact boundary edge before the wall picks up
## again -- confirmed via the escape-rate harness at full scale, where
## "tunneling" events clustered specifically just past the gap edge (15-20deg
## for a 15deg gap), not at random angles around the ring. That's a flag
## genuinely using the gap under crowd pressure, not a wall breach, so a
## small tolerance is added to the gap's angular window for classification
## purposes only (the physical wall segments themselves are unaffected).
@export var gap_edge_tolerance_degrees: float = 6.0

func gap_width_degrees() -> float:
	return 360.0 * float(gap_segment_count) / float(ring_segment_count)

# ---------------------------------------------------------------------------
# Flag physics
# ---------------------------------------------------------------------------

@export var flag_width_px: float = 46.0
@export var flag_bounce: float = 0.7
@export var flag_friction: float = 0.12
## Purely cosmetic tumble rate -- linear speed is enforced directly every
## frame (see relaunch_speed_base below), so linear_damp is irrelevant and
## intentionally not set at all (would be immediately overridden anyway).
@export var flag_angular_damp: float = 0.3

## Flags move at a genuinely constant speed -- enforced every physics frame
## in Flag._integrate_forces(), not just set once at launch. Collisions
## change direction freely; magnitude is always pinned back to this value
## times the current round's speed multiplier (1.0 during qualifying,
## decaying toward lfs_speed_multiplier_floor during Last Flag Standing).
## This single mechanism gives both "flags never stall" (no separate jitter
## impulse system needed) and "the match gradually slows down" for free.
@export var relaunch_speed_base: float = 180.0

# ---------------------------------------------------------------------------
# Rotating gap speed
# ---------------------------------------------------------------------------

## One full sweep around the ring every 8 seconds, base rate -- scaled by the
## same speed multiplier as flag relaunch speed during Last Flag Standing so
## the ratio between "how fast flags move" and "how fast the gap sweeps"
## stays constant while the match decelerates together.
@export var gap_rotation_speed_rad: float = TAU / 8.0

# ---------------------------------------------------------------------------
# Pacing
# ---------------------------------------------------------------------------

@export var qualifying_seconds: float = 1800.0  # 30 minutes
@export var intermission_seconds: float = 60.0   # 1 minute

## After every Last Flag Standing elimination, the speed multiplier decays by
## this fraction (compounding), never going below the floor -- confirmed
## requirement, not optional polish.
@export var lfs_speed_multiplier_decay_per_elimination: float = 0.03
@export var lfs_speed_multiplier_floor: float = 0.35

# ---------------------------------------------------------------------------
# Leaderboard (ported pattern from flagsplinko's PlinkoSettings)
# ---------------------------------------------------------------------------

@export var leaderboard_max_entries: int = 50
@export var leaderboard_page_size: int = 5
@export var leaderboard_page_seconds: float = 3.0
@export var leaderboard_transition_seconds: float = 0.5

# ---------------------------------------------------------------------------
# Announcement popups (ported pattern from flagsplinko's ScorePopup)
# ---------------------------------------------------------------------------

@export var announcement_lifetime: float = 1.5
@export var announcement_rise_distance: float = 40.0

# ---------------------------------------------------------------------------
# Roster strip
# ---------------------------------------------------------------------------

@export var roster_strip_columns: int = 25
@export var roster_strip_icon_width: float = 34.0
