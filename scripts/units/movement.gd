class_name Movement
extends RefCounted
## Movement system (Section 6.5): "path one thing, animate many".
## Leaders follow A* paths; members steer to formation slots; detached
## members path to the leader; cover seeking and bounding overwatch apply
## in combat. Everything here is static and operates on a World.

const FOOT := Balance.MoveClass.FOOT
const NO_CELL := Vector2i(-1, -1)


static func update(w: World, dt: float) -> void:
	for s in w.squads:
		_update_squad(w, s, dt)
	for v in w.vehicles:
		if v.alive:
			_update_vehicle(w, v, dt)
	_separation(w)


# ---------------------------------------------------------------------------
# Squad level
# ---------------------------------------------------------------------------

static func _update_squad(w: World, s: Squad, dt: float) -> void:
	s.refresh_leader()
	var leader := s.leader
	if leader == null:
		return
	for m in s.members:
		m.is_moving = false
	s.in_combat = _in_combat(w, s)
	_update_formation_choice(w, s, leader)
	_assign_slots(s)
	_update_bounding(w, s)
	_check_completion(w, s)
	if leader.state == Balance.MemberState.IN_VEHICLE:
		leader.pos = leader.vehicle.pos
		leader.heading = leader.vehicle.heading
	elif leader.state == Balance.MemberState.ALIVE:
		_update_leader(w, s, leader, dt)
	for m in s.members:
		if m != leader and m.state == Balance.MemberState.ALIVE:
			_update_member(w, s, m, dt)
		elif m.state == Balance.MemberState.IN_VEHICLE:
			m.pos = m.vehicle.pos


static func _in_combat(w: World, s: Squad) -> bool:
	if s.leader == null:
		return false
	var lp := s.leader.pos
	for u in s.visible_enemies.keys():
		if u.is_alive() and u.pos.distance_to(lp) <= Balance.COMBAT_CONTACT_DIST:
			return true
	return false


static func _update_formation_choice(w: World, s: Squad, leader: Member) -> void:
	var want := Formation.pick(w.grid.get_terrain(leader.cell()))
	if want == s.formation:
		s.formation_pending = ""
		return
	if s.formation_pending != want:
		s.formation_pending = want
		s.formation_pending_since = w.time
	elif w.time - s.formation_pending_since >= Balance.FORMATION_HYSTERESIS_S:
		s.formation = want
		s.formation_pending = ""


static func _assign_slots(s: Squad) -> void:
	var i := 0
	for m in s.members:
		if m == s.leader or not m.is_alive():
			continue
		m.slot_index = i
		# Bounding teams: leader + first two = team A (0), rest = team B (1).
		m.bound_team = 0 if i < 2 else 1
		i += 1


static func _update_bounding(w: World, s: Squad) -> void:
	var moving_order := s.destination().x >= 0 and not s.arrived and not s.is_mounted()
	if not s.in_combat or not moving_order:
		s.bound["moving"] = 0
		s.bound["start_pos"] = s.leader.pos
		s.bound["start_time"] = w.time
		return
	var elapsed: float = w.time - s.bound["start_time"]
	if s.bound["moving"] == 0:
		var moved: float = s.leader.pos.distance_to(s.bound["start_pos"])
		if moved >= s.bound_length() or elapsed >= Balance.BOUND_MAX_S:
			s.bound["moving"] = 1
			s.bound["start_time"] = w.time
	else:
		var all_in := true
		for m in s.members:
			if m.bound_team == 1 and m.is_on_foot() and m != s.leader and not m.detached:
				if m.pos.distance_to(_slot_target(s, m)) > Balance.SLOT_TOLERANCE * 2.0:
					all_in = false
		if all_in or elapsed >= Balance.BOUND_MAX_S:
			s.bound["moving"] = 0
			s.bound["start_pos"] = s.leader.pos
			s.bound["start_time"] = w.time


static func _check_completion(w: World, s: Squad) -> void:
	match s.order_type():
		Balance.Order.MOVE:
			if s.arrived:
				s.order_completed = true
		Balance.Order.ATTACK:
			if s.order["flag"].owner == s.team:
				s.order_completed = true
		Balance.Order.HOLD, Balance.Order.NONE:
			s.order_completed = true


# ---------------------------------------------------------------------------
# Leader
# ---------------------------------------------------------------------------

