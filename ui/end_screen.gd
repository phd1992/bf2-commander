extends Control
## End screen: winner, final tickets, per-squad kills/deaths.

signal play_again
signal menu

var _stats := {}


func setup(stats: Dictionary) -> void:
	_stats = stats


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-260, -220)
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	var winner: int = _stats.get("winner", Balance.Team.NONE)
	if winner == Balance.Team.BLUE:
		title.text = "BLUE WINS"
		title.modulate = Balance.COLOR_BLUE
	elif winner == Balance.Team.RED:
		title.text = "RED WINS"
		title.modulate = Balance.COLOR_RED
	else:
		title.text = "DRAW"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var tickets := Label.new()
	tickets.text = "Final tickets   BLUE %d   -   RED %d      (%s)" % [
		_stats.get("blue_tickets", 0), _stats.get("red_tickets", 0), _stats.get("clock", "")]
	tickets.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tickets)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	for h in ["Squad", "Stats", "Kills", "Deaths"]:
		var l := Label.new()
		l.text = h
		l.modulate = Color(0.7, 0.7, 0.7)
		grid.add_child(l)
	for row in _stats.get("squads", []):
		for v in [row["name"], row["stats"], str(row["kills"]), str(row["deaths"])]:
			var l := Label.new()
			l.text = v
			l.modulate = Balance.COLOR_BLUE if row["team"] == Balance.Team.BLUE else Balance.COLOR_RED
			grid.add_child(l)
	box.add_child(grid)

	var again := Button.new()
	again.text = "Play again"
	again.pressed.connect(func(): play_again.emit())
	box.add_child(again)
	var to_menu := Button.new()
	to_menu.text = "Menu"
	to_menu.pressed.connect(func(): menu.emit())
	box.add_child(to_menu)
