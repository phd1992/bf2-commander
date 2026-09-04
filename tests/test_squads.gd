extends TestCase
## Tests 7-9: stat rolling, order delay, formations and movement.

const T := Balance.Terrain


func _blank_world(seed: int = 1) -> World:
	var w := World.new()
	w.setup_blank(seed, 60, 40, T.OPEN)
	return w


func test_stat_rolling() -> void:
	var w := _blank_world(42)
	var seen := {}
	for i in 1000:
		var st: Array = w.roll_stats()
		var sum: int = st[0] + st[1] + st[2] + st[3]
		if sum != Balance.STAT_SUM:
			check(false, "roll %d sums to %d" % [i, sum])
			return
		for v in st:
			if v < Balance.STAT_MIN or v > Balance.STAT_MAX:
				check(false, "roll %d has stat %d out of range" % [i, v])
				return
		seen[str(st)] = true
	check(true, "1000 rolls all sum to 12 with each stat in [1,5]")
	check(seen.size() > 50, "rolls are spread over many combinations (%d distinct)" % seen.size())
	check_eq(World.stat_combos().size(), 85, "number of valid stat combinations")


func test_red_squads_uniform_and_blue_rolled() -> void:
	var w := World.new()
	w.setup(3)
	check_eq(w.squads.size(), 8, "eight squads")
	for s in w.squads_of(Balance.Team.RED):
		check(s.skill == 3 and s.discipline == 3 and s.aggression == 3 and s.comms == 3, "%s is uniform 3s" % s.name)
		check(s.name.begins_with("R-"), "red squad names are prefixed")
	for s in w.squads_of(Balance.Team.BLUE):
		check_eq(s.skill + s.discipline + s.aggression + s.comms, 12, "%s stats sum to 12" % s.name)
		check_eq(s.members.size(), 6, "six members")
		check_eq(s.leader.kit, Balance.Kit.LEADER, "leader has the LEADER kit")
		var at := 0
		for m in s.members:
			if m.kit == Balance.Kit.AT:
				at += 1
		check_eq(at, 1, "one AT per squad")


func test_order_delay() -> void:
	for disc in range(1, 6):
		var w := _blank_world()
		var s := w.create_squad(Balance.Team.BLUE, "T", [3, disc, 3, 3], Vector2(10, 10))
		w.give_order(s, Balance.Order.MOVE, Vector2i(30, 10))
		check(not s.pending.is_empty(), "order acknowledged immediately (pending) for D%d" % disc)
		check(not s.has_order(), "not executing yet for D%d" % disc)
		var expected := 6.0 - disc
		# one tick before the delay elapses the order is still pending
		run_ticks(w, int(round(expected / Balance.TICK)) - 1)
		check(not s.has_order(), "D%d: still pending at %.1f s" % [disc, w.time])
		run_ticks(w, 1)
		check(s.has_order(), "D%d: executing at %.1f s (delay %.1f)" % [disc, w.time, expected])
		check_near(s.order_delay(), expected, 0.001, "order_delay() equals 6 - Discipline")


func test_leader_reaches_destination() -> void:
	var w := _blank_world()
	var s := w.create_squad(Balance.Team.BLUE, "T", [3, 5, 3, 3], Vector2(10, 10))
	w.give_order(s, Balance.Order.MOVE, Vector2i(30, 10))
	run_seconds(w, 20.0)
	check(s.leader.pos.distance_to(Vector2(30.5, 10.5)) <= 1.0, "leader is at the destination after 20 s (at %s)" % str(s.leader.pos))
	check(s.order_completed, "MOVE order is completed")


func test_members_reach_slots() -> void:
	var w := _blank_world(5)
	var s := w.create_squad(Balance.Team.BLUE, "T", [3, 3, 3, 3], Vector2(20, 20))
	# scatter members near the leader, then hold position
	for m in s.members:
		if m != s.leader:
			m.pos = s.leader.pos + Vector2(w.rng.randf_range(-3, 3), w.rng.randf_range(-3, 3))
	w.give_order(s, Balance.Order.MOVE, s.leader.cell(), null, null, 0.0)
	run_seconds(w, 5.0)
	var worst := 0.0
	for m in s.members:
		if m == s.leader:
			continue
		var target: Vector2 = s.leader.pos + Formation.world_offset(Formation.slot(s.formation, m.slot_index), s.leader.heading)
		worst = maxf(worst, m.pos.distance_to(target))
	check(worst <= Balance.SLOT_TOLERANCE + 0.05, "all members within slot tolerance after 5 s (worst %.2f)" % worst)
	check_eq(s.formation, "WEDGE", "open ground uses WEDGE")


