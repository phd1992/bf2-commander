class_name Balance
extends RefCounted
## Every tunable number in the game lives here. Nothing gameplay-related is
## hard-coded elsewhere; systems read these constants at runtime so a human can
## rebalance the game from this single file.

# ---------------------------------------------------------------------------
# Enums shared by the whole simulation
# ---------------------------------------------------------------------------

enum Terrain { ROAD, OPEN, FOREST, URBAN, WATER, WALL, DOOR, INTERIOR, RUBBLE }
enum MoveClass { FOOT, WHEELED, TRACKED }
enum Team { NONE = -1, BLUE = 0, RED = 1 }
enum Kit { LEADER, AT, RIFLE }
enum MemberState { ALIVE, DEAD, IN_VEHICLE }
enum Order { NONE, MOVE, ATTACK, DEFEND, MOUNT, DISMOUNT, HOLD }

const TEAM_NAMES := { Team.BLUE: "BLUE", Team.RED: "RED" }
const SQUAD_NAMES := ["Alpha", "Bravo", "Charlie", "Delta"]
const RED_SQUAD_PREFIX := "R-"

# ---------------------------------------------------------------------------
# World / simulation
# ---------------------------------------------------------------------------

const CELL_PX := 32
const MAP_W := 96
const MAP_H := 64
const TICK := 0.1

const MATCH_LENGTH_S := 1200.0
const START_TICKETS := 300
const BLEED_INTERVAL_S := 3.0
const RESPAWN_TICKET_COST := 1

const FLAG_RADIUS := 4.0
const HQ_RADIUS := 4.0
const CAPTURE_TIME_S := 20.0
const CAPTURE_MAX_COUNT := 3

# ---------------------------------------------------------------------------
# Terrain table (Section 4.2): speed per move class, cover, LOS blocker.
# speed index order is MoveClass: [FOOT, WHEELED, TRACKED]. 0 = impassable.
# ---------------------------------------------------------------------------

const TERRAIN := {
	Terrain.ROAD:     { "name": "ROAD",     "speed": [1.2, 1.0, 1.0], "cover": 0.0,  "blocker": 0.0 },
	Terrain.OPEN:     { "name": "OPEN",     "speed": [1.0, 0.5, 0.8], "cover": 0.0,  "blocker": 0.0 },
	Terrain.FOREST:   { "name": "FOREST",   "speed": [0.7, 0.0, 0.4], "cover": 0.4,  "blocker": 1.0 },
	Terrain.URBAN:    { "name": "URBAN",    "speed": [0.9, 0.8, 0.6], "cover": 0.3,  "blocker": 0.0 },
	Terrain.WATER:    { "name": "WATER",    "speed": [0.0, 0.0, 0.0], "cover": 0.0,  "blocker": 0.0 },
	Terrain.WALL:     { "name": "WALL",     "speed": [0.0, 0.0, 0.0], "cover": 0.0,  "blocker": 2.0 },
	Terrain.DOOR:     { "name": "DOOR",     "speed": [0.8, 0.0, 0.0], "cover": 0.2,  "blocker": 0.0 },
	Terrain.INTERIOR: { "name": "INTERIOR", "speed": [0.6, 0.0, 0.0], "cover": 0.7,  "blocker": 2.0 },
	Terrain.RUBBLE:   { "name": "RUBBLE",   "speed": [0.5, 0.0, 0.5], "cover": 0.35, "blocker": 0.5 },
}

# Slope (Section 4.3): uphill multiplier = 1 + SLOPE_PER_LEVEL[class] * dh
const SLOPE_PER_LEVEL := [0.5, 1.5, 1.0]   # FOOT, WHEELED, TRACKED
const CLIFF_THRESHOLD := [3, 2, 2]          # |dh| >= threshold is impassable
const CLIFF_COST := 1.0e6
const MAX_ELEVATION := 5

# Line of sight (Section 4.5)
const EYE_FOOT := 1.5
const EYE_INTERIOR := 2.5
const EYE_VEHICLE := 1.5
const LOS_EPS := 0.01

# Pathfinding
const LEADER_REPATH_S := 2.0
const MEMBER_REPATH_S := 1.0
const DETACHED_REPATH_S := 2.0
const WAYPOINT_REACH := 0.3

# ---------------------------------------------------------------------------
# Members and squads (Section 6)
# ---------------------------------------------------------------------------

const SQUAD_SIZE := 6
const MEMBER_HP := 100.0
const MEMBER_BASE_SPEED := 2.0
const SPEED_VAR := [0.9, 1.1]
const CATCHUP_MULT := 1.3
const CATCHUP_DIST := 2.0
const SLOT_TOLERANCE := 0.5
const SEPARATION_DIST := 0.4
const SEPARATION_PUSH := 0.1
const DEAD_DRAW_S := 10.0

