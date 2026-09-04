class_name CommanderAI
extends RefCounted
## Rule-based commander (Section 13). Works for either team, so the headless
## sim can run AI vs AI. Runs every AI_TICK_S seconds of sim time and only
## knows its own team's revealed contacts (no cheating on vision).
## Each rule is its own function and can be switched off in `enabled`.

var team: int
var next_tick := 0.0
var enabled := {
	"defend": true, "attack": true, "desperation": true, "artillery": true,
	"uav": true, "supply": true, "vehicle_drop": true, "vehicles": true,
}
## Flag targeted by the most recent ATTACK order (used to aim the UAV).
var last_attack_flag: Flag = null
## Counters for the headless report / tests.
var orders_issued := 0
var mounts_issued := 0


func _init(p_team: int, first_tick: float = Balance.AI_TICK_S) -> void:
	team = p_team
	next_tick = first_tick


func update(w: World) -> void:
	if w.time + 0.0001 < next_tick:
		return
	next_tick = w.time + Balance.AI_TICK_S
	tick(w)


func tick(w: World) -> void:
	var contacts := w.fog.revealed_contacts(team, w.time)
	_rule_auto_dismount(w)
	if enabled["defend"]:
		_rule_defend(w, contacts)
	if enabled["attack"]:
		_rule_attack(w, contacts)
	if enabled["desperation"]:
		_rule_desperation(w)
	if enabled["artillery"]:
		_rule_artillery(w, contacts)
	if enabled["uav"]:
		_rule_uav(w, contacts)
	if enabled["supply"]:
		_rule_supply(w)
	if enabled["vehicle_drop"]:
		_rule_vehicle_drop(w)


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

## 1. Own flags with enemy contacts nearby and no own squad nearby get a defender.
func _rule_defend(w: World, contacts: Array) -> void:
	for f in _own_flags(w):
		if _contacts_near(contacts, f.centre_pos(), Balance.AI_DEFEND_RADIUS).is_empty():
			continue
		if _squad_near(w, f.centre_pos(), Balance.AI_DEFEND_RADIUS) != null:
			continue
		var best: Squad = null
		var best_d := 1.0e9
		for s in _living_squads(w):
			if _is_capturing(s) or (s.order_type() == Balance.Order.DEFEND and s.order["flag"] == f):
				continue
			var d := _squad_pos(s).distance_to(f.centre_pos())
			if d < best_d:
				best_d = d
				best = s
		if best != null:
			_issue(w, best, Balance.Order.DEFEND, f)


## 2. Every idle squad attacks the most valuable reachable flag.
func _rule_attack(w: World, contacts: Array) -> void:
	var targets := _non_own_flags(w)
	for s in _living_squads(w):
		if not _is_idle_for_ai(w, s, contacts):
			continue
		if targets.is_empty():
			_defend_forward(w, s)
			continue
		var best: Flag = null
		var best_score := -1.0
		for f in targets:
			if _assigned_count(w, f) >= Balance.AI_MAX_PER_FLAG and targets.size() > 1:
				continue
			var score := _flag_value(f, contacts) / (_squad_pos(s).distance_to(f.centre_pos()) + Balance.AI_FLAG_DIST_BIAS)
			if score > best_score:
				best_score = score
				best = f
		if best != null:
			_issue(w, s, Balance.Order.ATTACK, best)


## 3. Far behind and bleeding: everyone still idle attacks the nearest flag.
func _rule_desperation(w: World) -> void:
	var enemy := Balance.other_team(team)
	if w.tickets[team] >= w.tickets[enemy] - Balance.AI_DESPERATION_MARGIN:
		return
	if not Tickets.is_bleeding(w, team):
		return
	var targets := _non_own_flags(w)
	if targets.is_empty():
		return
	for s in _living_squads(w):
		if not s.is_idle():
			continue
		var best: Flag = null
		var best_d := 1.0e9
		for f in targets:
			var d := _squad_pos(s).distance_to(f.centre_pos())
			if d < best_d:
				best_d = d
				best = f
		_issue(w, s, Balance.Order.ATTACK, best)


