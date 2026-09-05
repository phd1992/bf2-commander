extends Control
## HUD: top bar (tickets, flags, clock, speed), squad cards, asset bar, tooltip.

const CARD_W := 230

var _top_label: Label
var _flag_row: HBoxContainer
var _tooltip: Label
var _mode_label: Label
var _cards: Array = []          # one Dictionary of controls per BLUE squad
var _asset_buttons := {}        # asset name -> Button
var _shop: PanelContainer       # Broken Arrow purchase panel
var _shop_points: Label
var _shop_entry: OptionButton
var _shop_buttons := {}         # vtype -> Button
var _shop_entry_names: Array = []
var _game: Node2D
var _units_layer: Node2D

var selected: Array = []        # squad ids
var pending_mode := ""          # "", "ATTACK", "DEFEND", "ASSET:UAV", ...
var _help_label: Label          # descriptions column
var _help_keys: Label           # keys column
var _help_title: Label
var _drag_start := Vector2(-1, -1)   # screen px of a left press on the map, or (-1,-1)
var _drag_start_world := Vector2.ZERO
var _dragging := false
const DRAG_THRESHOLD_PX := 6.0
const KEY_COL := 12


func _ready() -> void:
	_game = get_parent().get_parent()
	_units_layer = _game.get_node_or_null("UnitsLayer")
	_build_top_bar()
	_build_squad_panel()
	_build_asset_bar()
	_build_tooltip()
	_build_help_panel()
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
		var buy := Button.new()
		buy.visible = false
		buy.text = "Buy squad (%d)" % int(Balance.BA_COST_SQUAD)
		buy.pressed.connect(_on_buy_squad.bind(i))
		v.add_child(buy)
		card.gui_input.connect(_on_card_input.bind(i))
		box.add_child(card)
		_cards.append({ "panel": card, "title": title, "dots": dots, "hp": hp, "xp": xp, "order": order, "spawn": spawn, "spawn_flags": [], "buy": buy })
	_build_shop(box)


## Broken Arrow purchase panel: points, entry point, vehicle buttons.
func _build_shop(box: VBoxContainer) -> void:
	_shop = PanelContainer.new()
	_shop.visible = false
	var v := VBoxContainer.new()
	_shop.add_child(v)
	_shop_points = Label.new()
	_shop_points.add_theme_font_size_override("font_size", 14)
	v.add_child(_shop_points)
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "Entry"
	row.add_child(l)
	_shop_entry = OptionButton.new()
	for n in Balance.BA_ENTRY_NAMES:
		_shop_entry.add_item(n)
	_shop_entry.select(1)
	_shop_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_shop_entry)
	v.add_child(row)
	for vtype in ["JEEP", "APC", "TANK"]:
		var b := Button.new()
		b.text = "%s (%d)" % [vtype.capitalize(), int(Balance.BA_COST_VEHICLE[vtype])]
		b.pressed.connect(_on_buy_vehicle.bind(vtype))
		v.add_child(b)
		_shop_buttons[vtype] = b
	box.add_child(_shop)


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


