class_name Fog
extends RefCounted
## Fog of war and intel (Section 11): per-team spotting, contact reports with
## Comms delays, and (for rendering only) per-cell visibility.

var world: World
## team -> { unit: true } : enemy units currently spotted by that team.
var vision := { Balance.Team.BLUE: {}, Balance.Team.RED: {} }
## team -> { unit: contact } : contact = { unit, first_seen, reveal_at, last_seen, persist_until, pos, uav }
var contacts := { Balance.Team.BLUE: {}, Balance.Team.RED: {} }

## Rendering-only cell visibility for one team: 1 = seen now / seen ever.
var cell_seen_now := PackedByteArray()
var cell_seen_ever := PackedByteArray()
var cell_vision_team: int = Balance.Team.BLUE
var _next_cell_vision := 0.0


func _init(p_world: World) -> void:
	world = p_world
	cell_seen_now.resize(world.grid.W * world.grid.H)
	cell_seen_ever.resize(world.grid.W * world.grid.H)


# ---------------------------------------------------------------------------
# Unit spotting (every tick)
# ---------------------------------------------------------------------------

func update_spotting() -> void:
	var grid := world.grid
	var time := world.time
	for team in vision.keys():
		vision[team] = {}
	for s in world.squads:
		s.visible_enemies = {}
	for team in [Balance.Team.BLUE, Balance.Team.RED]:
		var enemy := Balance.other_team(team)
		var spotters := world.units_of(team)
		var targets := world.units_of(enemy)
		if targets.is_empty():
			continue
		var seen: Dictionary = vision[team]
		for sp in spotters:
			var sp_cell: Vector2i = sp.cell()
			var sp_veh: bool = sp.is_vehicle()
			var sp_eye := LOS.eye_height(grid, sp_cell, sp_veh)
			var spot_range := Balance.SPOT_VEH if sp_veh else Balance.SPOT_INF
			var squad: Squad = sp.crew_squad() if sp_veh else sp.squad
			for tg in targets:
				var d: float = sp.pos.distance_to(tg.pos)
				if d > Balance.FLASH_RANGE:
					continue
				var limit: float
				if tg.is_vehicle():
					limit = Balance.SPOT_VEH
				elif time - tg.last_shot_time <= Balance.FLASH_S:
					limit = Balance.FLASH_RANGE
				else:
					var t: int = grid.get_terrain(tg.cell())
					limit = Balance.SPOT_CONCEALED if (t == Balance.Terrain.FOREST or t == Balance.Terrain.INTERIOR) else spot_range
				if d > limit:
					continue
				var tg_cell: Vector2i = tg.cell()
				if not LOS.has_los(grid, sp_cell, sp_eye, tg_cell, LOS.eye_height(grid, tg_cell, tg.is_vehicle())):
					continue
				seen[tg] = true
				if squad != null:
					squad.visible_enemies[tg] = true
					if _touch_contact(team, tg, squad.comms_delay(), squad.comms_persist()):
						squad.contacts_reported += 1
	# UAV: live contacts for everything inside the circle.
	if world.assets != null:
		for team in [Balance.Team.BLUE, Balance.Team.RED]:
			for u in world.assets.active_uavs(team):
				var centre: Vector2 = Grid.centre_of(u["cell"])
				for tg in world.units_of(Balance.other_team(team)):
					if tg.pos.distance_to(centre) <= Balance.ASSETS["UAV"]["radius"]:
						vision[team][tg] = true
						_touch_contact(team, tg, 0.0, Balance.TICK * 2.0, true)
	# Reaction timers: a squad that just gained its first contact waits.
	for s in world.squads:
		if s.visible_enemies.is_empty():
			s.contact_since = -1.0
		elif s.contact_since < 0.0:
			s.contact_since = time
	_purge_contacts()


