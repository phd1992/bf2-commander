class_name Vehicle
extends RefCounted
## A ground vehicle (Section 7). Movement and combat live in movement.gd and
## combat.gd; this is the data plus small helpers.

var id := 0
var vtype := "JEEP"
var team: int = Balance.Team.BLUE
var hp := 150.0
var max_hp := 150.0
var pos := Vector2.ZERO
var heading := Vector2.RIGHT
var mclass: int = Balance.MoveClass.WHEELED
var seats := 4
var speed := 5.0
var weapon_names: Array = []
var occupants: Array[Member] = []
var owner_squad: Squad = null
var alive := true
var is_moving := false
var pad_index := -1

var path: Array[Vector2i] = []
var path_goal := Vector2i(-1, -1)
var next_repath := 0.0

var last_shot_time := -100.0
var shot_at_time := -100.0
var next_shot := {}


static func create(p_type: String, p_team: int, p_pos: Vector2) -> Vehicle:
	var v := Vehicle.new()
	var spec: Dictionary = Balance.VEHICLES[p_type]
	v.vtype = p_type
	v.team = p_team
	v.pos = p_pos
	v.hp = spec["hp"]
	v.max_hp = spec["hp"]
	v.mclass = spec["mclass"]
	v.seats = spec["seats"]
	v.speed = spec["speed"]
	v.weapon_names = spec["weapons"]
	return v


func is_vehicle() -> bool:
	return true


func is_alive() -> bool:
	return alive


func cell() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))


func free_seats() -> int:
	return seats - occupants.size()


func is_idle() -> bool:
	return alive and occupants.is_empty()


func can_fire() -> bool:
	return alive and occupants.size() >= Balance.VEHICLE_MIN_CREW


## Squad whose accuracy the vehicle uses: the owner, else the first occupant's.
func crew_squad() -> Squad:
	if owner_squad != null:
		return owner_squad
	if not occupants.is_empty():
		return occupants[0].squad
	return null


func size_px() -> Vector2:
	return Balance.VEHICLES[vtype]["size_px"]
