extends TestCase
## Test 1: terrain table speeds and impassability per class.
## Test 2: slope cost and cliff rules.

const T := Balance.Terrain
const MC := Balance.MoveClass


func test_terrain_table() -> void:
	var g := Grid.new(8, 8)
	var expected := {
		T.ROAD: [1.2, 1.0, 1.0], T.OPEN: [1.0, 0.5, 0.8], T.FOREST: [0.7, 0.0, 0.4],
		T.URBAN: [0.9, 0.8, 0.6], T.WATER: [0.0, 0.0, 0.0], T.WALL: [0.0, 0.0, 0.0],
		T.DOOR: [0.8, 0.0, 0.0], T.INTERIOR: [0.6, 0.0, 0.0], T.RUBBLE: [0.5, 0.0, 0.5],
	}
	for t in expected.keys():
		g.set_terrain(Vector2i(1, 1), t)
		for mc in 3:
			var want: float = expected[t][mc]
			check_near(g.speed_mult(Vector2i(1, 1), mc), want, 0.0001, "%s speed for class %d" % [Balance.terrain_name(t), mc])
			check_eq(g.is_passable(Vector2i(1, 1), mc), want > 0.0, "%s passability for class %d" % [Balance.terrain_name(t), mc])
	check_near(Balance.terrain_cover(T.INTERIOR), 0.7, 0.0001, "interior cover")
	check_near(Balance.terrain_blocker(T.WALL), 2.0, 0.0001, "wall blocker")
	check_eq(g.is_passable(Vector2i(-1, 0), MC.FOOT), false, "out of bounds is impassable")


func test_wall_hp_set_on_terrain_change() -> void:
	var g := Grid.new(4, 4)
	g.set_terrain(Vector2i(2, 2), T.WALL)
	check_eq(g.get_wall_hp(Vector2i(2, 2)), Balance.WALL_HP, "new wall has full HP")
	g.set_terrain(Vector2i(2, 2), T.RUBBLE)
	check_eq(g.get_wall_hp(Vector2i(2, 2)), 0, "rubble has no wall HP")


func test_slope_costs() -> void:
	var g := Grid.new(8, 8, T.OPEN)
	var a := Vector2i(1, 1)
	var b := Vector2i(2, 1)
	g.set_elev(a, 1)
	g.set_elev(b, 2)
	check_near(g.slope_mult(a, b, MC.FOOT), 1.5, 0.0001, "foot uphill 1 level")
	check_near(g.slope_mult(a, b, MC.TRACKED), 2.0, 0.0001, "tracked uphill 1 level")
	check_near(g.slope_mult(a, b, MC.WHEELED), 2.5, 0.0001, "wheeled uphill 1 level")
	check_near(g.slope_mult(b, a, MC.FOOT), 1.0, 0.0001, "downhill is free")
	check_near(g.slope_mult(b, a, MC.WHEELED), 1.0, 0.0001, "downhill is free (wheeled)")
	# step cost = distance / speed * slope
	check_near(Pathfinder.step_cost(g, a, b, MC.FOOT), 1.0 / 1.0 * 1.5, 0.0001, "foot step cost open uphill")
	check_near(Pathfinder.step_cost(g, a, b, MC.WHEELED), 1.0 / 0.5 * 2.5, 0.0001, "wheeled step cost open uphill")
	g.set_elev(b, 1)
	var d := Vector2i(2, 2)
	g.set_elev(d, 1)
	check_near(Pathfinder.step_cost(g, a, d, MC.FOOT), sqrt(2.0), 0.0001, "diagonal step cost")


func test_cliff_rules() -> void:
	var g := Grid.new(8, 8, T.OPEN)
	var a := Vector2i(1, 1)
	var b := Vector2i(2, 1)
	g.set_elev(a, 0)
	g.set_elev(b, 2)
	check_eq(g.is_cliff(a, b, MC.FOOT), false, "dh=2 is not a cliff on foot")
	check_eq(g.is_cliff(a, b, MC.TRACKED), true, "dh=2 is a cliff tracked")
	check_eq(g.is_cliff(a, b, MC.WHEELED), true, "dh=2 is a cliff wheeled")
	g.set_elev(b, 3)
	check_eq(g.is_cliff(a, b, MC.FOOT), true, "dh=3 is a cliff on foot")
	check_eq(g.is_cliff(b, a, MC.FOOT), true, "downhill cliff also impassable")
	check_eq(Pathfinder.step_cost(g, a, b, MC.FOOT) >= Balance.CLIFF_COST, true, "cliff step costs CLIFF_COST")
	check_eq(g.can_step(a, b, MC.FOOT), false, "can_step false across cliff")
	g.set_elev(b, 1)
	check_eq(g.can_step(a, b, MC.FOOT), true, "can_step true on gentle slope")
