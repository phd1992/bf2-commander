extends Node2D
## Draws flags, HQs, vehicles, members, contacts and asset markers every frame.

const PX := float(Balance.CELL_PX)
const MEMBER_RADIUS := 5.0
const SELECT_COLOR := Color(1, 1, 1, 0.9)
const ORDER_COLOR := Color(1, 0.9, 0.3, 0.8)

var selected_ids: Array = []   # squad ids highlighted (set by the HUD)
var player_team: int = Balance.Team.BLUE
## Asset being aimed ("" = none) and the cell under the mouse, set by the HUD.
var ghost_asset := ""
var ghost_cell := Vector2i(-1, -1)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var w: World = Sim.world
	if w == null:
		return
	_draw_flags(w)
	_draw_pads(w)
	_draw_assets(w)
	_draw_vehicles(w)
	_draw_members(w)
	_draw_contacts(w)
	_draw_orders(w)
	_draw_ghost(w)


func _draw_ghost(w: World) -> void:
	if ghost_asset == "" or not w.grid.in_bounds(ghost_cell):
		return
	var c := Grid.centre_of(ghost_cell) * PX
	var r: float = maxf(Balance.ASSETS[ghost_asset]["radius"], 1.0) * PX
	var col := Color(1, 0.9, 0.3, 0.9)
	_draw_dashed_circle(c, r, col)
	draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), col, 1.5)
	draw_line(c + Vector2(0, -8), c + Vector2(0, 8), col, 1.5)


static func team_color(team: int) -> Color:
	return Balance.COLOR_BLUE if team == Balance.Team.BLUE else (Balance.COLOR_RED if team == Balance.Team.RED else Color(0.8, 0.8, 0.8))


func _draw_flags(w: World) -> void:
	var font := ThemeDB.fallback_font
	for f in w.flags:
		var c: Vector2 = f.centre_pos() * PX
		var r: float = f.radius() * PX
		var col := team_color(f.owner)
		if f.is_hq:
			draw_rect(Rect2(c - Vector2(r, r), Vector2(2 * r, 2 * r)), Color(col, 0.12))
			draw_rect(Rect2(c - Vector2(r, r), Vector2(2 * r, 2 * r)), col, false, 2.0)
			draw_string(font, c + Vector2(-14, 6), "HQ", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, col)
		else:
			draw_circle(c, r, Color(col, 0.08))
			draw_arc(c, r, 0, TAU, 48, Color(col, 0.7), 2.0)
			if absf(f.progress) > 0.001:
				var pcol := Balance.COLOR_BLUE if f.progress > 0 else Balance.COLOR_RED
				draw_arc(c, r + 4, -PI / 2, -PI / 2 + TAU * absf(f.progress), 32, pcol, 4.0)
			draw_string(font, c + Vector2(-7, 8), f.name, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(1, 1, 1))


func _draw_pads(w: World) -> void:
	for p in w.pads:
		var c: Vector2 = Grid.centre_of(p["cell"]) * PX
		draw_rect(Rect2(c - Vector2(10, 6), Vector2(20, 12)), Color(1, 1, 1, 0.25), false, 1.0)


func _draw_assets(w: World) -> void:
	if not ("assets" in w) or w.assets == null:
		return
	for team in [Balance.Team.BLUE, Balance.Team.RED]:
		if team != player_team and not Sim.ai_vs_ai:
			continue
		var col := team_color(team)
		for u in w.assets.active_uavs(team):
			var c: Vector2 = Grid.centre_of(u["cell"]) * PX
			_draw_dashed_circle(c, Balance.ASSETS["UAV"]["radius"] * PX, Color(col, 0.8))
		for cr in w.assets.active_crates(team):
			var c: Vector2 = Grid.centre_of(cr["cell"]) * PX
			draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), Color(0.3, 0.9, 0.3))
			draw_arc(c, Balance.ASSETS["SUPPLY"]["radius"] * PX, 0, TAU, 32, Color(0.3, 0.9, 0.3, 0.5), 1.5)
		for a in w.assets.pending(team):
			var c: Vector2 = Grid.centre_of(a["cell"]) * PX
			var r: float = maxf(Balance.ASSETS[a["name"]]["radius"], 1.0) * PX
			_draw_dashed_circle(c, r, Color(1, 1, 1, 0.4))


