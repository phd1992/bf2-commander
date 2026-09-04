class_name Assets
extends RefCounted
## Commander assets (Section 12): UAV, artillery, supply drop, vehicle drop.
## Both teams have the same four, each with a cooldown and an arrival delay.

var world: World
## team -> { asset name -> time it is ready again }
var ready_at := {}
## team -> Array of { name, cell, at }
var _pending := {}
## team -> Array of { cell, until }
var _uavs := {}
## team -> Array of { cell, shots_left, next_shot }
var _artillery := {}
## team -> Array of { cell, until }
var _crates := {}
var used_count := 0


func _init(p_world: World) -> void:
	world = p_world
	for team in [Balance.Team.BLUE, Balance.Team.RED]:
		ready_at[team] = {}
		for name in Balance.ASSETS.keys():
			ready_at[team][name] = 0.0
		_pending[team] = []
		_uavs[team] = []
		_artillery[team] = []
		_crates[team] = []


func is_ready(team: int, name: String) -> bool:
	return world.time + 0.0001 >= ready_at[team][name]


func cooldown_remaining(team: int, name: String) -> float:
	return maxf(0.0, ready_at[team][name] - world.time)


## Uses an asset at a cell. Returns false when it is on cooldown.
## The cooldown starts now; the effect arrives after the delay.
func use(team: int, name: String, cell: Vector2i) -> bool:
	if not is_ready(team, name) or not world.grid.in_bounds(cell):
		return false
	var spec: Dictionary = Balance.ASSETS[name]
	ready_at[team][name] = world.time + spec["cooldown"]
	_pending[team].append({ "name": name, "cell": cell, "at": world.time + spec["delay"] })
	used_count += 1
	world.match_stats["assets_used"] += 1
	world.events.append({ "type": "asset_used", "team": team, "name": name, "cell": cell })
	return true


func pending(team: int) -> Array:
	return _pending[team]


func active_uavs(team: int) -> Array:
	return _uavs[team]


func active_crates(team: int) -> Array:
	return _crates[team]


func active_artillery(team: int) -> Array:
	return _artillery[team]


## True when a friendly supply crate is within its radius of the position.
func has_supply_near(team: int, pos: Vector2) -> bool:
	var r: float = Balance.ASSETS["SUPPLY"]["radius"]
	for c in _crates[team]:
		if pos.distance_to(Grid.centre_of(c["cell"])) <= r:
			return true
	return false


func update(dt: float) -> void:
	var time := world.time
	for team in [Balance.Team.BLUE, Balance.Team.RED]:
		# arrivals
		var still: Array = []
		for p in _pending[team]:
			if time + 0.0001 >= p["at"]:
				_arrive(team, p["name"], p["cell"])
			else:
				still.append(p)
		_pending[team] = still
		# UAV expiry
		var uavs: Array = []
		for u in _uavs[team]:
			if time < u["until"]:
				uavs.append(u)
		_uavs[team] = uavs
		# artillery shells
		var artys: Array = []
		for a in _artillery[team]:
			while a["shots_left"] > 0 and time + 0.0001 >= a["next_shot"]:
				_fire_shell(team, a["cell"])
				a["shots_left"] -= 1
				a["next_shot"] += Balance.ARTY_SHELL_INTERVAL_S
			if a["shots_left"] > 0:
				artys.append(a)
		_artillery[team] = artys
		# crates: heal
		var crates: Array = []
		for c in _crates[team]:
			if time < c["until"]:
				crates.append(c)
				var centre: Vector2 = Grid.centre_of(c["cell"])
				for m in world.members:
					if m.team == team and m.state == Balance.MemberState.ALIVE and m.pos.distance_to(centre) <= Balance.ASSETS["SUPPLY"]["radius"]:
						m.hp = minf(m.hp + Balance.SUPPLY_HEAL_PER_S * dt, Balance.MEMBER_HP)
		_crates[team] = crates


func _arrive(team: int, name: String, cell: Vector2i) -> void:
	var spec: Dictionary = Balance.ASSETS[name]
	match name:
		"UAV":
			_uavs[team].append({ "cell": cell, "until": world.time + spec["duration"] })
		"ARTILLERY":
			_artillery[team].append({ "cell": cell, "shots_left": Balance.ARTY_SHELLS, "next_shot": world.time })
		"SUPPLY":
			_crates[team].append({ "cell": cell, "until": world.time + spec["duration"] })
		"VEHICLE_DROP":
			var mc: int = Balance.VEHICLES[Balance.VEHICLE_DROP_TYPE]["mclass"]
			var c := world.grid.nearest_passable(cell, mc, 20)
			if c.x >= 0:
				world.spawn_vehicle(Balance.VEHICLE_DROP_TYPE, team, Grid.centre_of(c))
	world.events.append({ "type": "asset_arrived", "team": team, "name": name, "cell": cell })


func _fire_shell(team: int, cell: Vector2i) -> void:
	var r: float = Balance.ASSETS["ARTILLERY"]["radius"]
	var ang := world.rng.randf() * TAU
	var impact := Grid.centre_of(cell) + Vector2.from_angle(ang) * sqrt(world.rng.randf()) * r
	impact.x = clampf(impact.x, 0.0, world.grid.W - 0.01)
	impact.y = clampf(impact.y, 0.0, world.grid.H - 0.01)
	Combat.apply_splash(world, impact, "ARTY_SHELL", null)
