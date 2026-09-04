extends Node2D
## Game scene: wires input to the simulation and hosts the render layers.

signal match_finished

@onready var hud: Control = $HUDLayer/HUD
@onready var debug_layer: Node2D = $DebugLayer

var _debug_paths: Array = []   # Array of { "class": int, "cells": Array[Vector2i] }


func _ready() -> void:
	Sim.match_ended.connect(_on_match_ended)
	debug_layer.draw.connect(_draw_debug)


func _on_match_ended() -> void:
	match_finished.emit()


func mouse_cell() -> Vector2i:
	var p := get_global_mouse_position() / float(Balance.CELL_PX)
	return Vector2i(int(floor(p.x)), int(floor(p.y)))


func mouse_pos_cells() -> Vector2:
	return get_global_mouse_position() / float(Balance.CELL_PX)


func _unhandled_input(event: InputEvent) -> void:
	if Sim.world == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				_toggle_debug_paths()
			KEY_SPACE:
				Sim.toggle_pause()
			KEY_MINUS:
				Sim.speed_down()
			KEY_EQUAL:
				Sim.speed_up()
		if hud.has_method("handle_key"):
			hud.handle_key(event)
	elif event is InputEventMouseButton and event.pressed:
		if hud.has_method("handle_click"):
			hud.handle_click(event, mouse_cell(), mouse_pos_cells())


func _toggle_debug_paths() -> void:
	if not _debug_paths.is_empty():
		_debug_paths.clear()
		debug_layer.queue_redraw()
		return
	var w: World = Sim.world
	var blue := w.hq_of(Balance.Team.BLUE)
	var red := w.hq_of(Balance.Team.RED)
	if blue == null or red == null:
		return
	for mc in 3:
		var path := w.pathfinder(mc).find_path(blue.centre, red.centre)
		_debug_paths.append({ "class": mc, "cells": path, "from": blue.centre })
	debug_layer.queue_redraw()


func _draw_debug() -> void:
	var px := float(Balance.CELL_PX)
	var colors := [Color(1, 1, 0), Color(0, 1, 1), Color(1, 0, 1)]
	for p in _debug_paths:
		var pts := PackedVector2Array()
		pts.append(Grid.centre_of(p["from"]) * px)
		for c in p["cells"]:
			pts.append(Grid.centre_of(c) * px)
		if pts.size() >= 2:
			debug_layer.draw_polyline(pts, colors[p["class"]], 3.0)


func collect_end_stats() -> Dictionary:
	var w: World = Sim.world
	if w == null:
		return {}
	var out := { "winner": w.winner, "clock": "", "squads": [] }
	if "tickets" in w:
		out["blue_tickets"] = w.tickets[Balance.Team.BLUE]
		out["red_tickets"] = w.tickets[Balance.Team.RED]
	out["clock"] = "%d:%02d" % [int(w.time) / 60, int(w.time) % 60]
	if "squads" in w:
		for s in w.squads:
			out["squads"].append({ "name": s.name, "team": s.team, "kills": s.kills, "deaths": s.deaths, "stats": s.stats_text() })
	return out