const FORMATIONS := {
	"COLUMN":  [Vector2(-1.2, 0), Vector2(-2.4, 0), Vector2(-3.6, 0), Vector2(-4.8, 0), Vector2(-6.0, 0)],
	"WEDGE":   [Vector2(-1.5, 1.5), Vector2(-1.5, -1.5), Vector2(-3.0, 3.0), Vector2(-3.0, -3.0), Vector2(-3.0, 0)],
	"CLUSTER": [Vector2(-1.0, 0.8), Vector2(-1.0, -0.8), Vector2(-1.8, 0.3), Vector2(-0.6, 1.4), Vector2(-1.6, -1.2)],
}
const FORMATION_HYSTERESIS_S := 1.0

const PAUSE_INTERVAL := [8.0, 15.0]
const PAUSE_LEN := [0.5, 1.5]
const DETACH_DIST := 12.0
const REJOIN_DIST := 3.0

const STAT_SUM := 12
const STAT_MIN := 1
const STAT_MAX := 5
const RED_FIXED_STAT := 3

const ACCURACY_BASE := 0.7
const ACCURACY_PER_SKILL := 0.15
const REACTION_BASE := 2.0
const REACTION_PER_SKILL := 0.3
const ORDER_DELAY_BASE := 6.0
const COVER_RESUME_BASE := 8.0
const BOUND_BASE := 3.0
const BOUND_MAX_S := 6.0
const PURSUE_DIST := 8.0
const LOW_AGGRESSION_ENGAGE_RANGE := 10.0
const COMBAT_CONTACT_DIST := 20.0
const COVER_SEEK_AFTER_SHOT_S := 2.0
const COVER_SEARCH_RADIUS := 3.0
const COVER_DIST_WEIGHT := 0.1
const ORDER_ARRIVE_DIST := 1.0

const XP_KILL := 10
const XP_VEHICLE := 30
const XP_CAPTURE := 20
const XP_THRESHOLDS := [100, 250]

# ---------------------------------------------------------------------------
# Vehicles (Section 7)
# ---------------------------------------------------------------------------

const VEHICLES := {
	"JEEP": { "mclass": MoveClass.WHEELED, "hp": 150.0, "seats": 4, "speed": 5.0, "weapons": ["HMG"], "size_px": Vector2(20, 12) },
	"APC":  { "mclass": MoveClass.TRACKED, "hp": 400.0, "seats": 6, "speed": 3.0, "weapons": ["AUTOCANNON"], "size_px": Vector2(28, 16) },
	"TANK": { "mclass": MoveClass.TRACKED, "hp": 800.0, "seats": 2, "speed": 2.5, "weapons": ["CANNON", "HMG"], "size_px": Vector2(32, 18) },
}
const VEHICLE_MIN_CREW := 2
const PAD_RESPAWN_S := 60.0
const PAD_SEARCH_DIST := 3
const MOUNT_DIST := 1.0
const MOUNT_SEARCH_DIST := 12.0
const DISMOUNT_RADIUS := 1.5

# ---------------------------------------------------------------------------
# Weapons and combat (Section 8)
# ---------------------------------------------------------------------------

const WEAPONS := {
	"RIFLE":      { "range": 12.0, "interval": 1.0,  "dmg_inf": 25.0, "dmg_veh": 2.0,   "splash": 0.0, "cover_ignore": 0.0, "wall_dmg": 0.0 },
	"AT":         { "range": 12.0, "interval": 4.0,  "dmg_inf": 40.0, "dmg_veh": 270.0, "splash": 1.0, "cover_ignore": 0.3, "wall_dmg": 30.0 },
	"HMG":        { "range": 10.0, "interval": 0.4,  "dmg_inf": 8.0,  "dmg_veh": 3.0,   "splash": 0.0, "cover_ignore": 0.0, "wall_dmg": 0.0 },
	"AUTOCANNON": { "range": 14.0, "interval": 0.5,  "dmg_inf": 15.0, "dmg_veh": 20.0,  "splash": 0.0, "cover_ignore": 0.2, "wall_dmg": 5.0 },
	"CANNON":     { "range": 18.0, "interval": 5.0,  "dmg_inf": 60.0, "dmg_veh": 150.0, "splash": 1.5, "cover_ignore": 0.3, "wall_dmg": 40.0 },
	"ARTY_SHELL": { "range": 0.0,  "interval": 0.0,  "dmg_inf": 80.0, "dmg_veh": 60.0,  "splash": 1.5, "cover_ignore": 0.5, "wall_dmg": 50.0 },
}

const HIT_BASE := 0.5
const RANGE_MIN_FACTOR := 0.5
const HEIGHT_UP := 1.15
const HEIGHT_DOWN := 0.9
const MOVE_INF := 0.7
const MOVE_VEH := 0.8
const VEHICLE_COVER_MULT := 0.5
# A missed splash shot lands at a random point within this many cells of the
# target. The missed target itself is excluded from that splash (see DECISIONS).
const MISS_SCATTER := 3.0

# ---------------------------------------------------------------------------
# Buildings (Section 9)
# ---------------------------------------------------------------------------

const WALL_HP := 100
const COLLAPSE_FRACTION := 0.5
const COLLAPSE_DAMAGE := 50.0

# ---------------------------------------------------------------------------
# Spawning (Section 10)
# ---------------------------------------------------------------------------

