# Decisions

One line per ambiguity: what was ambiguous, what was chosen, why.

- Headless class_name resolution: Godot only resolves `class_name` scripts under `--script` after the project has been imported once, so `godot --headless --import` is a documented one-time step (wrapped in `run_tests.sh` / `run_sim.sh`). Autoloads are not instantiated under `--script`, which is fine because `World` never touches `Sim`.
- Variant inference warnings are errors in Godot 4.4's default project config; the code uses explicit types where a value is Variant instead of relaxing the warning, so the project stays clean with default settings.
- River position: spec says x ≈ 22, but flag A/B at x = 20 have a radius-4 capture circle reaching x = 24; the river is centred at x ≈ 27 (cells 25–29) so no capture zone overlaps water.
- Town size: the spec's "roughly 20×14" became 24×15 (x 36–59, y 25–39) so each block fits two buildings side by side; 4 buildings per half, 8 total, mirrored around a central north–south street at x = 47/48 so no mirrored buildings touch.
- Buildings are placed flush against the main east–west street (y = 32) so every door opens onto a street cell.
- Roads are drawn as 4-connected lines (a diagonal Bresenham step also fills the orthogonal cell) so wheeled vehicles never need a diagonal squeeze between two obstacles.
- Smoothing of elevation locks town and flag areas; cliffs are removed by moving the *unlocked* cell of a pair, so flats stay flat.
- Forest keeps a 1-cell clearance from roads and water (spec only demanded 3 cells from flags and the town) so road corners stay open for wheeled traffic.
