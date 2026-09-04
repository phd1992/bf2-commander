extends TestCase
## Test 13: fog of war spotting rules and Comms-delayed contacts.

const T := Balance.Terrain


func _pair(w: World, blue_pos: Vector2, red_pos: Vector2, red_stats: Array = [3, 3, 3, 3], blue_stats: Array = [3, 3, 3, 3]) -> Array:
	var b := w.create_squad(Balance.Team.BLUE, "B", blue_stats, blue_pos)
	var r := w.create_squad(Balance.Team.RED, "R", red_stats, red_pos)
	for s in [b, r]:
		for i in range(1, 6):
			s.members[i].state = Balance.MemberState.DEAD
		s.refresh_leader()
		w.give_order(s, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	return [b, r]


func test_forest_concealment() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	w.grid.fill_rect(30, 0, 10, 40, T.FOREST)
	var pair := _pair(w, Vector2(24.5, 20.5), Vector2(32.5, 20.5))   # 8 cells
	var red_unit: Member = pair[1].leader
	w.step(Balance.TICK)
	check(not w.fog.is_visible_to(Balance.Team.BLUE, red_unit), "unit in FOREST is unseen at 8 cells")
	check(w.fog.is_visible_to(Balance.Team.RED, pair[0].leader), "but it sees the BLUE soldier in the open")
	pair[0].leader.pos = Vector2(27.5, 20.5)   # 5 cells
	w.step(Balance.TICK)
	check(w.fog.is_visible_to(Balance.Team.BLUE, red_unit), "seen at 5 cells")


func test_firing_reveals() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	w.grid.fill_rect(30, 0, 10, 40, T.FOREST)
	var pair := _pair(w, Vector2(17.5, 20.5), Vector2(32.5, 20.5))   # 15 cells
	var red_unit: Member = pair[1].leader
	w.step(Balance.TICK)
	check(not w.fog.is_visible_to(Balance.Team.BLUE, red_unit), "unseen at 15 cells in forest")
	red_unit.last_shot_time = w.time
	w.step(Balance.TICK)
	check(w.fog.is_visible_to(Balance.Team.BLUE, red_unit), "firing reveals it at 15 cells")
	run_seconds(w, Balance.FLASH_S + 0.2)
	check(not w.fog.is_visible_to(Balance.Team.BLUE, red_unit), "flash fades after 3 s")


func test_open_spot_ranges() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	var pair := _pair(w, Vector2(10.5, 20.5), Vector2(24.5, 20.5))   # 14 cells
	w.step(Balance.TICK)
	check(w.fog.is_visible_to(Balance.Team.BLUE, pair[1].leader), "infantry seen at 14 cells in the open")
	pair[1].leader.pos = Vector2(25.5, 20.5)   # 15 cells
	w.step(Balance.TICK)
	check(not w.fog.is_visible_to(Balance.Team.BLUE, pair[1].leader), "not at 15")
	# vehicles are loud: spotted at 16 even in forest
	w.grid.fill_rect(26, 0, 6, 40, T.FOREST)
	var jeep := w.spawn_vehicle("JEEP", Balance.Team.RED, Vector2(26.5, 20.5))   # 16 cells
	w.step(Balance.TICK)
	check(w.fog.is_visible_to(Balance.Team.BLUE, jeep), "vehicle spotted at 16 cells in forest")
	jeep.pos = Vector2(27.5, 20.5)
	w.step(Balance.TICK)
	check(not w.fog.is_visible_to(Balance.Team.BLUE, jeep), "not at 17")


func test_los_blocks_spotting() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	for y in range(0, 40):
		w.grid.set_terrain(Vector2i(20, y), T.WALL)
	var pair := _pair(w, Vector2(15.5, 20.5), Vector2(25.5, 20.5))
	w.step(Balance.TICK)
	check(not w.fog.is_visible_to(Balance.Team.BLUE, pair[1].leader), "wall blocks spotting")
	w.grid.set_terrain(Vector2i(20, 20), T.RUBBLE)
	w.step(Balance.TICK)
	check(w.fog.is_visible_to(Balance.Team.BLUE, pair[1].leader), "rubble lets the spotter see through")


func test_contact_comms_delay_and_persistence() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	# BLUE squad with Comms 2: delay 4 s, persists 8 s after last seen
	var pair := _pair(w, Vector2(10.5, 20.5), Vector2(20.5, 20.5), [3, 3, 3, 3], [3, 3, 4, 2])
	var red_unit: Member = pair[1].leader
	w.step(Balance.TICK)
	check_eq(w.fog.revealed_contacts(Balance.Team.BLUE, w.time).size(), 0, "no commander contact yet")
	run_seconds(w, 3.8)
	check_eq(w.fog.revealed_contacts(Balance.Team.BLUE, w.time).size(), 0, "still hidden before 4 s")
	run_seconds(w, 0.3)
	var contacts := w.fog.revealed_contacts(Balance.Team.BLUE, w.time)
	check_eq(contacts.size(), 1, "contact revealed after the Comms delay")
	check(contacts.size() == 1 and contacts[0]["unit"] == red_unit, "it is the RED soldier")
	# break line of sight: the contact persists then fades
	red_unit.pos = Vector2(50.5, 20.5)
	w.step(Balance.TICK)
	check(not w.fog.is_visible_to(Balance.Team.BLUE, red_unit), "no longer seen")
	run_seconds(w, 7.5)
	check_eq(w.fog.revealed_contacts(Balance.Team.BLUE, w.time).size(), 1, "persists 8 s after last seen")
	run_seconds(w, 1.0)
	check_eq(w.fog.revealed_contacts(Balance.Team.BLUE, w.time).size(), 0, "faded")
	# RED (Comms 3) keeps its contact on the BLUE soldier for 10 s after last seen
	check_eq(w.fog.revealed_contacts(Balance.Team.RED, w.time).size(), 1, "RED contact still persists at 8.6 s")
	run_seconds(w, 1.6)
	check_eq(w.fog.revealed_contacts(Balance.Team.RED, w.time).size(), 0, "RED contact faded after 10 s")


func test_best_delay_wins() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	var slow := w.create_squad(Balance.Team.BLUE, "slow", [3, 3, 5, 1], Vector2(10.5, 20.5))   # delay 5
	var fast := w.create_squad(Balance.Team.BLUE, "fast", [3, 3, 1, 5], Vector2(10.5, 26.5))   # delay 1
	var red := w.create_squad(Balance.Team.RED, "R", [3, 3, 3, 3], Vector2(20.5, 23.5))
	for s in [slow, fast, red]:
		w.give_order(s, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	run_seconds(w, 1.2)
	check(w.fog.revealed_contacts(Balance.Team.BLUE, w.time).size() > 0, "the Comms-5 squad's report arrives after 1 s")


func test_cell_vision_states() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	for y in range(0, 40):
		w.grid.set_terrain(Vector2i(20, y), T.WALL)
	var b := w.create_squad(Balance.Team.BLUE, "B", [3, 3, 3, 3], Vector2(10.5, 20.5))
	w.give_order(b, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	w.step(Balance.TICK)
	w.fog.update_cell_vision(Balance.Team.BLUE, true)
	var g := w.grid
	check_eq(w.fog.cell_seen_now[g.idx(12, 20)], 1, "nearby open cell seen")
	check_eq(w.fog.cell_seen_now[g.idx(25, 20)], 0, "cell behind the wall unseen")
	check_eq(w.fog.cell_seen_now[g.idx(10, 38)], 0, "cell beyond spot range unseen")
	# move away: the first cell becomes 'seen before'
	for m in b.members:
		m.pos = Vector2(10.5, 5.5)
	w.step(Balance.TICK)
	w.fog.update_cell_vision(Balance.Team.BLUE, true)
	check_eq(w.fog.cell_seen_now[g.idx(12, 20)], 0, "no longer seen now")
	check_eq(w.fog.cell_seen_ever[g.idx(12, 20)], 1, "but remembered as seen")
	check_eq(w.fog.cell_seen_ever[g.idx(25, 20)], 0, "never-seen cell stays unknown")