func _draw_dashed_circle(c: Vector2, r: float, col: Color) -> void:
	var segs := 36
	for i in segs:
		if i % 2 == 0:
			draw_arc(c, r, TAU * i / segs, TAU * (i + 1) / segs, 3, col, 2.0)


func _draw_vehicles(w: World) -> void:
	var visible := _visible_set(w)
	for v in w.vehicles:
		if not v.alive:
			continue
		if v.team != player_team and not Sim.ai_vs_ai and not visible.has(v):
			continue
		var c := v.pos * PX
		var size := v.size_px()
		var col := team_color(v.team)
		var ang := v.heading.angle()
		draw_set_transform(c, ang, Vector2.ONE)
		draw_rect(Rect2(-size * 0.5, size), col)
		draw_rect(Rect2(-size * 0.5, size), Color(0, 0, 0, 0.6), false, 1.0)
		draw_line(Vector2(0, 0), Vector2(size.x * 0.5 + 6, 0), Color(1, 1, 1), 2.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var hp_frac := v.hp / v.max_hp
		draw_rect(Rect2(c + Vector2(-12, -size.y * 0.5 - 8), Vector2(24 * hp_frac, 3)), Color(0.3, 1, 0.3))
		draw_string(ThemeDB.fallback_font, c + Vector2(-12, size.y * 0.5 + 14), "%s %d" % [v.vtype, v.occupants.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))


func _visible_set(w: World) -> Dictionary:
	if w.fog != null:
		return w.fog.vision.get(player_team, {})
	return {}


func _draw_members(w: World) -> void:
	var visible := _visible_set(w)
	for m in w.members:
		if m.state == Balance.MemberState.IN_VEHICLE:
			continue
		var enemy := m.team != player_team and not Sim.ai_vs_ai
		if m.state == Balance.MemberState.DEAD:
			var age: float = w.time - m.death_time
			if age > Balance.DEAD_DRAW_S or (enemy and not visible.has(m)):
				continue
			var fade := 1.0 - age / Balance.DEAD_DRAW_S
			draw_circle(m.pos * PX, MEMBER_RADIUS, Color(team_color(m.team), 0.5 * fade))
			continue
		if enemy and not visible.has(m):
			continue
		var c := m.pos * PX
		var col := team_color(m.team)
		var selected := m.squad != null and m.squad.id in selected_ids
		if selected:
			draw_circle(c, MEMBER_RADIUS + 3, Color(SELECT_COLOR, 0.35))
		draw_circle(c, MEMBER_RADIUS, col)
		if m.is_leader():
			draw_arc(c, MEMBER_RADIUS + 1.5, 0, TAU, 16, Color(1, 1, 1), 1.5)
		if m.kit == Balance.Kit.AT:
			draw_circle(c, 2.0, Color(0.05, 0.05, 0.05))
		if m.hp < Balance.MEMBER_HP:
			draw_rect(Rect2(c + Vector2(-6, -10), Vector2(12 * m.hp / Balance.MEMBER_HP, 2)), Color(0.3, 1, 0.3))


func _draw_contacts(w: World) -> void:
	if not ("fog" in w) or w.fog == null or Sim.ai_vs_ai:
		return
	var visible := _visible_set(w)
	for ct in w.fog.revealed_contacts(player_team, w.time):
		var u = ct["unit"]
		if visible.has(u):
			continue
		var age: float = w.time - ct["last_seen"]
		var alpha := clampf(1.0 - age / maxf(ct["persist_until"] - ct["last_seen"], 0.1), 0.15, 0.8)
		var c: Vector2 = ct["pos"] * PX
		var col := Color(team_color(u.team), alpha)
		if u.is_vehicle():
			draw_rect(Rect2(c - Vector2(10, 6), Vector2(20, 12)), col, false, 2.0)
		else:
			draw_arc(c, MEMBER_RADIUS, 0, TAU, 12, col, 2.0)


func _draw_orders(w: World) -> void:
	for s in w.squads:
		if not (s.id in selected_ids) or s.leader == null:
			continue
		var dest := s.destination()
		if dest.x < 0:
			continue
		var d := Grid.centre_of(dest) * PX
		draw_line(s.leader.pos * PX, d, Color(ORDER_COLOR, 0.35), 1.0)
		draw_arc(d, 8, 0, TAU, 12, ORDER_COLOR, 2.0)
