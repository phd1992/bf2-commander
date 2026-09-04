extends Control
## HUD: top bar (tickets, flags, clock, speed), squad cards, asset bar, tooltip.

const CARD_W := 230

var _top_label: Label
var _flag_row: HBoxContainer
var _tooltip: Label
var _mode_label: Label
var _cards: Array = []          # one Dictionary of controls per BLUE squad
var _asset_buttons := {}        # asset name -> Button
var _game: Node2D
var _units_layer: Node2D

var selected: Array = []        # squad ids
var pending_mode := ""          # "", "ATTACK", "DEFEND", "ASSET:UAV", ...


func _ready() -> void:
	_game = get_parent().get_parent()
	_units_layer = _game.get_node_or_null("UnitsLayer")
	_build_top_bar()
	_build_squad_panel()
	_build_asset_bar()
	_build_tooltip()
	_mode_label = Label.new()
	_mode_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mode_label.position = Vector2(-100, 40)
	_mode_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mode_label)


# ---------------------------------------------------------------------------
# Building the widgets
# ---------------------------------------------------------------------------

func _build_top_bar() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_label = Label.new()
	_top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_top_label)
	_flag_row = HBoxContainer.new()
	_flag_row.add_theme_constant_override("separation", 6)
	_flag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_flag_row)
	top.add_child(row)
	add_child(top)


func _build_squad_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.position = Vector2(0, 40)
	panel.custom_minimum_size = Vector2(CARD_W, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	add_child(panel)
	for i in Balance.SQUAD_NAMES.size():
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(CARD_W - 10, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 15)
		v.add_child(title)
		var dots := Label.new()
		dots.add_theme_font_size_override("font_size", 14)
		v.add_child(dots)
		var hp := ProgressBar.new()
		hp.custom_minimum_size = Vector2(0, 10)
		hp.show_percentage = false
		hp.max_value = Balance.MEMBER_HP
		hp.modulate = Color(0.5, 1, 0.5)
		v.add_child(hp)
		var xp := ProgressBar.new()
		xp.custom_minimum_size = Vector2(0, 6)
		xp.show_percentage = false
		xp.modulate = Color(1, 0.85, 0.3)
		v.add_child(xp)
		var order := Label.new()
		order.add_theme_font_size_override("font_size", 12)
		order.modulate = Color(0.85, 0.85, 0.85)
		v.add_child(order)
		var spawn := OptionButton.new()
		spawn.visible = false
		spawn.item_selected.connect(_on_spawn_selected.bind(i))
		v.add_child(spawn)
		card.gui_input.connect(_on_card_input.bind(i))
		box.add_child(card)
		_cards.append({ "panel": card, "title": title, "dots": dots, "hp": hp, "xp": xp, "order": order, "spawn": spawn, "spawn_flags": [] })


func _build_asset_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position = Vector2(-230, -60)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	add_child(bar)
	var keys := { "UAV": "Q", "ARTILLERY": "W", "SUPPLY": "E", "VEHICLE_DROP": "R" }
	for name: String in Balance.ASSET_ORDER:
		var b := Button.new()
		b.custom_minimum_size = Vector2(108, 44)
		b.text = "%s (%s)" % [name.capitalize(), keys[name]]
		b.pressed.connect(_select_asset.bind(name))
		row.add_child(b)
		_asset_buttons[name] = b


func _build_tooltip() -> void:
	_tooltip = Label.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_color_override("font_color", Color(1, 1, 1))
	_tooltip.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	_tooltip.add_theme_constant_override("shadow_offset_x", 1)
	_tooltip.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_tooltip)


# ---------------------------------------------------------------------------
# Per-frame refresh
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var w: World = Sim.world
	if w == null:
		return
	var t := int(w.time)
	var speed := "PAUSED" if Sim.paused else "%dx" % Sim.time_scale
	_top_label.text = "BLUE %d   RED %d      %d:%02d   %s   seed %d" % [
		w.tickets[Balance.Team.BLUE], w.tickets[Balance.Team.RED], t / 60, t % 60, speed, w.seed]
	_refresh_flags(w)
	_refresh_cards(w)
	_refresh_assets(w)
	_update_tooltip(w)
	_mode_label.text = "" if pending_mode == "" else "%s: click the map (ESC cancels)" % pending_mode
	if _units_layer != null:
		_units_layer.selected_ids = selected


func _refresh_flags(w: World) -> void:
	# lazily create one label per capturable flag
	var caps: Array = []
	for f in w.flags:
		if not f.is_hq:
			caps.append(f)
	while _flag_row.get_child_count() < caps.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 16)
		_flag_row.add_child(l)
	for i in caps.size():
		var f: Flag = caps[i]
		var l: Label = _flag_row.get_child(i)
		var pct := int(round(absf(f.progress) * 100))
		l.text = "%s%s" % [f.name, "" if pct == 0 or pct == 100 else " %d%%" % pct]
		l.modulate = Balance.COLOR_BLUE if f.owner == Balance.Team.BLUE else (Balance.COLOR_RED if f.owner == Balance.Team.RED else Color(0.75, 0.75, 0.75))


