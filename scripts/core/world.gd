class_name World
extends RefCounted
## Plain-data game world plus its systems. No Node dependencies so it runs
## headless. Rendering reads from it; Sim drives step().

var seed: int = 1
var rng := RandomNumberGenerator.new()
var time := 0.0
var tick_count := 0

var grid: Grid
var pathfinders: Array[Pathfinder] = []   # index = MoveClass
var buildings: Buildings
var flags: Array = []                      # Array[Flag]
var pads: Array = []                       # Array[Dictionary]
var town_rect := Rect2i()
var generator_log: Array = []

## True when any cell's terrain changed since the renderer last looked.
var terrain_dirty := true
## Per-step events consumed by the effects layer: Array[Dictionary].
var events: Array = []

var game_over := false
var winner: int = Balance.Team.NONE


func setup(p_seed: int) -> void:
	seed = p_seed
	rng.seed = p_seed
	time = 0.0
	tick_count = 0
	var result := MapGenerator.generate(p_seed, generator_log)
	_install_map(result)


## Installs a generated (or hand-built) map. Used by setup() and by tests
## that construct custom grids.
func _install_map(result: Dictionary) -> void:
	grid = result["grid"]
	town_rect = result.get("town_rect", Rect2i())
	pathfinders.clear()
	for mc in 3:
		pathfinders.append(Pathfinder.new(grid, mc))
	grid.cell_listeners.append(_on_cell_changed)
	buildings = Buildings.new(grid)
	buildings.scan()
	flags.clear()
	for fd in result.get("flags", []):
		var f := Flag.new()
		f.id = flags.size()
		f.name = fd["name"]
		f.centre = fd["centre"]
		f.is_hq = fd["is_hq"]
		f.owner = fd["team"]
		f.progress = 1.0 if f.owner == Balance.Team.BLUE else (-1.0 if f.owner == Balance.Team.RED else 0.0)
		flags.append(f)
	pads.clear()
	for pd in result.get("pads", []):
		pads.append({ "flag": pd["flag"], "vtype": pd["vtype"], "cell": pd["cell"], "vehicle": null, "respawn_at": 0.0 })
	terrain_dirty = true


## Builds a flat map of one terrain with no flags; tests add what they need.
func setup_blank(p_seed: int, w: int = Balance.MAP_W, h: int = Balance.MAP_H, terrain: int = Balance.Terrain.OPEN) -> void:
	seed = p_seed
	rng.seed = p_seed
	time = 0.0
	tick_count = 0
	_install_map({ "grid": Grid.new(w, h, terrain), "flags": [], "pads": [] })


func _on_cell_changed(c: Vector2i) -> void:
	for pf in pathfinders:
		pf.update_cell(c)
	terrain_dirty = true


func pathfinder(mc: int) -> Pathfinder:
	return pathfinders[mc]


func flag_by_name(n: String) -> Flag:
	for f in flags:
		if f.name == n:
			return f
	return null


func hq_of(team: int) -> Flag:
	for f in flags:
		if f.is_hq and f.owner == team:
			return f
	return null


func step(dt: float) -> void:
	if game_over:
		return
	time += dt
	tick_count += 1
	var collapsed := buildings.check_collapses()
	if not collapsed.is_empty():
		events.append({ "type": "collapse", "cells": collapsed })
