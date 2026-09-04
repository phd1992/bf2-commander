extends TestCase
## Phase 2.1: Broken Arrow spawn mode, and 2.2: RED stat variance toggle.

const T := Balance.Terrain
const B := Balance.Team.BLUE
const R := Balance.Team.RED


func _world() -> World:
	var w := World.new()
	w.setup(3)
	w.set_spawn_mode("BROKEN_ARROW")
	return w


func test_entry_points_from_generator() -> void:
	var w := _world()
	check_eq(w.entry_points[B].size(), 3, "three BLUE entry points")
	check_eq(w.entry_points[R].size(), 3, "three RED entry points")
	for i in 3:
		var b: Vector2i = w.entry_points[B][i]
		var r: Vector2i = w.entry_points[R][i]
		check(b.x <= 8, "BLUE entry %d is on the west edge (%s)" % [i, str(b)])
		check(r.x >= Balance.MAP_W - 9, "RED entry %d is on the east edge (%s)" % [i, str(r)])
		check(w.grid.is_passable(b, Balance.MoveClass.FOOT), "BLUE entry %d passable" % i)
		check_eq(r, MapGenerator.mirror_cell(b), "RED entry mirrors BLUE")
	check_eq(w.spawn_policy.get_spawn_points(B), [w.entry_points[B][0], w.entry_points[B][1], w.entry_points[B][2]], "entry points are the spawn points")


func test_income_and_costs() -> void:
	var w := _world()
	var ba: SpawnBrokenArrow = w.spawn_policy
	check_near(ba.points[B], 100.0, 0.001, "starting balance 100")
	run_seconds(w, 60.0)
	check_near(ba.points[B], 110.0, 0.05, "10 per minute with no flags (%.2f)" % ba.points[B])
	w.flag_by_name("A").owner = B
	w.flag_by_name("B").owner = B
	run_seconds(w, 60.0)
	check_near(ba.points[B], 124.0, 0.05, "+2 per flag per minute (%.2f)" % ba.points[B])
	check_near(ba.income_per_min(B), 14.0, 0.001, "income shown as 14/min")
	var jeep := ba.buy_vehicle(B, "JEEP", 0)
	check(jeep != null and jeep.team == B, "jeep bought")
	check_near(ba.points[B], 104.0, 0.05, "jeep costs 20")
	check(jeep.pos.distance_to(Grid.centre_of(w.entry_points[B][0])) <= 6.0, "jeep enters at the north entry")
	check(ba.buy_vehicle(B, "TANK", 1) == null, "cannot afford a tank (120)")
	check_near(ba.points[B], 104.0, 0.05, "failed purchase costs nothing")


func test_no_respawns_and_buying_a_squad() -> void:
	var w := _world()
	var ba: SpawnBrokenArrow = w.spawn_policy
	var s := w.squads_of(B)[0]
	w.kill_member(s.members[2])
	run_seconds(w, 40.0)
	check_eq(s.members[2].state, Balance.MemberState.DEAD, "no member respawn in Broken Arrow")
	check_eq(w.tickets[B], Balance.START_TICKETS, "deaths cost no tickets")
	for m in s.members:
		w.kill_member(m)
	run_seconds(w, 40.0)
	check(s.is_wiped(), "wiped squad stays gone")
	check(ba.buy_squad(w.squads_of(B)[1], 1) == false, "cannot buy a squad that is still alive")
	var pts_before: float = ba.points[B]
	check(ba.buy_squad(s, 2), "wiped squad bought back")
	check_near(ba.points[B], pts_before - Balance.BA_COST_SQUAD, 0.001, "squad costs 50")
	check_eq(s.alive_count(), 6, "six fresh members")
	check(s.leader != null and s.leader.is_alive(), "leader restored")
	check_eq(s.xp, 0, "no veterancy carried over")
	for m in s.members:
		check(m.pos.distance_to(Grid.centre_of(w.entry_points[B][2])) <= 4.0, "entered at the south entry")
	ba.points[B] = 10.0
	for m in s.members:
		w.kill_member(m)
	check(not ba.buy_squad(s, 1), "cannot afford another squad")


func test_flags_still_bleed_tickets() -> void:
	var w := _world()
	w.flag_by_name("A").owner = R
	run_seconds(w, 30.0)
	check_eq(w.tickets[B], Balance.START_TICKETS - 10, "BLUE bleeds 10 tickets in 30 s with fewer flags")
	check_eq(w.tickets[R], Balance.START_TICKETS, "RED does not")


func test_ai_buys_reinforcements() -> void:
	var w := _world()
	w.configure_match(false)
	var ba: SpawnBrokenArrow = w.spawn_policy
	var s := w.squads_of(R)[0]
	for m in s.members:
		w.kill_member(m)
	ba.points[R] = 200.0
	run_seconds(w, Balance.AI_TICK_S + 0.2)
	check(not s.is_wiped(), "the RED AI bought its wiped squad back")
	check(ba.purchases[R] >= 1, "purchase counted")


func test_red_stat_variance_toggle() -> void:
	var w := World.new()
	w.setup(4, true, true)
	var varied := false
	for s in w.squads_of(R):
		check_eq(s.skill + s.discipline + s.aggression + s.comms, 12, "%s rolled stats sum to 12" % s.name)
		if s.skill != 3 or s.discipline != 3 or s.aggression != 3 or s.comms != 3:
			varied = true
	check(varied, "RED squads are no longer uniform 3s")
	var w2 := World.new()
	w2.setup(4)
	for s in w2.squads_of(R):
		check(s.skill == 3 and s.discipline == 3 and s.aggression == 3 and s.comms == 3, "default RED stays uniform")
