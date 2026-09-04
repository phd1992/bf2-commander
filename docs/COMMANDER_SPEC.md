# COMMANDER — Build Spec, MVP v1

A single-player, top-down 2D game in the style of Battlefield 2's Commander Mode. The player commands BLUE; an AI commands RED. Both sides field squads of individual soldiers and ground vehicles, fight over flags, and bleed tickets. Terrain, elevation, line of sight and destructible buildings all matter.

---

## 0. Instructions for the implementing agent

Read this whole document before writing code. Then work through the milestones in Section 18 in order.

- **Do not stop to ask questions.** When something is ambiguous, pick the simplest option consistent with this spec, implement it, and record the choice in `DECISIONS.md` (one line each: what was ambiguous, what you chose, why).
- **The game must run at the end of every milestone.** Never leave the project in a state where `Play` errors on launch.
- **All tunable numbers live in one file**: `scripts/config/balance.gd`. Every number in this spec is a starting value; put it there, not inline.
- **Commit after each milestone** with message `M<n>: <milestone title>`. Run the test runner (Section 17) before each commit; fix failures before moving on.
- **Maintain `PROGRESS.md`**: which milestones are complete, exact commands to run the game / tests / headless sim, known issues, and what you would do next.
- **No external art, audio, fonts or addons.** Everything is drawn with primitives (`_draw`, `Polygon2D`, `Line2D`, `Label`). No asset downloads. No GUT or other test frameworks; use the plain runner in Section 17.
- If Godot is not installed, download the latest stable Godot 4.x Linux build from the official `godotengine/godot` GitHub releases, unpack it, and use it as `godot`. The standard editor binary supports `--headless`.
- Prefer clarity over cleverness. This codebase will be extended by a human afterwards.

---

## 1. Overview

**Pitch.** You are the commander. You see the whole map from above, you give orders to four squads, you call in artillery, UAVs, supplies and vehicles, and you watch tiny soldiers carry out (or fumble) your plan. Your squads have different personalities; the enemy commander is trying to do the same thing to you.

**Core loop.** Capture flags → hold more flags than the enemy → enemy bleeds tickets → enemy reaches zero tickets → you win. Assets on cooldown are your way to tip fights your squads would otherwise lose.

**In scope (v1).**
- One symmetric generated map, ~96×64 cells, with roads, a river with bridges, forests, a central ridge, a central town.
- Elevation (0–5) affecting movement, line of sight and combat.
- Buildings with walls, doors and interiors; walls degrade to rubble; buildings can collapse.
- 4 squads per team × 6 soldiers, with visible stat profiles on the player side.
- Ground vehicles: jeep, APC, tank. Mount/dismount, vehicle pads at flags.
- Conquest spawning (spawn at owned flags), tickets, 5 flags + 2 HQs.
- Commander assets: UAV, artillery, supply drop, vehicle drop.
- Fog of war with squad-quality-dependent contact reporting.
- Enemy commander AI (rule-based, no cheating on vision).
- Headless AI-vs-AI simulation for balance and stability checks.

**Out of scope (v1).** Air units, multiplayer, sound, art assets, Broken Arrow spawn mode (specified in Section 19 as Phase 2), enemy squad stat variance (RED squads are uniform), squads refusing orders beyond the Discipline delay, suppression, medics, save/load.

---

## 2. Tech stack and project layout

- **Engine:** Godot 4.4 or newer stable (use whatever latest stable is available). GDScript only. 2D renderer.
- **Resolution:** 1600×900 window, resizable. Camera pans and zooms; the whole map is 3072×2048 px at 32 px per cell.
- **Simulation:** fixed-step, 10 ticks per second (`dt = 0.1`), driven by an autoload `Sim`. Rendering reads simulation state; no game logic lives in rendering nodes. Sim speed 1×/2×/4× = 1/2/4 `step()` calls per physics frame. Headless mode calls `step()` in a tight loop.
- **Determinism:** the world is seeded; use one `RandomNumberGenerator` owned by `Sim` for all gameplay randomness so a given seed replays the same AI-vs-AI match.

```
project.godot
scripts/
  config/balance.gd          # every tunable constant (const or static vars)
  core/sim.gd                # autoload: tick loop, RNG, time scale, pause
  core/world.gd              # owns grid, teams, squads, vehicles, flags, assets
  map/grid.gd                # cell storage + terrain table + elevation helpers
  map/pathfinder.gd          # AStarGrid2D subclass per movement class
  map/los.gd                 # line of sight
  map/map_generator.gd       # seeded generator (Section 15)
  map/buildings.gd           # building ids, wall HP, rubble, collapse
  units/squad.gd
  units/member.gd
  units/vehicle.gd
  units/formation.gd
  units/movement.gd          # leader path following, slots, bounding, cover seeking
  combat/weapons.gd          # weapon table
  combat/combat.gd           # target selection, hit rolls, damage, splash, wall damage
  game/flags.gd
  game/tickets.gd
  game/spawn_policy.gd       # base class
  game/spawn_conquest.gd
  game/assets.gd             # UAV / artillery / supply / vehicle drop
  game/fog.gd                # per-team visibility + contact reports
  ai/commander_ai.gd         # rule-based commander, usable by either team
render/
  terrain_layer.gd           # draws cells; queue_redraw only on change
  fog_layer.gd
  units_layer.gd
  effects_layer.gd
  camera.gd
ui/
  hud.tscn / hud.gd          # top bar, squad panel, asset bar, tooltips
  main_menu.tscn
  end_screen.tscn
scenes/
  main.tscn                  # menu → game
  game.tscn
sim/
  run_headless.gd            # AI vs AI batch runner
tests/
  run_tests.gd               # plain assertion runner
  test_*.gd
DECISIONS.md
PROGRESS.md
```

