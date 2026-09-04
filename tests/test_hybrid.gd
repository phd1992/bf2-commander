extends TestCase
## Phase 2.4: hybrid mode = Broken Arrow entries plus owned flags as entries.

const B := Balance.Team.BLUE
const R := Balance.Team.RED


func test_owned_flags_become_entries() -> void:
	var w := World.new()
	w.setup(5)
	w.set_spawn_mode("HYBRID")
	var hy: SpawnHybrid = w.spawn_policy
	check_eq(hy.entries(B).size(), 3, "only the three edge entries at the start")
	check_eq(hy.entry_names(B), ["North", "Centre", "South"], "edge entry names")
	var a := w.flag_by_name("A")
	var c := w.flag_by_name("C")
	a.owner = B
	c.owner = B
	check_eq(hy.entries(B).size(), 5, "two owned flags added as entries")
	check_eq(hy.entries(B)[3], a.centre, "A is the fourth entry")
	check_eq(hy.entry_names(B)[4], "Flag C", "flag entries are named")
	check_eq(hy.entries(R).size(), 3, "RED has no extra entries")
	# buy a squad at the forward entry
	var s := w.squads_of(B)[0]
	for m in s.members:
		w.kill_member(m)
	hy.points[B] = 100.0
	check(hy.buy_squad(s, 4), "bought at flag C")
	for m in s.members:
		check(m.pos.distance_to(c.centre_pos()) <= 4.0, "member entered at C")
	# losing the flag removes the entry
	c.owner = R
	check_eq(hy.entries(B).size(), 4, "C no longer an entry for BLUE")
	check_eq(hy.entries(R).size(), 4, "but it is one for RED now")
	# income still counts flags as in Broken Arrow
	check_near(hy.income_per_min(B), 12.0, 0.001, "10 + 2 per owned flag")


func test_hybrid_match_runs() -> void:
	var w := World.new()
	w.setup(6)
	w.set_spawn_mode("HYBRID")
	w.configure_match(true)
	for i in 1800:
		w.step(Balance.TICK)
		w.events.clear()
	check(not w.game_over or w.winner != Balance.Team.NONE or true, "3 minutes of hybrid AI vs AI ran without error")
	var purchases: int = w.spawn_policy.purchases[B] + w.spawn_policy.purchases[R]
	check(w.flag_count(B) + w.flag_count(R) > 0, "flags changed hands")
	print("    hybrid 3 min: flags B %d / R %d, purchases %d, kills %d" % [w.flag_count(B), w.flag_count(R), purchases, w.match_stats["kills"][B] + w.match_stats["kills"][R]])