func _refresh_cards(w: World) -> void:
	var blue := w.squads_of(Sim.player_team)
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		if i >= blue.size():
			c["panel"].visible = false
			continue
		var s: Squad = blue[i]
		c["panel"].visible = true
		c["title"].text = "%d  %s   %s" % [i + 1, s.name, s.stats_text()]
		var dots := ""
		for m in s.members:
			dots += "●" if m.is_alive() else "○"
			dots += " "
		c["dots"].text = dots + ("  [%s]" % s.vehicle.vtype if s.vehicle != null and s.is_mounted() else "")
		c["hp"].value = s.avg_hp()
		var next_thr: int = Balance.XP_THRESHOLDS[mini(s.xp_level, Balance.XP_THRESHOLDS.size() - 1)]
		c["xp"].max_value = next_thr
		c["xp"].value = mini(s.xp, next_thr)
		c["order"].text = s.order_text() + ("   kills %d" % s.kills)
		var sel := s.id in selected
		c["panel"].modulate = Color(1, 1, 1) if sel else Color(0.75, 0.75, 0.8)
		c["panel"].self_modulate = Color(1.3, 1.3, 0.9) if sel else Color(1, 1, 1)
		_refresh_spawn_selector(w, s, c)


func _refresh_spawn_selector(w: World, s: Squad, c: Dictionary) -> void:
	var opt: OptionButton = c["spawn"]
	if not s.is_wiped() or not ("spawn_policy" in w) or w.spawn_policy == null:
		opt.visible = false
		return
	var points: Array = w.spawn_policy.spawn_flags(s.team)
	var names: Array = []
	for f in points:
		names.append(f.name)
	if names != c["spawn_flags"]:
		opt.clear()
		for f in points:
			opt.add_item("Spawn at " + f.name)
		c["spawn_flags"] = names
		for i in points.size():
			if points[i] == s.spawn_pref:
				opt.select(i)
	opt.visible = true


func _refresh_assets(w: World) -> void:
	if not ("assets" in w) or w.assets == null:
		for b in _asset_buttons.values():
			b.disabled = true
		return
	for name: String in _asset_buttons.keys():
		var b: Button = _asset_buttons[name]
		var remaining: float = w.assets.cooldown_remaining(Sim.player_team, name)
		b.disabled = remaining > 0.0
		var label: String = name.capitalize()
		b.text = label if remaining <= 0.0 else "%s %ds" % [label, int(ceil(remaining))]
		b.modulate = Color(1, 0.9, 0.4) if pending_mode == "ASSET:" + name else Color(1, 1, 1)


func _update_tooltip(w: World) -> void:
	var cell: Vector2i = _game.mouse_cell()
	if not w.grid.in_bounds(cell):
		_tooltip.text = ""
		return
	var g := w.grid
	var t := g.get_terrain(cell)
	var text := "%s  elev %d  cover %.2f" % [Balance.terrain_name(t), g.get_elev(cell), g.cover(cell)]
	if t == Balance.Terrain.WALL:
		text += "  wall HP %d" % g.get_wall_hp(cell)
	var unit = _unit_at(w, _game.mouse_pos_cells())
	if unit != null:
		if unit.is_vehicle():
			text += "\n%s %s  HP %d  crew %d" % [Balance.TEAM_NAMES[unit.team], unit.vtype, int(unit.hp), unit.occupants.size()]
		else:
			text += "\n%s %s  HP %d" % [unit.squad.name, unit.kit_name(), int(unit.hp)]
	_tooltip.text = text
	_tooltip.position = get_viewport().get_mouse_position() + Vector2(14, 14)


func _unit_at(w: World, pos: Vector2):
	var best = null
	var best_d := 0.6
	for m in w.members:
		if m.state != Balance.MemberState.ALIVE:
			continue
		if m.team != Sim.player_team and not Sim.ai_vs_ai and not _is_visible(w, m):
			continue
		var d := m.pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = m
	for v in w.vehicles:
		if not v.alive:
			continue
		var d := v.pos.distance_to(pos)
		if d < 0.8 and (best == null or d < best_d):
			best_d = d
			best = v
	return best


func _is_visible(w: World, u) -> bool:
	if "vision" in w and w.vision != null:
		return w.vision.get(Sim.player_team, {}).has(u)
	return true


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_index(index, event.shift_pressed)