---

## 3. Glossary

- **Cell:** one 32×32 px grid square. Positions of units are floats in cell units (e.g. `Vector2(12.4, 30.9)`); `cell = Vector2i(floor(x), floor(y))`.
- **Member:** one soldier. Belongs to exactly one squad.
- **Squad:** 6 members; one is the **leader**. Orders are given to squads.
- **Movement class:** `FOOT`, `WHEELED`, `TRACKED`. Members are `FOOT`; jeep is `WHEELED`; APC and tank are `TRACKED`.
- **Flag:** capturable control point. **HQ:** uncapturable team spawn point.
- **Contact:** an enemy unit a team currently knows about (with a timestamp).
- **Asset:** a commander ability on cooldown.

---

## 4. World grid

### 4.1 Cell data

Map is `W=96` × `H=64` cells, origin top-left, +x east, +y south. Store per-cell arrays (PackedByteArray / PackedInt32Array, index `y*W+x`):

- `terrain` — enum below
- `elevation` — 0..5
- `building_id` — -1 or id (Section 9)
- `wall_hp` — 0..100, only meaningful for WALL cells

### 4.2 Terrain table

Speed multipliers scale a unit's base speed; `0` = impassable for that class. `cover` reduces hit chance on units standing in the cell (Section 8). `blocker` is added to elevation for line-of-sight purposes (Section 4.5).

| Terrain  | FOOT | WHEELED | TRACKED | cover | blocker | notes |
|----------|------|---------|---------|-------|---------|-------|
| ROAD     | 1.2  | 1.0     | 1.0     | 0.0   | 0.0     | also used for bridges over WATER |
| OPEN     | 1.0  | 0.5     | 0.8     | 0.0   | 0.0     | fields, grass |
| FOREST   | 0.7  | 0       | 0.4     | 0.4   | 1.0     | |
| URBAN    | 0.9  | 0.8     | 0.6     | 0.3   | 0.0     | streets and yards in town |
| WATER    | 0    | 0       | 0       | 0.0   | 0.0     | |
| WALL     | 0    | 0       | 0       | —     | 2.0     | HP 100; becomes RUBBLE at 0 |
| DOOR     | 0.8  | 0       | 0       | 0.2   | 0.0     | |
| INTERIOR | 0.6  | 0       | 0       | 0.7   | 2.0     | inside a building |
| RUBBLE   | 0.5  | 0       | 0.5     | 0.35  | 0.5     | |

### 4.3 Elevation and slope

Moving from cell `a` to adjacent cell `b`, `Δh = elev(b) − elev(a)`.

- Uphill cost multiplier: FOOT `1 + 0.5·Δh`, TRACKED `1 + 1.0·Δh`, WHEELED `1 + 1.5·Δh`. Downhill: no change.
- Impassable (cliff) if `Δh ≥ 3` for FOOT, `Δh ≥ 2` for TRACKED and WHEELED. Downhill cliffs are also impassable (use `|Δh|`).
- Combat and spotting bonuses for height are in Sections 8 and 11.

### 4.4 Pathfinding

- One `AStarGrid2D` per movement class, size W×H, `diagonal_mode = DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`, `default_compute_heuristic = HEURISTIC_OCTILE`.
- Mark a cell solid for a class when its terrain speed multiplier is 0.
- Subclass `AStarGrid2D` and override `_compute_cost(from, to)`: `distance(from,to) × (1 / speed_mult(to)) × slope_mult(from,to)`; return `1e6` when the step is a cliff for that class. Override `_estimate_cost` with plain octile distance so the heuristic stays admissible.
- If profiling shows a single path request above 15 ms, replace with a custom binary-heap A* over the same cost function. Do not optimise before measuring.
- Paths are requested only for squad leaders, detached members (Section 6.5) and vehicles. Leaders repath every 2 s while moving and immediately on a new order or when a cell on their remaining path becomes solid.
- When a cell's terrain changes (Section 9), update the solid flags of all three grids.

### 4.5 Line of sight

`has_los(from_cell, from_eye, to_cell, to_eye) -> bool`

- `eye` values are absolute heights: `elevation(cell) + eye_offset`. Eye offsets: FOOT 1.5; a FOOT unit standing in INTERIOR 2.5 (at a window); vehicles 1.5. The same offsets apply to the target.
- Walk the Bresenham line between the cells, **excluding both endpoints**. For each intermediate cell at fraction `t` along the line: `line_h = from_eye + t·(to_eye − from_eye)`; `top = elevation + blocker`. Blocked if `top > line_h − 0.01`.
- Worked checks (must be covered by tests): two units at elevation 0 with an elevation-2 cell between them → blocked. Observer at elevation 3 looking down to elevation 0 with an elevation-2 cell midway → visible. A unit in INTERIOR looking out through an adjacent WALL to a unit 5 cells away on flat ground → visible, and symmetric.
- LOS is evaluated on live data, so rubble opens sightlines as walls fall.

---

## 5. Teams, flags, tickets, victory

### 5.1 Layout

