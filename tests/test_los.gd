extends TestCase
## Test 4: line of sight worked checks (Section 4.5) plus rubble opening a sightline.

const T := Balance.Terrain


func test_hill_between_blocks() -> void:
	var g := Grid.new(20, 5, T.OPEN)
	g.set_elev(Vector2i(5, 2), 2)
	var a := Vector2i(1, 2)
	var b := Vector2i(9, 2)
	var ea := LOS.eye_height(g, a, false)
	var eb := LOS.eye_height(g, b, false)
	check_near(ea, 1.5, 0.001, "foot eye height at elevation 0")
	check(not LOS.has_los(g, a, ea, b, eb), "elevation-2 cell between two flat units blocks LOS")
	check(not LOS.has_los(g, b, eb, a, ea), "and it is symmetric")


func test_observer_on_height_sees_over() -> void:
	var g := Grid.new(20, 5, T.OPEN)
	var a := Vector2i(1, 2)
	var b := Vector2i(9, 2)
	g.set_elev(a, 3)
	g.set_elev(Vector2i(5, 2), 2)
	var ea := LOS.eye_height(g, a, false)
	var eb := LOS.eye_height(g, b, false)
	check_near(ea, 4.5, 0.001, "eye height on elevation 3")
	check(LOS.has_los(g, a, ea, b, eb), "observer at elevation 3 sees past an elevation-2 cell to elevation 0")
	check(LOS.has_los(g, b, eb, a, ea), "and the unit below sees the observer")


func test_interior_through_wall() -> void:
	var g := Grid.new(20, 5, T.OPEN)
	var inside := Vector2i(3, 2)
	var wall := Vector2i(4, 2)
	var outside := Vector2i(9, 2)   # 5 cells beyond the wall
	g.set_terrain(inside, T.INTERIOR)
	g.set_terrain(wall, T.WALL)
	var ei := LOS.eye_height(g, inside, false)
	var eo := LOS.eye_height(g, outside, false)
	check_near(ei, 2.5, 0.001, "interior eye height is 2.5 (window)")
	check(LOS.has_los(g, inside, ei, outside, eo), "unit inside sees out through an adjacent wall to 5 cells away")
	check(LOS.has_los(g, outside, eo, inside, ei), "symmetric: outside unit sees the window")
	# but a unit right up against the wall cannot see in
	var close := Vector2i(5, 2)
	var ec := LOS.eye_height(g, close, false)
	check(not LOS.has_los(g, close, ec, inside, ei), "adjacent to the wall the line is blocked")
	# two walls in a row (thick) still fine at distance, wall two cells out blocks
	g.set_terrain(Vector2i(6, 2), T.WALL)
	check(not LOS.has_los(g, inside, ei, outside, eo), "a second wall further away blocks")


func test_rubble_opens_sightline() -> void:
	var g := Grid.new(20, 5, T.OPEN)
	var a := Vector2i(2, 2)
	var b := Vector2i(6, 2)
	g.set_terrain(Vector2i(4, 2), T.WALL)
	var ea := LOS.eye_height(g, a, false)
	var eb := LOS.eye_height(g, b, false)
	check(not LOS.has_los(g, a, ea, b, eb), "wall blocks")
	g.set_terrain(Vector2i(4, 2), T.RUBBLE)
	check(LOS.has_los(g, a, ea, b, eb), "rubble (blocker 0.5) no longer blocks")


func test_forest_does_not_block_flat() -> void:
	var g := Grid.new(20, 5, T.OPEN)
	g.set_terrain(Vector2i(4, 2), T.FOREST)
	var a := Vector2i(2, 2)
	var b := Vector2i(8, 2)
	check(LOS.has_los(g, a, 1.5, b, 1.5), "forest blocker 1.0 is under the 1.5 eye line")
	g.set_elev(Vector2i(4, 2), 1)
	check(not LOS.has_los(g, a, 1.5, b, 1.5), "forest on a 1-high cell reaches 2.0 and blocks")


func test_adjacent_and_same_cell() -> void:
	var g := Grid.new(5, 5, T.OPEN)
	check(LOS.has_los(g, Vector2i(1, 1), 1.5, Vector2i(2, 1), 1.5), "adjacent cells always see each other")
	check(LOS.has_los(g, Vector2i(1, 1), 1.5, Vector2i(1, 1), 1.5), "same cell")


func test_bresenham() -> void:
	var line := LOS.bresenham(Vector2i(0, 0), Vector2i(4, 2))
	check_eq(line.size(), 5, "bresenham length")
	check_eq(line[0], Vector2i(0, 0), "starts at a")
	check_eq(line[4], Vector2i(4, 2), "ends at b")
