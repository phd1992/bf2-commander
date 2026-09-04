class_name Pathfinder
extends AStarGrid2D
## One A* grid per movement class. Cells with speed 0 for the class are solid;
## slopes scale the step cost and cliffs cost CLIFF_COST (effectively blocking).

var grid: Grid
var mclass: int


func _init(p_grid: Grid, p_mclass: int) -> void:
	grid = p_grid
	mclass = p_mclass
	region = Rect2i(0, 0, grid.W, grid.H)
	cell_size = Vector2(1, 1)
	diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	jumping_enabled = false
	update()
	rebuild()


## Recomputes the solid flag of every cell from the terrain table.
func rebuild() -> void:
	for y in grid.H:
		for x in grid.W:
			var c := Vector2i(x, y)
			set_point_solid(c, not grid.is_passable(c, mclass))


## Called by the grid when one cell's terrain changed.
func update_cell(c: Vector2i) -> void:
	set_point_solid(c, not grid.is_passable(c, mclass))


## Step cost between two adjacent cells for a class (Sections 4.3 / 4.4).
static func step_cost(g: Grid, from: Vector2i, to: Vector2i, mc: int) -> float:
	if g.is_cliff(from, to, mc):
		return Balance.CLIFF_COST
	var speed := g.speed_mult(to, mc)
	if speed <= 0.0:
		return Balance.CLIFF_COST
	var dist := 1.0 if (from.x == to.x or from.y == to.y) else sqrt(2.0)
	return dist * (1.0 / speed) * g.slope_mult(from, to, mc)


func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
	return step_cost(grid, from_id, to_id, mclass)


func _estimate_cost(from_id: Vector2i, to_id: Vector2i) -> float:
	var dx := absf(from_id.x - to_id.x)
	var dy := absf(from_id.y - to_id.y)
	# Plain octile distance; multiplying by the best possible speed (1.2 for
	# FOOT on road) would still be admissible but we keep it simple.
	return maxf(dx, dy) + (sqrt(2.0) - 1.0) * minf(dx, dy)


## Returns the list of cells from `from` (exclusive) to `to` (inclusive). If the
## target is solid the nearest passable cell is used. Returns an empty array if
## no path exists.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not grid.in_bounds(from) or not grid.in_bounds(to):
		return out
	if is_point_solid(from):
		from = grid.nearest_passable(from, mclass, 3)
		if from.x < 0:
			return out
	if is_point_solid(to):
		to = grid.nearest_passable(to, mclass)
		if to.x < 0:
			return out
	if from == to:
		return out
	var raw := get_id_path(from, to, false)
	if raw.size() <= 1:
		return out
	for i in range(1, raw.size()):
		out.append(raw[i])
	return out


## Total cost of a path as computed by the cost function (used by tests).
func path_cost(from: Vector2i, path: Array[Vector2i]) -> float:
	var total := 0.0
	var prev := from
	for c in path:
		total += step_cost(grid, prev, c, mclass)
		prev = c
	return total