## Creates or refreshes a contact. Returns true when a new report was created.
func _touch_contact(team: int, unit, delay: float, persist: float, uav: bool = false) -> bool:
	var time := world.time
	var table: Dictionary = contacts[team]
	var c: Dictionary = table.get(unit, {})
	var created := false
	if c.is_empty() or time > c["persist_until"]:
		c = { "unit": unit, "first_seen": time, "reveal_at": time + delay, "last_seen": time, "persist_until": time + persist, "pos": unit.pos, "uav": uav }
		table[unit] = c
		created = true
	else:
		c["reveal_at"] = minf(c["reveal_at"], time + delay)
		c["last_seen"] = time
		c["persist_until"] = maxf(c["persist_until"], time + persist)
		c["uav"] = c["uav"] or uav
	c["pos"] = unit.pos
	return created


func _purge_contacts() -> void:
	if world.tick_count % 20 != 0:
		return
	for team in contacts.keys():
		var table: Dictionary = contacts[team]
		for u in table.keys():
			if world.time > table[u]["persist_until"] or not u.is_alive():
				table.erase(u)


## Contacts a commander of `team` can see right now (after Comms delay,
## before fade). Each entry is the contact dictionary.
func revealed_contacts(team: int, time: float) -> Array:
	var out: Array = []
	for c in contacts[team].values():
		if time >= c["reveal_at"] and time <= c["persist_until"] and c["unit"].is_alive():
			out.append(c)
	return out


func is_visible_to(team: int, unit) -> bool:
	return vision[team].has(unit)


# ---------------------------------------------------------------------------
# Cell visibility for rendering (not part of the simulation)
# ---------------------------------------------------------------------------

## Recomputes which cells `team` can currently see, at most every
## CELL_VISION_INTERVAL_S. Returns true when the arrays changed.
func update_cell_vision(team: int, force: bool = false) -> bool:
	if not force and world.time < _next_cell_vision:
		return false
	_next_cell_vision = world.time + Balance.CELL_VISION_INTERVAL_S
	cell_vision_team = team
	var grid := world.grid
	var W := grid.W
	cell_seen_now.fill(0)
	for u in world.units_of(team):
		var origin: Vector2i = u.cell()
		var range_cells := Balance.SPOT_VEH if u.is_vehicle() else Balance.SPOT_INF
		var eye := LOS.eye_height(grid, origin, u.is_vehicle())
		_cast_rays(origin, eye, range_cells)
	for i in cell_seen_now.size():
		if cell_seen_now[i] == 1:
			cell_seen_ever[i] = 1
	return true


## Shadow-casting by rays to the perimeter of the spot circle; a cell is
## visible if the sight line to a FOOT eye standing there is unobstructed.
func _cast_rays(origin: Vector2i, eye: float, r: float) -> void:
	var grid := world.grid
	var W := grid.W
	var ir := int(ceil(r))
	var idx0 := origin.y * W + origin.x
	cell_seen_now[idx0] = 1
	var perimeter: Array[Vector2i] = []
	for dx in range(-ir, ir + 1):
		perimeter.append(Vector2i(origin.x + dx, origin.y - ir))
		perimeter.append(Vector2i(origin.x + dx, origin.y + ir))
	for dy in range(-ir + 1, ir):
		perimeter.append(Vector2i(origin.x - ir, origin.y + dy))
		perimeter.append(Vector2i(origin.x + ir, origin.y + dy))
	var r2 := r * r
	for end in perimeter:
		var line := LOS.bresenham(origin, end)
		var max_slope := -1.0e9
		for i in range(1, line.size()):
			var c := line[i]
			if not grid.in_bounds(c):
				break
			var dist2 := float((c.x - origin.x) * (c.x - origin.x) + (c.y - origin.y) * (c.y - origin.y))
			if dist2 > r2:
				break
			var dist := sqrt(dist2)
			var target_eye := float(grid.get_elev(c)) + Balance.EYE_FOOT
			# visible when the eye line to this cell clears every previous blocker
			if (target_eye - eye) / dist >= max_slope - Balance.LOS_EPS:
				cell_seen_now[c.y * W + c.x] = 1
			var top := grid.los_top(c)
			max_slope = maxf(max_slope, (top - eye) / dist)
