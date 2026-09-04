extends TestCase
## Commander AI (Section 13): rule-level checks on synthetic setups and a
## short RED-vs-defending-BLUE match to see the AI capture, defend, mount
## vehicles and use its assets.

const T := Balance.Terrain
const B := Balance.Team.BLUE
const R := Balance.Team.RED


func _blank() -> World:
	var w := World.new()
	w.setup_blank(1, 80, 40, T.OPEN)
	w.add_flag("BLUE HQ", Vector2i(5, 20), true, B)
	w.add_flag("A", Vector2i(25, 20))
	w.add_flag("B", Vector2i(50, 20))
	w.add_flag("RED HQ", Vector2i(75, 20), true, R)
	return w


func test_attack_rule_sends_idle_squads_to_flags_with_cap() -> void:
	var w := _blank()
	var ai := CommanderAI.new(R, 0.0)
	ai.enabled["vehicles"] = false
	var squads: Array = []
	for i in 4:
		squads.append(w.create_squad(R, "R%d" % i, [3, 3, 3, 3], Vector2(70.5, 15.5 + i * 3)))
	ai.tick(w)
	var counts := {}
	for s in squads:
		check_eq(s.pending.get("type", -1), Balance.Order.ATTACK, "%s got an ATTACK order" % s.name)
		var f: Flag = s.pending.get("flag")
		if f != null:
			counts[f.name] = counts.get(f.name, 0) + 1
	check_eq(counts.get("B", 0), 2, "at most two squads per flag (B)")
	check_eq(counts.get("A", 0), 2, "the other two go to the next flag (A)")
	check_eq(ai.orders_issued, 4, "four orders issued")


