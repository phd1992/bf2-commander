extends TestCase
## Vehicles (Section 7): pads, mounting with overflow on foot, driving,
## dismounting and capturing, pad respawn, side change on capture.

const T := Balance.Terrain


func test_pads_spawn_for_owner() -> void:
	var w := World.new()
	w.setup(4)
	run_ticks(w, 1)
	var jeep := w.pad_vehicle("BLUE HQ", "JEEP")
	var apc := w.pad_vehicle("BLUE HQ", "APC")
	check(jeep != null and jeep.alive and jeep.team == Balance.Team.BLUE, "BLUE HQ jeep spawned")
	check(apc != null and apc.alive and apc.vtype == "APC", "BLUE HQ APC spawned")
	check(w.pad_vehicle("RED HQ", "APC") != null, "RED HQ APC spawned")
	check(w.pad_vehicle("A", "JEEP") == null, "neutral flag pad is empty")
	check(w.pad_vehicle("C", "TANK") == null, "neutral C has no tank yet")
	var a := w.flag_by_name("A")
	a.owner = Balance.Team.RED
	run_ticks(w, 1)
	var aj := w.pad_vehicle("A", "JEEP")
	check(aj != null and aj.team == Balance.Team.RED, "captured flag pad spawns for the owner")
	# destroy it: respawns 60 s later
	w.destroy_vehicle(aj, null)
	run_seconds(w, 59.5)
	check(w.pad_vehicle("A", "JEEP") == null, "no respawn before 60 s")
	run_seconds(w, 1.0)
	check(w.pad_vehicle("A", "JEEP") != null, "pad respawn after 60 s")


