extends Control
## HUD: top bar (tickets, flags, clock, speed), tooltip. Squad cards and the
## asset bar are added in later milestones.

var _top_label: Label
var _tooltip: Label
var _game: Node2D


func _ready() -> void:
	_game = get_parent().get_parent()
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_label = Label.new()
	_top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_top_label)
	add_child(top)

	_tooltip = Label.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_color_override("font_color", Color(1, 1, 1))
	_tooltip.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	_tooltip.add_theme_constant_override("shadow_offset_x", 1)
	_tooltip.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_tooltip)


func _process(_delta: float) -> void:
	var w: World = Sim.world
	if w == null:
		return
	var t := int(w.time)
	var speed := "PAUSED" if Sim.paused else "%dx" % Sim.time_scale
	_top_label.text = "%d:%02d    %s    seed %d" % [t / 60, t % 60, speed, w.seed]
	_update_tooltip(w)


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
	var b := g.get_building(cell)
	if b >= 0:
		text += "  building %d" % b
	_tooltip.text = text
	_tooltip.position = get_viewport().get_mouse_position() + Vector2(14, 14)


func handle_key(_event: InputEventKey) -> void:
	pass


func handle_click(_event: InputEventMouseButton, _cell: Vector2i, _pos: Vector2) -> void:
	pass