func test_defend_rule_and_flag_values() -> void:
	var w := _blank()
	var ai := CommanderAI.new(R, 0.0)
	ai.enabled["vehicles"] = false
	var b := w.flag_by_name("B")
	b.owner = R
	b.progress = -1.0
	var defender := w.create_squad(R, "Rd", [3, 3, 3, 3], Vector2(40.5, 20.5))
	w.give_order(defender, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	# an enemy squad approaches B and is spotted by nobody: no contact -> no defend order
	var enemy := w.create_squad(B, "Bx", [3, 3, 3, 3], Vector2(52.5, 20.5))
	w.give_order(enemy, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	# a RED spotter near the flag reports the contact (Comms 3 -> 3 s)
	var spotter := w.create_squad(R, "Rs", [3, 3, 3, 3], Vector2(48.5, 24.5))
	for i in range(1, 6):
		spotter.members[i].state = Balance.MemberState.DEAD
	spotter.refresh_leader()
	spotter.leader.pos = Vector2(58.5, 28.5)   # inside spot range, outside the 6-cell defend radius
	w.give_order(spotter, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	run_seconds(w, 3.5)
	var contacts := w.fog.revealed_contacts(R, w.time)
	check(contacts.size() > 0, "RED has a contact on the BLUE squad")
	ai.tick(w)
	check_eq(defender.pending.get("type", -1), Balance.Order.DEFEND, "nearest free squad sent to DEFEND B")
	check_eq(defender.pending.get("flag"), b, "...B specifically")
	# flag values: enemy-owned with many defenders is worth less than a neutral one
	check_near(ai._flag_value(w.flag_by_name("A"), contacts), Balance.AI_FLAG_VALUE_NEUTRAL, 0.001, "neutral flag value 3")
	var a := w.flag_by_name("A")
	a.owner = B
	check_near(ai._flag_value(a, []), Balance.AI_FLAG_VALUE_WEAK_ENEMY, 0.001, "enemy flag with no visible defenders: 4")
	check_near(ai._flag_value(b, contacts), 0.0, 0.001, "own flag: 0")


func test_artillery_rule_needs_cluster_and_safety() -> void:
	var w := _blank()
	var ai := CommanderAI.new(R, 0.0)
	var enemy := w.create_squad(B, "Bx", [3, 3, 3, 3], Vector2(40.5, 20.5))
	w.give_order(enemy, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	# put RED eyes on them from 10 cells (Comms 3 -> 3 s report delay)
	var spotter := w.create_squad(R, "Rs", [3, 3, 3, 3], Vector2(50.5, 20.5))
	w.give_order(spotter, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	run_seconds(w, 3.5)
	var contacts := w.fog.revealed_contacts(R, w.time)
	check(contacts.size() >= 3, "cluster of contacts (%d)" % contacts.size())
	ai._rule_artillery(w, contacts)
	check(not w.assets.is_ready(R, "ARTILLERY"), "artillery fired on the cluster")
	check_eq(w.assets.pending(R).size(), 1, "one strike pending")
	var target: Vector2i = w.assets.pending(R)[0]["cell"]
	check(Grid.centre_of(target).distance_to(Vector2(40.5, 20.5)) <= 4.0, "aimed at the cluster")
	# unsafe: own units within 5 cells of the cluster -> no fire
	var w2 := _blank()
	var ai2 := CommanderAI.new(R, 0.0)
	var e2 := w2.create_squad(B, "Bx", [3, 3, 3, 3], Vector2(40.5, 20.5))
	w2.give_order(e2, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	var close := w2.create_squad(R, "Rc", [3, 3, 3, 3], Vector2(44.5, 20.5))
	w2.give_order(close, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	run_seconds(w2, 3.5)
	ai2._rule_artillery(w2, w2.fog.revealed_contacts(R, w2.time))
	check(w2.assets.is_ready(R, "ARTILLERY"), "no strike when own units are within 5 cells")


func test_mount_rule_for_long_trips() -> void:
	var w := _blank()
	var ai := CommanderAI.new(R, 0.0)
	var s := w.create_squad(R, "R0", [3, 3, 3, 3], Vector2(70.5, 20.5))
	var apc := w.spawn_vehicle("APC", R, Vector2(72.5, 22.5))
	ai.tick(w)
	check_eq(s.pending.get("type", -1), Balance.Order.MOUNT, "far target with an idle vehicle nearby: MOUNT first")
	check_eq(s.pending.get("vehicle"), apc, "the APC")
	check_eq(s.pending["then"]["type"], Balance.Order.ATTACK, "movement order queued behind the mount")
	for i in 200:
		w.step(Balance.TICK)
		if s.is_mounted() and s.order_type() == Balance.Order.ATTACK:
			break
	check(s.is_mounted(), "squad mounted")
	check_eq(s.order_type(), Balance.Order.ATTACK, "attack order applied once aboard")
	var start_x := apc.pos.x
	run_seconds(w, 3.0)
	check(apc.pos.x < start_x - 5.0, "APC is driving west toward the flag (%.1f -> %.1f)" % [start_x, apc.pos.x])
	# drive until near the flag, then the AI dismounts the squad
	for i in 600:
		w.step(Balance.TICK)
		ai.update(w)
		if not s.is_mounted():
			break
	check(not s.is_mounted(), "AI dismounted near the destination")
	check(apc.pos.distance_to(s.order["flag"].centre_pos()) <= Balance.AI_DISMOUNT_DIST + 1.0, "dismounted within 4 cells of the flag")


func test_red_ai_plays_a_match() -> void:
	var w := World.new()
	w.setup(11)
	w.configure_match(false)
	var red_ai: CommanderAI = w.ais[0]
	# BLUE digs in on A and B and never moves
	var blue := w.squads_of(B)
	w.give_order(blue[0], Balance.Order.DEFEND, Vector2i(-1, -1), w.flag_by_name("A"), null, 0.0)
	w.give_order(blue[1], Balance.Order.DEFEND, Vector2i(-1, -1), w.flag_by_name("B"), null, 0.0)
	w.give_order(blue[2], Balance.Order.DEFEND, Vector2i(-1, -1), w.flag_by_name("A"), null, 0.0)
	w.give_order(blue[3], Balance.Order.DEFEND, Vector2i(-1, -1), w.flag_by_name("B"), null, 0.0)
	var mounted_seen := false
	var assets_used := {}
	var ticks := 0
	while ticks < 4800 and not w.game_over:   # 8 minutes of sim time
		w.step(Balance.TICK)
		ticks += 1
		for e in w.events:
			if e["type"] == "asset_used" and e["team"] == R:
				assets_used[e["name"]] = true
		w.events.clear()
		for s in w.squads_of(R):
			if s.is_mounted():
				mounted_seen = true
	var red_flags := w.flag_count(R)
	print("    RED after 8 min: flags %d, tickets B %d / R %d, assets %s, orders %d, mounts %d" % [red_flags, w.tickets[B], w.tickets[R], str(assets_used.keys()), red_ai.orders_issued, red_ai.mounts_issued])
	check(red_flags >= 2, "RED captured at least two flags (%d)" % red_flags)
	check(mounted_seen, "RED squads used vehicles")
	check(assets_used.has("UAV"), "RED used the UAV")
	check(assets_used.has("VEHICLE_DROP") or assets_used.has("SUPPLY") or assets_used.has("ARTILLERY"), "RED used other assets too (%s)" % str(assets_used.keys()))
	check(w.tickets[B] < Balance.START_TICKETS, "BLUE is losing tickets: the player can lose")
	var defending := false
	for s in w.squads_of(R):
		if s.order_type() == Balance.Order.DEFEND:
			defending = true
	check(defending or red_flags >= 3, "RED defends what it holds or keeps expanding")