## 4. Artillery on the biggest safe cluster of contacts (or any vehicle).
func _rule_artillery(w: World, contacts: Array) -> void:
	if not w.assets.is_ready(team, "ARTILLERY"):
		return
	var radius: float = Balance.ASSETS["ARTILLERY"]["radius"]
	var best_pos := Vector2(-1, -1)
	var best_count := 0
	var own_units := w.units_of(team)
	for c in contacts:
		var centre: Vector2 = c["pos"]
		var cluster := _contacts_near(contacts, centre, radius)
		var has_vehicle := false
		for cc in cluster:
			if cc["unit"].is_vehicle():
				has_vehicle = true
		if cluster.size() < Balance.AI_ARTY_MIN_CLUSTER and not has_vehicle:
			continue
		var safe := true
		for u in own_units:
			if u.pos.distance_to(centre) <= Balance.AI_ARTY_SAFE_DIST:
				safe = false
				break
		if not safe:
			continue
		var weight := cluster.size() + (Balance.AI_ARTY_MIN_CLUSTER if has_vehicle else 0)
		if weight > best_count:
			best_count = weight
			best_pos = centre
	if best_count > 0:
		w.assets.use(team, "ARTILLERY", Grid.cell_of(best_pos))


## 5. UAV over the next attack target, else over the most threatened own flag.
func _rule_uav(w: World, contacts: Array) -> void:
	if not w.assets.is_ready(team, "UAV"):
		return
	var target: Flag = null
	if last_attack_flag != null and last_attack_flag.owner != team:
		target = last_attack_flag
	else:
		var best_n := 0
		for f in _own_flags(w):
			var n := _contacts_near(contacts, f.centre_pos(), Balance.AI_DEFEND_RADIUS).size()
			if n > best_n:
				best_n = n
				target = f
	if target != null:
		w.assets.use(team, "UAV", target.centre)


## 6. Supply crate on the squad in combat with the lowest average HP.
func _rule_supply(w: World) -> void:
	if not w.assets.is_ready(team, "SUPPLY"):
		return
	var best: Squad = null
	var best_hp := Balance.MEMBER_HP
	for s in _living_squads(w):
		if not s.in_combat or s.is_mounted():
			continue
		var hp: float = s.avg_hp()
		if hp < best_hp:
			best_hp = hp
			best = s
	if best != null:
		w.assets.use(team, "SUPPLY", best.leader.cell())


## 7. Vehicle drop at the HQ when the team has no living jeep.
func _rule_vehicle_drop(w: World) -> void:
	if not w.assets.is_ready(team, "VEHICLE_DROP"):
		return
	for v in w.vehicles:
		if v.alive and v.team == team and v.vtype == Balance.VEHICLE_DROP_TYPE:
			return
	var hq := w.hq_of(team)
	if hq != null:
		w.assets.use(team, "VEHICLE_DROP", hq.centre)


## 8b. Mounted squads dismount when the vehicle is close to the destination.
func _rule_auto_dismount(w: World) -> void:
	for s in _living_squads(w):
		if not s.is_mounted() or s.vehicle == null:
			continue
		var dest: Vector2i = s.destination()
		if s.order_type() == Balance.Order.MOUNT or dest.x < 0:
			continue
		if s.vehicle.pos.distance_to(Grid.centre_of(dest)) <= Balance.AI_DISMOUNT_DIST:
			w.dismount_squad(s)
			s.arrived = false


# ---------------------------------------------------------------------------
# Order issuing (rule 8: mount an idle vehicle for long trips)
# ---------------------------------------------------------------------------

func _issue(w: World, s: Squad, type: int, flag: Flag) -> void:
	orders_issued += 1
	if type == Balance.Order.ATTACK:
		last_attack_flag = flag
	var movement := { "type": type, "cell": flag.centre, "flag": flag, "vehicle": null }
	if enabled["vehicles"] and not s.is_mounted() and s.vehicle == null:
		var dist := _squad_pos(s).distance_to(flag.centre_pos())
		if dist > Balance.AI_MOUNT_MIN_DIST:
			var v := _idle_vehicle_near(w, _squad_pos(s), Balance.AI_MOUNT_SEARCH)
			if v != null:
				mounts_issued += 1
				w.give_order(s, Balance.Order.MOUNT, v.cell(), null, v, -1.0, movement)
				return
	w.give_order(s, type, flag.centre, flag)