static func _update_leader(w: World, s: Squad, m: Member, dt: float) -> void:
	if _handle_pause(w, s, m):
		return
	if _handle_mount(w, s, m, dt):
		return
	if _handle_cover(w, s, m, dt):
		return
	var dest := s.destination()
	if dest.x < 0:
		_hold_behaviour(w, s, m, dt)
		return
	var dpos := Grid.centre_of(dest)
	if not s.arrived and m.pos.distance_to(dpos) <= Balance.ORDER_ARRIVE_DIST:
		s.arrived = true
		s.path.clear()
		if s.in_combat:
			s.objectives_in_combat += 1
	if s.arrived:
		_objective_behaviour(w, s, m, dt)
		return
	# bounding overwatch: team A (with the leader) waits while team B moves
	if s.in_combat and s.bound["moving"] == 1:
		return
	if s.path_goal != dest or w.time >= s.next_repath or _path_blocked(w, s.path):
		s.path = w.pathfinder(FOOT).find_path(m.cell(), dest)
		s.path_goal = dest
		s.next_repath = w.time + Balance.LEADER_REPATH_S
	if s.path.is_empty():
		_move_toward(w, m, dpos, _leader_speed(w, s, m), dt)
	elif not _follow_path(w, m, s.path, _leader_speed(w, s, m), dt):
		s.path.clear()
		s.next_repath = w.time


static func _path_blocked(w: World, path: Array[Vector2i]) -> bool:
	for i in mini(3, path.size()):
		if not w.grid.is_passable(path[i], FOOT):
			return true
	return false


## Leader moves at the pace of the squad's slowest member so formations hold.
static func _leader_speed(w: World, s: Squad, m: Member) -> float:
	var var_min := m.speed_var
	for o in s.members:
		if o.is_on_foot():
			var_min = minf(var_min, o.speed_var)
	return Balance.MEMBER_BASE_SPEED * _terrain_speed(w, m.cell()) * var_min


## Behaviour once the objective is reached, per Aggression (Section 6.2).
static func _objective_behaviour(w: World, s: Squad, m: Member, dt: float) -> void:
	var obj := s.objective_pos()
	var capturing := s.order_type() == Balance.Order.ATTACK and not s.order_completed
	if s.aggression >= 4 and not capturing:
		var target = _nearest_visible_enemy(s, obj, Balance.PURSUE_DIST)
		if target != null:
			var goal: Vector2i = target.cell()
			if s.pursue_goal != goal or w.time >= s.next_repath:
				s.path = w.pathfinder(FOOT).find_path(m.cell(), goal)
				s.pursue_goal = goal
				s.next_repath = w.time + Balance.LEADER_REPATH_S
			_follow_path(w, m, s.path, _leader_speed(w, s, m), dt)
			return
		s.pursue_goal = NO_CELL
		if m.pos.distance_to(obj) > Balance.ORDER_ARRIVE_DIST * 1.5:
			_go_to_cell(w, m, Grid.cell_of(obj), _leader_speed(w, s, m), dt, Balance.LEADER_REPATH_S)
		return
	if s.aggression <= 1:
		_seek_hold_cover(w, m, dt)


static func _hold_behaviour(w: World, s: Squad, m: Member, dt: float) -> void:
	if s.order_type() == Balance.Order.HOLD or s.aggression <= 1:
		_seek_hold_cover(w, m, dt)


static func _nearest_visible_enemy(s: Squad, from: Vector2, max_dist: float):
	var best = null
	var best_d := max_dist
	for u in s.visible_enemies.keys():
		if not u.is_alive():
			continue
		var d: float = u.pos.distance_to(from)
		if d <= best_d:
			best_d = d
			best = u
	return best


# ---------------------------------------------------------------------------
# Members
# ---------------------------------------------------------------------------

