class_name SpawnPolicy
extends RefCounted
## Spawning interface (Section 10.1). Conquest implements it in v1; Broken
## Arrow (Phase 2) can be added without touching squads, flags or combat.

var world: World


func _init(p_world: World = null) -> void:
	world = p_world


## Cells a team may spawn at right now.
func get_spawn_points(team: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for f in spawn_flags(team):
		out.append(f.centre)
	return out


## Flags (including the HQ) a team may spawn at right now.
func spawn_flags(team: int) -> Array:
	var out: Array = []
	for f in world.flags:
		if f.is_spawnable_for(team):
			out.append(f)
	return out


## Called when a member dies.
func request_member_respawn(_member: Member) -> void:
	pass


## Called when the 6th member dies.
func request_squad_respawn(_squad: Squad) -> void:
	pass


## Commander choice of where a fully dead squad comes back.
func set_preferred_spawn(_squad: Squad, _cell: Vector2i) -> void:
	pass


## Advance timers and perform spawns.
func tick(_dt: float) -> void:
	pass
