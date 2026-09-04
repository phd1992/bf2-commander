class_name World
extends RefCounted
## Plain-data game world plus its systems. No Node dependencies so it runs
## headless. Rendering reads from it; Sim drives step().

var seed: int = 1
var rng := RandomNumberGenerator.new()
var time := 0.0
var tick_count := 0

var grid: Grid
var pathfinders: Array[Pathfinder] = []   # index = MoveClass
var buildings: Buildings
var flags: Array = []                      # Array[Flag]
var pads: Array = []                       # Array[Dictionary]
var town_rect := Rect2i()
var generator_log: Array = []

var squads: Array[Squad] = []
var members: Array[Member] = []
var vehicles: Array[Vehicle] = []
var tickets := { Balance.Team.BLUE: Balance.START_TICKETS, Balance.Team.RED: Balance.START_TICKETS }
var bleed_timer := 0.0
var spawn_policy: SpawnPolicy
var fog: Fog
var assets: Assets
var ais: Array = []                        # CommanderAI instances (M9)
var match_stats := { "walls_destroyed": 0, "assets_used": 0, "kills": { Balance.Team.BLUE: 0, Balance.Team.RED: 0 } }

## True when any cell's terrain changed since the renderer last looked.
var terrain_dirty := true
## Per-step events consumed by the effects layer: Array[Dictionary].
var events: Array = []

var game_over := false
var winner: int = Balance.Team.NONE

var _next_member_id := 0
var _next_vehicle_id := 0

## All (skill, discipline, aggression, comms) combinations summing to STAT_SUM.
static var _stat_combos: Array = []


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(p_seed: int, with_squads: bool = true) -> void:
	seed = p_seed
	rng.seed = p_seed
	time = 0.0
	tick_count = 0
	var result := MapGenerator.generate(p_seed, generator_log)
	_install_map(result)
	if with_squads:
		create_squads()


func _init() -> void:
	spawn_policy = SpawnConquest.new(self)


## Installs a generated (or hand-built) map. Used by setup() and by tests
## that construct custom grids.
func _install_map(result: Dictionary) -> void:
	grid = result["grid"]
	town_rect = result.get("town_rect", Rect2i())
	pathfinders.clear()
	for mc in 3:
		pathfinders.append(Pathfinder.new(grid, mc))
	grid.cell_listeners.append(_on_cell_changed)
	buildings = Buildings.new(grid)
	buildings.scan()
	fog = Fog.new(self)
	assets = Assets.new(self)
	flags.clear()
	for fd in result.get("flags", []):
		var f := Flag.new()
		f.id = flags.size()
		f.name = fd["name"]
		f.centre = fd["centre"]
		f.is_hq = fd["is_hq"]
		f.owner = fd["team"]
		f.progress = 1.0 if f.owner == Balance.Team.BLUE else (-1.0 if f.owner == Balance.Team.RED else 0.0)
		flags.append(f)
	pads.clear()
	for pd in result.get("pads", []):
		pads.append({ "flag": pd["flag"], "vtype": pd["vtype"], "cell": pd["cell"], "vehicle": null, "respawn_at": 0.0 })
	terrain_dirty = true


## Builds a flat map of one terrain with no flags; tests add what they need.
func setup_blank(p_seed: int, w: int = Balance.MAP_W, h: int = Balance.MAP_H, terrain: int = Balance.Terrain.OPEN) -> void:
	seed = p_seed
	rng.seed = p_seed
	time = 0.0
	tick_count = 0
	_install_map({ "grid": Grid.new(w, h, terrain), "flags": [], "pads": [] })


func _on_cell_changed(c: Vector2i) -> void:
	for pf in pathfinders:
		pf.update_cell(c)
	terrain_dirty = true


func pathfinder(mc: int) -> Pathfinder:
	return pathfinders[mc]


func flag_by_name(n: String) -> Flag:
	for f in flags:
		if f.name == n:
			return f
	return null


