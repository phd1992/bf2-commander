extends TestCase
## Test 15: generator validation for seeds 1-20 and mirror symmetry.

const T := Balance.Terrain


func test_seeds_1_to_20_validate() -> void:
	for seed in range(1, 21):
		var log: Array = []
		var result := MapGenerator.generate(seed, log)
		var problems := MapGenerator.validate(result)
		check(problems.is_empty(), "seed %d validates (%s)" % [seed, ", ".join(problems)])
		check_eq(result["flags"].size(), 7, "seed %d has 5 flags + 2 HQs" % seed)


func test_mirror_symmetry() -> void:
	for seed in [1, 7, 13]:
		var result := MapGenerator.generate(seed)
		var g: Grid = result["grid"]
		var asym := 0
		for y in g.H:
			for x in g.W / 2:
				var a := Vector2i(x, y)
				var b := MapGenerator.mirror_cell(a)
				if g.get_terrain(a) != g.get_terrain(b) or g.get_elev(a) != g.get_elev(b):
					asym += 1
		check_eq(asym, 0, "seed %d terrain and elevation are mirror-symmetric" % seed)
		var flags: Array = result["flags"]
		check_eq(flags[4]["centre"], MapGenerator.mirror_cell(flags[1]["centre"]), "D mirrors A")
		check_eq(flags[5]["centre"], MapGenerator.mirror_cell(flags[2]["centre"]), "E mirrors B")
		check_eq(flags[6]["centre"], MapGenerator.mirror_cell(flags[0]["centre"]), "RED HQ mirrors BLUE HQ")


func test_map_contents() -> void:
	var result := MapGenerator.generate(3)
	var g: Grid = result["grid"]
	var counts := {}
	for i in g.terrain.size():
		counts[g.terrain[i]] = counts.get(g.terrain[i], 0) + 1
	check(counts.get(T.WATER, 0) > 100, "there is a river")
	check(counts.get(T.ROAD, 0) > 100, "there are roads")
	check(counts.get(T.FOREST, 0) > 0.12 * g.terrain.size(), "forest covers a good fraction of the map")
	check(counts.get(T.WALL, 0) > 60, "there are building walls")
	check(counts.get(T.DOOR, 0) >= 8, "at least one door per building")
	# no cliffs except (rare) intentional ones: fewer than 5% of edges
	var edges := 0
	var cliffs := 0
	for y in g.H:
		for x in g.W:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b: Vector2i = Vector2i(x, y) + d
				if g.in_bounds(b):
					edges += 1
					if absi(g.get_elev(Vector2i(x, y)) - g.get_elev(b)) >= 3:
						cliffs += 1
	check(float(cliffs) / float(edges) <= 0.05, "at most 5%% of edges are cliffs (%d of %d)" % [cliffs, edges])
	# the town is flat
	var town: Rect2i = result["town_rect"]
	var e0 := g.get_elev(town.position)
	var flat := true
	for y in range(town.position.y, town.end.y):
		for x in range(town.position.x, town.end.x):
			if g.get_elev(Vector2i(x, y)) != e0:
				flat = false
	check(flat, "town is a single elevation")
	# every flag radius is flat and centred on a passable cell
	for f in result["flags"]:
		var c: Vector2i = f["centre"]
		check(g.is_passable(c, Balance.MoveClass.FOOT), "%s centre passable" % f["name"])
		var ec := g.get_elev(c)
		var ok := true
		for q in g.cells_in_radius(c, Balance.FLAG_RADIUS):
			if g.get_elev(q) != ec:
				ok = false
		check(ok, "%s radius is flat" % f["name"])
	check_eq(result["pads"].size(), 9, "7 flag pads + 2 extra HQ pads")


func test_world_setup_installs_map() -> void:
	var w := World.new()
	w.setup(5)
	check_eq(w.flags.size(), 7, "world has 7 flags")
	check(w.buildings.count() >= 8, "world scanned at least 8 buildings")
	check(w.hq_of(Balance.Team.BLUE) != null and w.hq_of(Balance.Team.RED) != null, "both HQs exist")
	check_eq(w.pathfinders.size(), 3, "three pathfinders")
	var path := w.pathfinder(Balance.MoveClass.FOOT).find_path(w.hq_of(Balance.Team.BLUE).centre, w.hq_of(Balance.Team.RED).centre)
	check(not path.is_empty(), "HQ to HQ foot path exists")