static func _update_member(w: World, s: Squad, m: Member, dt: float) -> void:
	if _handle_pause(w, s, m):
		return
	if _handle_mount(w, s, m, dt):
		return
	if _handle_cover(w, s, m, dt):
		return
	var leader := s.leader
	# Detached members rejoin first, whatever the order.
	if leader.state != Balance.MemberState.IN_VEHICLE:
		var d := m.pos.distance_to(leader.pos)
		if m.detached:
			if d <= Balance.REJOIN_DIST:
				m.detached = false
				m.path.clear()
			else:
				_go_to_cell(w, m, leader.cell(), _member_speed(w, m) * Balance.CATCHUP_MULT, dt, Balance.DETACHED_REPATH_S)
				return
		elif d > Balance.DETACH_DIST:
			m.detached = true
			m.path.clear()
			return
	# DEFEND: each member holds the best cover cell within the flag radius.
	if s.order_type() == Balance.Order.DEFEND and s.arrived:
		if m.defend_cell == NO_CELL or not w.grid.is_passable(m.defend_cell, FOOT):
			m.defend_cell = _pick_defend_cell(w, s, m)
		if m.defend_cell != NO_CELL:
			_go_to_cell(w, m, m.defend_cell, _member_speed(w, m), dt, Balance.MEMBER_REPATH_S)
		return
	if s.order_type() == Balance.Order.HOLD or (s.arrived and s.aggression <= 1):
		_seek_hold_cover(w, m, dt)
		return
	# Leader mounted: walk toward the squad destination on foot.
	if leader.state == Balance.MemberState.IN_VEHICLE:
		var dest := s.destination()
		if dest.x >= 0:
			_go_to_cell(w, m, dest, _member_speed(w, m), dt, Balance.DETACHED_REPATH_S)
		return
	# Bounding overwatch: the halted team stays put and fires.
	if s.in_combat and not s.arrived and s.destination().x >= 0 and m.bound_team != s.bound["moving"]:
		return
	_steer_to_slot(w, s, m, dt)


static func _slot_target(s: Squad, m: Member) -> Vector2:
	return s.leader.pos + Formation.world_offset(Formation.slot(s.formation, m.slot_index), s.leader.heading)


static func _steer_to_slot(w: World, s: Squad, m: Member, dt: float) -> void:
	var target := _slot_target(s, m)
	var dist := m.pos.distance_to(target)
	if dist <= Balance.SLOT_TOLERANCE:
		m.path.clear()
		m.heading = s.leader.heading
		return
	var speed := _member_speed(w, m)
	if dist > Balance.CATCHUP_DIST:
		speed *= Balance.CATCHUP_MULT
	var tcell := Grid.cell_of(target)
	if not w.grid.in_bounds(tcell) or not w.grid.is_passable(tcell, FOOT):
		# slot is inside something solid: aim for the nearest passable cell
		tcell = w.grid.nearest_passable(w.grid.clamp_cell(tcell), FOOT, 3)
		if tcell == NO_CELL:
			return
		target = Grid.centre_of(tcell)
	if _straight_clear(w, m.cell(), tcell):
		m.path.clear()
		_move_toward(w, m, target, speed, dt)
	else:
		_go_to_cell(w, m, tcell, speed, dt, Balance.MEMBER_REPATH_S)


static func _pick_defend_cell(w: World, s: Squad, m: Member) -> Vector2i:
	var flag: Flag = s.order["flag"]
	var centre := flag.centre_pos()
	var best := NO_CELL
	var best_score := -1.0e9
	var taken := {}
	for o in s.members:
		if o != m and o.defend_cell != NO_CELL:
			taken[o.defend_cell] = true
	for c in w.grid.cells_in_radius(flag.centre, flag.radius()):
		if taken.has(c) or not w.grid.is_passable(c, FOOT):
			continue
		var score := w.grid.cover(c) - Balance.COVER_DIST_WEIGHT * Grid.centre_of(c).distance_to(centre)
		if score > best_score:
			best_score = score
			best = c
	return best


# ---------------------------------------------------------------------------
# Shared behaviours
# ---------------------------------------------------------------------------

## Random pauses outside combat (Section 6.5 "Variance"). Returns true when paused.
static func _handle_pause(w: World, s: Squad, m: Member) -> bool:
	if s.in_combat:
		return false
	if w.time < m.pause_until:
		return true
	if w.time >= m.next_pause_at:
		m.pause_until = w.time + w.rng.randf_range(Balance.PAUSE_LEN[0], Balance.PAUSE_LEN[1])
		m.next_pause_at = m.pause_until + w.rng.randf_range(Balance.PAUSE_INTERVAL[0], Balance.PAUSE_INTERVAL[1])
		return true
	return false


