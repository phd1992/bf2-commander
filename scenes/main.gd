extends Node
## Root scene: main menu -> game -> end screen.

const MENU_SCENE := preload("res://ui/main_menu.tscn")
const GAME_SCENE := preload("res://scenes/game.tscn")
const END_SCENE := preload("res://ui/end_screen.tscn")

var _current: Node


func _ready() -> void:
	# Developer conveniences from the command line (after "--"):
	#   --autoplay [--ai] [--seed=N]   start a match immediately
	var args := OS.get_cmdline_user_args()
	var autoplay := "--autoplay" in args
	var ai := "--ai" in args
	var mode := "CONQUEST"
	if "--broken-arrow" in args:
		mode = "BROKEN_ARROW"
	elif "--hybrid" in args:
		mode = "HYBRID"
	var red_rolled := "--red-rolled" in args
	var hidden := "--hidden-stats" in args
	var seed := randi() % 100000
	for a in args:
		if a.begins_with("--seed="):
			seed = int(a.trim_prefix("--seed="))
	if autoplay:
		start_game(seed, ai, mode, red_rolled, hidden)
	else:
		show_menu()


func _clear() -> void:
	if _current != null:
		_current.queue_free()
		_current = null


func show_menu() -> void:
	_clear()
	Sim.end_match()
	var menu := MENU_SCENE.instantiate()
	menu.play_requested.connect(start_game)
	add_child(menu)
	_current = menu


func start_game(seed: int, ai_vs_ai: bool, mode: String = "CONQUEST", red_rolled: bool = false, hidden_stats: bool = false) -> void:
	_clear()
	Sim.start_match(seed, ai_vs_ai, mode, red_rolled, hidden_stats)
	var game := GAME_SCENE.instantiate()
	game.match_finished.connect(show_end)
	add_child(game)
	_current = game


func show_end() -> void:
	var stats := {}
	if _current != null and _current.has_method("collect_end_stats"):
		stats = _current.collect_end_stats()
	_clear()
	var end := END_SCENE.instantiate()
	end.setup(stats)
	end.play_again.connect(func(): start_game(Sim.seed, Sim.ai_vs_ai, Sim.spawn_mode, Sim.red_rolled, Sim.hidden_stats))
	end.menu.connect(show_menu)
	add_child(end)
	_current = end