const MEMBER_RESPAWN_S := 15.0
const SQUAD_RESPAWN_S := 20.0
const SPAWN_SCATTER := 1.0

# ---------------------------------------------------------------------------
# Fog of war (Section 11)
# ---------------------------------------------------------------------------

const SPOT_INF := 14.0
const SPOT_VEH := 16.0
const SPOT_CONCEALED := 6.0
const FLASH_RANGE := 20.0
const FLASH_S := 3.0
const COMMS_DELAY_BASE := 6.0
const COMMS_PERSIST_BASE := 4.0
const COMMS_PERSIST_PER := 2.0
const CELL_VISION_INTERVAL_S := 0.5

# ---------------------------------------------------------------------------
# Commander assets (Section 12)
# ---------------------------------------------------------------------------

const ASSETS := {
	"UAV":          { "radius": 12.0, "duration": 30.0, "cooldown": 90.0,  "delay": 3.0 },
	"ARTILLERY":    { "radius": 4.0,  "duration": 6.0,  "cooldown": 120.0, "delay": 5.0 },
	"SUPPLY":       { "radius": 3.0,  "duration": 60.0, "cooldown": 90.0,  "delay": 8.0 },
	"VEHICLE_DROP": { "radius": 0.0,  "duration": 0.0,  "cooldown": 180.0, "delay": 8.0 },
}
const ASSET_ORDER := ["UAV", "ARTILLERY", "SUPPLY", "VEHICLE_DROP"]
const ARTY_SHELLS := 6
const ARTY_SHELL_INTERVAL_S := 1.0
const SUPPLY_HEAL_PER_S := 10.0
const SUPPLY_ACCURACY_BONUS := 0.3
const VEHICLE_DROP_TYPE := "JEEP"

# ---------------------------------------------------------------------------
# Commander AI (Section 13)
# ---------------------------------------------------------------------------

const AI_TICK_S := 5.0
const AI_DEFEND_RADIUS := 6.0
const AI_MAX_PER_FLAG := 2
const AI_DESPERATION_MARGIN := 30
const AI_ARTY_MIN_CLUSTER := 3
const AI_ARTY_SAFE_DIST := 5.0
const AI_MOUNT_MIN_DIST := 15.0
const AI_MOUNT_SEARCH := 8.0
const AI_DISMOUNT_DIST := 4.0
const AI_FLAG_VALUE_NEUTRAL := 3.0
const AI_FLAG_VALUE_WEAK_ENEMY := 4.0
const AI_FLAG_VALUE_STRONG_ENEMY := 2.0
const AI_FLAG_DIST_BIAS := 5.0
const AI_WEAK_DEFENDERS := 3

# ---------------------------------------------------------------------------
# Rendering colours (Section 14) - kept here so the palette is tunable too
# ---------------------------------------------------------------------------

const COLOR_BLUE := Color("#3a7bd5")
const COLOR_RED := Color("#d5473a")
const TERRAIN_COLORS := {
	Terrain.ROAD: Color(0.72, 0.72, 0.70),
	Terrain.OPEN: Color(0.45, 0.52, 0.25),
	Terrain.FOREST: Color(0.16, 0.36, 0.18),
	Terrain.URBAN: Color(0.68, 0.60, 0.45),
	Terrain.WATER: Color(0.20, 0.38, 0.68),
	Terrain.WALL: Color(0.28, 0.28, 0.30),
	Terrain.DOOR: Color(0.48, 0.32, 0.18),
	Terrain.INTERIOR: Color(0.82, 0.76, 0.62),
	Terrain.RUBBLE: Color(0.50, 0.50, 0.50),
}
const ELEVATION_BRIGHTNESS_PER_LEVEL := 0.08


# ---------------------------------------------------------------------------
# Small helpers so callers do not repeat table lookups
# ---------------------------------------------------------------------------

static func terrain_speed(t: int, mc: int) -> float:
	return TERRAIN[t]["speed"][mc]


static func terrain_cover(t: int) -> float:
	return TERRAIN[t]["cover"]


static func terrain_blocker(t: int) -> float:
	return TERRAIN[t]["blocker"]


static func terrain_name(t: int) -> String:
	return TERRAIN[t]["name"]


static func other_team(team: int) -> int:
	return Team.RED if team == Team.BLUE else Team.BLUE


static func accuracy_mult(skill: int) -> float:
	return ACCURACY_BASE + ACCURACY_PER_SKILL * (skill - 1)


static func reaction_time(skill: int) -> float:
	return REACTION_BASE - REACTION_PER_SKILL * (skill - 1)


static func order_delay(discipline: int) -> float:
	return ORDER_DELAY_BASE - discipline


static func cover_resume(discipline: int) -> float:
	return COVER_RESUME_BASE - discipline


static func bound_length(aggression: int) -> float:
	return BOUND_BASE + aggression


static func comms_delay(comms: int) -> float:
	return COMMS_DELAY_BASE - comms


static func comms_persist(comms: int) -> float:
	return COMMS_PERSIST_BASE + COMMS_PERSIST_PER * comms
