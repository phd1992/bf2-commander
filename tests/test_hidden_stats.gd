extends TestCase
## Phase 2.3: squad stats start hidden and are revealed by observed events.

const T := Balance.Terrain
const B := Balance.Team.BLUE
const R := Balance.Team.RED


func test_stats_reveal_on_events() -> void:
	var w := World.new()
	w.setup_blank(1, 60, 40, T.OPEN)
	w.hidden_stats = true
	var s := w.create_squad(B, "S", [4, 2, 5, 1], Vector2(10.5, 20.5))
	check_eq(s.hidden_stats_text(), "S? D? A? C?", "everything hidden at the start")
	check_eq(s.stats_text(), "S4 D2 A5 C1", "the real stats still exist")
	# Discipline: revealed after two executed orders
	w.give_order(s, Balance.Order.MOVE, Vector2i(12, 20), null, null, 0.0)
	check(not s.discipline_revealed(), "one order is not enough")
	w.give_order(s, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	check(s.discipline_revealed(), "two executed orders reveal Discipline")
	check_eq(s.hidden_stats_text(), "S? D2 A? C?", "only Discipline shown")
	# Comms: three contact reports
	var e1 := w.create_squad(R, "E1", [3, 3, 3, 3], Vector2(20.5, 20.5))
	w.give_order(e1, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)
	for m in e1.members:
		m.kit = Balance.Kit.RIFLE
	run_ticks(w, 1)
	check(s.contacts_reported >= 3, "six enemies in view create at least three reports (%d)" % s.contacts_reported)
	check(s.comms_revealed(), "Comms revealed")
	# Skill: twenty shots fired by the squad
	run_seconds(w, 8.0)
	check(s.shots_fired >= Balance.HIDDEN_SHOTS_FOR_SKILL, "a firefight produced %d shots" % s.shots_fired)
	check(s.skill_revealed(), "Skill revealed after a firefight")
	# Aggression: reaching an objective while in combat. Move the enemy just
	# outside rifle range (12) but inside spot range (14) so the squad stays
	# in contact without anyone being pinned in cover.
	check(not s.aggression_revealed(), "Aggression still hidden")
	for m in e1.members:
		m.pos = Vector2(22.5, 20.5)
	w.give_order(e1, Balance.Order.HOLD, Vector2i(-1, -1), null, null, 0.0)   # forget the old cover cells
	run_seconds(w, Balance.COVER_RESUME_BASE)
	check(s.in_combat, "still in combat with the enemy 13 cells away")
	w.give_order(s, Balance.Order.MOVE, s.leader.cell() + Vector2i(-2, 0), null, null, 0.0)
	run_seconds(w, 6.0)
	check(s.aggression_revealed(), "reaching an objective in combat reveals Aggression")
	check_eq(s.hidden_stats_text(), s.stats_text(), "everything revealed now")


func test_hidden_stats_only_affects_display() -> void:
	var w := World.new()
	w.setup(2)
	w.hidden_stats = true
	var s := w.squads_of(B)[0]
	check_near(s.accuracy_mult(), Balance.accuracy_mult(s.skill), 0.001, "hidden stats still drive the simulation")
	check(s.hidden_stats_text().contains("?"), "display masks unknown values")
