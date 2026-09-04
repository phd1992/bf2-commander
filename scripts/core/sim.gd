extends Node
## Autoload "Sim": owns the World, the fixed-step tick loop, time scale and
## pause. Rendering nodes read Sim.world; nothing here does game logic.

signal match_started
signal match_ended
signal stepped

var world: World
var time_scale := 1
var paused := false
var seed := 1
var ai_vs_ai := false
var player_team: int = Balance.Team.BLUE
var spawn_mode := "CONQUEST"
var red_rolled := false

var _accum := 0.0
var _last_stats := {}


func start_match(p_seed: int, p_ai_vs_ai: bool = false, p_mode: String = "CONQUEST", p_red_rolled: bool = false) -> void:
	seed = p_seed
	ai_vs_ai = p_ai_vs_ai
	spawn_mode = p_mode
	red_rolled = p_red_rolled
	world = World.new()
	world.setup(seed, true, red_rolled)
	world.set_spawn_mode(spawn_mode)
	world.configure_match(ai_vs_ai)
	paused = false
	_accum = 0.0
	match_started.emit()


func end_match() -> void:
	world = null


func _physics_process(delta: float) -> void:
	if world == null or paused or world.game_over:
		return
	_accum += delta * time_scale
	var steps := 0
	while _accum >= Balance.TICK and steps < 4 * time_scale:
		world.step(Balance.TICK)
		_accum -= Balance.TICK
		steps += 1
	if steps > 0:
		stepped.emit()
		if world.game_over:
			match_ended.emit()


func set_speed(scale: int) -> void:
	time_scale = clampi(scale, 1, 4)


func speed_up() -> void:
	time_scale = 2 if time_scale == 1 else 4


func speed_down() -> void:
	time_scale = 1 if time_scale == 2 else (2 if time_scale == 4 else 1)


func toggle_pause() -> void:
	paused = not paused


## Events accumulated by the world since the last call; clears the list.
func take_events() -> Array:
	if world == null:
		return []
	var ev := world.events
	world.events = []
	return ev