- BLUE HQ near the west edge, RED HQ near the east edge. HQs are uncapturable, always spawnable, radius 4 cells.
- Five capturable flags, named A–E. A and B in the west third, D and E in the east third, C in the central town. Exact placement in Section 15.
- Flags have `owner ∈ {NONE, BLUE, RED}` and `progress ∈ [−1, +1]` (+1 = fully BLUE, −1 = fully RED). Initial state: all NONE, progress 0.

### 5.2 Capture

Every tick, for each flag, count team members within radius 4 cells of the flag centre. Members inside vehicles count. Let `nb = min(blue,3)`, `nr = min(red,3)`, `n = nb − nr`.

- `progress += n · dt / 20`, clamped to [−1, +1]. (One soldier alone flips a neutral flag in 20 s; three flip it in ~7 s; more than three add nothing.)
- Owner becomes BLUE when progress reaches +1, RED at −1. Owner becomes NONE the moment progress crosses 0 from the owner's side.
- Contested (`n = 0` with both present): no change.

### 5.3 Tickets

- Each team starts with 200 tickets.
- **Bleed:** every 3 s, a team that owns fewer flags than the other team loses 1 ticket.
- **Respawn cost:** 1 ticket per member respawn (Section 10). Vehicles cost nothing.
- **Victory:** the first team to reduce the enemy to 0 wins. At 20 minutes match time, the team with more tickets wins; equal is a draw.

---

## 6. Squads and members

### 6.1 Composition

Each team has 4 squads (BLUE: Alpha, Bravo, Charlie, Delta; RED: same names, prefixed "R-"). Each squad has 6 members:

- 1 × LEADER (RIFLE weapon)
- 1 × AT (AT weapon; also carries RIFLE and uses it when no vehicle target is in range)
- 4 × RIFLE

Member: `hp` (100), `pos` (Vector2, cell units), `state ∈ {ALIVE, DEAD, IN_VEHICLE}`, `kit`, `speed_var` (fixed per member, uniform 0.9–1.1), `last_shot_at_time`, `fired_at_time` (for cover seeking and muzzle-flash reveal). Base speed 2.0 cells/s before terrain and variance.

If the leader dies, the next living member (AT first, then rifles) becomes leader immediately.

### 6.2 Squad stats

Four stats, each an integer 1–5: **Skill**, **Discipline**, **Aggression**, **Comms**.

- BLUE squads: rolled at match start. Sum of the four = 12, each in [1,5]. Choose uniformly among all valid combinations, using the sim RNG.
- RED squads: all four fixed at 3. (v1 keeps the enemy predictable.)
- Stats are displayed on the squad panel and never hidden in v1.

Effects:

| Stat | Effect |
|------|--------|
| Skill | `accuracy_mult = 0.7 + 0.15·(Skill−1)` (0.7 … 1.3). Reaction time to a new contact before the first shot: `2.0 − 0.3·(Skill−1)` s. |
| Discipline | Order delay: a new order is acknowledged immediately but executed after `6 − Discipline` s (5 … 1). After taking cover, members resume formation `8 − Discipline` s after last incoming fire (7 … 3). |
| Aggression | Behaviour on reaching an objective: 4–5 pursue visible enemies up to 8 cells from the objective; 2–3 hold the objective and engage anything in weapon range; 1 holds, seeks cover, and only engages within 10 cells. Bound length during bounding overwatch: `3 + Aggression` cells. |
| Comms | Enemy contacts spotted by this squad appear on the commander map after `6 − Comms` s and persist `4 + 2·Comms` s after last seen. |

### 6.3 Veterancy

Squad XP: +10 per enemy member killed by the squad, +30 per enemy vehicle destroyed, +20 per flag capture completed while at least one member is in the radius. At 100 XP and again at 250 XP, Skill +1 (cap 5). If all six members are dead at the same time (full wipe), XP resets to 0 and Skill resets to the rolled value. XP is shown as a small bar on the squad card.

### 6.4 Orders

One order at a time; a new order replaces the old one after the Discipline delay.

- `MOVE(cell)` — leader paths to the cell; squad forms up there and behaves per Aggression.
- `ATTACK(flag)` — move to the flag centre, capture, then per Aggression.
- `DEFEND(flag)` — move to the flag, then each member takes the best cover cell within radius 4 (score = cover − 0.1·distance from flag centre; INTERIOR cells count), and engages anything in range. Members do not leave the radius.
- `MOUNT(vehicle)` — Section 7.3.
- `DISMOUNT` — Section 7.3.
- `HOLD` — stop, take cover in place, engage in range.

An order is *completed* when the leader is within 1 cell of the destination (MOVE) or the flag's owner is the squad's team (ATTACK). DEFEND never completes. Completed and idle states are what the AI (Section 13) looks for.

### 6.5 Movement model

The principle: **path one thing, animate many.**

**Leader.** Follows its A* path as a list of cell centres; moves toward the next waypoint, pops it within 0.3 cells. Speed = base × terrain(FOOT) under the leader × speed_var. Heading = direction of travel (smoothed).

**Formation slots.** Each non-leader member has a slot: an offset in the leader's local frame (x forward, y right), rotated by leader heading each tick. Formation is chosen by the terrain under the leader, with 1 s hysteresis:

- `COLUMN` (leader on ROAD): slots at (−1.2, 0), (−2.4, 0), (−3.6, 0), (−4.8, 0), (−6.0, 0).
- `WEDGE` (OPEN): (−1.5, +1.5), (−1.5, −1.5), (−3.0, +3.0), (−3.0, −3.0), (−3.0, 0).
- `CLUSTER` (FOREST, URBAN, DOOR, INTERIOR, RUBBLE): five fixed offsets within radius 1.5, e.g. (−1, 0.8), (−1, −0.8), (−1.8, 0.3), (−0.6, 1.4), (−1.6, −1.2).

