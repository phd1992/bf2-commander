# Progress

## Commands

```
# one-time (and after adding any new class_name script): build the script class cache
godot --headless --import

# run the game
godot                                # or: godot --path .

# run the tests
godot --headless --script res://tests/run_tests.gd
godot --headless --script res://tests/run_tests.gd -- --filter=los   # subset

# headless AI vs AI (from M10); add --mode broken-arrow and/or --red-rolled
godot --headless --script res://sim/run_headless.gd -- --matches 10 --seed 1

# start a match straight away for testing (after --):
godot -- --autoplay [--ai] [--broken-arrow] [--red-rolled] [--seed=N] [--speed=4] [--screenshot=/path.png --shot-after=5 --quit-after-s=6]
```

`godot` is any Godot 4.4+ stable Linux editor binary on PATH (the tests were run with 4.4.1).

## UX pass (after the first browser playtest)

Bottom-right context help panel (what each mouse button and key does right now), click and box selection of squads on the map, right-click to board vehicles, pulsing labels on empty own vehicles and pads, order pings and Discipline countdowns on the cards, and the jeep/APC arrival rule (troops out, driver + gunner stay; tanks stay crewed). Verified in headless Chromium by scripting drag-select → board jeep → attack A.

## Web build

`export_presets.cfg` has a "Web" preset (GL Compatibility, thread support off). `godot --headless --export-release Web build/web/index.html` produces a ~44 MB build that was verified to load and run in headless Chromium with no console errors. `.github/workflows/web.yml` builds and deploys it to GitHub Pages on push (enable Pages with source "GitHub Actions" once).

## Milestones

- [x] M0 — Skeleton: project, autoload `Sim`, `balance.gd`, menu → game scene, camera, empty test runner.
- [x] M1 — Grid, terrain, elevation, pathfinding, LOS, generator (tests 1–4, 15; `F1` draws HQ-to-HQ paths per class).
- [x] M2 — Squads and movement (tests 7–9; squad cards, selection, MOVE orders, formations, variance, detached members).
- [x] M3 — Flags, tickets, victory, Conquest spawning (tests 5, 6, 12; end screen).
- [x] M4 — Combat (test 10; spotting, targeting, hit rolls, splash, veterancy, cover seeking, bounding, effects layer).
- [x] M5 — Vehicles (pads, mount/dismount with overflow on foot, driving, vehicle weapons, side change on capture; `M` mounts nearest, `X` dismounts, left-click an own vehicle to mount).
- [x] M6 — Destruction (test 11; walls to rubble, collapse with occupant damage, pathfinder and LOS follow; `F2` = free debug artillery at the mouse).
- [x] M7 — Fog and intel (test 13; spotting with concealment and muzzle flash, Comms-delayed contacts that fade, three-state fog overlay).
- [x] M8 — Assets (test 14; UAV, artillery, supply drop, vehicle drop with cooldowns and arrival delays; asset bar with `Q/W/E/R`, ghost circle before confirming).
- [x] M9 — Commander AI (rule-based, per-rule switches; RED captures, defends, mounts vehicles and uses all four assets; the player can lose).
- [x] M10 — Headless sim, balance, polish (test 16, `Watch AI vs AI`, wrapper scripts, README, determinism replay test).

Phase 2 (Section 19):

- [x] 19.1 Broken Arrow spawn mode: reinforcement points (10/min + 2/min per flag, start 100), squads 50 / jeep 20 / APC 60 / tank 120, three map-edge entry points per team from the generator, no respawns, purchase panel on the squad panel, AI buys squads back and armour, mode chosen on the main menu (`--broken-arrow` for autoplay, `--mode broken-arrow` headless).
- [x] 19.2 RED stat variance: menu checkbox (`--red-rolled` on the command line / headless).
- [x] 19.3 Hidden stats: menu checkbox / `--hidden-stats`; Skill shows after 20 squad shots, Discipline after 2 executed orders, Comms after 3 contact reports, Aggression after reaching an objective in combat (thresholds in balance.gd).
- [x] 19.4 Hybrid mode: Broken Arrow plus owned flags as forward entries (`--hybrid`, `--mode hybrid`).
- [ ] 19.5 Suppression, medics, helicopters, air.