func test_members_follow_while_marching() -> void:
	var w := _blank_world(9)
	var s := w.create_squad(Balance.Team.BLUE, "T", [3, 3, 3, 3], Vector2(5, 20))
	w.give_order(s, Balance.Order.MOVE, Vector2i(50, 20), null, null, 0.0)
	run_seconds(w, 12.0)
	var worst := 0.0
	for m in s.members:
		if m == s.leader:
			continue
		var target: Vector2 = s.leader.pos + Formation.world_offset(Formation.slot(s.formation, m.slot_index), s.leader.heading)
		worst = maxf(worst, m.pos.distance_to(target))
	check(s.leader.pos.x > 20.0, "leader has marched east (%s)" % str(s.leader.pos))
	check(worst <= 2.5, "members stay near their slots while marching (worst %.2f)" % worst)


func test_formation_switches_on_road() -> void:
	var w := _blank_world()
	for x in range(0, 60):
		w.grid.set_terrain(Vector2i(x, 10), T.ROAD)
	var s := w.create_squad(Balance.Team.BLUE, "T", [3, 3, 3, 3], Vector2(5.5, 10.5))
	check_eq(s.formation, "WEDGE", "starts as WEDGE")
	w.give_order(s, Balance.Order.MOVE, Vector2i(50, 10), null, null, 0.0)
	run_seconds(w, 0.5)
	check_eq(s.formation, "WEDGE", "hysteresis: no switch before 1 s")
	run_seconds(w, 1.0)
	check_eq(s.formation, "COLUMN", "COLUMN on a road after the hysteresis")
	run_seconds(w, 8.0)
	# column: everyone trails behind the leader along the road
	for m in s.members:
		if m != s.leader:
			check(m.pos.x < s.leader.pos.x, "%d trails the leader in column" % m.id)
			check(absf(m.pos.y - s.leader.pos.y) < 1.0, "column stays on the road line")
	# leave the road: back to WEDGE
	w.give_order(s, Balance.Order.MOVE, Vector2i(30, 25), null, null, 0.0)
	run_seconds(w, 8.0)
	check_eq(s.formation, "WEDGE", "WEDGE again on open ground")


func test_forest_cluster() -> void:
	var w := _blank_world()
	w.grid.fill_rect(20, 0, 20, 40, T.FOREST)
	var s := w.create_squad(Balance.Team.BLUE, "T", [3, 3, 3, 3], Vector2(25, 20))
	w.give_order(s, Balance.Order.MOVE, Vector2i(25, 20), null, null, 0.0)
	run_seconds(w, 2.0)
	check_eq(s.formation, "CLUSTER", "CLUSTER in forest")


func test_detached_member_rejoins() -> void:
	var w := _blank_world()
	var s := w.create_squad(Balance.Team.BLUE, "T", [3, 3, 3, 3], Vector2(30, 20))
	var far := s.members[3]
	far.pos = Vector2(30, 2)   # 18 cells away
	run_seconds(w, 1.0)
	check(far.detached, "member 18 cells away becomes detached")
	run_seconds(w, 14.0)
	check(not far.detached, "detached member rejoined after walking back")
	check(far.pos.distance_to(s.leader.pos) < 4.0, "member is back near the leader (%.1f)" % far.pos.distance_to(s.leader.pos))


func test_leader_succession() -> void:
	var w := _blank_world()
	var s := w.create_squad(Balance.Team.BLUE, "T", [3, 3, 3, 3], Vector2(30, 20))
	var old := s.leader
	old.state = Balance.MemberState.DEAD
	run_ticks(w, 1)
	check(s.leader != old, "new leader chosen")
	check_eq(s.leader.kit, Balance.Kit.AT, "AT is promoted first")
	s.leader.state = Balance.MemberState.DEAD
	run_ticks(w, 1)
	check_eq(s.leader.kit, Balance.Kit.RIFLE, "then a rifleman")


func test_movement_never_enters_water() -> void:
	var w := _blank_world()
	for y in range(0, 40):
		if y != 30:
			w.grid.set_terrain(Vector2i(25, y), T.WATER)
	var s := w.create_squad(Balance.Team.BLUE, "T", [3, 3, 3, 3], Vector2(10, 10))
	w.give_order(s, Balance.Order.MOVE, Vector2i(40, 10), null, null, 0.0)
	var wet := false
	for i in 400:
		w.step(Balance.TICK)
		for m in s.members:
			if w.grid.get_terrain(m.cell()) == T.WATER:
				wet = true
	check(not wet, "no member ever stands in water")
	check(s.leader.pos.x > 30.0, "squad crossed via the gap (leader at %s)" % str(s.leader.pos))
