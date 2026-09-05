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

Modes: Conquest (respawn at owned flags, the v1 mode), Broken Arrow (buy
reinforcements that enter at the map edge) and Hybrid (Broken Arrow plus owned
flags as forward entries). Both are chosen on the main menu,
which also has a toggle for RED squads rolling stats like BLUE.

Requires a Godot 4.4+ standard editor binary on `PATH` as `godot` (or set
`GODOT=/path/to/godot`).

## Play in a browser

The project exports to the web (HTML + WebAssembly, no threads required, so
it works on any static host without special headers). Two ways:

- **GitHub Pages**: `.github/workflows/web.yml` runs the tests, exports the
  web build and deploys it on every push. Enable it once under
  *Settings → Pages → Source: GitHub Actions*; the URL is then
  `https://<owner>.github.io/<repo>/`.
- **Locally**: install the web export templates (Editor → Manage Export
  Templates, or unzip `web_nothreads_release.zip` from the official
  templates archive into `~/.local/share/godot/export_templates/4.4.1.stable/`),
  then

  ```
  mkdir -p build/web
  godot --headless --export-release Web build/web/index.html
  npx http-server build/web -p 8080      # or: python3 -m http.server -d build/web 8080
  ```

  and open <http://localhost:8080>. The build must be served over HTTP;
  opening `index.html` directly from disk does not work in browsers.

## Controls

A panel in the bottom-right corner always lists what the mouse and keys do in
the current situation. In short:

- **Select**: left-click one of your soldiers, drag a box around several
  squads, click a squad card, or press `1`–`4`. `Shift` adds to the selection.
- **Move / attack / defend**: right-click the ground to move; right-click a
  flag to attack it (enemy or neutral) or defend it (yours). `A` + click is an
  attack-move, `D` + click defends the nearest flag, `H` holds and takes cover.
- **Vehicles**: right-click one of your empty vehicles (they pulse and are
  labelled `JEEP 0/4`, `TANK 0/2`) to board it with the selected squad; `M`
  boards the nearest one. A mounted squad drives wherever you right-click.
  When a jeep or APC reaches a flag you ordered it to attack or defend, the
  troops get out and a driver + gunner stay aboard so the vehicle keeps
  firing; tank crews stay in the tank. `X` gets everyone out. Pads show which
  vehicle they spawn and which flag you must own for it.
- **Assets**: `Q`/`W`/`E`/`R` (or the bottom buttons), then click the map;
  the circle shows the radius. `Esc` cancels.
- **Camera and time**: WASD / arrows / middle-drag pan, wheel zooms, `Space`
  pauses, `-`/`=` change speed. `F1` draws HQ-to-HQ paths, `F2` fires free
  debug artillery at the mouse.

Every order shows a yellow ping at its target and a countdown on the squad
card until the squad's Discipline delay elapses.
