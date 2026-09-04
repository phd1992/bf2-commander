class_name Combat
extends RefCounted
## Target selection, hit rolls, damage, splash and wall damage (Section 8).


static func update(w: World, _dt: float) -> void:
	for team in [Balance.Team.BLUE, Balance.Team.RED]:
		var visible: Dictionary = w.fog.vision[team]
		if visible.is_empty():
			continue
		for shooter in w.units_of(team):
			_shooter_tick(w, shooter, visible)


static func _shooter_tick(w: World, shooter, visible: Dictionary) -> void:
	var is_veh: bool = shooter.is_vehicle()
	if is_veh and not shooter.can_fire():
		return
	var squad: Squad = shooter.crew_squad() if is_veh else shooter.squad
	if squad == null:
		return
	if squad.contact_since >= 0.0 and w.time < squad.contact_since + squad.reaction_time():
		return
	var range_cap := 1.0e9
	if squad.aggression <= 1 and (squad.arrived or not squad.has_order()):
		range_cap = Balance.LOW_AGGRESSION_ENGAGE_RANGE
	var weapons: Array = shooter.weapon_names if is_veh else shooter.weapons()
	for wname in weapons:
		if w.time + 0.0001 < shooter.next_shot.get(wname, 0.0):
			continue
		# The tank's HMG only ever engages infantry; the cannon handles vehicles.
		var inf_only: bool = is_veh and shooter.vtype == "TANK" and wname == "HMG"
		var target = pick_target(w, shooter, wname, visible, range_cap, inf_only)
		if target == null:
			continue
		resolve_shot(w, shooter, squad, wname, target)
		shooter.next_shot[wname] = w.time + Weapons.interval(wname)
		shooter.last_shot_time = w.time
		if not is_veh:
			break   # a soldier fires one weapon per tick


## Nearest valid target for a weapon, following the preference table.
static func pick_target(w: World, shooter, wname: String, visible: Dictionary, range_cap: float = 1.0e9, inf_only: bool = false):
	var r := minf(Weapons.range_of(wname), range_cap)
	var pref := Weapons.preference(wname, inf_only)
	var s_cell: Vector2i = shooter.cell()
	var s_eye := LOS.eye_height(w.grid, s_cell, shooter.is_vehicle())
	var best_inf = null
	var best_inf_d := 1.0e9
	var best_veh = null
	var best_veh_d := 1.0e9
	for u in visible.keys():
		if not u.is_alive() or u.team == shooter.team:
			continue
		var uv: bool = u.is_vehicle()
		if pref == "INF_ONLY" and uv:
			continue
		if pref == "VEH_ONLY" and not uv:
			continue
		var d: float = shooter.pos.distance_to(u.pos)
		if d > r:
			continue
		if uv and d >= best_veh_d:
			continue
		if not uv and d >= best_inf_d:
			continue
		var u_cell: Vector2i = u.cell()
		if not LOS.has_los(w.grid, s_cell, s_eye, u_cell, LOS.eye_height(w.grid, u_cell, uv)):
			continue
		if uv:
			best_veh = u
			best_veh_d = d
		else:
			best_inf = u
			best_inf_d = d
	match pref:
		"INF_FIRST", "INF_ONLY":
			return best_inf if best_inf != null else best_veh
		"VEH_FIRST", "VEH_ONLY":
			return best_veh if best_veh != null else best_inf
	# ANY: nearest of either
	if best_inf != null and best_veh != null:
		return best_inf if best_inf_d <= best_veh_d else best_veh
	return best_inf if best_inf != null else best_veh


## Hit probability for one shot (Section 8.3), exposed for tests.
static func hit_chance(w: World, shooter, squad: Squad, wname: String, target) -> float:
	var spec := Weapons.spec(wname)
	var d: float = shooter.pos.distance_to(target.pos)
	var tv: bool = target.is_vehicle()
	var cover: float = w.grid.cover(target.cell())
	if tv:
		cover *= Balance.VEHICLE_COVER_MULT
	var cover_eff: float = cover * (1.0 - spec["cover_ignore"])
	var se := w.grid.get_elev(shooter.cell())
	var te := w.grid.get_elev(target.cell())
	var height := Balance.HEIGHT_UP if se > te else (Balance.HEIGHT_DOWN if se < te else 1.0)
	var move := Balance.MOVE_VEH if tv else (Balance.MOVE_INF if target.is_moving else 1.0)
	var acc := squad.accuracy_mult()
	if w.assets != null and w.assets.has_supply_near(shooter.team, shooter.pos):
		acc += Balance.SUPPLY_ACCURACY_BONUS
	return Balance.HIT_BASE * acc * Weapons.range_factor(wname, d) * (1.0 - cover_eff) * height * move


static func resolve_shot(w: World, shooter, squad: Squad, wname: String, target) -> void:
	var spec := Weapons.spec(wname)
	var p := hit_chance(w, shooter, squad, wname, target)
	var hit := w.rng.randf() < p
	target.shot_at_time = w.time
	squad.shots_fired += 1
	w.events.append({ "type": "shot", "from": shooter.pos, "to": target.pos, "hit": hit, "weapon": wname, "team": shooter.team })
	if spec["splash"] > 0.0:
		var impact: Vector2 = target.pos
		if not hit:
			var ang := w.rng.randf() * TAU
			impact += Vector2.from_angle(ang) * sqrt(w.rng.randf()) * Balance.MISS_SCATTER
		# A missed target is not inside its own miss (see DECISIONS.md).
		apply_splash(w, impact, wname, squad, null if hit else target)
	elif hit:
		apply_damage(w, target, wname, squad)


## Full damage to every unit within the splash radius and wall damage to
## WALL cells in it. `exclude` is skipped (the missed primary target).
static func apply_splash(w: World, impact: Vector2, wname: String, squad: Squad, exclude = null) -> void:
	var spec := Weapons.spec(wname)
	var radius: float = spec["splash"]
	w.events.append({ "type": "impact", "pos": impact, "radius": radius, "weapon": wname })
	for u in w.units_of(Balance.Team.BLUE) + w.units_of(Balance.Team.RED):
		if u == exclude:
			continue
		if u.pos.distance_to(impact) <= radius:
			apply_damage(w, u, wname, squad)
	if spec["wall_dmg"] > 0.0:
		for c in w.grid.cells_in_radius(Grid.cell_of(impact), radius):
			if w.grid.get_terrain(c) == Balance.Terrain.WALL:
				w.damage_wall(c, spec["wall_dmg"])


static func apply_damage(w: World, u, wname: String, squad: Squad) -> void:
	var spec := Weapons.spec(wname)
	if not u.is_alive():
		return
	if u.is_vehicle():
		u.hp -= spec["dmg_veh"]
		if u.hp <= 0.0:
			w.destroy_vehicle(u, squad)
	else:
		u.hp -= spec["dmg_inf"]
		if u.hp <= 0.0:
			w.kill_member(u, squad)
