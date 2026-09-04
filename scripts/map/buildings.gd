class_name Buildings
extends RefCounted
## Building bookkeeping (Section 9): flood-filled ids, wall damage, rubble and
## collapse. Damage to occupants is returned to the caller (World) so this
## class stays independent of units.

var grid: Grid
## id -> { "cells": Array[Vector2i], "original_walls": int, "rubble_walls": int, "collapsed": bool }
var buildings: Array = []


func _init(p_grid: Grid) -> void:
	grid = p_grid


## Flood-fills connected WALL/DOOR/INTERIOR cells into buildings and assigns
## building ids. Called once after map generation.
func scan() -> void:
	buildings.clear()
	grid.building_id.fill(-1)
	for y in grid.H:
		for x in grid.W:
			var c := Vector2i(x, y)
			if grid.get_building(c) != -1 or not _is_building_terrain(grid.get_terrain(c)):
				continue
			var id := buildings.size()
			var cells: Array[Vector2i] = []
			var walls := 0
			var stack: Array[Vector2i] = [c]
			grid.building_id[grid.idx(x, y)] = id
			while not stack.is_empty():
				var cur: Vector2i = stack.pop_back()
				cells.append(cur)
				if grid.get_terrain(cur) == Balance.Terrain.WALL:
					walls += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cur + d
					if grid.in_bounds(n) and grid.get_building(n) == -1 and _is_building_terrain(grid.get_terrain(n)):
						grid.building_id[grid.idx(n.x, n.y)] = id
						stack.append(n)
			buildings.append({ "cells": cells, "original_walls": walls, "rubble_walls": 0, "collapsed": false })


static func _is_building_terrain(t: int) -> bool:
	return t == Balance.Terrain.WALL or t == Balance.Terrain.DOOR or t == Balance.Terrain.INTERIOR


func count() -> int:
	return buildings.size()


## Applies damage to a WALL cell. Returns true when the wall became rubble.
func damage_wall(c: Vector2i, dmg: float) -> bool:
	if grid.get_terrain(c) != Balance.Terrain.WALL or dmg <= 0.0:
		return false
	var hp := grid.get_wall_hp(c) - int(ceil(dmg))
	if hp > 0:
		grid.set_wall_hp(c, hp)
		return false
	grid.set_terrain(c, Balance.Terrain.RUBBLE)
	var id := grid.get_building(c)
	if id >= 0 and id < buildings.size():
		buildings[id]["rubble_walls"] += 1
	return true


## Collapses any building whose rubble fraction exceeds the threshold.
## Returns the INTERIOR cells that collapsed (their occupants take damage).
func check_collapses() -> Array[Vector2i]:
	var hit: Array[Vector2i] = []
	for id in buildings.size():
		var b: Dictionary = buildings[id]
		if b["collapsed"] or b["original_walls"] == 0:
			continue
		if float(b["rubble_walls"]) > Balance.COLLAPSE_FRACTION * float(b["original_walls"]):
			hit.append_array(collapse(id))
	return hit


func collapse(id: int) -> Array[Vector2i]:
	var b: Dictionary = buildings[id]
	var interiors: Array[Vector2i] = []
	b["collapsed"] = true
	for c in b["cells"]:
		var t := grid.get_terrain(c)
		if t == Balance.Terrain.INTERIOR:
			interiors.append(c)
		if t == Balance.Terrain.WALL or t == Balance.Terrain.DOOR or t == Balance.Terrain.INTERIOR:
			grid.set_terrain(c, Balance.Terrain.RUBBLE)
	b["rubble_walls"] = b["original_walls"]
	return interiors


func is_collapsed(id: int) -> bool:
	return id >= 0 and id < buildings.size() and buildings[id]["collapsed"]


func walls_destroyed_total() -> int:
	var n := 0
	for b in buildings:
		n += b["rubble_walls"]
	return n
