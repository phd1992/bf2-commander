class_name SpawnBrokenArrow
extends SpawnPolicy
## Broken Arrow spawning (Section 19.1). No respawns: dead soldiers stay
## dead and a wiped squad is gone until it is bought back. Each team earns
## reinforcement points (10/min + 2/min per owned flag) and spends them on
## squads and vehicles that enter at one of three map-edge entry points.
## Flags still bleed tickets; death costs nothing but the replacement.

var points := { Balance.Team.BLUE: Balance.BA_START_POINTS, Balance.Team.RED: Balance.BA_START_POINTS }
## squad -> entry index chosen by the commander for its next purchase.
var entry_choice := {}
var purchases := { Balance.Team.BLUE: 0, Balance.Team.RED: 0 }


## Entry points are the spawn points in this mode.
func get_spawn_points(team: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in world.entry_points[team]:
		out.append(c)
	return out


## No flags to choose from: the purchase panel replaces the selector.
func spawn_flags(_team: int) -> Array:
	return []


func request_member_respawn(_member: Member) -> void:
	pass   # the dead stay dead


func request_squad_respawn(_squad: Squad) -> void:
	pass   # bought back explicitly, never automatically


func set_preferred_spawn(s: Squad, cell: Vector2i) -> void:
	var pts: Array = world.entry_points[s.team]
	for i in pts.size():
		if pts[i] == cell:
			entry_choice[s] = i
			return


func entry_index_for(s: Squad) -> int:
	return entry_choice.get(s, 1)


func tick(dt: float) -> void:
	for team in [Balance.Team.BLUE, Balance.Team.RED]:
		var per_min: float = Balance.BA_INCOME_PER_MIN + Balance.BA_INCOME_PER_FLAG_PER_MIN * world.flag_count(team)
		points[team] += per_min * dt / 60.0


func income_per_min(team: int) -> float:
	return Balance.BA_INCOME_PER_MIN + Balance.BA_INCOME_PER_FLAG_PER_MIN * world.flag_count(team)


func can_afford(team: int, cost: float) -> bool:
	return points[team] + 0.0001 >= cost


## Buys a wiped squad back at an entry point. Returns false when the squad
## is still alive, the entry is invalid or the team cannot pay.
func buy_squad(s: Squad, entry_index: int = -1) -> bool:
	if not s.is_wiped():
		return false
	if entry_index < 0:
		entry_index = entry_index_for(s)
	var pts: Array = world.entry_points[s.team]
	if pts.is_empty():
		return false
	entry_index = clampi(entry_index, 0, pts.size() - 1)
	if not can_afford(s.team, Balance.BA_COST_SQUAD):
		return false
	points[s.team] -= Balance.BA_COST_SQUAD
	purchases[s.team] += 1
	world.rebuy_squad(s, Grid.centre_of(pts[entry_index]))
	return true


## Buys a vehicle of the given type at an entry point. Returns the vehicle
## or null when the team cannot pay or nothing passable is near the entry.
func buy_vehicle(team: int, vtype: String, entry_index: int = 1) -> Vehicle:
	if not Balance.BA_COST_VEHICLE.has(vtype):
		return null
	var cost: float = Balance.BA_COST_VEHICLE[vtype]
	if not can_afford(team, cost):
		return null
	var pts: Array = world.entry_points[team]
	if pts.is_empty():
		return null
	entry_index = clampi(entry_index, 0, pts.size() - 1)
	var mc: int = Balance.VEHICLES[vtype]["mclass"]
	var cell := world.grid.nearest_passable(pts[entry_index], mc, 12)
	if cell.x < 0:
		return null
	points[team] -= cost
	purchases[team] += 1
	return world.spawn_vehicle(vtype, team, Grid.centre_of(cell))