## Cover seeking after being shot at. Returns true when the member is busy with cover.
static func _handle_cover(w: World, s: Squad, m: Member, dt: float) -> bool:
	var recently_shot_at := w.time - m.shot_at_time <= Balance.COVER_SEEK_AFTER_SHOT_S
	if m.cover_cell == NO_CELL:
		if not recently_shot_at:
			return false
		m.cover_cell = _best_cover_cell(w, m, Balance.COVER_SEARCH_RADIUS)
		if m.cover_cell == NO_CELL:
			return false
	if w.time - m.shot_at_time > s.cover_resume():
		m.cover_cell = NO_CELL
		m.path.clear()
		return false
	if m.cell() != m.cover_cell:
		_go_to_cell(w, m, m.cover_cell, _member_speed(w, m), dt, Balance.MEMBER_REPATH_S)
	return true


## Low-aggression / HOLD behaviour: settle into nearby cover and stay.
static func _seek_hold_cover(w: World, m: Member, dt: float) -> void:
	if m.hold_cell == NO_CELL:
		m.hold_cell = _best_cover_cell(w, m, Balance.COVER_SEARCH_RADIUS)
		if m.hold_cell == NO_CELL:
			m.hold_cell = m.cell()
	if m.cell() != m.hold_cell:
		_go_to_cell(w, m, m.hold_cell, _member_speed(w, m), dt, Balance.MEMBER_REPATH_S)


static func _best_cover_cell(w: World, m: Member, radius: float) -> Vector2i:
	var origin := m.cell()
	var best := NO_CELL
	var best_score := -1.0e9
	var occupied := w.occupied_cells()
	for c in w.grid.cells_in_radius(origin, radius):
		if not w.grid.is_passable(c, FOOT):
			continue
		if c != origin and occupied.has(c):
			continue
		var score := w.grid.cover(c) - Balance.COVER_DIST_WEIGHT * Grid.centre_of(c).distance_to(m.pos)
		if score > best_score:
			best_score = score
			best = c
	return best


static func _handle_mount(w: World, s: Squad, m: Member, dt: float) -> bool:
	if s.order_type() != Balance.Order.MOUNT:
		return false
	var v: Vehicle = s.order.get("vehicle")
	if v == null or not v.alive or v.team != s.team:
		return false
	if v.free_seats() <= 0:
		return false   # seats full: continue on foot toward the destination
	if m.pos.distance_to(v.pos) <= Balance.MOUNT_DIST:
		w.board_vehicle(m, v)
		return true
	_go_to_cell(w, m, v.cell(), _member_speed(w, m), dt, Balance.MEMBER_REPATH_S)
	return true


# ---------------------------------------------------------------------------
# Vehicles
# ---------------------------------------------------------------------------

static func _update_vehicle(w: World, v: Vehicle, dt: float) -> void:
	v.is_moving = false
	var s := v.owner_squad
	if s == null or s.leader == null or s.leader.vehicle != v:
		return
	var dest := s.destination()
	if s.order_type() == Balance.Order.MOUNT:
		# Waiting for the rest of the squad; the movement order comes next.
		return
	if dest.x < 0 or s.arrived:
		return
	var dpos := Grid.centre_of(dest)
	if v.pos.distance_to(dpos) <= Balance.ORDER_ARRIVE_DIST * 1.5:
		s.arrived = true
		v.path.clear()
		return
	var pf := w.pathfinder(v.mclass)
	if v.path_goal != dest or w.time >= v.next_repath:
		v.path = pf.find_path(v.cell(), dest)
		v.path_goal = dest
		v.next_repath = w.time + Balance.LEADER_REPATH_S
		if v.path.is_empty():
			# destination unreachable for this class: stop as close as possible
			var near := w.grid.nearest_passable(dest, v.mclass)
			if near != NO_CELL and near != v.cell():
				v.path = pf.find_path(v.cell(), near)
			if v.path.is_empty():
				s.arrived = true
				return
	var speed := v.speed * w.grid.speed_mult(v.cell(), v.mclass)
	if speed <= 0.0:
		speed = v.speed * 0.5
	while not v.path.is_empty():
		var wp := Grid.centre_of(v.path[0])
		if v.pos.distance_to(wp) <= Balance.WAYPOINT_REACH:
			v.path.pop_front()
			continue
		var from := v.cell()
		var to := v.path[0]
		if to != from and not w.grid.can_step(from, to, v.mclass):
			v.path.clear()
			v.next_repath = w.time
			break
		var delta := wp - v.pos
		var step := minf(speed * dt / w.grid.slope_mult(from, to, v.mclass), delta.length())
		v.pos += delta.normalized() * step
		v.heading = delta.normalized()
		v.is_moving = true
		break
	for m in v.occupants:
		m.pos = v.pos
		m.heading = v.heading


