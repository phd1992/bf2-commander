extends TestCase
## Test 5: capture timings. Test 6: bleed, respawn cost, victory conditions.

const T := Balance.Terrain


func _world_with_flag() -> Dictionary:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	var f := w.add_flag("A", Vector2i(30, 20))
	w.add_flag("BLUE HQ", Vector2i(5, 20), true, Balance.Team.BLUE)
	w.add_flag("RED HQ", Vector2i(55, 20), true, Balance.Team.RED)
	return { "w": w, "f": f }


func _place(w: World, team: int, n: int, pos: Vector2) -> Squad:
	var s := w.create_squad(team, "S%d" % w.squads.size(), [3, 3, 3, 3], pos)
	# keep only n alive, park everyone on the flag centre so movement is irrelevant
	for i in s.members.size():
		var m: Member = s.members[i]
		if i < n:
			m.pos = pos
		else:
			m.state = Balance.MemberState.DEAD
	s.refresh_leader()
	w.give_order(s, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	return s


func test_one_soldier_flips_neutral_in_20s() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	var f: Flag = d["f"]
	_place(w, Balance.Team.BLUE, 1, f.centre_pos())
	run_seconds(w, 19.5)
	check_eq(f.owner, Balance.Team.NONE, "not yet captured at 19.5 s (progress %.2f)" % f.progress)
	run_seconds(w, 0.6)
	check_eq(f.owner, Balance.Team.BLUE, "captured by 20.1 s")
	check_near(f.progress, 1.0, 0.001, "progress clamped at +1")


func test_three_soldiers_flip_in_about_7s() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	var f: Flag = d["f"]
	_place(w, Balance.Team.RED, 3, f.centre_pos())
	run_seconds(w, 6.0)
	check_eq(f.owner, Balance.Team.NONE, "not yet at 6 s")
	run_seconds(w, 1.0)
	check_eq(f.owner, Balance.Team.RED, "RED owns it by 7 s")


func test_more_than_three_add_nothing() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	var f: Flag = d["f"]
	_place(w, Balance.Team.BLUE, 6, f.centre_pos())
	run_seconds(w, 6.0)
	check_eq(f.owner, Balance.Team.NONE, "six soldiers are no faster than three")
	run_seconds(w, 1.0)
	check_eq(f.owner, Balance.Team.BLUE, "captured at ~7 s")


func test_contested_does_not_move() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	var f: Flag = d["f"]
	_place(w, Balance.Team.BLUE, 2, f.centre_pos() + Vector2(1, 0))
	_place(w, Balance.Team.RED, 2, f.centre_pos() + Vector2(-1, 0))
	run_seconds(w, 10.0)
	check_near(f.progress, 0.0, 0.001, "contested flag does not move")
	check_eq(f.owner, Balance.Team.NONE, "still neutral")


func test_neutralisation_crossing_zero() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	var f: Flag = d["f"]
	f.owner = Balance.Team.RED
	f.progress = -1.0
	_place(w, Balance.Team.BLUE, 3, f.centre_pos())
	run_seconds(w, 6.5)
	check_eq(f.owner, Balance.Team.RED, "still RED before crossing 0 (%.2f)" % f.progress)
	run_seconds(w, 0.5)
	check_eq(f.owner, Balance.Team.NONE, "neutral once progress crosses 0 (%.2f)" % f.progress)
	run_seconds(w, 7.0)
	check_eq(f.owner, Balance.Team.BLUE, "BLUE after a full further capture")


func test_bleed_timing() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	var f: Flag = d["f"]
	f.owner = Balance.Team.BLUE
	f.progress = 1.0
	run_seconds(w, 2.9)
	check_eq(w.tickets[Balance.Team.RED], 200, "no bleed before 3 s")
	run_seconds(w, 0.2)
	check_eq(w.tickets[Balance.Team.RED], 199, "RED bleeds 1 ticket at 3 s")
	check_eq(w.tickets[Balance.Team.BLUE], 200, "BLUE does not bleed")
	run_seconds(w, 27.0)
	check_eq(w.tickets[Balance.Team.RED], 190, "10 tickets after 30 s")
	f.owner = Balance.Team.NONE
	run_seconds(w, 9.0)
	check_eq(w.tickets[Balance.Team.RED], 190, "equal flag counts: no bleed")


func test_respawn_costs() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	var s := _place(w, Balance.Team.BLUE, 6, Vector2(10, 20))
	w.kill_member(s.members[2])
	run_seconds(w, 15.1)
	check_eq(w.tickets[Balance.Team.BLUE], 199, "member respawn costs 1 ticket")
	for m in s.members:
		w.kill_member(m)
	run_seconds(w, 20.1)
	check_eq(w.tickets[Balance.Team.BLUE], 193, "squad respawn costs 6 tickets")
	check_eq(s.alive_count(), 6, "all six are back")


func test_victory_on_zero_tickets() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	w.tickets[Balance.Team.RED] = 1
	d["f"].owner = Balance.Team.BLUE
	run_seconds(w, 3.1)
	check(w.game_over, "game over when RED hits 0")
	check_eq(w.winner, Balance.Team.BLUE, "BLUE wins")


func test_time_limit_rule() -> void:
	var d := _world_with_flag()
	var w: World = d["w"]
	w.tickets[Balance.Team.BLUE] = 150
	w.tickets[Balance.Team.RED] = 120
	w.tick_count = int(Balance.MATCH_LENGTH_S / Balance.TICK) - 2
	w.time = w.tick_count * Balance.TICK
	run_ticks(w, 1)
	check(not w.game_over, "not over one tick before 20 minutes")
	run_ticks(w, 1)
	check(w.game_over, "over at 20 minutes")
	check_eq(w.winner, Balance.Team.BLUE, "team with more tickets wins")
	# draw
	var d2 := _world_with_flag()
	var w2: World = d2["w"]
	w2.tick_count = int(Balance.MATCH_LENGTH_S / Balance.TICK) - 1
	w2.time = w2.tick_count * Balance.TICK
	run_ticks(w2, 1)
	check(w2.game_over, "over at the time limit")
	check_eq(w2.winner, Balance.Team.NONE, "equal tickets is a draw")


func test_match_against_idle_red_is_winnable() -> void:
	var w := World.new()
	w.setup(2)
	w.tickets[Balance.Team.RED] = 12
	var blue := w.squads_of(Balance.Team.BLUE)
	var targets := ["A", "B", "A", "B"]
	for i in blue.size():
		w.give_order(blue[i], Balance.Order.ATTACK, Vector2i(-1, -1), w.flag_by_name(targets[i]), null, 0.0)
	var ticks := 0
	while not w.game_over and ticks < 6000:
		w.step(Balance.TICK)
		ticks += 1
	check(w.game_over, "match ended within 10 minutes of sim time (%d ticks)" % ticks)
	check_eq(w.winner, Balance.Team.BLUE, "BLUE beats an idle RED by bleed")
	check(w.flag_by_name("A").owner == Balance.Team.BLUE and w.flag_by_name("B").owner == Balance.Team.BLUE, "A and B captured")