func hq_of(team: int) -> Flag:
	for f in flags:
		if f.is_hq and f.owner == team:
			return f
	return null


func flag_count(team: int) -> int:
	var n := 0
	for f in flags:
		if not f.is_hq and f.owner == team:
			n += 1
	return n


## Adds a flag to a hand-built map (tests).
func add_flag(n: String, centre: Vector2i, is_hq: bool = false, owner: int = Balance.Team.NONE) -> Flag:
	var f := Flag.new()
	f.id = flags.size()
	f.name = n
	f.centre = centre
	f.is_hq = is_hq
	f.owner = owner
	f.progress = 1.0 if owner == Balance.Team.BLUE else (-1.0 if owner == Balance.Team.RED else 0.0)
	flags.append(f)
	return f


# ---------------------------------------------------------------------------
# Squads and members
# ---------------------------------------------------------------------------

static func stat_combos() -> Array:
	if _stat_combos.is_empty():
		for a in range(Balance.STAT_MIN, Balance.STAT_MAX + 1):
			for b in range(Balance.STAT_MIN, Balance.STAT_MAX + 1):
				for c in range(Balance.STAT_MIN, Balance.STAT_MAX + 1):
					var d := Balance.STAT_SUM - a - b - c
					if d >= Balance.STAT_MIN and d <= Balance.STAT_MAX:
						_stat_combos.append([a, b, c, d])
	return _stat_combos


## Rolls a BLUE-style stat line: four values in [1,5] summing to 12, uniform
## over all valid combinations.
func roll_stats() -> Array:
	var combos := stat_combos()
	return combos[rng.randi_range(0, combos.size() - 1)]


## Creates 4 squads per team at their HQs (or at explicit positions).
func create_squads() -> void:
	for team in [Balance.Team.BLUE, Balance.Team.RED]:
		var hq := hq_of(team)
		var origin := hq.centre_pos() if hq != null else Vector2(5, 5)
		for i in Balance.SQUAD_NAMES.size():
			var n: String = Balance.SQUAD_NAMES[i]
			if team == Balance.Team.RED:
				n = Balance.RED_SQUAD_PREFIX + n
			var stats: Array
			if team == Balance.Team.BLUE:
				stats = roll_stats()
			else:
				stats = [Balance.RED_FIXED_STAT, Balance.RED_FIXED_STAT, Balance.RED_FIXED_STAT, Balance.RED_FIXED_STAT]
			var offset := Vector2(0, -3.0 + 2.0 * i)
			create_squad(team, n, stats, origin + offset)


func create_squad(team: int, n: String, stats: Array, pos: Vector2) -> Squad:
	var s := Squad.new()
	s.id = squads.size()
	s.team = team
	s.name = n
	s.skill = stats[0]
	s.discipline = stats[1]
	s.aggression = stats[2]
	s.comms = stats[3]
	s.base_skill = s.skill
	var kits := [Balance.Kit.LEADER, Balance.Kit.AT, Balance.Kit.RIFLE, Balance.Kit.RIFLE, Balance.Kit.RIFLE, Balance.Kit.RIFLE]
	for i in Balance.SQUAD_SIZE:
		var m := Member.new()
		m.id = _next_member_id
		_next_member_id += 1
		m.team = team
		m.squad = s
		m.kit = kits[i]
		m.speed_var = rng.randf_range(Balance.SPEED_VAR[0], Balance.SPEED_VAR[1])
		m.next_pause_at = rng.randf_range(Balance.PAUSE_INTERVAL[0], Balance.PAUSE_INTERVAL[1])
		var offset := Vector2.ZERO if i == 0 else Formation.slot("CLUSTER", i - 1)
		m.pos = _nearest_open_pos(pos + offset)
		s.members.append(m)
		members.append(m)
	s.leader = s.members[0]
	squads.append(s)
	return s


