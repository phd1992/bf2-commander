class_name Grid
extends RefCounted
## Cell storage for the map: terrain, elevation, building ids and wall HP.
## Index is y * W + x. Positions of units are floats in cell units; the cell a
## unit stands in is floor(pos).

var W: int
var H: int
var terrain := PackedByteArray()
var elevation := PackedByteArray()
var building_id := PackedInt32Array()
var wall_hp := PackedByteArray()

## Callables invoked with (cell: Vector2i) whenever a cell's terrain changes.
## Pathfinders and the renderer subscribe here.
var cell_listeners: Array[Callable] = []

# Flattened lookup tables so hot loops avoid dictionary access.
var _speed_table := PackedFloat32Array()   # index terrain * 3 + move class
var _cover_table := PackedFloat32Array()
var _blocker_table := PackedFloat32Array()


func _init(w: int = Balance.MAP_W, h: int = Balance.MAP_H, fill_terrain: int = Balance.Terrain.OPEN) -> void:
	W = w
	H = h
	terrain.resize(W * H)
	terrain.fill(fill_terrain)
	elevation.resize(W * H)
	elevation.fill(0)
	building_id.resize(W * H)
	building_id.fill(-1)
	wall_hp.resize(W * H)
	wall_hp.fill(0)
	for t in Balance.TERRAIN.keys():
		for mc in 3:
			_speed_table.append(Balance.terrain_speed(t, mc))
		_cover_table.append(Balance.terrain_cover(t))
		_blocker_table.append(Balance.terrain_blocker(t))


# --- coordinates ------------------------------------------------------------

func idx(x: int, y: int) -> int:
	return y * W + x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))


static func centre_of(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


func clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, W - 1), clampi(c.y, 0, H - 1))


# --- terrain ----------------------------------------------------------------

func get_terrain(c: Vector2i) -> int:
	return terrain[c.y * W + c.x]


func get_terrain_xy(x: int, y: int) -> int:
	return terrain[y * W + x]


## Sets the terrain of a cell and notifies listeners. Also resets wall HP when
## a cell becomes a WALL and clears it otherwise.
func set_terrain(c: Vector2i, t: int, notify: bool = true) -> void:
	var i := c.y * W + c.x
	if terrain[i] == t:
		return
	terrain[i] = t
	wall_hp[i] = Balance.WALL_HP if t == Balance.Terrain.WALL else 0
	if notify:
		for cb in cell_listeners:
			cb.call(c)


func get_elev(c: Vector2i) -> int:
	return elevation[c.y * W + c.x]


func set_elev(c: Vector2i, e: int) -> void:
	elevation[c.y * W + c.x] = clampi(e, 0, Balance.MAX_ELEVATION)


func get_building(c: Vector2i) -> int:
	return building_id[c.y * W + c.x]


func get_wall_hp(c: Vector2i) -> int:
	return wall_hp[c.y * W + c.x]


func set_wall_hp(c: Vector2i, hp: int) -> void:
	wall_hp[c.y * W + c.x] = clampi(hp, 0, 255)


# --- derived properties -------------------------------------------------------

func speed_mult(c: Vector2i, mc: int) -> float:
	return _speed_table[terrain[c.y * W + c.x] * 3 + mc]


func is_passable(c: Vector2i, mc: int) -> bool:
	return in_bounds(c) and _speed_table[terrain[c.y * W + c.x] * 3 + mc] > 0.0


func cover(c: Vector2i) -> float:
	return _cover_table[terrain[c.y * W + c.x]]


func blocker(c: Vector2i) -> float:
	return _blocker_table[terrain[c.y * W + c.x]]


## Height that blocks line of sight at this cell: elevation + terrain blocker.
func los_top(c: Vector2i) -> float:
	var i := c.y * W + c.x
	return float(elevation[i]) + _blocker_table[terrain[i]]


## Uphill cost multiplier when moving from a to b (downhill is 1.0).
func slope_mult(a: Vector2i, b: Vector2i, mc: int) -> float:
	var dh := get_elev(b) - get_elev(a)
	if dh <= 0:
		return 1.0
	return 1.0 + Balance.SLOPE_PER_LEVEL[mc] * dh


## True when the elevation change between a and b is a cliff for the class.
func is_cliff(a: Vector2i, b: Vector2i, mc: int) -> bool:
	return absi(get_elev(b) - get_elev(a)) >= Balance.CLIFF_THRESHOLD[mc]


## True when a unit of the given class may step from a to adjacent b.
func can_step(a: Vector2i, b: Vector2i, mc: int) -> bool:
	return is_passable(b, mc) and not is_cliff(a, b, mc)


# --- queries -----------------------------------------------------------------

## All in-bounds cells whose centre is within radius r of the centre cell.
func cells_in_radius(centre: Vector2i, r: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ir := int(ceil(r))
	for dy in range(-ir, ir + 1):
		for dx in range(-ir, ir + 1):
			if dx * dx + dy * dy <= r * r:
				var c := Vector2i(centre.x + dx, centre.y + dy)
				if in_bounds(c):
					out.append(c)
	return out


## Nearest passable cell for the class, searching outward from the target.
## Returns the target itself when it is passable, or Vector2i(-1, -1) if none
## is found within max_r.
func nearest_passable(target: Vector2i, mc: int, max_r: int = 12) -> Vector2i:
	if is_passable(target, mc):
		return target
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := 1.0e9
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := Vector2i(target.x + dx, target.y + dy)
				if is_passable(c, mc):
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func fill_rect(x0: int, y0: int, w: int, h: int, t: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if x >= 0 and y >= 0 and x < W and y < H:
				set_terrain(Vector2i(x, y), t, false)
