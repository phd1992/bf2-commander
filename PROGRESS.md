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

# headless AI vs AI (from M10)
godot --headless --script res://sim/run_headless.gd -- --matches 10 --seed 1
```

`godot` is any Godot 4.4+ stable Linux editor binary on PATH (the tests were run with 4.4.1).

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
- [ ] M10 — Headless sim, balance, polish.

## Balance changes from the spec's starting values

Made while getting the Section 8.4 sanity expectations to hold (test 10). All in `scripts/config/balance.gd`.

| Constant | Spec | Now | Why |
|---|---|---|---|
| `MISS_SCATTER` | 1.0 | 3.0 | With a 1-cell scatter every missed cannon/AT shell still landed inside its own splash radius, so cover never mattered against splash weapons. |
| AT `range` / `interval` / `dmg_veh` | 10 / 6 s / 120 | 12 / 4 s / 270 | Three rockets kill a tank; the AT gets meaningful shots from cover before the tank's cannon works through the squad. |
| CANNON `cover_ignore` / `interval` | 0.5 / 4 s | 0.3 / 5 s | Interior cover now actually protects infantry from tank fire. |
| HMG `interval` | 0.33 s | 0.4 s | Slightly less HMG attrition on covered infantry. |

Results with these values (10 seeded runs each): 6v3 riflemen 10/10, interior defenders 10/10, tank in the open 10/10, tank vs interior squad loses 7/10.

## Known issues

- Godot prints "ObjectDB instances leaked at exit" after the tests: squads and members reference each other (RefCounted cycles) and are not torn down explicitly. Harmless for a game process; noted here so nobody chases it.

## Next

- M10.
