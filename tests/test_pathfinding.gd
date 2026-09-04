extends TestCase
## Test 3: pathfinding behaviours per movement class.

const T := Balance.Terrain
const MC := Balance.MoveClass


func _contains(path: Array[Vector2i], pred: Callable) -> bool:
	for c in path:
		if pred.call(c):
			return true
	return false


func test_foot_path_around_water() -> void:
	var g := Grid.new(20, 10, T.OPEN)
	# vertical river with a gap at the bottom
	for y in range(0, 8):
		g.set_terrain(Vector2i(10, y), T.WATER)
	var pf := Pathfinder.new(g, MC.FOOT)
	var path := pf.find_path(Vector2i(2, 2), Vector2i(18, 2))
	check(not path.is_empty(), "a path exists around the water")
	check(not _contains(path, func(c): return g.get_terrain(c) == T.WATER), "path never enters WATER")
	check(_contains(path, func(c): return c.y >= 8), "path goes through the gap at the bottom")
	check_eq(path[path.size() - 1], Vector2i(18, 2), "path ends at target")
	# fully blocked -> no path
	g.set_terrain(Vector2i(10, 8), T.WATER)
	g.set_terrain(Vector2i(10, 9), T.WATER)
	pf.update_cell(Vector2i(10, 8))
	pf.update_cell(Vector2i(10, 9))
	check(pf.find_path(Vector2i(2, 2), Vector2i(18, 2)).is_empty(), "no path when water blocks completely")


func test_wheeled_prefers_road() -> void:
	var g := Grid.new(30, 12, T.OPEN)
	# straight OPEN route along y=5; a longer ROAD detour along y=9
	for x in range(2, 28):
		g.set_terrain(Vector2i(x, 9), T.ROAD)
	for y in range(5, 10):
		g.set_terrain(Vector2i(2, y), T.ROAD)
		g.set_terrain(Vector2i(27, y), T.ROAD)
	var wheeled := Pathfinder.new(g, MC.WHEELED)
	var path := wheeled.find_path(Vector2i(2, 5), Vector2i(27, 5))
	check(not path.is_empty(), "wheeled path exists")
	var road_cells := 0
	for c in path:
		if g.get_terrain(c) == T.ROAD:
			road_cells += 1
	check(road_cells >= path.size() - 2, "wheeled path stays on the road (%d of %d cells)" % [road_cells, path.size()])
	check(_contains(path, func(c): return c.y == 9), "wheeled path takes the road detour")
	# a foot unit takes the direct route (road 1.2 vs open 1.0 does not justify the detour)
	var foot := Pathfinder.new(g, MC.FOOT)
	var fpath := foot.find_path(Vector2i(2, 5), Vector2i(27, 5))
	check(not _contains(fpath, func(c): return c.y == 9), "foot path takes the shorter open route")


func test_tracked_refuses_interior() -> void:
	var g := Grid.new(20, 12, T.OPEN)
	# a building spanning most of the height with a door on each side
	for y in range(1, 11):
		for x in range(8, 12):
			var edge := x == 8 or x == 11 or y == 1 or y == 10
			g.set_terrain(Vector2i(x, y), T.WALL if edge else T.INTERIOR)
	g.set_terrain(Vector2i(8, 5), T.DOOR)
	g.set_terrain(Vector2i(11, 5), T.DOOR)
	var tracked := Pathfinder.new(g, MC.TRACKED)
	var path := tracked.find_path(Vector2i(2, 5), Vector2i(17, 5))
	check(not path.is_empty(), "tracked path exists around the building")
	check(not _contains(path, func(c): return g.get_terrain(c) == T.INTERIOR or g.get_terrain(c) == T.DOOR), "tracked path avoids INTERIOR and DOOR")
	var foot := Pathfinder.new(g, MC.FOOT)
	var fpath := foot.find_path(Vector2i(2, 5), Vector2i(17, 5))
	check(_contains(fpath, func(c): return g.get_terrain(c) == T.INTERIOR), "foot path cuts through the building via the doors")


func test_path_updates_when_wall_becomes_rubble() -> void:
	var g := Grid.new(20, 10, T.OPEN)
	for y in range(0, 10):
		g.set_terrain(Vector2i(10, y), T.WALL)
	var pf := Pathfinder.new(g, MC.FOOT)
	g.cell_listeners.append(pf.update_cell)
	check(pf.find_path(Vector2i(2, 5), Vector2i(18, 5)).is_empty(), "wall blocks completely")
	g.set_terrain(Vector2i(10, 5), T.RUBBLE)
	var path := pf.find_path(Vector2i(2, 5), Vector2i(18, 5))
	check(not path.is_empty(), "path exists once a wall cell is rubble")
	check(_contains(path, func(c): return c == Vector2i(10, 5)), "path goes through the rubble gap")


func test_cliff_avoided() -> void:
	var g := Grid.new(20, 10, T.OPEN)
	# a plateau of elevation 3 across the middle with a ramp on the bottom row
	for y in range(0, 10):
		for x in range(8, 12):
			g.set_elev(Vector2i(x, y), 3)
	for x in range(6, 14):
		g.set_elev(Vector2i(x, 9), 1)
	g.set_elev(Vector2i(8, 9), 2)
	g.set_elev(Vector2i(9, 9), 2)
	g.set_elev(Vector2i(10, 9), 2)
	g.set_elev(Vector2i(11, 9), 2)
	var pf := Pathfinder.new(g, MC.FOOT)
	var path := pf.find_path(Vector2i(2, 4), Vector2i(18, 4))
	check(not path.is_empty(), "path exists via the ramp")
	var prev := Vector2i(2, 4)
	var crossed_cliff := false
	for c in path:
		if g.is_cliff(prev, c, MC.FOOT):
			crossed_cliff = true
		prev = c
	check(not crossed_cliff, "path never steps across a cliff")
