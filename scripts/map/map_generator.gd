class_name MapGenerator
extends RefCounted
## Seeded, mirror-symmetric map generator (Section 15). The west half
## (x < HALF) is generated, then mirrored to the east so both teams get an
## identical layout. Returns a Dictionary:
##   grid: Grid, flags: Array[Dictionary], pads: Array[Dictionary],
##   seed_used: int, town_rect: Rect2i
## Flag dict: { name, centre: Vector2i, is_hq: bool, team: int }
## Pad dict:  { flag: int (index into flags), vtype: String, cell: Vector2i }

const HALF := 48
const RIVER_X := 27
const TOWN_RECT := Rect2i(36, 25, 24, 15)   # full width rect, x 36..59, y 25..39
const TOWN_MAIN_STREET_Y := 32
const TOWN_BLOCK_X0 := 37
const TOWN_BLOCK_W := 10
const BLUE_HQ := Vector2i(6, 32)
const FLAG_A := Vector2i(20, 16)
const FLAG_B := Vector2i(20, 48)
const FLAG_C := Vector2i(48, 32)
const BRIDGE_NORTH_Y := 16
const BRIDGE_SOUTH_Y := 48
const MAX_ATTEMPTS := 30
const NOISE_FREQUENCY := 0.035
const FOREST_NOISE_FREQUENCY := 0.09
const FOREST_FRACTION := 0.25


static func mirror_x(x: int) -> int:
	return Balance.MAP_W - 1 - x


static func mirror_cell(c: Vector2i) -> Vector2i:
	return Vector2i(mirror_x(c.x), c.y)


## Generates a valid map, retrying with seed + 1 while validation fails.
static func generate(seed: int, log: Array = []) -> Dictionary:
	var s := seed
	for attempt in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var result := _generate_once(rng)
		var problems := validate(result)
		if problems.is_empty():
			result["seed_used"] = s
			return result
		log.append("map seed %d rejected: %s" % [s, ", ".join(problems)])
		s += 1
	push_error("MapGenerator: no valid map found starting at seed %d" % seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var fallback := _generate_once(rng)
	fallback["seed_used"] = seed
	return fallback


static func _generate_once(rng: RandomNumberGenerator) -> Dictionary:
	var grid := Grid.new(Balance.MAP_W, Balance.MAP_H, Balance.Terrain.OPEN)
	var W := grid.W
	var H := grid.H
	var locked := PackedByteArray()
	locked.resize(W * H)
	locked.fill(0)

	_heightmap(grid, rng)
	_ridge(grid)
	var town_elev := _flatten_town(grid, locked)
	for f in [BLUE_HQ, FLAG_A, FLAG_B]:
		_flatten_flag(grid, locked, f)
	_smooth(grid, locked)
	_river(grid, rng)
	_roads(grid, locked)
	_smooth(grid, locked)
	_forest(grid, rng)
	var buildings_made := _town(grid, rng, town_elev)
	# flag centres are always passable road/street cells on flat ground
	for f in [BLUE_HQ, FLAG_A, FLAG_B]:
		grid.set_terrain(f, Balance.Terrain.ROAD, false)
	grid.set_terrain(Vector2i(HALF - 1, FLAG_C.y), Balance.Terrain.ROAD, false)
	_mirror(grid)

	var flags: Array = [
		{ "name": "BLUE HQ", "centre": BLUE_HQ, "is_hq": true, "team": Balance.Team.BLUE },
		{ "name": "A", "centre": FLAG_A, "is_hq": false, "team": Balance.Team.NONE },
		{ "name": "B", "centre": FLAG_B, "is_hq": false, "team": Balance.Team.NONE },
		{ "name": "C", "centre": FLAG_C, "is_hq": false, "team": Balance.Team.NONE },
		{ "name": "D", "centre": mirror_cell(FLAG_A), "is_hq": false, "team": Balance.Team.NONE },
		{ "name": "E", "centre": mirror_cell(FLAG_B), "is_hq": false, "team": Balance.Team.NONE },
		{ "name": "RED HQ", "centre": mirror_cell(BLUE_HQ), "is_hq": true, "team": Balance.Team.RED },
	]
	var pads := _pads(grid, flags)
	return {
		"grid": grid,
		"flags": flags,
		"pads": pads,
		"seed_used": rng.seed,
		"town_rect": TOWN_RECT,
		"buildings_made": buildings_made,
	}


# --- 1. heightmap -------------------------------------------------------------

static func _heightmap(grid: Grid, rng: RandomNumberGenerator) -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = rng.randi()
	noise.frequency = NOISE_FREQUENCY
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var vals := PackedFloat32Array()
	vals.resize(grid.W * grid.H)
	var vmin := 1.0e9
	var vmax := -1.0e9
	for y in grid.H:
		for x in HALF:
			var v := noise.get_noise_2d(x, y)
			vals[y * grid.W + x] = v
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)
	var span := maxf(vmax - vmin, 0.0001)
	for y in grid.H:
		for x in HALF:
			var n := (vals[y * grid.W + x] - vmin) / span
			grid.set_elev(Vector2i(x, y), clampi(int(floor(n * 6.0)), 0, Balance.MAX_ELEVATION))


