class_name Squad
extends RefCounted
## Six members, one leader, four stats, one order at a time (Section 6).

var id := 0
var team: int = Balance.Team.BLUE
var name := ""
var members: Array[Member] = []
var leader: Member = null

# stats 1-5
var skill := 3
var discipline := 3
var aggression := 3
var comms := 3
var base_skill := 3
var xp := 0
var xp_level := 0

## Current order: { "type": Balance.Order, "cell": Vector2i, "flag": Flag, "vehicle": Vehicle }
var order := {}
## Pending order waiting for the Discipline delay: same keys plus "at".
var pending := {}
var order_completed := false
## Leader has reached the order destination at least once.
var arrived := false
var last_order_cell := Vector2i(-1, -1)

var formation := "WEDGE"
var formation_pending := ""
var formation_pending_since := 0.0
var path: Array[Vector2i] = []
var path_goal := Vector2i(-1, -1)
var next_repath := 0.0
var pursue_goal := Vector2i(-1, -1)

var vehicle: Vehicle = null
var in_combat := false
var contact_since := -1.0
## Enemy units seen by this squad's own members this tick (unit -> true).
var visible_enemies := {}
var bound := { "moving": 0, "start_pos": Vector2.ZERO, "start_time": 0.0 }

var kills := 0
var deaths := 0
var vehicle_kills := 0
var captures := 0

# Observed events for hidden-stat reveals (Section 19.3)
var orders_executed := 0
var shots_fired := 0
var contacts_reported := 0
var objectives_in_combat := 0
var spawn_pref: Flag = null
var wipe_respawn_at := -1.0
var wiped_since := -1.0


func living() -> Array[Member]:
	var out: Array[Member] = []
	for m in members:
		if m.is_alive():
			out.append(m)
	return out


func alive_count() -> int:
	var n := 0
	for m in members:
		if m.is_alive():
			n += 1
	return n


func is_wiped() -> bool:
	return alive_count() == 0


func avg_hp() -> float:
	var alive := living()
	if alive.is_empty():
		return 0.0
	var total := 0.0
	for m in alive:
		total += m.hp
	return total / alive.size()


## Promotes the next living member (AT first, then rifles) when the leader is dead.
func refresh_leader() -> void:
	if leader != null and leader.is_alive():
		return
	leader = null
	for m in members:
		if m.is_alive() and m.kit == Balance.Kit.AT:
			leader = m
			break
	if leader == null:
		for m in members:
			if m.is_alive():
				leader = m
				break


func leader_pos() -> Vector2:
	if leader == null:
		return Vector2(-1, -1)
	return leader.pos


func accuracy_mult() -> float:
	return Balance.accuracy_mult(skill)


func reaction_time() -> float:
	return Balance.reaction_time(skill)


func order_delay() -> float:
	return Balance.order_delay(discipline)


func cover_resume() -> float:
	return Balance.cover_resume(discipline)


func bound_length() -> float:
	return Balance.bound_length(aggression)


func comms_delay() -> float:
	return Balance.comms_delay(comms)


func comms_persist() -> float:
	return Balance.comms_persist(comms)


func order_type() -> int:
	return order.get("type", Balance.Order.NONE)


func has_order() -> bool:
	return order_type() != Balance.Order.NONE


## Idle = nothing pending and either no order or a completed one.
func is_idle() -> bool:
	return pending.is_empty() and (not has_order() or order_completed)


func is_mounted() -> bool:
	return leader != null and leader.state == Balance.MemberState.IN_VEHICLE


## Cell the squad is trying to reach, or (-1,-1) when it has nowhere to go.
func destination() -> Vector2i:
	match order_type():
		Balance.Order.MOVE:
			return order["cell"]
		Balance.Order.ATTACK, Balance.Order.DEFEND:
			return order["flag"].centre
		Balance.Order.MOUNT:
			var v: Vehicle = order.get("vehicle")
			if v != null and v.alive:
				return v.cell()
	return Vector2i(-1, -1)


func objective_pos() -> Vector2:
	var d := destination()
	return Grid.centre_of(d) if d.x >= 0 else leader_pos()


func stats_text() -> String:
	return "S%d D%d A%d C%d" % [skill, discipline, aggression, comms]


func skill_revealed() -> bool:
	return shots_fired >= Balance.HIDDEN_SHOTS_FOR_SKILL


func discipline_revealed() -> bool:
	return orders_executed >= Balance.HIDDEN_ORDERS_FOR_DISCIPLINE


func aggression_revealed() -> bool:
	return objectives_in_combat >= Balance.HIDDEN_OBJECTIVES_FOR_AGGRESSION


func comms_revealed() -> bool:
	return contacts_reported >= Balance.HIDDEN_CONTACTS_FOR_COMMS


## Stats with "?" for values the commander has not observed yet.
func hidden_stats_text() -> String:
	return "S%s D%s A%s C%s" % [
		str(skill) if skill_revealed() else "?",
		str(discipline) if discipline_revealed() else "?",
		str(aggression) if aggression_revealed() else "?",
		str(comms) if comms_revealed() else "?"]


func order_text() -> String:
	var t := ""
	match order_type():
		Balance.Order.NONE: t = "idle"
		Balance.Order.MOVE: t = "MOVE %s" % str(order["cell"])
		Balance.Order.ATTACK: t = "ATTACK %s" % order["flag"].name
		Balance.Order.DEFEND: t = "DEFEND %s" % order["flag"].name
		Balance.Order.MOUNT: t = "MOUNT %s" % (order["vehicle"].vtype if order.get("vehicle") != null else "")
		Balance.Order.HOLD: t = "HOLD"
		Balance.Order.DISMOUNT: t = "DISMOUNT"
	if order_completed:
		t += " (done)"
	if not pending.is_empty():
		t += " -> pending"
	return t


func add_xp(amount: int) -> void:
	xp += amount
	while xp_level < Balance.XP_THRESHOLDS.size() and xp >= Balance.XP_THRESHOLDS[xp_level]:
		xp_level += 1
		skill = mini(skill + 1, Balance.STAT_MAX)


func reset_veterancy() -> void:
	xp = 0
	xp_level = 0
	skill = base_skill