func _nearest_open_pos(p: Vector2) -> Vector2:
	var c := grid.clamp_cell(Grid.cell_of(p))
	if grid.is_passable(c, Balance.MoveClass.FOOT):
		return Vector2(clampf(p.x, 0.05, grid.W - 0.05), clampf(p.y, 0.05, grid.H - 0.05))
	var near := grid.nearest_passable(c, Balance.MoveClass.FOOT)
	if near.x < 0:
		return p
	return Grid.centre_of(near)


func squads_of(team: int) -> Array[Squad]:
	var out: Array[Squad] = []
	for s in squads:
		if s.team == team:
			out.append(s)
	return out


## Living members on foot (not dead, not inside a vehicle).
func foot_members() -> Array[Member]:
	var out: Array[Member] = []
	for m in members:
		if m.state == Balance.MemberState.ALIVE:
			out.append(m)
	return out


## Targetable / spotting units of a team: members on foot plus live vehicles.
func units_of(team: int) -> Array:
	var out: Array = []
	for m in members:
		if m.team == team and m.state == Balance.MemberState.ALIVE:
			out.append(m)
	for v in vehicles:
		if v.team == team and v.alive:
			out.append(v)
	return out


## Cells currently occupied by a member on foot (cell -> true).
func occupied_cells() -> Dictionary:
	var out := {}
	for m in members:
		if m.state == Balance.MemberState.ALIVE:
			out[m.cell()] = true
	return out


# ---------------------------------------------------------------------------
# Orders
# ---------------------------------------------------------------------------

## Issues an order. It is acknowledged now and executed after the squad's
## Discipline delay (Section 6.2). `delay_override` < 0 uses the stat delay.
func give_order(s: Squad, type: int, cell: Vector2i = Vector2i(-1, -1), flag: Flag = null, vehicle: Vehicle = null, delay_override: float = -1.0) -> void:
	var delay := s.order_delay() if delay_override < 0.0 else delay_override
	s.pending = { "type": type, "cell": cell, "flag": flag, "vehicle": vehicle, "at": time + delay }
	if delay <= 0.0:
		_apply_order(s, s.pending)
		s.pending = {}


func _execute_pending_orders() -> void:
	for s in squads:
		if s.pending.is_empty() or time < s.pending["at"]:
			continue
		var o: Dictionary = s.pending
		s.pending = {}
		_apply_order(s, o)


func _apply_order(s: Squad, o: Dictionary) -> void:
	var type: int = o["type"]
	if type == Balance.Order.DISMOUNT:
		dismount_squad(s)
		s.order = {}
		s.order_completed = true
		s.arrived = false
		return
	s.order = { "type": type, "cell": o.get("cell", Vector2i(-1, -1)), "flag": o.get("flag"), "vehicle": o.get("vehicle") }
	s.order_completed = false
	s.arrived = false
	s.path.clear()
	s.path_goal = Vector2i(-1, -1)
	s.pursue_goal = Vector2i(-1, -1)
	if type == Balance.Order.MOUNT and o.get("vehicle") != null:
		s.order["vehicle"].owner_squad = s
		s.vehicle = s.order["vehicle"]
	var dest := s.destination()
	if dest.x >= 0:
		s.last_order_cell = dest
	for m in s.members:
		m.path.clear()
		m.path_goal = Vector2i(-1, -1)
		m.defend_cell = Vector2i(-1, -1)
		m.hold_cell = Vector2i(-1, -1)
	if s.vehicle != null:
		s.vehicle.path.clear()
		s.vehicle.path_goal = Vector2i(-1, -1)
	if type == Balance.Order.HOLD:
		s.order_completed = true


# ---------------------------------------------------------------------------
# Vehicles (data-level helpers; behaviour in movement.gd / combat.gd)
# ---------------------------------------------------------------------------

func spawn_vehicle(vtype: String, team: int, pos: Vector2, pad_index: int = -1) -> Vehicle:
	var v := Vehicle.create(vtype, team, pos)
	v.id = _next_vehicle_id
	_next_vehicle_id += 1
	v.pad_index = pad_index
	vehicles.append(v)
	return v