## Bottom-right panel listing what the mouse and keys do right now.
func _build_help_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_title = Label.new()
	_help_title.add_theme_font_size_override("font_size", 13)
	_help_title.modulate = Color(1, 0.9, 0.4)
	v.add_child(_help_title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_keys = Label.new()
	_help_keys.add_theme_font_size_override("font_size", 13)
	_help_keys.modulate = Color(1, 0.95, 0.7)
	_help_keys.custom_minimum_size = Vector2(110, 0)
	cols.add_child(_help_keys)
	_help_label = Label.new()
	_help_label.add_theme_font_size_override("font_size", 13)
	_help_label.custom_minimum_size = Vector2(300, 0)
	cols.add_child(_help_label)
	v.add_child(cols)
	panel.add_child(v)
	add_child(panel)


## A help line is "key|what"; the two halves go to the two columns.
static func _line(key: String, what: String) -> String:
	return key + "|" + what


## Context-sensitive help lines, most specific first.
func _help_lines(w: World) -> Array:
	var lines: Array = []
	var sel := _selected_squads()
	if pending_mode.begins_with("ASSET:"):
		_help_title.text = "Aiming %s" % pending_mode.trim_prefix("ASSET:").capitalize()
		lines.append(_line("Left-click", "Place it here (circle = radius)"))
		lines.append(_line("Esc", "Cancel"))
		return lines
	if pending_mode == "ATTACK":
		_help_title.text = "Attack-move"
		lines.append(_line("Left-click", "Attack-move the selected squads here"))
		lines.append(_line("Esc", "Cancel"))
		return lines
	if pending_mode == "DEFEND":
		_help_title.text = "Defend"
		lines.append(_line("Left-click", "Defend the flag nearest the click"))
		lines.append(_line("Esc", "Cancel"))
		return lines
	# hover-specific line
	var hover = _unit_at(w, _game.mouse_pos_cells())
	var hover_flag := _flag_containing(w, _game.mouse_cell())
	if sel.is_empty():
		_help_title.text = "No squad selected"
		if hover != null and not hover.is_vehicle() and hover.team == Sim.player_team:
			lines.append(_line("Left-click", "Select %s" % hover.squad.name))
		lines.append(_line("Left-click", "Select the squad of a soldier"))
		lines.append(_line("Drag", "Box-select squads (Shift adds)"))
		lines.append(_line("1-4 / cards", "Select squad (Shift adds)"))
		lines.append(_line("Q W E R", "UAV / Artillery / Supply / Vehicle drop"))
		lines.append(_line("Space", "Pause      -/= speed"))
		lines.append(_line("WASD, wheel", "Pan, zoom"))
		return lines
	var names: Array = []
	var mounted := false
	var wiped := true
	for s in sel:
		names.append(s.name)
		if s.is_mounted():
			mounted = true
		if not s.is_wiped():
			wiped = false
	_help_title.text = "Selected: " + ", ".join(names)
	if wiped:
		lines.append(_line("Card", "Choose spawn point / buy the squad back"))
		return lines
	if hover != null and hover.is_vehicle() and hover.team == Sim.player_team and hover.is_idle():
		lines.append(_line("Right-click", "Board %s (%d seats)" % [hover.vtype, hover.seats]))
	elif hover_flag != null and not hover_flag.is_hq:
		if hover_flag.owner == Sim.player_team:
			lines.append(_line("Right-click", "Defend flag %s" % hover_flag.name))
		else:
			lines.append(_line("Right-click", "Attack flag %s" % hover_flag.name))
	if mounted:
		lines.append(_line("Right-click", "Drive there"))
		lines.append(_line("Right-click flag", "Attack/defend: jeep & APC drop troops, driver+gunner stay"))
		lines.append(_line("", "Tank crews stay aboard"))
		lines.append(_line("X", "Everyone out"))
	else:
		lines.append(_line("Right-click", "Move here"))
		lines.append(_line("Right-click flag", "Attack it (enemy/neutral) or defend it (yours)"))
		lines.append(_line("Right-click", "...own empty vehicle: board it"))
		lines.append(_line("M", "Board the nearest empty vehicle"))
		lines.append(_line("A + click", "Attack-move    D + click: defend flag"))
		lines.append(_line("H", "Hold and take cover"))
	lines.append(_line("Shift+click", "Add a squad to the selection"))
	lines.append(_line("Q W E R", "Assets    Space pause    -/= speed"))
	return lines


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
	_refresh_shop(w)
	_refresh_assets(w)
	_update_tooltip(w)
	_mode_label.text = "" if pending_mode == "" else "%s: click the map (ESC cancels)" % pending_mode
	if Sim.ai_vs_ai:
		_help_title.text = "Watching AI vs AI"
		_help_keys.text = "Space\n-/=\nWASD, wheel"
		_help_label.text = "Pause\nSpeed\nPan, zoom"
	else:
		var keys: Array = []
		var whats: Array = []
		for l in _help_lines(w):
			var parts: PackedStringArray = l.split("|", true, 1)
			keys.append(parts[0])
			whats.append(parts[1] if parts.size() > 1 else "")
		_help_keys.text = "\n".join(keys)
		_help_label.text = "\n".join(whats)
	if _units_layer != null:
		_units_layer.selected_ids = selected
		_units_layer.ghost_asset = pending_mode.trim_prefix("ASSET:") if pending_mode.begins_with("ASSET:") else ""
		_units_layer.ghost_cell = _game.mouse_cell()
		_units_layer.hover_unit = _unit_at(w, _game.mouse_pos_cells()) if not Sim.ai_vs_ai else null
		if _dragging:
			var now_world: Vector2 = _game.mouse_pos_cells() * float(Balance.CELL_PX)
			_units_layer.drag_rect = Rect2(_drag_start_world, now_world - _drag_start_world)
		else:
			_units_layer.drag_rect = Rect2()


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
		c["title"].text = "%d  %s   %s" % [i + 1, s.name, s.hidden_stats_text() if w.hidden_stats else s.stats_text()]
		var dots := ""
		for m in s.members:
			# ASCII on purpose: the web build's fallback font has no dot glyphs
			dots += "O" if m.is_alive() else "x"
			dots += " "
		var veh_text := ""
		if s.vehicle != null and s.vehicle.alive:
			var own := w.crew_of(s, s.vehicle)
			if s.is_mounted():
				veh_text = "  [%s %d/%d]" % [s.vehicle.vtype, s.vehicle.occupants.size(), s.vehicle.seats]
			elif own > 0:
				veh_text = "  [crew of %d in %s]" % [own, s.vehicle.vtype]
		c["dots"].text = dots + veh_text
		c["hp"].value = s.avg_hp()
		var next_thr: int = Balance.XP_THRESHOLDS[mini(s.xp_level, Balance.XP_THRESHOLDS.size() - 1)]
		c["xp"].max_value = next_thr
		c["xp"].value = mini(s.xp, next_thr)
		var order_text := s.order_text()
		if not s.pending.is_empty():
			order_text = "%s in %d s" % [_pending_text(s), int(ceil(s.pending["at"] - w.time))]
		c["order"].text = order_text + ("   kills %d" % s.kills)
		var sel := s.id in selected
		c["panel"].modulate = Color(1, 1, 1) if sel else Color(0.75, 0.75, 0.8)
		c["panel"].self_modulate = Color(1.3, 1.3, 0.9) if sel else Color(1, 1, 1)
		_refresh_spawn_selector(w, s, c)


static func _order_name(o: Dictionary) -> String:
	match o.get("type", Balance.Order.NONE):
		Balance.Order.MOVE: return "MOVE"
		Balance.Order.ATTACK: return "ATTACK %s" % o["flag"].name
		Balance.Order.DEFEND: return "DEFEND %s" % o["flag"].name
		Balance.Order.MOUNT: return "BOARD %s" % (o["vehicle"].vtype if o.get("vehicle") != null else "")
		Balance.Order.HOLD: return "HOLD"
		Balance.Order.DISMOUNT: return "DISMOUNT"
	return ""


func _pending_text(s: Squad) -> String:
	return _order_name(s.pending)


func _refresh_spawn_selector(w: World, s: Squad, c: Dictionary) -> void:
	var opt: OptionButton = c["spawn"]
	var buy: Button = c["buy"]
	if w.spawn_policy is SpawnBrokenArrow:
		var ba: SpawnBrokenArrow = w.spawn_policy
		opt.visible = false
		buy.visible = s.is_wiped() and not Sim.ai_vs_ai
		buy.disabled = not ba.can_afford(s.team, Balance.BA_COST_SQUAD)
		return
	buy.visible = false
	if not s.is_wiped() or w.spawn_policy == null:
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


func _refresh_shop(w: World) -> void:
	if not (w.spawn_policy is SpawnBrokenArrow) or Sim.ai_vs_ai:
		_shop.visible = false
		return
	var ba: SpawnBrokenArrow = w.spawn_policy
	_shop.visible = true
	_shop_points.text = "Reinforcements: %d pts  (+%.0f/min)" % [int(ba.points[Sim.player_team]), ba.income_per_min(Sim.player_team)]
	var names: Array = ba.entry_names(Sim.player_team)
	if names != _shop_entry_names:
		var keep := _shop_entry.selected
		_shop_entry.clear()
		for n in names:
			_shop_entry.add_item(n)
		_shop_entry.select(clampi(keep, 0, maxi(names.size() - 1, 0)))
		_shop_entry_names = names
	for vtype in _shop_buttons.keys():
		_shop_buttons[vtype].disabled = not ba.can_afford(Sim.player_team, Balance.BA_COST_VEHICLE[vtype])


func _on_buy_squad(card_index: int) -> void:
	var w: World = Sim.world
	if not (w.spawn_policy is SpawnBrokenArrow):
		return
	var blue := w.squads_of(Sim.player_team)
	if card_index < blue.size():
		w.spawn_policy.buy_squad(blue[card_index], _shop_entry.selected)


func _on_buy_vehicle(vtype: String) -> void:
	var w: World = Sim.world
	if w.spawn_policy is SpawnBrokenArrow:
		w.spawn_policy.buy_vehicle(Sim.player_team, vtype, _shop_entry.selected)


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
			text += "\n%s %s  HP %d  crew %d/%d" % [Balance.TEAM_NAMES[unit.team], unit.vtype, int(unit.hp), unit.occupants.size(), unit.seats]
			if unit.team == Sim.player_team and unit.is_idle() and not Sim.ai_vs_ai:
				text += "\nRight-click with a squad selected: board"
		else:
			text += "\n%s %s  HP %d" % [unit.squad.name, unit.kit_name(), int(unit.hp)]
			if unit.team == Sim.player_team and not Sim.ai_vs_ai:
				text += "\nLeft-click: select %s" % unit.squad.name
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
	if w.fog != null:
		return w.fog.is_visible_to(Sim.player_team, u)
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


## All mouse events on the map arrive here (press, release, motion).
func handle_mouse(event: InputEvent, cell: Vector2i, pos: Vector2) -> void:
	var w: World = Sim.world
	if Sim.ai_vs_ai:
		return
	if event is InputEventMouseMotion:
		if _drag_start.x >= 0 and not _dragging and event.position.distance_to(_drag_start) > DRAG_THRESHOLD_PX:
			_dragging = true
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not w.grid.in_bounds(cell):
				return
			if pending_mode != "":
				_apply_pending_click(w, cell)
				return
			_drag_start = event.position
			_drag_start_world = pos * float(Balance.CELL_PX)
			_dragging = false
		else:
			if _drag_start.x < 0:
				return
			if _dragging:
				_select_in_box(w, _drag_start_world, pos * float(Balance.CELL_PX), event.shift_pressed)
			else:
				_left_click(w, cell, pos, event.shift_pressed)
			_drag_start = Vector2(-1, -1)
			_dragging = false
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not w.grid.in_bounds(cell):
			return
		pending_mode = ""
		_order_at(cell, pos, false)


func _apply_pending_click(w: World, cell: Vector2i) -> void:
	if pending_mode.begins_with("ASSET:"):
		var name := pending_mode.trim_prefix("ASSET:")
		if w.assets.use(Sim.player_team, name, cell):
			_ping(Grid.centre_of(cell), name.capitalize())
	elif pending_mode == "ATTACK":
		_order_at(cell, Grid.centre_of(cell), true)
	elif pending_mode == "DEFEND":
		var f := _nearest_flag(w, cell, false)
		if f != null:
			for s in _selected_squads():
				w.give_order(s, Balance.Order.DEFEND, cell, f)
			_ping(f.centre_pos(), "DEFEND %s" % f.name)
	pending_mode = ""


## Plain left click: select the squad of a soldier / crewed vehicle, or board
## an own empty vehicle with the selection.
func _left_click(w: World, cell: Vector2i, pos: Vector2, add: bool) -> void:
	var unit = _unit_at(w, pos)
	if unit == null:
		if not add:
			selected = []
		return
	if unit.team != Sim.player_team:
		return
	if unit.is_vehicle():
		if unit.is_idle():
			_board(w, unit)
		elif unit.owner_squad != null:
			_select_squad(unit.owner_squad, add)
		return
	_select_squad(unit.squad, add)


func _select_squad(s: Squad, add: bool) -> void:
	if add:
		if s.id in selected:
			selected.erase(s.id)
		else:
			selected.append(s.id)
	else:
		selected = [s.id]


func _select_in_box(w: World, a: Vector2, b: Vector2, add: bool) -> void:
	var r := Rect2(a, b - a).abs()
	var hit: Array = []
	for s in w.squads_of(Sim.player_team):
		for m in s.members:
			if m.is_alive() and r.has_point(m.pos * float(Balance.CELL_PX)):
				hit.append(s.id)
				break
	if not add:
		selected = []
	for id in hit:
		if id not in selected:
			selected.append(id)


## Sends as many selected squads as the free seats can take (a jeep or a
## tank takes one squad, an APC one full squad).
func _board(w: World, v: Vehicle) -> void:
	var capacity := v.free_seats()
	var names: Array = []
	for s in _selected_squads():
		if s.is_wiped() or capacity <= 0:
			continue
		w.give_order(s, Balance.Order.MOUNT, v.cell(), null, v)
		capacity -= s.alive_count()
		names.append(s.name)
	if not names.is_empty():
		_ping(v.pos, "BOARD %s: %s" % [v.vtype, ", ".join(names)])


## Visual confirmation of an order at its target.
func _ping(pos: Vector2, text: String) -> void:
	Sim.world.events.append({ "type": "order_ping", "pos": pos, "text": text })


## Right-click / attack-move: board an own empty vehicle, ATTACK a non-own
## flag, DEFEND an own flag, or MOVE to a cell.
func _order_at(cell: Vector2i, pos: Vector2, attack_move: bool) -> void:
	var w: World = Sim.world
	var sel := _selected_squads()
	if sel.is_empty():
		return
	if not attack_move:
		var unit = _unit_at(w, pos)
		if unit != null and unit.is_vehicle() and unit.team == Sim.player_team and unit.is_idle():
			_board(w, unit)
			return
	var f := _flag_containing(w, cell)
	var text := "MOVE"
	for s in sel:
		if s.is_wiped():
			continue
		if f != null and not f.is_hq:
			if f.owner == s.team:
				w.give_order(s, Balance.Order.DEFEND, cell, f)
				text = "DEFEND %s" % f.name
			else:
				w.give_order(s, Balance.Order.ATTACK, cell, f)
				text = "ATTACK %s" % f.name
		else:
			w.give_order(s, Balance.Order.MOVE, cell)
			text = "ATTACK-MOVE" if attack_move else "MOVE"
	_ping(f.centre_pos() if f != null and not f.is_hq else Grid.centre_of(cell), text)


func _order_all(type: int) -> void:
	for s in _selected_squads():
		if s.is_wiped() or s.leader == null:
			continue
		Sim.world.give_order(s, type)
		_ping(s.leader.pos, "HOLD" if type == Balance.Order.HOLD else "DISMOUNT")


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
			_ping(best.pos, "BOARD %s" % best.vtype)


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
