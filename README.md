# Commander

A single-player, top-down 2D game in the style of Battlefield 2's Commander
Mode, built in Godot 4 (GDScript only, no external assets). You command BLUE;
a rule-based AI commands RED. Squads of soldiers and ground vehicles fight over
five flags on a symmetric generated map with elevation, line of sight, fog of
war and destructible buildings.

- `docs/COMMANDER_SPEC.md` — the build specification this implements.
- `PROGRESS.md` — milestone status, exact commands, balance results, known issues.
- `DECISIONS.md` — every ambiguity in the spec and the choice made.
- `scripts/config/balance.gd` — every tunable number.

## Quick start

```
godot --headless --import      # once, builds the script class cache
godot                          # play (menu -> Play / Watch AI vs AI)
./run_tests.sh                 # tests
./run_sim.sh --matches 10      # headless AI vs AI batch
```

Requires a Godot 4.4+ standard editor binary on `PATH` as `godot` (or set
`GODOT=/path/to/godot`).

## Controls

WASD / arrows / middle-drag pan, wheel zooms. `1`–`4` select squads (`Shift`
adds), right-click orders MOVE / ATTACK / DEFEND, `A` + click attack-move, `D` +
click defend nearest flag, `M` mount nearest vehicle, `X` dismount, `H` hold,
`Q`/`W`/`E`/`R` then click for UAV / artillery / supply / vehicle drop, `SPACE`
pauses, `-`/`=` change speed, `F1` draws HQ-to-HQ paths, `F2` fires free debug
artillery at the mouse.