## With every flag owned, idle squads guard the flag closest to the enemy HQ
## that has the fewest defenders.
func _defend_forward(w: World, s: Squad) -> void:
	if s.order_type() == Balance.Order.DEFEND:
		return
	var enemy_hq := w.hq_of(Balance.other_team(team))
	var best: Flag = null
	var best_score := -1.0e9
	for f in _own_flags(w):
		var defenders := 0
		for o in _living_squads(w):
			if o.order_type() == Balance.Order.DEFEND and o.order["flag"] == f:
				defenders += 1
		var d: float = f.centre_pos().distance_to(enemy_hq.centre_pos()) if enemy_hq != null else 0.0
		var score: float = -defenders * 100.0 - d
		if score > best_score:
			best_score = score
			best = f
	if best != null:
		_issue(w, s, Balance.Order.DEFEND, best)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _living_squads(w: World) -> Array:
	var out: Array = []
	for s in w.squads_of(team):
		if s.leader != null and s.leader.is_alive():
			out.append(s)
	return out


func _own_flags(w: World) -> Array:
	var out: Array = []
	for f in w.flags:
		if not f.is_hq and f.owner == team:
			out.append(f)
	return out


func _non_own_flags(w: World) -> Array:
	var out: Array = []
	for f in w.flags:
		if not f.is_hq and f.owner != team:
			out.append(f)
	return out


func _squad_pos(s: Squad) -> Vector2:
	return s.leader.pos


func _contacts_near(contacts: Array, pos: Vector2, r: float) -> Array:
	var out: Array = []
	for c in contacts:
		if c["pos"].distance_to(pos) <= r:
			out.append(c)
	return out


func _squad_near(w: World, pos: Vector2, r: float) -> Squad:
	for s in _living_squads(w):
		if _squad_pos(s).distance_to(pos) <= r:
			return s
	return null


func _is_capturing(s: Squad) -> bool:
	return s.order_type() == Balance.Order.ATTACK and s.arrived and not s.order_completed


## Idle for the AI: no order / completed order, or a DEFEND with no threat left.
func _is_idle_for_ai(w: World, s: Squad, contacts: Array) -> bool:
	if s.is_idle():
		return true
	if s.order_type() == Balance.Order.DEFEND:
		var f: Flag = s.order["flag"]
		if f.owner != team:
			return true
		return _contacts_near(contacts, f.centre_pos(), Balance.AI_DEFEND_RADIUS).is_empty() and s.arrived
	return false


func _assigned_count(w: World, f: Flag) -> int:
	var n := 0
	for s in _living_squads(w):
		var o: Dictionary = s.order
		if s.pending.has("flag") and s.pending["flag"] == f:
			n += 1
		elif o.get("flag") == f and o.get("type") == Balance.Order.ATTACK and not s.order_completed:
			n += 1
		elif o.get("type") == Balance.Order.MOUNT and o.get("then", {}).get("flag") == f:
			n += 1
	return n


func _flag_value(f: Flag, contacts: Array) -> float:
	if f.owner == team:
		return 0.0
	if f.owner == Balance.Team.NONE:
		return Balance.AI_FLAG_VALUE_NEUTRAL
	var defenders := _contacts_near(contacts, f.centre_pos(), Balance.AI_DEFEND_RADIUS).size()
	return Balance.AI_FLAG_VALUE_WEAK_ENEMY if defenders <= Balance.AI_WEAK_DEFENDERS else Balance.AI_FLAG_VALUE_STRONG_ENEMY


func _idle_vehicle_near(w: World, pos: Vector2, r: float) -> Vehicle:
	var best: Vehicle = null
	var best_d := r
	for v in w.vehicles:
		if not v.alive or v.team != team or not v.is_idle():
			continue
		# not already claimed by another squad's pending mount
		var claimed := false
		for s in w.squads_of(team):
			if s.pending.get("vehicle") == v or (s.order_type() == Balance.Order.MOUNT and s.order.get("vehicle") == v):
				claimed = true
		if claimed:
			continue
		var d := v.pos.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = v
	return best
