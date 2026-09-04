class_name SpawnConquest
extends SpawnPolicy
## Conquest spawning (Section 10.2): members respawn 15 s after death at the
## owned point nearest their leader; a wiped squad comes back together 20 s
## later at its preferred point.

var pending_members: Array[Member] = []


func request_member_respawn(m: Member) -> void:
	m.respawn_at = world.time + Balance.MEMBER_RESPAWN_S
	if m not in pending_members:
		pending_members.append(m)


func request_squad_respawn(s: Squad) -> void:
	for m in s.members:
		pending_members.erase(m)
		m.respawn_at = -1.0
	s.wipe_respawn_at = world.time + Balance.SQUAD_RESPAWN_S


func set_preferred_spawn(s: Squad, cell: Vector2i) -> void:
	for f in world.flags:
		if f.centre == cell:
			s.spawn_pref = f
			return
	s.spawn_pref = null


func tick(_dt: float) -> void:
	_tick_members()
	_tick_squads()


func _tick_members() -> void:
	var i := 0
	while i < pending_members.size():
		var m: Member = pending_members[i]
		if m.state != Balance.MemberState.DEAD:
			pending_members.remove_at(i)
			continue
		if world.time + 0.0001 < m.respawn_at:
			i += 1
			continue
		var points := spawn_flags(m.team)
		if points.is_empty():
			i += 1   # wait until the team owns a spawn point
			continue
		var s := m.squad
		var anchor: Vector2 = s.leader.pos if s.leader != null and s.leader.is_alive() else Grid.centre_of(s.last_order_cell)
		if s.last_order_cell.x < 0 and (s.leader == null or not s.leader.is_alive()):
			anchor = points[0].centre_pos()
		var f: Flag = _nearest_flag(points, anchor)
		if world.tickets[m.team] <= 0:
			i += 1
			continue
		world.tickets[m.team] -= Balance.RESPAWN_TICKET_COST
		world.revive_member(m, _scatter(f.centre_pos()))
		m.detached = true
		pending_members.remove_at(i)


func _tick_squads() -> void:
	for s in world.squads:
		if s.wipe_respawn_at < 0.0 or world.time + 0.0001 < s.wipe_respawn_at:
			continue
		var points := spawn_flags(s.team)
		if points.is_empty():
			continue
		var f: Flag = null
		if s.spawn_pref != null and s.spawn_pref.is_spawnable_for(s.team):
			f = s.spawn_pref
		else:
			var anchor: Vector2 = Grid.centre_of(s.last_order_cell) if s.last_order_cell.x >= 0 else points[0].centre_pos()
			f = _nearest_flag(points, anchor)
		var cost := Balance.RESPAWN_TICKET_COST * s.members.size()
		if world.tickets[s.team] < cost:
			# Not enough tickets for the whole squad: bring back what we can.
			cost = world.tickets[s.team]
		world.tickets[s.team] -= cost
		var revived := 0
		for m in s.members:
			if revived >= cost / Balance.RESPAWN_TICKET_COST:
				break
			world.revive_member(m, _scatter(f.centre_pos()))
			revived += 1
		s.wipe_respawn_at = -1.0
		s.wiped_since = -1.0
		s.refresh_leader()
		for m in s.members:
			m.detached = false
		world.events.append({ "type": "squad_respawn", "squad": s, "cell": f.centre })


func _nearest_flag(points: Array, anchor: Vector2) -> Flag:
	var best: Flag = points[0]
	var best_d := 1.0e9
	for f in points:
		var d: float = f.centre_pos().distance_to(anchor)
		if d < best_d:
			best_d = d
			best = f
	return best


func _scatter(p: Vector2) -> Vector2:
	var q := p + Vector2(world.rng.randf_range(-Balance.SPAWN_SCATTER, Balance.SPAWN_SCATTER), world.rng.randf_range(-Balance.SPAWN_SCATTER, Balance.SPAWN_SCATTER))
	return world._nearest_open_pos(q)