func _select_index(index: int, add: bool) -> void:
	var blue := Sim.world.squads_of(Sim.player_team)
	if index >= blue.size():
		return
	var id: int = blue[index].id
	if add:
		if id in selected:
			selected.erase(id)
		else:
			selected.append(id)
	else:
		selected = [id]


func _selected_squads() -> Array:
	var out: Array = []
	for s in Sim.world.squads:
		if s.id in selected:
			out.append(s)
	return out


func handle_key(event: InputEventKey) -> void:
	var shift := event.shift_pressed
	match event.keycode:
		KEY_1: _select_index(0, shift)
		KEY_2: _select_index(1, shift)
		KEY_3: _select_index(2, shift)
		KEY_4: _select_index(3, shift)
		KEY_A: pending_mode = "ATTACK"
		KEY_D: pending_mode = "DEFEND"
		KEY_H: _order_all(Balance.Order.HOLD)
		KEY_X: _order_all(Balance.Order.DISMOUNT)
		KEY_M: _mount_nearest()
		KEY_Q: _select_asset("UAV")
		KEY_W: _select_asset("ARTILLERY")
		KEY_E: _select_asset("SUPPLY")
		KEY_R: _select_asset("VEHICLE_DROP")
		KEY_ESCAPE: pending_mode = ""


func _select_asset(name: String) -> void:
	if Sim.ai_vs_ai:
		return
	pending_mode = "ASSET:" + name


func handle_click(event: InputEventMouseButton, cell: Vector2i, pos: Vector2) -> void:
	var w: World = Sim.world
	if not w.grid.in_bounds(cell) or Sim.ai_vs_ai:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		pending_mode = ""
		_order_at(cell, false)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if pending_mode.begins_with("ASSET:"):
		var name := pending_mode.trim_prefix("ASSET:")
		if "assets" in w and w.assets != null:
			w.assets.use(Sim.player_team, name, cell)
		pending_mode = ""
		return
	if pending_mode == "ATTACK":
		_order_at(cell, true)
		pending_mode = ""
		return
	if pending_mode == "DEFEND":
		var f := _nearest_flag(w, cell, false)
		if f != null:
			for s in _selected_squads():
				w.give_order(s, Balance.Order.DEFEND, cell, f)
		pending_mode = ""
		return
	# plain left click: own idle vehicle -> MOUNT
	var unit = _unit_at(w, pos)
	if unit != null and unit.is_vehicle() and unit.team == Sim.player_team:
		for s in _selected_squads():
			w.give_order(s, Balance.Order.MOUNT, cell, null, unit)


## Right-click / attack-move: MOVE to a cell, ATTACK a non-own flag, DEFEND an own flag.
func _order_at(cell: Vector2i, attack_move: bool) -> void:
	var w: World = Sim.world
	var f := _flag_containing(w, cell)
	for s in _selected_squads():
		if f != null and not f.is_hq:
			if f.owner == s.team:
				w.give_order(s, Balance.Order.DEFEND, cell, f)
			else:
				w.give_order(s, Balance.Order.ATTACK, cell, f)
		else:
			w.give_order(s, Balance.Order.MOVE, cell)


func _order_all(type: int) -> void:
	for s in _selected_squads():
		Sim.world.give_order(s, type)


func _mount_nearest() -> void:
	var w: World = Sim.world
	for s in _selected_squads():
		if s.leader == null:
			continue
		var best: Vehicle = null
		var best_d := Balance.MOUNT_SEARCH_DIST
		for v in w.vehicles:
			if v.alive and v.team == s.team and v.is_idle():
				var d := v.pos.distance_to(s.leader.pos)
				if d < best_d:
					best_d = d
					best = v
		if best != null:
			w.give_order(s, Balance.Order.MOUNT, best.cell(), null, best)


func _flag_containing(w: World, cell: Vector2i) -> Flag:
	for f in w.flags:
		if f.contains(Grid.centre_of(cell)):
			return f
	return null


func _nearest_flag(w: World, cell: Vector2i, include_hq: bool) -> Flag:
	var best: Flag = null
	var best_d := 1.0e9
	for f: Flag in w.flags:
		if f.is_hq and not include_hq:
			continue
		var d: float = f.centre_pos().distance_to(Grid.centre_of(cell))
		if d < best_d:
			best_d = d
			best = f
	return best


func _on_spawn_selected(index: int, card_index: int) -> void:
	var w: World = Sim.world
	var blue := w.squads_of(Sim.player_team)
	if card_index >= blue.size() or not ("spawn_policy" in w) or w.spawn_policy == null:
		return
	var s: Squad = blue[card_index]
	var points: Array = w.spawn_policy.spawn_flags(s.team)
	if index >= 0 and index < points.size():
		w.spawn_policy.set_preferred_spawn(s, points[index].centre)
