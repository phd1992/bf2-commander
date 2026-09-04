extends TestCase
## Test 10: combat sanity expectations (Section 8.4), plus hit-chance and
## targeting unit checks.

const T := Balance.Terrain


func _world(seed: int) -> World:
	var w := World.new()
	w.setup_blank(seed, 60, 40, T.OPEN)
	return w


## Creates a squad of n members, all with the given kits, at pos, holding.
func _squad(w: World, team: int, n: int, pos: Vector2, kits: Array = [], stats: Array = [3, 3, 3, 3]) -> Squad:
	var s := w.create_squad(team, "%s%d" % [Balance.TEAM_NAMES[team], w.squads.size()], stats, pos)
	for i in s.members.size():
		var m: Member = s.members[i]
		if i >= n:
			m.state = Balance.MemberState.DEAD
			continue
		if not kits.is_empty():
			m.kit = kits[mini(i, kits.size() - 1)]
	s.refresh_leader()
	w.give_order(s, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	return s


func _run_until_decided(w: World, a: Squad, b: Squad, max_s: float = 180.0) -> void:
	var ticks := int(max_s / Balance.TICK)
	for i in ticks:
		w.step(Balance.TICK)
		if a.alive_count() == 0 or b.alive_count() == 0:
			return


func test_hit_chance_formula() -> void:
	var w := _world(1)
	var blue := _squad(w, Balance.Team.BLUE, 1, Vector2(10.5, 10.5))
	var red := _squad(w, Balance.Team.RED, 1, Vector2(16.5, 10.5))   # 6 cells = half rifle range
	var shooter: Member = blue.leader
	var target: Member = red.leader
	check_near(Combat.hit_chance(w, shooter, blue, "RIFLE", target), 0.5, 0.001, "base 0.5 at half range, flat, stationary, no cover")
	target.pos = Vector2(22.5, 10.5)   # max range 12
	check_near(Combat.hit_chance(w, shooter, blue, "RIFLE", target), 0.25, 0.001, "half at max range")
	target.pos = Vector2(16.5, 10.5)
	target.is_moving = true
	check_near(Combat.hit_chance(w, shooter, blue, "RIFLE", target), 0.35, 0.001, "moving infantry 0.7")
	target.is_moving = false
	w.grid.set_terrain(target.cell(), T.FOREST)
	check_near(Combat.hit_chance(w, shooter, blue, "RIFLE", target), 0.3, 0.001, "forest cover 0.4")
	check_near(Combat.hit_chance(w, shooter, blue, "AT", target), 0.5 * (1.0 - 0.4 * 0.7) * Weapons.range_factor("AT", 6.0), 0.001, "AT ignores 30% of cover")
	w.grid.set_terrain(target.cell(), T.OPEN)
	w.grid.set_elev(shooter.cell(), 2)
	check_near(Combat.hit_chance(w, shooter, blue, "RIFLE", target), 0.575, 0.001, "height advantage 1.15")
	check_near(Combat.hit_chance(w, target, red, "RIFLE", shooter), 0.45, 0.001, "shooting uphill 0.9")
	w.grid.set_elev(shooter.cell(), 0)
	blue.skill = 5
	check_near(Combat.hit_chance(w, shooter, blue, "RIFLE", target), 0.65, 0.001, "skill 5 accuracy 1.3")
	blue.skill = 1
	check_near(Combat.hit_chance(w, shooter, blue, "RIFLE", target), 0.35, 0.001, "skill 1 accuracy 0.7")


func test_targeting_and_reaction() -> void:
	var w := _world(1)
	var blue := _squad(w, Balance.Team.BLUE, 1, Vector2(10.5, 10.5), [], [5, 3, 3, 3])
	var red := _squad(w, Balance.Team.RED, 1, Vector2(18.5, 10.5))
	run_ticks(w, 1)
	check(w.fog.vision[Balance.Team.BLUE].has(red.leader), "BLUE spots the RED soldier at 8 cells")
	check(blue.contact_since >= 0.0, "contact timer started")
	var shots_before_reaction := 0
	# Skill 5 reacts in 2 - 0.3*4 = 0.8 s
	run_ticks(w, 7)
	for e in w.events:
		if e["type"] == "shot" and e["team"] == Balance.Team.BLUE:
			shots_before_reaction += 1
	check_eq(shots_before_reaction, 0, "no shot before the reaction delay")
	run_ticks(w, 3)
	var shots := 0
	for e in w.events:
		if e["type"] == "shot" and e["team"] == Balance.Team.BLUE:
			shots += 1
	check(shots >= 1, "fires after the reaction delay")
	# out of range: no shots
	var w2 := _world(2)
	var b2 := _squad(w2, Balance.Team.BLUE, 1, Vector2(10.5, 10.5))
	_squad(w2, Balance.Team.RED, 1, Vector2(24.5, 10.5))   # 14 cells: seen but out of rifle range
	run_seconds(w2, 5.0)
	var any := false
	for e in w2.events:
		if e["type"] == "shot":
			any = true
	check(not any, "no shots beyond weapon range")
	check(b2.in_combat, "but the squad is in combat (contact within 20 cells)")


func test_six_vs_three_riflemen() -> void:
	var wins := 0
	for seed in range(1, 11):
		var w := _world(seed)
		var six := _squad(w, Balance.Team.BLUE, 6, Vector2(20.5, 20.5), [Balance.Kit.RIFLE])
		var three := _squad(w, Balance.Team.RED, 3, Vector2(28.5, 20.5), [Balance.Kit.RIFLE])
		_run_until_decided(w, six, three)
		if three.alive_count() == 0 and six.alive_count() >= 3:
			wins += 1
	print("    6v3 riflemen: %d/10" % wins)
	check(wins >= 9, "6 riflemen beat 3 with >= 3 survivors in %d of 10 runs" % wins)


func _building(w: World, x0: int, y0: int, bw: int, bh: int) -> void:
	for y in range(y0, y0 + bh):
		for x in range(x0, x0 + bw):
			var edge := x == x0 or y == y0 or x == x0 + bw - 1 or y == y0 + bh - 1
			w.grid.set_terrain(Vector2i(x, y), T.WALL if edge else T.INTERIOR)
	w.grid.set_terrain(Vector2i(x0, y0 + bh / 2), T.DOOR)
	w.buildings.scan()


func test_defenders_in_interior_win() -> void:
	var wins := 0
	for seed in range(1, 11):
		var w := _world(seed)
		_building(w, 30, 17, 8, 7)
		var defenders := _squad(w, Balance.Team.BLUE, 6, Vector2(33.5, 20.5), [Balance.Kit.RIFLE])
		# spread the defenders over interior cells
		var interior: Array = []
		for y in range(18, 23):
			for x in range(31, 37):
				interior.append(Vector2i(x, y))
		for i in defenders.members.size():
			defenders.members[i].pos = Grid.centre_of(interior[i * 5 % interior.size()])
		var attackers := _squad(w, Balance.Team.RED, 6, Vector2(12.5, 20.5), [Balance.Kit.RIFLE])
		w.give_order(attackers, Balance.Order.MOVE, Vector2i(28, 20), null, null, 0.0)
		_run_until_decided(w, defenders, attackers, 240.0)
		if attackers.alive_count() == 0:
			wins += 1
	print("    interior defenders: %d/10" % wins)
	check(wins >= 8, "interior defenders win in %d of 10 runs" % wins)


func _tank_with_crew(w: World, pos: Vector2) -> Vehicle:
	var crew := _squad(w, Balance.Team.RED, 2, pos + Vector2(3, 3), [Balance.Kit.RIFLE])
	var tank := w.spawn_vehicle("TANK", Balance.Team.RED, pos)
	for m in crew.living():
		w.board_vehicle(m, tank)
	crew.order = {}
	return tank


func test_tank_vs_infantry_in_open() -> void:
	var wins := 0
	for seed in range(1, 11):
		var w := _world(seed)
		var tank := _tank_with_crew(w, Vector2(30.5, 20.5))
		var inf := _squad(w, Balance.Team.BLUE, 6, Vector2(22.5, 20.5))
		for i in int(180.0 / Balance.TICK):
			w.step(Balance.TICK)
			if inf.alive_count() == 0 or not tank.alive:
				break
		if tank.alive and inf.alive_count() == 0:
			wins += 1
	print("    tank in open: %d/10" % wins)
	check(wins >= 7, "tank beats infantry in the open in %d of 10 runs" % wins)


func test_tank_vs_infantry_in_interior() -> void:
	var losses := 0
	for seed in range(1, 11):
		var w := _world(seed)
		_building(w, 18, 17, 8, 7)
		var inf := _squad(w, Balance.Team.BLUE, 6, Vector2(23.5, 20.5))
		# The squad mans the east wall (interior cells at x = 24 look out through
		# the wall at x = 25); the AT is not the nearest soldier to the tank.
		var spots := [Vector2i(24, 20), Vector2i(24, 19), Vector2i(24, 21), Vector2i(24, 18), Vector2i(23, 20)]
		var si := 0
		for m in inf.members:
			if m.kit == Balance.Kit.AT:
				m.pos = Grid.centre_of(Vector2i(24, 22))
			else:
				m.pos = Grid.centre_of(spots[si])
				si += 1
		var tank := _tank_with_crew(w, Vector2(32.5, 20.5))   # 8 cells from the wall line
		for i in int(240.0 / Balance.TICK):
			w.step(Balance.TICK)
			if inf.alive_count() == 0 or not tank.alive:
				break
		if not tank.alive:
			losses += 1
	print("    tank vs interior: loses %d/10" % losses)
	check(losses >= 5, "tank loses to interior infantry with AT in %d of 10 runs" % losses)


func test_veterancy() -> void:
	var w := _world(1)
	var s := _squad(w, Balance.Team.BLUE, 6, Vector2(10.5, 10.5), [], [2, 3, 3, 4])
	var victims := _squad(w, Balance.Team.RED, 6, Vector2(14.5, 10.5))
	check_eq(s.skill, 2, "rolled skill")
	for i in 10:
		w.kill_member(victims.members[i % 6], s)
		victims.members[i % 6].state = Balance.MemberState.ALIVE
	check_eq(s.xp, 100, "10 kills = 100 XP")
	check_eq(s.skill, 3, "skill +1 at 100 XP")
	s.add_xp(150)
	check_eq(s.skill, 4, "skill +1 again at 250 XP")
	s.add_xp(500)
	check_eq(s.skill, 4, "no third promotion")
	for m in s.members:
		w.kill_member(m)
	check_eq(s.xp, 0, "wipe resets XP")
	check_eq(s.skill, 2, "wipe resets skill to the rolled value")


func test_cover_seeking_and_bounding() -> void:
	var w := _world(3)
	w.grid.fill_rect(20, 18, 3, 5, T.FOREST)
	var s := _squad(w, Balance.Team.BLUE, 6, Vector2(18.5, 20.5))
	var enemy := _squad(w, Balance.Team.RED, 6, Vector2(30.5, 20.5))
	w.give_order(s, Balance.Order.MOVE, Vector2i(40, 20), null, null, 0.0)
	run_seconds(w, 8.0)
	check(s.in_combat, "squad is in combat")
	var in_cover := 0
	for m in s.members:
		if m.cover_cell.x >= 0:
			in_cover += 1
	check(in_cover > 0, "members shot at seek cover (%d of 6)" % in_cover)
	check(enemy.alive_count() < 6 or s.alive_count() < 6, "shots were exchanged")