func test_idle_pad_vehicle_changes_side() -> void:
	var w := World.new()
	w.setup(4)
	var a := w.flag_by_name("A")
	a.owner = Balance.Team.RED
	a.progress = -1.0
	run_ticks(w, 1)
	var aj := w.pad_vehicle("A", "JEEP")
	check_eq(aj.team, Balance.Team.RED, "RED jeep at A")
	# BLUE captures A with three soldiers parked on it
	var s := w.create_squad(Balance.Team.BLUE, "Cap", [3, 3, 3, 3], a.centre_pos())
	for i in 3:
		s.members[i].pos = a.centre_pos()
		s.members[i].kit = Balance.Kit.RIFLE   # an AT soldier would just destroy the jeep
	for i in range(3, 6):
		s.members[i].state = Balance.MemberState.DEAD
	w.give_order(s, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	run_seconds(w, 15.0)
	check_eq(a.owner, Balance.Team.BLUE, "A is BLUE now")
	check_eq(aj.team, Balance.Team.BLUE, "idle pad jeep switched to BLUE")


func test_mount_drive_dismount_capture() -> void:
	var w := World.new()
	w.setup(6)
	run_ticks(w, 1)
	var s := w.squads_of(Balance.Team.BLUE)[0]
	var jeep := w.pad_vehicle("BLUE HQ", "JEEP")
	var a := w.flag_by_name("A")
	w.give_order(s, Balance.Order.MOUNT, jeep.cell(), null, jeep, 0.0)
	run_seconds(w, 12.0)
	check_eq(jeep.occupants.size(), 4, "four seats filled")
	check(s.is_mounted(), "leader is mounted")
	check_eq(s.vehicle, jeep, "squad owns the jeep")
	var on_foot := 0
	for m in s.members:
		if m.is_on_foot():
			on_foot += 1
	check_eq(on_foot, 2, "two members remain on foot")
	# now drive to A
	w.give_order(s, Balance.Order.MOVE, a.centre, null, null, 0.0)
	run_seconds(w, 25.0)
	check(jeep.pos.distance_to(a.centre_pos()) <= 2.0, "jeep drove to A (at %s)" % str(jeep.pos))
	var walking_behind := 0
	for m in s.members:
		if m.is_on_foot() and m.pos.distance_to(jeep.pos) > 3.0:
			walking_behind += 1
	check(walking_behind >= 1, "the foot members are still jogging behind (%d)" % walking_behind)
	check_eq(s.leader.pos, jeep.pos, "mounted leader position is the vehicle's")
	w.give_order(s, Balance.Order.DISMOUNT, Vector2i(-1, -1), null, null, 0.0)
	run_ticks(w, 2)
	check_eq(jeep.occupants.size(), 0, "everyone dismounted")
	check(jeep.is_idle(), "jeep is idle and unowned")
	check(s.vehicle == null, "squad no longer owns a vehicle")
	for m in s.members:
		if m.is_alive():
			check(m.state == Balance.MemberState.ALIVE, "member on foot after dismount")
	w.give_order(s, Balance.Order.ATTACK, a.centre, a, null, 0.0)
	run_seconds(w, 40.0)
	check_eq(a.owner, Balance.Team.BLUE, "A captured after dismount")
	check(s.order_completed, "ATTACK order completed on capture")


func test_vehicle_needs_two_crew_to_fire() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	var jeep := w.spawn_vehicle("JEEP", Balance.Team.BLUE, Vector2(10.5, 10.5))
	var crew := w.create_squad(Balance.Team.BLUE, "C", [3, 3, 3, 3], Vector2(10.5, 12.5))
	var target := w.create_squad(Balance.Team.RED, "R", [3, 3, 3, 3], Vector2(16.5, 10.5))
	w.give_order(target, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	for m in target.members:
		m.kit = Balance.Kit.RIFLE
	w.board_vehicle(crew.members[0], jeep)
	crew.order = {}
	run_seconds(w, 4.0)
	var hmg := 0
	for e in w.events:
		if e["type"] == "shot" and e["weapon"] == "HMG":
			hmg += 1
	check_eq(hmg, 0, "one occupant: the HMG stays silent")
	w.board_vehicle(crew.members[1], jeep)
	w.events.clear()
	run_seconds(w, 4.0)
	for e in w.events:
		if e["type"] == "shot" and e["weapon"] == "HMG":
			hmg += 1
	check(hmg > 0, "two occupants: the HMG fires")


func test_destroyed_vehicle_kills_occupants() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	var jeep := w.spawn_vehicle("JEEP", Balance.Team.RED, Vector2(10.5, 10.5))
	var crew := w.create_squad(Balance.Team.RED, "C", [3, 3, 3, 3], Vector2(10.5, 12.5))
	var killer := w.create_squad(Balance.Team.BLUE, "K", [3, 3, 3, 3], Vector2(30.5, 30.5))
	for i in 3:
		w.board_vehicle(crew.members[i], jeep)
	w.destroy_vehicle(jeep, killer)
	check(not jeep.alive, "jeep destroyed")
	check(jeep not in w.vehicles, "wreck removed")
	check_eq(crew.alive_count(), 3, "three occupants died")
	check_eq(killer.kills, 3, "kills credited")
	check_eq(killer.xp, 3 * Balance.XP_KILL + Balance.XP_VEHICLE, "XP for occupants and the vehicle")
	check_eq(killer.vehicle_kills, 1, "vehicle kill counted")


func test_tracked_vehicle_avoids_forest_and_water() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	w.grid.fill_rect(20, 0, 3, 30, T.WATER)
	w.grid.fill_rect(20, 30, 3, 10, T.FOREST)
	for y in range(28, 30):
		for x in range(20, 23):
			w.grid.set_terrain(Vector2i(x, y), T.ROAD)
	var apc := w.spawn_vehicle("APC", Balance.Team.BLUE, Vector2(5.5, 5.5))
	var s := w.create_squad(Balance.Team.BLUE, "S", [3, 3, 3, 3], Vector2(5.5, 5.5))
	for m in s.members:
		w.board_vehicle(m, apc)
	w.give_order(s, Balance.Order.MOVE, Vector2i(40, 5), null, null, 0.0)
	var bad := false
	for i in 600:
		w.step(Balance.TICK)
		var t := w.grid.get_terrain(apc.cell())
		if t == T.WATER or t == T.FOREST:
			bad = true
	check(not bad, "APC never enters water or forest")
	check(apc.pos.x > 30.0, "APC crossed via the road bridge (at %s)" % str(apc.pos))