**Member steering.** Target = leader position + rotated slot. If distance to target > 0.5 cell, move toward it at member speed (terrain under the *member*, not the leader — a wedge stretches crossing a treeline). Catch-up: if more than 2 cells from the slot, speed ×1.3. If the straight line to the slot crosses a solid cell for FOOT, request an A* path to the slot cell and follow it (repath at most once per second). Separation: if two members of any team are within 0.4 cell, push each apart along the connecting line by 0.1 cell per tick.

**Variance.** Outside combat, every member independently pauses 0.5–1.5 s at random intervals of 8–15 s.

**Combat movement** (any enemy contact visible to this squad within 20 cells of the leader):

- *Bounding overwatch.* Split into team A (leader + 2) and team B (3). The moving team advances along the path for `3 + Aggression` cells or 6 s, whichever first, then halts; the other team then moves. The halted team fires. Formation slots are still used, but only for the moving team.
- *Cover seeking.* A member that has been shot at within the last 2 s (a shot was resolved against it, hit or miss) picks the best passable, unoccupied cell within 3 cells: score = cover − 0.1·distance. It moves there and stays until `8 − Discipline` s pass without incoming fire, then rejoins its slot.

**Detached members.** A member more than 12 cells from the leader (e.g. a fresh respawn, or left behind when a vehicle drove off) is *detached*: it gets its own A* path to the leader's current position (repath every 2 s) and rejoins when within 3 cells.

---

## 7. Vehicles

### 7.1 Table

| Vehicle | class   | HP  | seats | speed (cells/s) | weapons |
|---------|---------|-----|-------|-----------------|---------|
| JEEP    | WHEELED | 150 | 4     | 5.0             | HMG |
| APC     | TRACKED | 400 | 6     | 3.0             | AUTOCANNON |
| TANK    | TRACKED | 800 | 2     | 2.5             | CANNON + HMG |

Weapons fire only when the vehicle has ≥ 2 occupants (driver + gunner). Vehicles path with their own movement class and turn instantly (no turn radius in v1); draw them with their heading.

### 7.2 Vehicle pads

Pads are placed by the map generator (Section 15) and belong to a flag or HQ. A pad spawns its vehicle type for the flag's owner when the flag is owned and no vehicle from this pad is alive; after the pad's vehicle is destroyed, the timer is 60 s. Spawned vehicles sit idle until a squad mounts them. If a flag changes owner while its pad vehicle is idle and unoccupied, the vehicle changes team.

### 7.3 Mount and dismount

- `MOUNT(vehicle)`: all living members path to the vehicle and board when within 1.0 cell, leader first. When seats are full, the remaining members continue **on foot toward the squad's current destination** (not toward the vehicle). A squad may own at most one vehicle at a time.
- While the leader is mounted, the vehicle receives the squad's movement orders and the leader's position is the vehicle's position. Unmounted members path to the squad destination on foot and become detached if they fall behind; this is intended — the squad stretches out.
- `DISMOUNT`: occupants are placed on the nearest passable FOOT cells within 1.5 cells; the vehicle becomes idle and unowned.
- Destruction: all occupants die. The wreck is removed (no obstacle). Award XP to the killing squad.
- The UI's `M` key mounts the nearest team-owned idle vehicle within 12 cells of the leader.

---

## 8. Weapons and combat

### 8.1 Weapon table

| Weapon      | range (cells) | interval (s) | dmg_inf | dmg_veh | splash (cells) | cover_ignore | wall_dmg |
|-------------|---------------|--------------|---------|---------|----------------|--------------|----------|
| RIFLE       | 12 | 1.0  | 25 | 2   | 0   | 0.0 | 0  |
| AT          | 10 | 6.0  | 40 | 120 | 1.0 | 0.3 | 30 |
| HMG         | 10 | 0.33 | 8  | 3   | 0   | 0.0 | 0  |
| AUTOCANNON  | 14 | 0.5  | 15 | 20  | 0   | 0.2 | 5  |
| CANNON      | 18 | 4.0  | 60 | 150 | 1.5 | 0.5 | 40 |
| ARTY_SHELL  | —  | —    | 80 | 60  | 1.5 | 0.5 | 50 |

### 8.2 Target selection

Each armed unit picks a target each tick if its weapon is ready:

- Candidates: enemy units visible to the shooter's team (Section 11) with LOS from the shooter (Section 4.5) and within range.
- RIFLE / HMG: nearest infantry, else nearest vehicle. AT: nearest vehicle if any in range, else nearest infantry. AUTOCANNON: nearest of either. CANNON: nearest vehicle, else nearest infantry; the tank's HMG independently targets infantry.
- A new contact for the shooter's squad triggers the Skill reaction delay before the first shot.

### 8.3 Hit resolution

For each shot:

```
p = 0.5 × accuracy_mult(shooter squad)
      × range_factor          # 1.0 within half range, linear to 0.5 at max range
      × (1 − cover_eff)       # cover_eff = target_cover × (1 − cover_ignore)
      × height_factor         # 1.15 if shooter elevation > target elevation, 0.9 if lower, else 1.0
      × move_factor           # infantry moving 0.7, stationary 1.0; vehicles always 0.8
```

