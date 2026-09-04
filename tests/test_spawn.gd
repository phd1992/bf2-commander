extends TestCase
## Test 12: Conquest spawn policy.

const T := Balance.Terrain


func _world() -> World:
	var w := World.new()
	w.setup_blank(1, 80, 40, T.OPEN)
	w.add_flag("BLUE HQ", Vector2i(5, 20), true, Balance.Team.BLUE)
	w.add_flag("A", Vector2i(30, 20))
	w.add_flag("B", Vector2i(50, 20))
	w.add_flag("RED HQ", Vector2i(75, 20), true, Balance.Team.RED)
	return w


func test_member_respawns_at_nearest_owned_point() -> void:
	var w := _world()
	var a := w.flag_by_name("A")
	a.owner = Balance.Team.BLUE
	a.progress = 1.0
	var s := w.create_squad(Balance.Team.BLUE, "S", [3, 3, 3, 3], Vector2(40, 20))
	w.give_order(s, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	var m: Member = s.members[4]
	w.kill_member(m)
	check_eq(m.state, Balance.MemberState.DEAD, "member is dead")
	run_seconds(w, 14.9)
	check_eq(m.state, Balance.MemberState.DEAD, "still dead before 15 s")
	run_seconds(w, 0.2)
	check_eq(m.state, Balance.MemberState.ALIVE, "alive after 15 s")
	check(m.pos.distance_to(a.centre_pos()) <= 2.0, "respawned at A (nearest owned to the leader), at %s" % str(m.pos))
	check(m.detached, "respawned member walks back as detached")
	check_eq(w.tickets[Balance.Team.BLUE], Balance.START_TICKETS - 1, "cost one ticket")
	check_near(m.hp, Balance.MEMBER_HP, 0.001, "full HP")
	run_seconds(w, 12.0)
	check(not m.detached, "rejoined the squad")


func test_squad_respawn_after_wipe() -> void:
	var w := _world()
	var b := w.flag_by_name("B")
	b.owner = Balance.Team.BLUE
	b.progress = 1.0
	var s := w.create_squad(Balance.Team.BLUE, "S", [3, 3, 3, 3], Vector2(40, 20))
	w.give_order(s, Balance.Order.MOVE, Vector2i(52, 20), null, null, 0.0)
	s.add_xp(120)
	check_eq(s.skill, 4, "veteran skill before the wipe")
	w.kill_member(s.members[0])
	run_seconds(w, 5.0)
	for m in s.members:
		w.kill_member(m)
	check(s.is_wiped(), "squad is wiped")
	check_eq(s.xp, 0, "XP reset on wipe")
	check_eq(s.skill, 3, "skill reset to the rolled value")
	# pending member respawn from the first death must have been cancelled
	run_seconds(w, 12.0)
	check_eq(s.alive_count(), 0, "individual respawn cancelled by the wipe")
	run_seconds(w, 8.2)
	check_eq(s.alive_count(), 6, "all six respawn together 20 s after the wipe")
	check(s.leader != null and s.leader.is_alive(), "leader restored")
	for m in s.members:
		check(m.pos.distance_to(b.centre_pos()) <= 2.5, "respawned at B, the owned point nearest the last order")
	check_eq(w.tickets[Balance.Team.BLUE], Balance.START_TICKETS - 6, "squad respawn cost six tickets")


func test_preferred_spawn_point() -> void:
	var w := _world()
	var a := w.flag_by_name("A")
	a.owner = Balance.Team.BLUE
	a.progress = 1.0
	var s := w.create_squad(Balance.Team.BLUE, "S", [3, 3, 3, 3], Vector2(28, 20))
	w.give_order(s, Balance.Order.MOVE, Vector2i(29, 20), null, null, 0.0)
	for m in s.members:
		w.kill_member(m)
	w.spawn_policy.set_preferred_spawn(s, w.hq_of(Balance.Team.BLUE).centre)
	run_seconds(w, 20.2)
	for m in s.members:
		check(m.pos.distance_to(w.hq_of(Balance.Team.BLUE).centre_pos()) <= 2.5, "respawned at the chosen HQ point")


func test_no_spawn_when_nothing_owned() -> void:
	var w := _world()
	var hq := w.hq_of(Balance.Team.BLUE)
	hq.owner = Balance.Team.NONE   # simulate a team with no spawn point at all
	var s := w.create_squad(Balance.Team.BLUE, "S", [3, 3, 3, 3], Vector2(20, 20))
	w.kill_member(s.members[3])
	run_seconds(w, 30.0)
	check_eq(s.members[3].state, Balance.MemberState.DEAD, "no owned point: waits")
	check_eq(w.tickets[Balance.Team.BLUE], Balance.START_TICKETS, "no ticket spent while waiting")
	w.flag_by_name("A").owner = Balance.Team.BLUE
	run_seconds(w, 0.2)
	check_eq(s.members[3].state, Balance.MemberState.ALIVE, "respawns as soon as a point is owned")
	check(s.members[3].pos.distance_to(w.flag_by_name("A").centre_pos()) <= 2.0, "at the newly owned flag")


func test_spawn_points_list() -> void:
	var w := _world()
	check_eq(w.spawn_policy.get_spawn_points(Balance.Team.BLUE), [Vector2i(5, 20)], "only the HQ at start")
	w.flag_by_name("B").owner = Balance.Team.RED
	check_eq(w.spawn_policy.get_spawn_points(Balance.Team.RED).size(), 2, "RED: HQ + B")
