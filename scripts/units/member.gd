class_name Member
extends RefCounted
## One soldier. Belongs to exactly one squad.

var id := 0
var team: int = Balance.Team.BLUE
var squad: Squad
var kit: int = Balance.Kit.RIFLE
var hp := Balance.MEMBER_HP
var pos := Vector2.ZERO
var state: int = Balance.MemberState.ALIVE
var speed_var := 1.0
var heading := Vector2.RIGHT
var is_moving := false

## Time this member last fired (muzzle flash / concealment break).
var last_shot_time := -100.0
## Time a shot was last resolved against this member (hit or miss).
var shot_at_time := -100.0
## Weapon name -> time the weapon is ready again.
var next_shot := {}

# movement bookkeeping
var slot_index := 0
var path: Array[Vector2i] = []
var path_time := -100.0
var path_goal := Vector2i(-1, -1)
var cover_cell := Vector2i(-1, -1)
var hold_cell := Vector2i(-1, -1)
var defend_cell := Vector2i(-1, -1)
var detached := false
var pause_until := 0.0
var next_pause_at := 0.0
var bound_team := 0

var vehicle: Vehicle = null
var death_time := -100.0
var respawn_at := -1.0
var kills := 0
var deaths := 0


func is_vehicle() -> bool:
	return false


func is_alive() -> bool:
	return state != Balance.MemberState.DEAD


func is_on_foot() -> bool:
	return state == Balance.MemberState.ALIVE


func cell() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))


func is_leader() -> bool:
	return squad != null and squad.leader == self


func kit_name() -> String:
	match kit:
		Balance.Kit.LEADER: return "LEADER"
		Balance.Kit.AT: return "AT"
	return "RIFLE"


## Weapons this member can use, in priority order.
func weapons() -> Array:
	if kit == Balance.Kit.AT:
		return ["AT", "RIFLE"]
	return ["RIFLE"]


func reset_movement() -> void:
	path.clear()
	path_goal = Vector2i(-1, -1)
	cover_cell = Vector2i(-1, -1)
	hold_cell = Vector2i(-1, -1)
	defend_cell = Vector2i(-1, -1)
	detached = false
