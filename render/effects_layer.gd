extends Node2D
## Transient visuals: tracer lines, deaths, splash rings, captures, collapses.
## Consumes World.events via Sim.take_events() each frame.

const PX := float(Balance.CELL_PX)

var _effects: Array = []   # { "type", "until", ... }
var _wall := 0.0


func _process(delta: float) -> void:
	_wall += delta
	if Sim.world == null:
		_effects.clear()
		return
	for e in Sim.take_events():
		_add(e)
	var keep: Array = []
	for fx in _effects:
		if fx["until"] > _wall:
			keep.append(fx)
	_effects = keep
	queue_redraw()


func _add(e: Dictionary) -> void:
	match e["type"]:
		"shot":
			_effects.append({ "type": "shot", "from": e["from"], "to": e["to"], "hit": e["hit"], "weapon": e["weapon"], "team": e["team"], "until": _wall + 0.12, "start": _wall })
		"death":
			_effects.append({ "type": "death", "pos": e["pos"], "team": e["team"], "until": _wall + 1.5, "start": _wall })
		"impact":
			_effects.append({ "type": "impact", "pos": e["pos"], "radius": e["radius"], "until": _wall + 0.6, "start": _wall })
		"capture":
			_effects.append({ "type": "capture", "pos": e["flag"].centre_pos(), "team": e["team"], "until": _wall + 1.2, "start": _wall })
		"collapse":
			for c in e["cells"]:
				_effects.append({ "type": "collapse", "pos": Grid.centre_of(c), "until": _wall + 1.0, "start": _wall })
		"vehicle_destroyed":
			_effects.append({ "type": "impact", "pos": e["pos"], "radius": 2.0, "until": _wall + 1.0, "start": _wall })
		"order_ping":
			_effects.append({ "type": "order_ping", "pos": e["pos"], "text": e["text"], "until": _wall + 1.2, "start": _wall })
		"dismount":
			_effects.append({ "type": "capture", "pos": e["pos"], "team": e["team"], "until": _wall + 0.6, "start": _wall })
		"squad_respawn":
			_effects.append({ "type": "capture", "pos": Grid.centre_of(e["cell"]), "team": e["squad"].team, "until": _wall + 1.0, "start": _wall })


func _draw() -> void:
	for fx in _effects:
		var t: float = clampf((_wall - fx["start"]) / maxf(fx["until"] - fx["start"], 0.001), 0.0, 1.0)
		match fx["type"]:
			"shot":
				var col := Color(1, 0.95, 0.6, 0.9) if fx["hit"] else Color(1, 1, 1, 0.45)
				var width := 1.0
				if fx["weapon"] in ["CANNON", "AT", "ARTY_SHELL"]:
					width = 3.0
					col = Color(1, 0.6, 0.2, 0.9)
				elif fx["weapon"] == "AUTOCANNON":
					width = 2.0
				draw_line(fx["from"] * PX, fx["to"] * PX, col, width)
			"death":
				var c: Vector2 = fx["pos"] * PX
				var col := Color(1, 0.3, 0.2, 1.0 - t)
				draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), col, 2.0)
				draw_line(c + Vector2(-6, 6), c + Vector2(6, -6), col, 2.0)
			"impact":
				var c: Vector2 = fx["pos"] * PX
				var r: float = fx["radius"] * PX * (0.3 + 0.7 * t)
				draw_arc(c, r, 0, TAU, 32, Color(1, 0.7, 0.3, 1.0 - t), 3.0)
				draw_circle(c, 4.0 * (1.0 - t), Color(1, 0.9, 0.5, 1.0 - t))
			"capture":
				var c: Vector2 = fx["pos"] * PX
				var col := Balance.COLOR_BLUE if fx["team"] == Balance.Team.BLUE else Balance.COLOR_RED
				draw_arc(c, Balance.FLAG_RADIUS * PX * (1.0 + 0.5 * t), 0, TAU, 48, Color(col, 1.0 - t), 4.0)
			"order_ping":
				var c: Vector2 = fx["pos"] * PX
				var col := Color(1, 0.9, 0.3, 1.0 - t)
				draw_arc(c, 26.0 * (1.0 - t) + 6.0, 0, TAU, 24, col, 2.5)
				draw_string(ThemeDB.fallback_font, c + Vector2(-20, -22 - 10 * t), fx["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
			"collapse":
				var c: Vector2 = fx["pos"] * PX
				draw_circle(c, PX * 0.6 * (1.0 + t), Color(0.5, 0.45, 0.4, 0.8 * (1.0 - t)))