- `target_cover` for infantry is the cover of the cell they stand in. For vehicles it is `terrain cover × 0.5`. Vehicles use `accuracy_mult` of the squad that occupies them.
- Roll with the sim RNG. On hit apply `dmg_inf` or `dmg_veh`.
- Splash weapons: the impact point is the target position on a hit, or a random point within 1 cell of the target on a miss. Every unit within the splash radius of the impact takes full damage (infantry `dmg_inf`, vehicles `dmg_veh`), friendly units included. WALL cells within the splash radius take `wall_dmg` (Section 9) on hit or miss.
- Members die at 0 HP (state DEAD, drawn faded for 10 s). Vehicles are destroyed at 0 HP.
- Healing: supply crates only (Section 12). No passive regen.

### 8.4 Sanity expectations (used as tests)

On flat OPEN ground with LOS, stats 3/3/3/3, no vehicles: 6 riflemen vs 3 riflemen → the 6 win with ≥ 3 survivors in at least 9 of 10 seeded runs. 6 riflemen in INTERIOR vs 6 attacking across OPEN → defenders win at least 8 of 10. A tank vs 6 riflemen with one AT in the open → tank wins at least 7 of 10; the same squad in INTERIOR with the tank at 8 cells → the tank loses at least 5 of 10 (AT gets several shots from cover). If these don't hold, tune `balance.gd` and record the change.

---

## 9. Buildings and destruction

- At map load, flood-fill connected WALL/DOOR/INTERIOR cells into buildings; assign `building_id` and remember each building's original wall count.
- WALL cells start at `wall_hp = 100`. Any `wall_dmg` (Section 8.3) subtracts from it. At ≤ 0 the cell becomes RUBBLE; elevation is unchanged.
- **Collapse:** when more than 50% of a building's original WALL cells are RUBBLE, the building collapses: all its remaining WALL, DOOR and INTERIOR cells become RUBBLE, and every member standing in one of its INTERIOR cells takes 50 damage.
- On any cell change: update pathfinder solids for all classes, mark the terrain layer for redraw, and note that LOS now uses the new `blocker`.
- There is no way to target a wall directly in v1; walls are damaged incidentally by splash weapons and by artillery. Artillery is the intended demolition tool.

---

## 10. Spawning

### 10.1 Policy interface

Spawning is behind an interface so that a second mode (Phase 2, Section 19) can be added without touching squads, flags or combat.

```gdscript
class_name SpawnPolicy
func get_spawn_points(team: int) -> Array[Vector2i]        # cells a team may spawn at right now
func request_member_respawn(member) -> void                # called when a member dies
func request_squad_respawn(squad) -> void                  # called when the 6th member dies
func set_preferred_spawn(squad, cell: Vector2i) -> void    # commander choice
func tick(dt: float) -> void                               # advance timers, perform spawns
```

### 10.2 Conquest policy (v1)