## Vehicle pads (Section 7.2): spawn for the owner when nothing from the pad
## is alive and the respawn timer has elapsed.
func _update_pads() -> void:
	for i in pads.size():
		var p: Dictionary = pads[i]
		var v: Vehicle = p["vehicle"]
		if v != null and v.alive:
			continue
		p["vehicle"] = null
		var flag: Flag = flags[p["flag"]]
		if flag.owner == Balance.Team.NONE or time + 0.0001 < p["respawn_at"]:
			continue
		p["vehicle"] = spawn_vehicle(p["vtype"], flag.owner, Grid.centre_of(p["cell"]), i)


func pad_vehicle(flag_name: String, vtype: String) -> Vehicle:
	var f := flag_by_name(flag_name)
	if f == null:
		return null
	for p in pads:
		if p["flag"] == f.id and p["vtype"] == vtype:
			return p["vehicle"]
	return null


func board_vehicle(m: Member, v: Vehicle) -> void:
	if v.free_seats() <= 0 or not v.alive:
		return
	m.state = Balance.MemberState.IN_VEHICLE
	m.vehicle = v
	m.pos = v.pos
	m.path.clear()
	m.cover_cell = Vector2i(-1, -1)
	v.occupants.append(m)
	if m.squad != null:
		v.owner_squad = m.squad
		m.squad.vehicle = v
	# The whole squad boarded (or all seats are taken): the movement order
	# stored with the MOUNT order takes over.
	if m.squad != null and m.squad.order_type() == Balance.Order.MOUNT:
		var all_in := true
		for o in m.squad.members:
			if o.is_on_foot():
				all_in = false
		if all_in or v.free_seats() <= 0:
			var follow: Dictionary = m.squad.order.get("then", {})
			if follow.is_empty():
				m.squad.order_completed = true
			else:
				_apply_order(m.squad, follow)


func unboard_member(m: Member, v: Vehicle) -> void:
	v.occupants.erase(m)
	m.vehicle = null
	m.state = Balance.MemberState.ALIVE
	var c := grid.nearest_passable(v.cell(), Balance.MoveClass.FOOT, 3)
	var placed := false
	for q in grid.cells_in_radius(v.cell(), Balance.DISMOUNT_RADIUS):
		if grid.is_passable(q, Balance.MoveClass.FOOT) and not occupied_cells().has(q):
			m.pos = Grid.centre_of(q)
			placed = true
			break
	if not placed:
		m.pos = Grid.centre_of(c) if c.x >= 0 else v.pos
	m.detached = false
	m.path.clear()


func dismount_squad(s: Squad) -> void:
	var v := s.vehicle
	if v == null:
		return
	for m in s.members.duplicate():
		if m.state == Balance.MemberState.IN_VEHICLE and m.vehicle == v:
			unboard_member(m, v)
	s.vehicle = null
	if v.occupants.is_empty():
		v.owner_squad = null
		v.path.clear()


# ---------------------------------------------------------------------------
# Deaths and respawns
# ---------------------------------------------------------------------------

## Kills a member. `killer` is the squad credited with the kill (or null).
func kill_member(m: Member, killer: Squad = null) -> void:
	if m.state == Balance.MemberState.DEAD:
		return
	if m.state == Balance.MemberState.IN_VEHICLE and m.vehicle != null:
		m.vehicle.occupants.erase(m)
		if m.vehicle.occupants.is_empty():
			m.vehicle.owner_squad = null
		m.vehicle = null
	m.state = Balance.MemberState.DEAD
	m.death_time = time
	m.deaths += 1
	m.reset_movement()
	var s := m.squad
	s.deaths += 1
	if killer != null and killer.team != m.team:
		killer.kills += 1
		killer.add_xp(Balance.XP_KILL)
		match_stats["kills"][killer.team] += 1
	events.append({ "type": "death", "pos": m.pos, "team": m.team })
	s.refresh_leader()
	if s.is_wiped():
		s.reset_veterancy()
		s.wiped_since = time
		s.vehicle = null
		spawn_policy.request_squad_respawn(s)
	else:
		spawn_policy.request_member_respawn(m)


