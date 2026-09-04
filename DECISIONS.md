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
- Simulation clock is `tick_count * TICK` rather than accumulated floats, so timers that must fire at exactly N seconds (order delays, respawns, bleed) are not off by one tick from float drift.
- The squad leader marches at the pace of the squad's slowest member (min speed_var) so formations hold on the move; individual variance still applies to everyone else.
- Under a HOLD order (and any other order) detached members still walk back and rejoin before taking cover; the spec only says HOLD stops the squad, not its stragglers.
- A test method that records no checks is counted as a failure by the runner: a GDScript runtime error aborts the method silently and would otherwise pass.
- Squad respawn with fewer than 6 tickets left revives as many members as the team can pay for instead of waiting forever.
- Flag capture XP (+20) goes to every squad of the capturing team with at least one member inside the radius at the moment the capture completes.
- Splash on a miss: the missed primary target is excluded from its own miss splash (otherwise a miss with 1-cell scatter was identical to a hit); other units near the impact still take full damage.
- AT kit: the launcher only engages vehicles; when no vehicle is in range the AT soldier uses the rifle on infantry (Section 6.1's wording over Section 8.2's "else nearest infantry"), so rockets are not wasted on riflemen.
- "Visible to the shooter's team" for targeting means units spotted by any unit of that team this tick (raw vision), not the Comms-delayed commander contacts; the commander map delay is an intel-reporting effect, not a targeting one.
- Section 8.4's "squad in INTERIOR" scenario places the soldiers on interior cells adjacent to the wall facing the tank: with the spec's LOS rule a wall at the midpoint of the sight line blocks it, so only "window" cells can shoot out at 8 cells.
- Artillery kills are credited to nobody (no XP); vehicle-destruction XP (+30) is awarded on top of +10 per occupant killed.
- Vehicles are treated as loud (spotted at 16 cells) even by infantry spotters whose normal spot range is 14.
- Empty enemy vehicles are valid targets (an AT soldier will destroy an abandoned enemy jeep rather than wait to capture it with the flag); the side-change rule only matters if the vehicle survives.
- A pad vehicle whose flag is neutralised keeps its old team until the other team completes the capture.
- The camera starts over the player's HQ, offset so the squad panel does not cover it.
- AI idle detection: a squad with a DEFEND order counts as idle for the attack rule once no enemy contacts remain within 6 cells of its flag (DEFEND never completes on its own, so without this the AI would park squads forever). A squad with a pending (not yet executed) order is never idle.
- AI with every flag owned: idle squads DEFEND the own flag nearest the enemy HQ with the fewest defenders (the spec's attack rule has nothing to send them to).
- AI mount rule: the follow-on ATTACK/DEFEND order is stored with the MOUNT order and applied the moment the squad is aboard (or the seats are full); auto-dismount happens at the start of the AI tick when the vehicle is within 4 cells of the destination.
- AI UAV targeting uses the flag of the most recently issued ATTACK order while that flag is still not owned; otherwise the own flag with the most contacts nearby.
- AI artillery clusters are evaluated with each contact as a candidate centre; a vehicle contact counts as a full cluster.
- Broken Arrow squads: a purchase brings a wiped squad slot back (same name, new rolled stats, no XP) rather than adding a fifth squad, so a team never has more than four squads and the squad panel, AI and end screen stay the same.
- Broken Arrow entry points sit one cell in from the map edge at rows 8, 32 and 55 (nearest passable cell), RED mirrored; vehicles bought there appear on the nearest cell passable for their class.
- Broken Arrow ticket rule: since Conquest charges tickets at respawn time and Broken Arrow never respawns, deaths cost nothing automatically; bleed is unchanged.
- The Broken Arrow AI buys wiped squads back at the entry nearest the closest non-own flag, and keeps one tank then up to two APCs while it can still afford a squad on top.
- Hidden stats reveal events: the spec names two examples (order executed → Discipline, firefight → Skill); Comms is revealed after the squad has produced three contact reports and Aggression after it reaches an objective while in contact. Hidden stats only mask the display; the simulation always uses the real values. Off in AI-vs-AI mode.