# ---------------------------------------------------------------------------
# Primitive movement helpers
# ---------------------------------------------------------------------------

static func _terrain_speed(w: World, c: Vector2i) -> float:
	var sm := w.grid.speed_mult(c, FOOT)
	return sm if sm > 0.0 else 0.5


static func _member_speed(w: World, m: Member) -> float:
	return Balance.MEMBER_BASE_SPEED * _terrain_speed(w, m.cell()) * m.speed_var


## True when every cell on the straight line is passable on foot.
static func _straight_clear(w: World, a: Vector2i, b: Vector2i) -> bool:
	for c in LOS.bresenham(a, b):
		if not w.grid.is_passable(c, FOOT):
			return false
	return true


## Moves a member toward a target point. Returns false when blocked.
static func _move_toward(w: World, m: Member, target: Vector2, speed: float, dt: float) -> bool:
	var delta := target - m.pos
	var dist := delta.length()
	if dist < 0.0001:
		return true
	var dir := delta / dist
	var step := minf(speed * dt, dist)
	var from := m.cell()
	var np := m.pos + dir * step
	var to := Grid.cell_of(np)
	if to != from:
		if w.grid.can_step(from, to, FOOT):
			step /= w.grid.slope_mult(from, to, FOOT)
			np = m.pos + dir * step
		else:
			var alt_x := Vector2(np.x, m.pos.y)
			var alt_y := Vector2(m.pos.x, np.y)
			var cx := Grid.cell_of(alt_x)
			var cy := Grid.cell_of(alt_y)
			if cx == from or w.grid.can_step(from, cx, FOOT):
				np = alt_x
			elif cy == from or w.grid.can_step(from, cy, FOOT):
				np = alt_y
			else:
				return false
	m.pos = np
	m.heading = m.heading.lerp(dir, 0.35).normalized() if m.heading.length_squared() > 0.0 else dir
	m.is_moving = true
	return true


## Follows a waypoint list, popping reached waypoints. Returns false when blocked.
static func _follow_path(w: World, m: Member, path: Array[Vector2i], speed: float, dt: float) -> bool:
	while not path.is_empty():
		var wp := Grid.centre_of(path[0])
		if m.pos.distance_to(wp) <= Balance.WAYPOINT_REACH:
			path.pop_front()
			continue
		return _move_toward(w, m, wp, speed, dt)
	return true


## Paths a member to a cell, repathing at most every `interval` seconds.
static func _go_to_cell(w: World, m: Member, goal: Vector2i, speed: float, dt: float, interval: float) -> void:
	if goal == NO_CELL:
		return
	if m.cell() == goal:
		_move_toward(w, m, Grid.centre_of(goal), speed, dt)
		m.path.clear()
		m.path_goal = goal
		return
	var goal_changed := m.path_goal != goal
	var can_repath := m.path_goal == NO_CELL or w.time - m.path_time >= interval
	if can_repath and (goal_changed or m.path.is_empty()):
		if m.pos.distance_to(Grid.centre_of(goal)) < 6.0 and _straight_clear(w, m.cell(), goal):
			m.path.clear()
		else:
			m.path = w.pathfinder(FOOT).find_path(m.cell(), goal)
		m.path_goal = goal
		m.path_time = w.time
	if m.path.is_empty():
		if not _move_toward(w, m, Grid.centre_of(goal), speed, dt):
			m.path_time = -100.0
	elif not _follow_path(w, m, m.path, speed, dt):
		m.path.clear()
		m.path_time = -100.0


## Pushes members of any team apart when they overlap.
static func _separation(w: World) -> void:
	var list := w.foot_members()
	var n := list.size()
	for i in n:
		var a: Member = list[i]
		for j in range(i + 1, n):
			var b: Member = list[j]
			var delta: Vector2 = b.pos - a.pos
			var d := delta.length()
			if d >= Balance.SEPARATION_DIST:
				continue
			var dir := delta / d if d > 0.0001 else Vector2(1, 0)
			var pa := a.pos - dir * Balance.SEPARATION_PUSH
			var pb := b.pos + dir * Balance.SEPARATION_PUSH
			if w.grid.is_passable(Grid.cell_of(pa), FOOT):
				a.pos = pa
			if w.grid.is_passable(Grid.cell_of(pb), FOOT):
				b.pos = pb