static func _ridge(grid: Grid) -> void:
	# North-south ridge centred on the map axis, with a gap at the town.
	var heights := { 47: 4, 46: 4, 45: 3, 44: 2, 43: 1 }
	for y in grid.H:
		if y >= TOWN_RECT.position.y - 1 and y < TOWN_RECT.end.y + 1:
			continue
		for x in heights.keys():
			var c := Vector2i(x, y)
			grid.set_elev(c, maxi(grid.get_elev(c), heights[x]))


static func _flatten_town(grid: Grid, locked: PackedByteArray) -> int:
	var e := clampi(grid.get_elev(Vector2i(HALF - 1, TOWN_MAIN_STREET_Y)), 1, 3)
	for y in range(TOWN_RECT.position.y, TOWN_RECT.end.y):
		for x in range(TOWN_RECT.position.x, HALF):
			grid.set_elev(Vector2i(x, y), e)
			locked[y * grid.W + x] = 1
	return e


static func _flatten_flag(grid: Grid, locked: PackedByteArray, centre: Vector2i) -> void:
	var e := grid.get_elev(centre)
	for c in grid.cells_in_radius(centre, Balance.FLAG_RADIUS):
		if c.x >= HALF:
			continue
		grid.set_elev(c, e)
		locked[c.y * grid.W + c.x] = 1


## Removes cliffs (|dh| >= 3) by moving unlocked cells toward their neighbours.
static func _smooth(grid: Grid, locked: PackedByteArray) -> void:
	var W := grid.W
	for pass_i in 200:
		var changed := false
		for y in grid.H:
			for x in HALF:
				var a := Vector2i(x, y)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var b: Vector2i = a + d
					if b.x >= HALF or b.y >= grid.H:
						continue
					var ea := grid.get_elev(a)
					var eb := grid.get_elev(b)
					if absi(ea - eb) < 3:
						continue
					var hi: Vector2i = a if ea > eb else b
					var lo: Vector2i = b if ea > eb else a
					var hi_e := maxi(ea, eb)
					var lo_e := mini(ea, eb)
					if locked[hi.y * W + hi.x] == 0:
						grid.set_elev(hi, lo_e + 2)
						changed = true
					elif locked[lo.y * W + lo.x] == 0:
						grid.set_elev(lo, hi_e - 2)
						changed = true
		if not changed:
			return


# --- 2. river -------------------------------------------------------------------

static func _river(grid: Grid, rng: RandomNumberGenerator) -> void:
	var phase := rng.randf() * TAU
	var wnoise := FastNoiseLite.new()
	wnoise.seed = rng.randi()
	wnoise.frequency = 0.1
	for y in grid.H:
		var xc := RIVER_X + int(round(sin(y * 0.15 + phase)))
		var width := 2 + (1 if wnoise.get_noise_1d(y) > 0.0 else 0)
		for x in range(xc - 1, xc - 1 + width):
			grid.set_terrain(Vector2i(x, y), Balance.Terrain.WATER, false)


# --- 3. roads ---------------------------------------------------------------------

## 4-connected line (a diagonal Bresenham step also fills the orthogonal cell).
static func _road_line(grid: Grid, a: Vector2i, b: Vector2i, cells: Array[Vector2i]) -> void:
	var line := LOS.bresenham(a, b)
	var prev := a
	for c in line:
		if c.x != prev.x and c.y != prev.y:
			cells.append(Vector2i(c.x, prev.y))
		cells.append(c)
		prev = c


