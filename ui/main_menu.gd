extends Control
## Main menu: Play (seed field), Watch AI vs AI, Quit.

signal play_requested(seed: int, ai_vs_ai: bool, mode: String, red_rolled: bool)

var _seed_edit: LineEdit
var _mode: OptionButton
var _red_rolled: CheckBox


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(320, 0)
	box.position = Vector2(-160, -140)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "COMMANDER"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Command BLUE. Capture flags. Bleed RED."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(sub)

	var seed_row := HBoxContainer.new()
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(randi() % 100000)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.placeholder_text = "random"
	seed_row.add_child(_seed_edit)
	box.add_child(seed_row)

	var mode_row := HBoxContainer.new()
	var mode_label := Label.new()
	mode_label.text = "Mode"
	mode_row.add_child(mode_label)
	_mode = OptionButton.new()
	_mode.add_item("Conquest (respawn at flags)")
	_mode.add_item("Broken Arrow (buy reinforcements)")
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(_mode)
	box.add_child(mode_row)

	_red_rolled = CheckBox.new()
	_red_rolled.text = "RED squads roll stats too (default: uniform 3s)"
	box.add_child(_red_rolled)

	var play := Button.new()
	play.text = "Play"
	play.pressed.connect(func(): play_requested.emit(_seed(), false, _mode_name(), _red_rolled.button_pressed))
	box.add_child(play)

	var watch := Button.new()
	watch.text = "Watch AI vs AI"
	watch.pressed.connect(func(): play_requested.emit(_seed(), true, _mode_name(), _red_rolled.button_pressed))
	box.add_child(watch)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)

	var help := Label.new()
	help.text = "WASD pan  |  wheel zoom  |  1-4 squads  |  RMB order  |  Q/W/E/R assets  |  SPACE pause  |  -/= speed"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(0.55, 0.55, 0.55)
	box.add_child(help)


func _mode_name() -> String:
	return "BROKEN_ARROW" if _mode.selected == 1 else "CONQUEST"


func _seed() -> int:
	var t := _seed_edit.text.strip_edges()
	if t.is_valid_int():
		return int(t)
	return randi() % 100000
