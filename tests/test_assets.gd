extends TestCase
## Test 14: asset cooldown and arrival timing, artillery damages walls,
## supply heals and boosts accuracy, UAV reveals, vehicle drop spawns a jeep.

const T := Balance.Terrain
const B := Balance.Team.BLUE
const R := Balance.Team.RED


func _world() -> World:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	return w


func test_cooldown_and_arrival() -> void:
	var w := _world()
	var a := w.assets
	check(a.is_ready(B, "UAV"), "UAV ready at start")
	check(a.use(B, "UAV", Vector2i(30, 20)), "UAV used")
	check(not a.is_ready(B, "UAV"), "on cooldown immediately (cooldown starts on use)")
	check_near(a.cooldown_remaining(B, "UAV"), 90.0, 0.001, "90 s cooldown")
	check(not a.use(B, "UAV", Vector2i(30, 20)), "cannot use again")
	check(a.is_ready(R, "UAV"), "RED's UAV is independent")
	run_seconds(w, 2.9)
	check_eq(a.active_uavs(B).size(), 0, "not arrived before 3 s")
	check_eq(a.pending(B).size(), 1, "pending")
	run_seconds(w, 0.2)
	check_eq(a.active_uavs(B).size(), 1, "arrived after 3 s")
	run_seconds(w, 30.0)
	check_eq(a.active_uavs(B).size(), 0, "UAV expires after 30 s")
	run_seconds(w, 57.0)
	check(a.is_ready(B, "UAV"), "ready again 90 s after use")


func test_artillery_damages_walls_and_units() -> void:
	var w := _world()
	for y in range(15, 26):
		w.grid.set_terrain(Vector2i(30, y), T.WALL)
	w.buildings.scan()
	var victims := w.create_squad(R, "V", [3, 3, 3, 3], Vector2(32.5, 20.5))
	var spots := [Vector2(32.5, 20.5), Vector2(31.5, 18.5), Vector2(31.5, 22.5), Vector2(33.5, 18.5), Vector2(33.5, 22.5), Vector2(32.5, 24.5)]
	for i in victims.members.size():
		victims.members[i].pos = spots[i]
	w.give_order(victims, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	check(w.assets.use(B, "ARTILLERY", Vector2i(30, 20)), "artillery called")
	run_seconds(w, 4.9)
	check_eq(w.match_stats["walls_destroyed"], 0, "nothing before the 5 s arrival delay")
	# Step tick by tick and reconcile every shell with who stood inside its splash.
	var impacts := 0
	var hits := {}
	for m in victims.members:
		hits[m] = 0
	for i in 65:
		w.events.clear()
		w.step(Balance.TICK)
		for e in w.events:
			if e["type"] == "impact" and e["weapon"] == "ARTY_SHELL":
				impacts += 1
				check(Grid.centre_of(Vector2i(30, 20)).distance_to(e["pos"]) <= Balance.ASSETS["ARTILLERY"]["radius"] + 0.001, "shell lands inside the 4-cell radius")
				for m in victims.members:
					if m.pos.distance_to(e["pos"]) <= e["radius"]:
						hits[m] += 1
	check_eq(impacts, 6, "six shells landed")
	for m in victims.members:
		var expected := maxf(0.0, Balance.MEMBER_HP - Balance.WEAPONS["ARTY_SHELL"]["dmg_inf"] * hits[m])
		var actual: float = m.hp if m.is_alive() else 0.0
		check_near(actual, expected, 0.001, "member %d took %d splash hits" % [m.id, hits[m]])
	var damaged := 0
	var rubble := 0
	for y in range(15, 26):
		var c := Vector2i(30, y)
		if w.grid.get_terrain(c) == T.RUBBLE:
			rubble += 1
		elif w.grid.get_wall_hp(c) < Balance.WALL_HP:
			damaged += 1
	check(damaged + rubble > 0, "walls took damage (%d damaged, %d rubble)" % [damaged, rubble])


func test_supply_heals_and_boosts_accuracy() -> void:
	var w := _world()
	var s := w.create_squad(B, "S", [3, 3, 3, 3], Vector2(20.5, 20.5))
	w.give_order(s, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	for m in s.members:
		m.hp = 50.0
	var enemy := w.create_squad(R, "E", [3, 3, 3, 3], Vector2(56.5, 20.5))   # far away: no firefight
	var p_before := Combat.hit_chance(w, s.leader, s, "RIFLE", enemy.leader)
	check(w.assets.use(B, "SUPPLY", Vector2i(20, 20)), "supply called")
	run_seconds(w, 8.1)
	check_eq(w.assets.active_crates(B).size(), 1, "crate landed after 8 s")
	var p_after := Combat.hit_chance(w, s.leader, s, "RIFLE", enemy.leader)
	check_near(p_after - p_before, Balance.HIT_BASE * Balance.SUPPLY_ACCURACY_BONUS * Weapons.range_factor("RIFLE", 36.0), 0.01, "accuracy_mult +0.3 near the crate")
	var hp0 := s.members[2].hp
	run_seconds(w, 2.0)
	check(s.members[2].hp >= hp0 + 19.0 and s.members[2].hp <= hp0 + 21.0, "healed ~10 HP/s (%.1f -> %.1f)" % [hp0, s.members[2].hp])
	run_seconds(w, 10.0)
	check_near(s.members[2].hp, Balance.MEMBER_HP, 0.001, "capped at full HP")
	# the enemy squad gets no benefit
	check(not w.assets.has_supply_near(R, Vector2(20.5, 20.5)), "crate is team-specific")
	run_seconds(w, 60.0)
	check_eq(w.assets.active_crates(B).size(), 0, "crate gone after 60 s")


func test_uav_reveals_live_contacts() -> void:
	var w := _world()
	w.grid.fill_rect(30, 0, 20, 40, T.FOREST)
	var enemy := w.create_squad(R, "E", [3, 3, 3, 3], Vector2(40.5, 20.5))
	w.give_order(enemy, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	run_ticks(w, 1)
	check_eq(w.fog.revealed_contacts(B, w.time).size(), 0, "hidden in the forest with nobody nearby")
	w.assets.use(B, "UAV", Vector2i(40, 20))
	run_seconds(w, 3.1)
	check_eq(w.fog.revealed_contacts(B, w.time).size(), 6, "all six revealed immediately under the UAV")
	run_seconds(w, 31.0)
	check_eq(w.fog.revealed_contacts(B, w.time).size(), 0, "contacts drop once the UAV expires")


func test_vehicle_drop() -> void:
	var w := _world()
	w.grid.fill_rect(20, 0, 5, 40, T.FOREST)
	check_eq(w.vehicles.size(), 0, "no vehicles")
	w.assets.use(R, "VEHICLE_DROP", Vector2i(22, 20))   # forest: wheeled impassable
	run_seconds(w, 8.1)
	check_eq(w.vehicles.size(), 1, "jeep dropped after 8 s")
	var v: Vehicle = w.vehicles[0]
	check_eq(v.vtype, "JEEP", "it is a jeep")
	check_eq(v.team, R, "for the calling team")
	check(w.grid.is_passable(v.cell(), Balance.MoveClass.WHEELED), "placed on a wheeled-passable cell")
	check(v.pos.distance_to(Vector2(22.5, 20.5)) <= 4.0, "near the target")
	check_eq(w.match_stats["assets_used"], 1, "asset use counted")