static func _roads(grid: Grid, locked: PackedByteArray) -> void:
	var cells: Array[Vector2i] = []
	var north_join := Vector2i(31, BRIDGE_NORTH_Y)
	var south_join := Vector2i(31, BRIDGE_SOUTH_Y)
	var town_entry := Vector2i(TOWN_RECT.position.x, TOWN_MAIN_STREET_Y)
	_road_line(grid, BLUE_HQ, FLAG_A, cells)
	_road_line(grid, FLAG_A, north_join, cells)
	_road_line(grid, north_join, town_entry, cells)
	_road_line(grid, town_entry, Vector2i(HALF - 1, TOWN_MAIN_STREET_Y), cells)
	_road_line(grid, BLUE_HQ, FLAG_B, cells)
	_road_line(grid, FLAG_B, south_join, cells)
	_road_line(grid, south_join, town_entry, cells)
	for c in cells:
		if c.x >= HALF:
			continue
		grid.set_terrain(c, Balance.Terrain.ROAD, false)
	# gentle grades: road elevation = average of neighbours (unless locked)
	for c in cells:
		if c.x >= HALF or locked[c.y * grid.W + c.x] == 1:
			continue
		var sum := 0
		var n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := Vector2i(c.x + dx, c.y + dy)
				if grid.in_bounds(q) and q.x < HALF:
					sum += grid.get_elev(q)
					n += 1
		if n > 0:
			grid.set_elev(c, int(round(float(sum) / float(n))))


# --- 4. forest ---------------------------------------------------------------------

static func _forest(grid: Grid, rng: RandomNumberGenerator) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = FOREST_NOISE_FREQUENCY
	noise.fractal_octaves = 2
	var eligible: Array[Vector2i] = []
	var values := PackedFloat32Array()
	var town_margin := TOWN_RECT.grow(1)
	for y in grid.H:
		for x in HALF:
			var c := Vector2i(x, y)
			if grid.get_terrain(c) != Balance.Terrain.OPEN:
				continue
			if town_margin.has_point(c):
				continue
			var near_flag := false
			for f in [BLUE_HQ, FLAG_A, FLAG_B]:
				if Vector2(c - f).length() <= 3.0:
					near_flag = true
			if near_flag:
				continue
			if _near_terrain(grid, c, Balance.Terrain.ROAD, 1) or _near_terrain(grid, c, Balance.Terrain.WATER, 1):
				continue
			eligible.append(c)
			values.append(noise.get_noise_2d(x, y))
	if eligible.is_empty():
		return
	var sorted := values.duplicate()
	sorted.sort()
	var threshold := sorted[int(float(sorted.size()) * (1.0 - FOREST_FRACTION))]
	for i in eligible.size():
		if values[i] >= threshold:
			grid.set_terrain(eligible[i], Balance.Terrain.FOREST, false)


