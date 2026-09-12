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
@export var ring_radius: float = 450.0

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
##
## 144 (not the original 72) so gap_segment_count=11 lands on a clean +10%
## over the previous 5/72 * 360 = 25deg -- 11/144 * 360 = 27.5deg = 25 * 1.1
## exactly. A modest 2x resolution bump, not the 4x (288) tried and reverted
## for an over-precise +15% request -- simpler ask, simpler change.
@export var ring_segment_count: int = 144
## 14 segments * 2.5deg = 35deg opening (up from 11/27.5deg, then 12/30deg,
## per direct request to widen the escape gap -- 14 keeps the segment math
## clean against ring_segment_count=144). Originally widened from an
## initial 15deg after full-scale testing showed only ~8 qualifiers per
## 30-min window, too sparse for good stream pacing. Tune against
## tools/EscapeRateHistogram.gd -- though note that tool predates the
## round-based qualifying redesign and doesn't handle qualifying_round_reset,
## so it stops producing qualifiers after round one; still valid for reading
## gap_width_degrees()/tuning wall geometry, just not a realistic qualify-
## rate readout right now.
@export var gap_segment_count: int = 14

## How far past the ring radius (the wall's CENTERLINE, not its outer
## surface) a flag must be before EscapeDetector even looks at it -- anything
## under this threshold is treated as unremarkable and skipped entirely, no
## correction applied.
##
## The 45px first tried here was based on a mistaken premise: it was sized to
## tolerate "a flag resting against the wall's own outer face" without
## falsely tripping detection. But a flag whose CENTER has reached the wall's
## outer face (ring_radius + wall_thickness_px/2 = a good ~20px past this
## radius) is resting against it from the OUTSIDE -- genuinely beyond the
## arena's solid boundary, not a flag merely pressed hard against the wall
## from inside. (A flag resting against the wall from INSIDE has its center
## around ring_radius - wall_thickness_px/2 - flag_half_width, i.e. tens of
## pixels on the SAFE side of ring_radius itself -- it never needed a large
## margin to be classified correctly in the first place.) A 45px margin
## therefore created an entirely unmonitored ~45px band just past the wall
## where a flag that squeezed through the gap during the chaotic first-second
## launch cascade could get stranded on the wall's exterior, bouncing off it
## and other stranded flags with zero correction applied, until either its
## radius happened to exceed the threshold while the sweeping gap was back at
## its angle (a real but confusing "why did that flag just disappear" several
## seconds after spawn) or while it wasn't (silently teleported back inside).
## Confirmed via visual testing at full roster/speed. A small value here only
## needs to cover genuine CCD/contact-resolution jitter for a legitimate
## inside-resting flag, not a flag's own half-width. Tune against
## tools/EscapeRateHistogram.gd.
@export var escape_margin_px: float = 15.0

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

## Width of the second rotating wall arc (BlockerArc/GlowArc) that sweeps the
## OPPOSITE direction around the ring from the main gap (confirmed design,
## reference image) -- wider than the gap itself so it fully seals the gap
## for a real stretch of time whenever the two happen to overlap, not just
## a single instant.
@export var blocker_arc_width_degrees: float = 40.0

## The blocker arc's colour cycle (confirmed design), timed from each round
## start (resets every round). It stays green for
## blocker_arc_first_green_seconds, then repeats the sequence
## GREEN -> BLUE(freezing) -> GREEN -> RED(fire) forever, where each GREEN
## phase lasts blocker_arc_green_seconds, the BLUE phase
## blocker_arc_freezing_seconds and the RED phase blocker_arc_fire_seconds.
## See BlockerArc.current_state().
@export var blocker_arc_first_green_seconds: float = 15.0
@export var blocker_arc_green_seconds: float = 8.0
@export var blocker_arc_freezing_seconds: float = 5.0
@export var blocker_arc_fire_seconds: float = 8.0
## A flag's speed multiplier while it holds a state, for the rest of the
## round: frozen 0.45 (-55%), on fire 1.30 (+30%). A frozen flag that hits
## the fire (red) arc becomes normal; a fire flag that hits the freezing
## (blue) arc becomes normal; hitting the green arc, or the arc of its own
## element, leaves the state unchanged.
@export var frozen_flag_speed_factor: float = 0.45
@export var fire_flag_speed_factor: float = 1.30
## Hard cap on how long a flag stays frozen or on fire. If no arc contact
## has cleared or flipped the state within this many seconds, the flag
## reverts to NORMAL on its own. (Reset whenever the state changes.)
@export var special_state_max_seconds: float = 30.0