func destroy_vehicle(v: Vehicle, killer: Squad = null) -> void:
	if not v.alive:
		return
	v.alive = false
	v.hp = 0.0
	events.append({ "type": "vehicle_destroyed", "pos": v.pos, "team": v.team, "vtype": v.vtype })
	for m in v.occupants.duplicate():
		kill_member(m, killer)
	v.occupants.clear()
	if v.owner_squad != null and v.owner_squad.vehicle == v:
		v.owner_squad.vehicle = null
	v.owner_squad = null
	if killer != null and killer.team != v.team:
		killer.vehicle_kills += 1
		killer.add_xp(Balance.XP_VEHICLE)
	if v.pad_index >= 0 and v.pad_index < pads.size():
		pads[v.pad_index]["vehicle"] = null
		pads[v.pad_index]["respawn_at"] = time + Balance.PAD_RESPAWN_S
	vehicles.erase(v)


## Applies weapon damage to a WALL cell (Section 9).
func damage_wall(c: Vector2i, dmg: float) -> void:
	if buildings.damage_wall(c, dmg):
		match_stats["walls_destroyed"] += 1
		events.append({ "type": "wall_down", "cell": c })


func _apply_collapses() -> void:
	var collapsed := buildings.check_collapses()
	if collapsed.is_empty():
		return
	events.append({ "type": "collapse", "cells": collapsed })
	var hit := {}
	for c in collapsed:
		hit[c] = true
	for m in members:
		if m.state == Balance.MemberState.ALIVE and hit.has(m.cell()):
			m.hp -= Balance.COLLAPSE_DAMAGE
			if m.hp <= 0.0:
				kill_member(m, null)


func revive_member(m: Member, pos: Vector2) -> void:
	m.state = Balance.MemberState.ALIVE
	m.hp = Balance.MEMBER_HP
	m.pos = pos
	m.vehicle = null
	m.respawn_at = -1.0
	m.shot_at_time = -100.0
	m.last_shot_time = -100.0
	m.reset_movement()
	m.next_pause_at = time + rng.randf_range(Balance.PAUSE_INTERVAL[0], Balance.PAUSE_INTERVAL[1])
	m.squad.refresh_leader()


# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------

func _update_flags(dt: float) -> void:
	for f: Flag in flags:
		if f.is_hq:
			continue
		var blue := 0
		var red := 0
		var present: Array = []
		var centre := f.centre_pos()
		var r := f.radius()
		for m in members:
			if not m.is_alive():
				continue
			if m.pos.distance_to(centre) <= r:
				if m.team == Balance.Team.BLUE:
					blue += 1
				else:
					red += 1
				if m.squad not in present:
					present.append(m.squad)
		var captured := f.update_capture(blue, red, dt)
		if captured != Balance.Team.NONE:
			events.append({ "type": "capture", "flag": f, "team": captured })
			for s in present:
				if s.team == captured:
					s.add_xp(Balance.XP_CAPTURE)
					s.captures += 1
			_on_flag_owner_changed(f)


## Hook for pad vehicles changing side (Section 7.2); filled in with vehicles.
func _on_flag_owner_changed(f: Flag) -> void:
	for p in pads:
		if p["flag"] != f.id:
			continue
		var v: Vehicle = p["vehicle"]
		if v != null and v.alive and v.is_idle():
			v.team = f.owner


# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

func step(dt: float) -> void:
	if game_over:
		return
	tick_count += 1
	time = tick_count * dt
	_execute_pending_orders()
	_update_pads()
	Movement.update(self, dt)
	fog.update_spotting()
	Combat.update(self, dt)
	_apply_collapses()
	_update_flags(dt)
	Tickets.update(self, dt)
	spawn_policy.tick(dt)
	assets.update(dt)
	_apply_collapses()
	for ai in ais:
		ai.update(self)
	Tickets.check_victory(self)