static func _near_terrain(grid: Grid, c: Vector2i, t: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := Vector2i(c.x + dx, c.y + dy)
			if grid.in_bounds(q) and grid.get_terrain(q) == t:
				return true
	return false


# --- 5. town -------------------------------------------------------------------------

static func _town(grid: Grid, rng: RandomNumberGenerator, town_elev: int) -> int:
	# Urban ground everywhere in the (west half of the) town, main street stays ROAD.
	for y in range(TOWN_RECT.position.y, TOWN_RECT.end.y):
		for x in range(TOWN_RECT.position.x, HALF):
			var c := Vector2i(x, y)
			grid.set_elev(c, town_elev)
			if grid.get_terrain(c) != Balance.Terrain.ROAD:
				grid.set_terrain(c, Balance.Terrain.URBAN, false)
	var made := 0
	# Two block rows: north of the main street and south of it. Buildings sit
	# flush against the main street so their doors open onto it.
	for side in [-1, 1]:
		var w1 := rng.randi_range(4, 5)
		var w2 := rng.randi_range(4, mini(5, TOWN_BLOCK_W - w1 - 1))
		var leftover := TOWN_BLOCK_W - (w1 + 1 + w2)
		var x1 := TOWN_BLOCK_X0 + rng.randi_range(0, leftover)
		var x2 := x1 + w1 + 1 + rng.randi_range(0, leftover - (x1 - TOWN_BLOCK_X0))
		for spec in [[x1, w1], [x2, w2]]:
			var h := rng.randi_range(4, 6)
			var y0 := TOWN_MAIN_STREET_Y - h if side == -1 else TOWN_MAIN_STREET_Y + 1
			_building(grid, rng, spec[0], y0, spec[1], h, side)
			made += 1
	return made


static func _building(grid: Grid, rng: RandomNumberGenerator, x0: int, y0: int, w: int, h: int, side: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var c := Vector2i(x, y)
			var edge := x == x0 or y == y0 or x == x0 + w - 1 or y == y0 + h - 1
			grid.set_terrain(c, Balance.Terrain.WALL if edge else Balance.Terrain.INTERIOR, false)
	# Doors on the wall facing the main street.
	var door_y := y0 + h - 1 if side == -1 else y0
	var n_doors := rng.randi_range(1, 2)
	var xs := range(x0 + 1, x0 + w - 1)
	var chosen: Array = []
	for i in n_doors:
		var x: int = xs[rng.randi_range(0, xs.size() - 1)]
		if x not in chosen:
			chosen.append(x)
	for x in chosen:
		grid.set_terrain(Vector2i(x, door_y), Balance.Terrain.DOOR, false)


# --- 6. mirror -------------------------------------------------------------------------

static func _mirror(grid: Grid) -> void:
	for y in grid.H:
		for x in HALF:
			var src := grid.idx(x, y)
			var dst := grid.idx(mirror_x(x), y)
			grid.terrain[dst] = grid.terrain[src]
			grid.elevation[dst] = grid.elevation[src]
			grid.wall_hp[dst] = grid.wall_hp[src]


# --- 7. pads -----------------------------------------------------------------------------

static func _pads(grid: Grid, flags: Array) -> Array:
	var pads: Array = []
	var pfs := { Balance.MoveClass.WHEELED: Pathfinder.new(grid, Balance.MoveClass.WHEELED), Balance.MoveClass.TRACKED: Pathfinder.new(grid, Balance.MoveClass.TRACKED) }
	for fi in flags.size():
		var f: Dictionary = flags[fi]
		var types: Array = []
		if f["is_hq"]:
			types = ["JEEP", "APC"]
		elif f["name"] == "C":
			types = ["TANK"]
		else:
			types = ["JEEP"]
		var used: Array[Vector2i] = []
		for vtype in types:
			var mc: int = Balance.VEHICLES[vtype]["mclass"]
			var cell := _find_pad_cell(grid, pfs[mc], f["centre"], mc, used)
			if cell.x >= 0:
				used.append(cell)
				pads.append({ "flag": fi, "vtype": vtype, "cell": cell })
	return pads


static func _find_pad_cell(grid: Grid, pf: Pathfinder, centre: Vector2i, mc: int, used: Array[Vector2i]) -> Vector2i:
	var candidates := grid.cells_in_radius(centre, Balance.PAD_SEARCH_DIST)
	candidates.sort_custom(func(a, b): return Vector2(a - centre).length_squared() < Vector2(b - centre).length_squared())
	for c in candidates:
		if c == centre or c in used or not grid.is_passable(c, mc):
			continue
		if Vector2(c - centre).length() < 1.5:
			continue
		if not pf.find_path(centre, c).is_empty():
			return c
	return Vector2i(-1, -1)


# --- 8. validation --------------------------------------------------------------------------

## Returns a list of problems; empty means the map is valid.
static func validate(result: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var grid: Grid = result["grid"]
	var flags: Array = result["flags"]
	var foot := Pathfinder.new(grid, Balance.MoveClass.FOOT)
	var hqs: Array = []
	for f in flags:
		if f["is_hq"]:
			hqs.append(f["centre"])
	for hq in hqs:
		for f in flags:
			var c: Vector2i = f["centre"]
			if c == hq:
				continue
			if not grid.is_passable(c, Balance.MoveClass.FOOT):
				problems.append("%s centre impassable" % f["name"])
			elif foot.find_path(hq, c).is_empty():
				problems.append("%s unreachable on foot from HQ %s" % [f["name"], str(hq)])
	var pfs := {}
	for pad in result["pads"]:
		var mc: int = Balance.VEHICLES[pad["vtype"]]["mclass"]
		if not pfs.has(mc):
			pfs[mc] = Pathfinder.new(grid, mc)
		var centre: Vector2i = flags[pad["flag"]]["centre"]
		if pfs[mc].find_path(centre, pad["cell"]).is_empty():
			problems.append("pad %s at %s unreachable" % [pad["vtype"], str(pad["cell"])])
	var expected_pads := 0
	for f in flags:
		expected_pads += 2 if f["is_hq"] else 1
	if result["pads"].size() != expected_pads:
		problems.append("expected %d pads, got %d" % [expected_pads, result["pads"].size()])
	var b := Buildings.new(grid)
	b.scan()
	if b.count() < 8:
		problems.append("only %d buildings" % b.count())
	return problems
