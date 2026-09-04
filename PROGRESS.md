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
- [ ] M3 — Flags, tickets, victory, Conquest spawning.
- [ ] M4 — Combat.
- [ ] M5 — Vehicles.
- [ ] M6 — Destruction.
- [ ] M7 — Fog and intel.
- [ ] M8 — Assets.
- [ ] M9 — Commander AI.
- [ ] M10 — Headless sim, balance, polish.

## Known issues

- Godot prints "ObjectDB instances leaked at exit" after the tests: squads and members reference each other (RefCounted cycles) and are not torn down explicitly. Harmless for a game process; noted here so nobody chases it.

## Next

- M3.