- Spawn points: centres of flags and the HQ owned by the team.
- **Member respawn:** 15 s after death, the member reappears at the owned spawn point nearest to the squad leader (or nearest to the squad's last order target if the leader is dead), costs 1 ticket, and walks to rejoin as a detached member (Section 6.5). If the team owns no spawn point, the member waits and respawns as soon as one is owned.
- **Squad respawn:** when all six are dead, cancel pending member respawns; 20 s later respawn all six together at the squad's preferred spawn point (default: owned point nearest the last order target). Costs 6 tickets. The squad card shows a spawn-point selector while the squad is fully dead.
- Vehicles spawn from pads only (Section 7.2), or via the vehicle drop asset.

---

## 11. Fog of war and intel

- **Vision.** Each team sees a cell when a living unit of that team has LOS to it (Section 4.5) within spot range: infantry 14 cells, vehicles 16 cells. Targets standing in FOREST or INTERIOR are only spotted within 6 cells unless they fired in the last 3 s.
- **Muzzle flash.** A unit that fires is revealed to any enemy unit with LOS within 20 cells for 3 s, ignoring the FOREST/INTERIOR reduction.
- **Vehicles are loud:** spotted at 16 cells regardless of terrain.
- **Contacts.** When a squad sees an enemy unit, it creates or refreshes a contact for its team. For the player's map, a contact spotted by a squad becomes visible after that squad's Comms delay and fades `4 + 2·Comms` s after last seen (Section 6.2). If multiple squads see the same unit, use the best delay. UAV contacts are immediate and live.
- **Fog rendering.** Never seen: dark overlay. Seen before, not now: dim, terrain visible, no units. Currently seen: normal. Elevation and buildings are always drawn (it's a map), only the dimming changes.
- **RED does not cheat.** The AI commander only knows RED's contacts, computed with Comms 3 delays.

---

## 12. Commander assets

Both commanders have the same four assets. Use: select the asset (button or hotkey), click a map cell. Assets can be targeted anywhere on the map.

| Asset        | Effect | Radius | Duration | Cooldown | Arrival delay |
|--------------|--------|--------|----------|----------|---------------|
| UAV          | Reveals all enemy units within the radius as live contacts | 12 | 30 s | 90 s | 3 s |
| ARTILLERY    | 6 ARTY_SHELL impacts, one per second, each at a random point within the radius | 4 | 6 s | 120 s | 5 s |
| SUPPLY DROP  | A crate. Friendly members within 3 cells heal 10 HP/s and get `accuracy_mult +0.3` while the crate exists | 3 | 60 s | 90 s | 8 s |
| VEHICLE DROP | Spawns a team JEEP at the nearest WHEELED-passable cell to the target | — | — | 180 s | 8 s |

The supply drop is the deliberate equaliser: a Skill-1 squad on a crate shoots like a Skill-3 squad. Cooldown starts when the asset is used, not when it lands.

---

## 13. Enemy commander AI

`commander_ai.gd` takes a team id and works for either side, so the headless sim can run AI vs AI. It runs every 5 s of sim time. Definitions: a squad is *idle* if it has no order or its order is completed; *visible defenders* of a flag are enemy contacts within 6 cells of it.

Rules, evaluated in order each AI tick:

1. **Defend.** For each own flag with enemy contacts within 6 cells and no own squad within 6 cells: send the nearest squad that is not currently capturing a flag to `DEFEND` it.
2. **Attack.** For each idle squad: choose the flag maximising `value / (distance + 5)` where value is 3 for NONE, 4 for enemy-owned with ≤ 3 visible defenders, 2 for enemy-owned with more, 0 for own. Do not send more than 2 squads to the same flag unless it's the only non-own flag. Order `ATTACK`.
3. **Desperation.** If own tickets < enemy tickets − 30 and own team is bleeding: every idle squad attacks its nearest non-own flag, ignoring the 2-per-flag cap.
4. **Artillery.** If ready: find the largest cluster of ≥ 3 enemy contacts (or any enemy vehicle contact) within a 4-cell radius that contains no own units within 5 cells; fire there.
5. **UAV.** If ready: centre it on the flag the next `ATTACK` order targets, or on the own flag with the most enemy contacts nearby.
6. **Supply.** If ready: drop on the own squad currently in combat with the lowest average HP.
7. **Vehicle drop.** If ready and the team has no living JEEP: drop at the HQ.
8. **Vehicles.** When a squad receives an `ATTACK`/`DEFEND` order and the destination is > 15 cells away and an idle own vehicle is within 8 cells, issue `MOUNT` first; the movement order applies once mounted. Dismount automatically when the vehicle is within 4 cells of the destination.

Keep each rule a separate function so they can be tuned or disabled individually.

---

## 14. UI and controls

**Camera.** WASD or arrow keys pan; middle-mouse drag pans; scroll wheel zooms 0.5×–2×; edges of the map clamp.

**Top bar.** BLUE tickets, RED tickets, five flag icons A–E coloured by owner with a thin progress arc, match clock, sim speed indicator. Keys: `SPACE` pause, `-` / `=` speed down/up (1×, 2×, 4×).

**Left panel: squad cards** (Alpha–Delta). Each card: name, stats as `S D A C` with values, six member dots (alive/dead), average HP bar, XP bar, current order text, vehicle name if mounted, and, while fully dead, a spawn-point selector. Click a card or press `1`–`4` to select; `Shift`-click adds to a multi-selection.

**Map interaction with squads selected.**
- Right-click a cell → `MOVE`. Right-click within a flag radius → `ATTACK` if the flag is not own, `DEFEND` if own.
- `A` then left-click → `ATTACK`/`MOVE` (attack-move to a cell counts as MOVE with Aggression behaviour). `D` then left-click → `DEFEND` (nearest flag to the click). `M` → mount nearest vehicle (Section 7.3). `X` → dismount. `H` → hold. `ESC` cancels a pending mode.
- Left-click an own vehicle with a squad selected → `MOUNT` that vehicle.

**Bottom bar: assets.** Four buttons with a radial cooldown and hotkeys `Q` UAV, `W` artillery, `E` supply, `R` vehicle drop. Press, then left-click the map; a ghost circle shows the radius before confirming.

**Tooltip.** Hovering a cell shows terrain, elevation, cover and, if a building, wall HP. Hovering a unit shows squad, kit, HP.

**Drawing.** Terrain colours: ROAD light grey, OPEN olive, FOREST dark green, URBAN tan, WATER blue, WALL dark grey, DOOR brown, INTERIOR beige, RUBBLE mid-grey with a hatch. Elevation: brightness +8% per level plus thin contour lines where elevation changes between neighbours. Flags: 4-cell radius circle outline, letter, progress arc in owner colour. HQ: square. Members: 5 px circles in team colour (BLUE `#3a7bd5`, RED `#d5473a`), leader with a white ring, AT with a dark centre dot, dead faded for 10 s. Vehicles: rectangles JEEP 20×12, APC 28×16, TANK 32×18 px with a heading tick. Enemy contacts drawn with age-based fade. UAV: dashed circle. Artillery: expanding ring per impact. Supply crate: green square with a radius ring.

**Screens.** Main menu: `Play` (seed field, default random), `Watch AI vs AI`, `Quit`. End screen: winner, final tickets, per-squad kills/deaths, `Play again`, `Menu`.

---

## 15. Map generator

Deterministic from a seed. Generate the **west half** (x < 48) and mirror it to the east so the map is symmetric and balance tests are fair. Use `FastNoiseLite` seeded from the sim RNG.

1. **Heightmap.** Sum three low-frequency noise octaves, normalise, quantise to 0–5. Add a north–south ridge centred on x = 48 (height 3–4, ~6 cells wide) with a 6-cell gap at the town. Smooth so that no neighbouring cells differ by ≥ 3 except along intentionally placed cliff lines (≤ 5% of edges). Flatten the town area to a single elevation.
2. **River.** A river (WATER, 2–3 cells wide) running north–south around x ≈ 22, with two ROAD bridges (one north, one south).
3. **Roads.** A main road from BLUE HQ through A, C and the bridges toward the east; secondary roads HQ→B and B→C. Roads set their elevation to the average of their neighbours (gentle grades) and are 1 cell wide.
4. **Forest.** Noise-threshold patches covering ~25% of non-road land, none within 3 cells of a flag centre or the town.
5. **Town.** Around C: an area of URBAN cells roughly 20×14 with a small street grid, containing 8–12 buildings. Each building is a rectangle 4×4 to 8×6: WALL perimeter, INTERIOR inside, 1–2 DOOR cells on the perimeter facing a street. Buildings do not touch each other.
6. **Flags and HQs.** BLUE HQ (6, 32); A (20, 16); B (20, 48); C (48, 32); D and E are the mirrors of A and B; RED HQ mirrors BLUE HQ. Flag centres must be passable FOOT cells on flat ground (clamp elevation within radius 4 to a single value).
7. **Vehicle pads.** HQs: one JEEP pad and one APC pad. A, B, D, E: one JEEP pad each. C: one TANK pad. Pads are placed on a passable cell within 3 cells of the flag centre for the vehicle's class.
8. **Validation.** After generation assert that: every flag and HQ is FOOT-reachable from both HQs; every pad is reachable by its vehicle class from its flag; the town has at least 8 buildings. Regenerate with `seed + 1` on failure (log it).

---

## 16. Simulation architecture

- `Sim.step(dt)` runs, in order: order execution (Discipline delays) → movement (leaders, vehicles, members, detached) → spotting and contacts → combat (target selection, shots, splash, wall damage, deaths) → buildings (rubble, collapse) → flag capture → tickets → spawn policy tick → assets → commander AI (every 5 s) → victory check.
- `World` is plain data plus these systems; rendering nodes only read it. Keep `World` free of Node dependencies so it runs headless.
- `Sim` exposes `time_scale` (1, 2, 4), `paused`, and `seed`.
- **Headless runner:** `godot --headless --script res://sim/run_headless.gd -- --matches 10 --seed 1`. Runs AI vs AI (`commander_ai.gd` for both teams, BLUE with rolled stats, RED uniform) at maximum speed, prints one line per match (winner, tickets, duration, kills, assets used, walls destroyed) and a summary (BLUE win rate, average duration). Exit code 0 unless an exception occurs.

---

## 17. Tests

`tests/run_tests.gd` is a plain script: it instantiates each `tests/test_*.gd`, calls every method starting with `test_`, counts passes and failures using simple `check(cond, message)` helpers, prints a summary and exits with code 1 on any failure. Run with `godot --headless --script res://tests/run_tests.gd`.

Required tests:

1. Terrain table: speed and impassability per class for every terrain.
2. Slope cost and cliff rules for all three classes.
3. Pathfinding: a FOOT path around WATER; a WHEELED path prefers ROAD over shorter OPEN; a TRACKED path refuses to enter INTERIOR; a path updates when a WALL becomes RUBBLE.
4. LOS: the three worked checks in Section 4.5, plus rubble opening a sightline.
5. Capture: one soldier flips a neutral flag in 20 s; three do it in ~7 s; contested flags do not move; neutralisation crossing 0.
6. Tickets: bleed timing; respawn costs; victory conditions including the 20-minute rule.
7. Squad stat rolling: 1000 rolls all sum to 12 with each stat in [1,5].
8. Order delay equals `6 − Discipline`.
9. Formation: members reach their slots within 5 s on open ground; formation switches to COLUMN on a road.
10. Combat sanity expectations of Section 8.4 (seeded).
11. Buildings: flood fill counts, rubble at 0 HP, collapse at >50%, collapse damage to occupants.
12. Spawn policy: member respawn location and cost; squad respawn after wipe; no spawn when nothing is owned.
13. Fog: a unit in FOREST is unseen at 8 cells and seen at 5; firing reveals it at 15.
14. Assets: cooldown and arrival timing; artillery damages walls; supply heals and boosts accuracy.
15. Map generator: validation rules pass for seeds 1–20; the map is mirror-symmetric in terrain and elevation.
16. Headless sim: 3 matches with seeds 1–3 complete without error and each ends with a winner or a draw.

---

## 18. Milestones

Complete in order. Each milestone lists what must be true at the end ("Done when"). Keep `PROGRESS.md` current.

**M0 — Skeleton.** Project, autoloads, `balance.gd`, main menu → game scene, camera, empty test runner. *Done when:* the project launches, the menu opens an empty map view with a pannable camera, and `run_tests.gd` runs and reports 0 tests.

**M1 — Grid, terrain, elevation, pathfinding, LOS, generator.** Sections 4 and 15. Terrain layer draws the generated map with elevation shading and contours; tooltip works. *Done when:* tests 1–4 and 15 pass; a debug key (`F1`) draws a path from BLUE HQ to RED HQ for each movement class.

**M2 — Squads and movement.** Sections 6.1, 6.2, 6.4, 6.5 (excluding combat movement). Squad cards, selection, MOVE orders, formations, variance, detached members. *Done when:* tests 7–9 pass; four squads can be moved around the map and visibly change formation on roads and in forest.

**M3 — Flags, tickets, victory, Conquest spawning.** Sections 5 and 10. *Done when:* tests 5, 6, 12 pass; a match against an idle RED can be won by capturing flags and waiting for bleed; the end screen shows.

**M4 — Combat.** Sections 8, 6.3 (veterancy), combat movement in 6.5. Effects layer for shots and deaths. *Done when:* test 10 passes; two squads ordered at each other fight, bound, take cover, and one loses.

**M5 — Vehicles.** Section 7. *Done when:* a squad can mount a jeep at HQ, drive to a flag with the last two members jogging behind, dismount and capture; a tank fights infantry per Section 8.4.

**M6 — Destruction.** Section 9. *Done when:* test 11 passes; artillery (temporarily bound to a debug key `F2` before M8) turns walls to rubble and collapses a building, and squads path through the gap.

**M7 — Fog and intel.** Section 11. *Done when:* test 13 passes; contacts appear with Comms delay and fade; fog renders three states.

**M8 — Assets.** Section 12 and the asset bar. *Done when:* test 14 passes; all four assets work from the UI with cooldowns and arrival delays.

**M9 — Commander AI.** Section 13. *Done when:* RED captures flags, defends them, uses all four assets and mounts vehicles; the player can lose.

**M10 — Headless sim, balance, polish.** Section 16 runner, `Watch AI vs AI` menu option, test 16, balance pass. *Done when:* 10 AI-vs-AI matches with seeds 1–10 complete without errors, BLUE win rate is between 30% and 70% (RED is uniform 3s, BLUE is rolled, so exact parity is not expected), average match length is 8–18 minutes of sim time, and `PROGRESS.md` documents results and any `balance.gd` changes.

Only after M10 is complete and committed, and if time remains, start Section 19 in the order given.

---

## 19. Phase 2 backlog (only after M10)

1. **Broken Arrow spawn mode.** A second `SpawnPolicy`. Reinforcement points per team: income `10/min + 2/min per owned flag` (the flag bonus roughly pays for the longer walk to a forward front), starting balance 100. Costs: rifle squad 50, JEEP 20, APC 60, TANK 120. Entry points: 3 per team on their map edge (north, centre, south), defined by the generator. No respawns: dead members stay dead; a wiped squad is gone; new squads are bought and enter at a chosen entry point. Flags still bleed tickets as in Conquest; ticket loss on death is replaced by the cost of replacement. UI: a purchase panel replacing the spawn-point selector. Mode chosen on the main menu.
2. **RED stat variance.** Roll RED squads like BLUE; expose a menu toggle.
3. **Hidden stats.** Player squad stats start hidden and are revealed after N observed events (an order executed → Discipline, a firefight → Skill, etc.).
4. **Hybrid mode.** Broken Arrow entry plus owned flags as forward entry points.
5. **Suppression, medics, helicopters, air.** In that order.

---

## 20. `balance.gd` contents

Every constant referenced above, grouped and named. At minimum:

```
CELL_PX=32, MAP_W=96, MAP_H=64, TICK=0.1
MATCH_LENGTH_S=1200, START_TICKETS=200, BLEED_INTERVAL_S=3, RESPAWN_TICKET_COST=1
FLAG_RADIUS=4, CAPTURE_TIME_S=20, CAPTURE_MAX_COUNT=3
TERRAIN table (Section 4.2), SLOPE multipliers and CLIFF thresholds (4.3)
EYE_FOOT=1.5, EYE_INTERIOR=2.5, EYE_VEHICLE=1.5, LOS_EPS=0.01
MEMBER_HP=100, MEMBER_BASE_SPEED=2.0, SPEED_VAR=[0.9,1.1], CATCHUP_MULT=1.3, SLOT_TOLERANCE=0.5
FORMATIONS (6.5), PAUSE_INTERVAL=[8,15], PAUSE_LEN=[0.5,1.5], DETACH_DIST=12, REJOIN_DIST=3
STAT_SUM=12, ACCURACY_BASE=0.7, ACCURACY_PER_SKILL=0.15, REACTION_BASE=2.0, REACTION_PER_SKILL=0.3
ORDER_DELAY_BASE=6, COVER_RESUME_BASE=8, BOUND_BASE=3, BOUND_MAX_S=6, PURSUE_DIST=8
XP_KILL=10, XP_VEHICLE=30, XP_CAPTURE=20, XP_THRESHOLDS=[100,250]
VEHICLES table (7.1), PAD_RESPAWN_S=60, MOUNT_DIST=1.0, MOUNT_SEARCH_DIST=12
WEAPONS table (8.1), HIT_BASE=0.5, RANGE_MIN_FACTOR=0.5, HEIGHT_UP=1.15, HEIGHT_DOWN=0.9, MOVE_INF=0.7, MOVE_VEH=0.8, VEHICLE_COVER_MULT=0.5, MISS_SCATTER=1.0
WALL_HP=100, COLLAPSE_FRACTION=0.5, COLLAPSE_DAMAGE=50
MEMBER_RESPAWN_S=15, SQUAD_RESPAWN_S=20
SPOT_INF=14, SPOT_VEH=16, SPOT_CONCEALED=6, FLASH_RANGE=20, FLASH_S=3, COMMS_DELAY_BASE=6, COMMS_PERSIST_BASE=4, COMMS_PERSIST_PER=2
ASSETS table (Section 12), SUPPLY_HEAL_PER_S=10, SUPPLY_ACCURACY_BONUS=0.3
AI_TICK_S=5, AI_DEFEND_RADIUS=6, AI_MAX_PER_FLAG=2, AI_DESPERATION_MARGIN=30, AI_ARTY_MIN_CLUSTER=3, AI_ARTY_SAFE_DIST=5, AI_MOUNT_MIN_DIST=15, AI_MOUNT_SEARCH=8, AI_DISMOUNT_DIST=4
```

---

*End of spec.*
