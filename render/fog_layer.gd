extends Node2D
## Fog of war overlay for the player's team: never seen = dark, seen before
## but not now = dim, currently seen = clear. Elevation and buildings stay
## visible underneath (it's a map); only the dimming changes.

const PX := float(Balance.CELL_PX)
const NEVER_SEEN := Color(0.02, 0.02, 0.05, 0.78)
const SEEN_BEFORE := Color(0.05, 0.05, 0.1, 0.42)

var _last_time := -1.0


func _process(_delta: float) -> void:
	var w: World = Sim.world
	if w == null:
		return
	if Sim.ai_vs_ai:
		visible = false
		return
	visible = true
	if w.fog.update_cell_vision(Sim.player_team) or w.time != _last_time and w.time < 0.2:
		_last_time = w.time
		queue_redraw()


func _draw() -> void:
	var w: World = Sim.world
	if w == null:
		return
	var g := w.grid
	var now := w.fog.cell_seen_now
	var ever := w.fog.cell_seen_ever
	# Draw runs of identical cells per row to keep draw calls down.
	for y in g.H:
		var x := 0
		while x < g.W:
			var i := y * g.W + x
			var state := 2 if now[i] == 1 else (1 if ever[i] == 1 else 0)
			var x0 := x
			while x < g.W:
				var j := y * g.W + x
				var st := 2 if now[j] == 1 else (1 if ever[j] == 1 else 0)
				if st != state:
					break
				x += 1
			if state == 2:
				continue
			draw_rect(Rect2(x0 * PX, y * PX, (x - x0) * PX, PX), NEVER_SEEN if state == 0 else SEEN_BEFORE)