## Balance changes from the spec's starting values

Made while getting the Section 8.4 sanity expectations to hold (test 10). All in `scripts/config/balance.gd`.

| Constant | Spec | Now | Why |
|---|---|---|---|
| `MISS_SCATTER` | 1.0 | 3.0 | With a 1-cell scatter every missed cannon/AT shell still landed inside its own splash radius, so cover never mattered against splash weapons. |
| AT `range` / `interval` / `dmg_veh` | 10 / 6 s / 120 | 12 / 4 s / 270 | Three rockets kill a tank; the AT gets meaningful shots from cover before the tank's cannon works through the squad. |
| CANNON `cover_ignore` / `interval` | 0.5 / 4 s | 0.3 / 5 s | Interior cover now actually protects infantry from tank fire. |
| HMG `interval` | 0.33 s | 0.4 s | Slightly less HMG attrition on covered infantry. |
| `START_TICKETS` | 200 | 300 | AI-vs-AI matches averaged 7.1 min (target 8–18); respawn costs, not bleed, drain tickets. |

Results with these values (10 seeded runs each): 6v3 riflemen 10/10, interior defenders 10/10, tank in the open 10/10, tank vs interior squad loses 7/10.

## Known issues

- Deep interior cells cannot see out of a building (the spec's LOS rule blocks any sight line whose midpoint crosses a wall), so only soldiers on cells adjacent to the outer wall fight from inside; DEFEND picks cover by score and may park some members in the back.
- The test suite takes ~80 s because test 16 plays three full AI-vs-AI matches plus a determinism replay; use `--filter=` for quick runs.

- Godot prints "ObjectDB instances leaked at exit" after the tests: squads and members reference each other (RefCounted cycles) and are not torn down explicitly. Harmless for a game process; noted here so nobody chases it.

## AI vs AI results (M10, seeds 1–10, `./run_sim.sh --matches 10 --seed 1`)

| seed | winner | tickets B/R | length | kills B/R | assets | walls |
|---|---|---|---|---|---|---|
| 1 | RED | 0 / 239 | 8.0 min | 57 / 144 | 26 | 17 |
| 2 | BLUE | 119 / 0 | 10.3 min | 159 / 128 | 40 | 20 |
| 3 | RED | 0 / 122 | 10.2 min | 116 / 157 | 41 | 28 |
| 4 | BLUE | 66 / 0 | 10.8 min | 173 / 160 | 44 | 8 |
| 5 | RED | 0 / 74 | 10.4 min | 119 / 211 | 39 | 34 |
| 6 | RED | 0 / 44 | 11.6 min | 180 / 169 | 46 | 15 |
| 7 | RED | 0 / 105 | 10.5 min | 150 / 157 | 39 | 23 |
| 8 | BLUE | 159 / 0 | 9.2 min | 187 / 113 | 37 | 26 |
| 9 | BLUE | 147 / 0 | 10.2 min | 159 / 126 | 40 | 25 |
| 10 | BLUE | 116 / 0 | 9.7 min | 194 / 120 | 37 | 25 |

BLUE win rate 50% (5/10, no draws), average duration 10.1 min, no errors. All ten matches ended on tickets; the 20-minute clock was never reached. Each match takes 11–20 s of wall time headless.

Before the last balance change (START_TICKETS 200) the win rate was also 50% but matches averaged 7.1 min, below the 8–18 min target: with ~100 deaths per side per match the respawn cost dominates the ticket drain. Raising the starting tickets to 300 (see the table above) lengthens matches proportionally without touching the win rate.

Broken Arrow AI vs AI (seeds 1–4): all complete, RED 3 / BLUE 1, 15.9–20.0 min (one match reached the clock), ~35 kills per side. No balance target is set for this mode in the spec; it is bleed-driven and slower by design.

## Next

- Phase 2 backlog: 19.5 suppression, medics, helicopters, air (in that order). These add new unit and effect types and are best planned by a human before implementing.
- Possible polish: DEFEND cover choice could prefer interior cells adjacent to a wall ("windows"), since deep interior cells cannot see out under the LOS rule; a minimap; hover highlight of formation slots.