# ---------------------------------------------------------------------------
# Flag physics
# ---------------------------------------------------------------------------

@export var flag_width_px: float = 51.35  # 49.85 + 3%, per direct request
## Full elastic restitution (mirror reflection: angle in = angle out), not a
## softer value like the 0.7 first tried. A wall bounce only ever touches the
## NORMAL component of velocity; any restitution below 1.0 shrinks that
## normal component relative to the (friction-0, so untouched) tangential
## one, which biases EVERY wall bounce a little further toward tangential
## motion -- not a rare fluke, a structural drift that (confirmed via visual
## testing at full scale, over enough elapsed time) pulls the whole flag
## population toward skimming/orbiting the perimeter. This also depends on
## the wall itself combining to the same full-elastic value -- see
## GapRing.gd's matching physics_material_override, since a StaticBody2D
## with no override at all collides at the engine's default bounce (0.0),
## which can dominate the combined result regardless of this value.
@export var flag_bounce: float = 1.0
## Zero, not just low -- even a small nonzero friction is enough to let a
## flag grip tangentially against a wall/another flag's surface ("surface
## tension") instead of separating cleanly on contact, which combined with
## per-frame velocity renormalization was producing flags stuck oscillating
## at the arena's perimeter instead of bouncing away. Same lesson the
## sibling flagsplinko project already learned for its own peg contacts.
@export var flag_friction: float = 0.0

## Flags move at a genuinely constant speed -- enforced every physics frame
## in Flag._physics_process(), not just set once at launch. Collisions
## change direction freely; magnitude is always pinned back to this value
## times the current round's speed multiplier (1.0 during qualifying,
## decaying toward lfs_speed_multiplier_floor during Last Flag Standing).
## This single mechanism gives both "flags never stall" (no separate jitter
## impulse system needed) and "the match gradually slows down" for free.
## Dropped to 671.07 earlier this session after headless testing traced a
## "flags look jittery, especially diagonally" report to real per-tick
## collision distortion (confirmed via a diagnostic sampling one flag's
## exact position every physics tick: ~22% of ticks deviated over 20% from
## the expected constant-speed step, matching actual collision events, not
## a rendering bug -- physics interpolation, see project.godot, didn't fix
## it since the underlying simulated positions themselves were chaotic at
## that speed/density). Confirmed as clearly better at 671.07, then pushed
## back up to 750.
##
## A later "split/lagging" report (after flag_width_px grew 40 -> 44) tried
## cutting this to 682 (matching the size increase) on the theory that a
## bigger collision shape hits harder -- re-running the same full-roster
## diagnostic measured 8.1% distorted ticks at 750/44px vs 8.3% at 682/44px,
## i.e. no meaningful change, so that cut was reverted rather than kept on
## an unproven theory. Both numbers are well under the old 22% "bad" bar
## anyway, meaning per this specific metric the collision-level jitter that
## was fixed earlier this session is still fixed -- whatever's behind the
## newer report is likely a different mechanism, not this one. Re-run the
## same diagnostic (tools/ dir, sample one flag's position every tick
## against the expected constant-speed step) before assuming speed is the
## lever again.
@export var relaunch_speed_base: float = 712.5  # 750 - 5%, per direct request

# ---------------------------------------------------------------------------
# Departure animation
# ---------------------------------------------------------------------------

## When a flag escapes (qualifies or is eliminated), it just keeps flying
## onward in a straight line at its own actual exit velocity -- no redirect
## toward a fixed point (that made every departure visibly curve inward
## toward one spot, reading as an odd funnel effect rather than flags
## naturally continuing on their way out) and no spin/shrink flourish either
## (removed per direct request -- the flight itself is the whole animation
## now). It's simply removed once it crosses one of these lines, standing in
## for the top/bottom UI panels -- see Leaderboard.tscn/EjectedStrip.tscn,
## whose panel bounds these are hand-matched to (Flag.gd has no scene
## reference to either panel by design; it's a pure physics/movement script
## with zero UI awareness). A flag exiting toward the left/right instead just
## vanishes once fully off-screen (x<=0 or x>=1080, checked directly in
## Flag.gd -- no matching UI there, nothing to tune).
@export var departure_vanish_top_y: float = 520.0
@export var departure_vanish_bottom_y: float = 1440.0

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
@export var intermission_seconds: float = 15.0   # 15 seconds

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
