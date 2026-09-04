class_name LOS
extends RefCounted
## Line of sight over the grid (Section 4.5). Evaluated on live grid data so
## rubble opens sightlines as walls fall.


## Bresenham line from a to b, both endpoints included.
static func bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		out.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return out


## Absolute eye height of a unit standing in `cell`.
static func eye_height(grid: Grid, cell: Vector2i, is_vehicle: bool) -> float:
	var e := float(grid.get_elev(cell))
	if is_vehicle:
		return e + Balance.EYE_VEHICLE
	if grid.get_terrain(cell) == Balance.Terrain.INTERIOR:
		return e + Balance.EYE_INTERIOR
	return e + Balance.EYE_FOOT


## True when nothing between the two cells rises above the sight line.
## Both endpoints are excluded from the test.
static func has_los(grid: Grid, from_cell: Vector2i, from_eye: float, to_cell: Vector2i, to_eye: float) -> bool:
	var x0 := from_cell.x
	var y0 := from_cell.y
	var x1 := to_cell.x
	var y1 := to_cell.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var steps := maxi(dx, -dy)
	if steps <= 1:
		return true
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var n := 0
	var eps := Balance.LOS_EPS
	var W := grid.W
	var elev := grid.elevation
	var terr := grid.terrain
	var blockers := grid._blocker_table
	var rise := to_eye - from_eye
	while true:
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
		n += 1
		if x0 == x1 and y0 == y1:
			break
		# intermediate cell (x0, y0) at fraction t along the line
		var t := float(n) / float(steps)
		var line_h := from_eye + t * rise
		var i := y0 * W + x0
		var top := float(elev[i]) + blockers[terr[i]]
		if top > line_h - eps:
			return false
	return true


## Convenience: LOS between two units given their cells and vehicle flags.
static func unit_los(grid: Grid, a_cell: Vector2i, a_vehicle: bool, b_cell: Vector2i, b_vehicle: bool) -> bool:
	return has_los(grid, a_cell, eye_height(grid, a_cell, a_vehicle), b_cell, eye_height(grid, b_cell, b_vehicle))
