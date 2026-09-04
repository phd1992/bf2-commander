extends TestCase
## Test 11: flood fill counts, rubble at 0 HP, collapse at > 50%, collapse
## damage to occupants, pathing through the gap.

const T := Balance.Terrain


func _world_with_building() -> World:
	var w := World.new()
	w.setup_blank(1, 40, 30, T.OPEN)
	# 6x5 building: 18 wall cells, 12 interior, one door
	for y in range(10, 15):
		for x in range(10, 16):
			var edge := x == 10 or x == 15 or y == 10 or y == 14
			w.grid.set_terrain(Vector2i(x, y), T.WALL if edge else T.INTERIOR)
	w.grid.set_terrain(Vector2i(10, 12), T.DOOR)
	# a second, separate building
	for y in range(20, 24):
		for x in range(20, 24):
			var edge := x == 20 or x == 23 or y == 20 or y == 23
			w.grid.set_terrain(Vector2i(x, y), T.WALL if edge else T.INTERIOR)
	w.buildings.scan()
	return w


func test_flood_fill_counts() -> void:
	var w := _world_with_building()
	check_eq(w.buildings.count(), 2, "two buildings found")
	check_eq(w.buildings.buildings[0]["original_walls"], 17, "first building has 17 wall cells (18 minus the door)")
	check_eq(w.buildings.buildings[0]["cells"].size(), 30, "first building has 30 cells")
	check_eq(w.grid.get_building(Vector2i(12, 12)), 0, "interior cell belongs to building 0")
	check_eq(w.grid.get_building(Vector2i(21, 21)), 1, "second building has id 1")
	check_eq(w.grid.get_building(Vector2i(5, 5)), -1, "open ground has no building")
	var gen := World.new()
	gen.setup(2, false)
	check(gen.buildings.count() >= 8, "generated map has at least 8 buildings (%d)" % gen.buildings.count())


func test_wall_becomes_rubble_at_zero() -> void:
	var w := _world_with_building()
	var c := Vector2i(15, 12)
	check_eq(w.grid.get_wall_hp(c), 100, "wall starts at 100 HP")
	w.damage_wall(c, 30.0)
	check_eq(w.grid.get_wall_hp(c), 70, "70 after 30 damage")
	check_eq(w.grid.get_terrain(c), T.WALL, "still a wall")
	w.damage_wall(c, 30.0)
	w.damage_wall(c, 30.0)
	check_eq(w.grid.get_terrain(c), T.WALL, "10 HP left")
	w.damage_wall(c, 30.0)
	check_eq(w.grid.get_terrain(c), T.RUBBLE, "rubble at <= 0")
	check_eq(w.buildings.buildings[0]["rubble_walls"], 1, "rubble counted")
	check_eq(w.match_stats["walls_destroyed"], 1, "match stat updated")
	check(w.grid.is_passable(c, Balance.MoveClass.FOOT), "rubble is passable on foot")
	check(w.pathfinder(Balance.MoveClass.FOOT).is_point_solid(c) == false, "pathfinder updated")


func test_collapse_over_half() -> void:
	var w := _world_with_building()
	var occupant := w.create_squad(Balance.Team.BLUE, "O", [3, 3, 3, 3], Vector2(12.5, 12.5))
	for m in occupant.members:
		m.pos = Vector2(12.5, 12.5)
	occupant.members[0].hp = 40.0
	w.give_order(occupant, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	var walls: Array = []
	for c in w.buildings.buildings[0]["cells"]:
		if w.grid.get_terrain(c) == T.WALL:
			walls.append(c)
	# 8 of 17 walls: not yet over half
	for i in 8:
		w.damage_wall(walls[i], 100.0)
	run_ticks(w, 1)
	check(not w.buildings.is_collapsed(0), "8 of 17 rubble: standing")
	check_eq(w.grid.get_terrain(Vector2i(12, 12)), T.INTERIOR, "interior intact")
	w.damage_wall(walls[8], 100.0)
	run_ticks(w, 1)
	check(w.buildings.is_collapsed(0), "9 of 17 rubble (> 50%): collapsed")
	check_eq(w.grid.get_terrain(Vector2i(12, 12)), T.RUBBLE, "interior became rubble")
	check_eq(w.grid.get_terrain(Vector2i(10, 12)), T.RUBBLE, "door became rubble")
	check_eq(w.grid.get_terrain(Vector2i(15, 14)), T.RUBBLE, "remaining walls became rubble")
	check_eq(occupant.members[0].state, Balance.MemberState.DEAD, "occupant at 40 HP died from 50 collapse damage")
	check_near(occupant.members[1].hp, 50.0, 0.001, "other occupants took 50")
	check(not w.buildings.is_collapsed(1), "the other building is untouched")


func test_squad_paths_through_the_gap() -> void:
	var w := World.new()
	w.setup_blank(1, 40, 20, T.OPEN)
	for y in range(0, 20):
		w.grid.set_terrain(Vector2i(20, y), T.WALL)
	w.buildings.scan()
	var s := w.create_squad(Balance.Team.BLUE, "S", [3, 5, 3, 3], Vector2(10.5, 10.5))
	w.give_order(s, Balance.Order.MOVE, Vector2i(30, 10), null, null, 0.0)
	run_seconds(w, 10.0)
	check(s.leader.pos.x < 20.0, "blocked by the wall line")
	# artillery-style damage knocks a hole
	Combat.apply_splash(w, Vector2(20.5, 10.5), "ARTY_SHELL", null)
	Combat.apply_splash(w, Vector2(20.5, 10.5), "ARTY_SHELL", null)
	check_eq(w.grid.get_terrain(Vector2i(20, 10)), T.RUBBLE, "two shells open the wall")
	run_seconds(w, 20.0)
	check(s.leader.pos.x > 28.0, "squad walked through the gap (leader at %s)" % str(s.leader.pos))


func test_los_opens_when_wall_falls() -> void:
	var w := _world_with_building()
	# the wall cell at x=10 sits at the midpoint of the 4-cell line: blocked
	var inside2 := Vector2i(12, 11)
	var outside2 := Vector2i(8, 11)
	check(not LOS.has_los(w.grid, outside2, LOS.eye_height(w.grid, outside2, false), inside2, LOS.eye_height(w.grid, inside2, false)), "blocked before")
	w.damage_wall(Vector2i(10, 11), 100.0)
	check(LOS.has_los(w.grid, outside2, LOS.eye_height(w.grid, outside2, false), inside2, LOS.eye_height(w.grid, inside2, false)), "rubble opens the sightline")
