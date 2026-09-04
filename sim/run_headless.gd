extends SceneTree
## Headless AI-vs-AI batch runner (Section 16).
## godot --headless --script res://sim/run_headless.gd -- --matches 10 --seed 1
## Prints one line per match and a summary. Exit code 0 unless a match fails
## to finish (an exception or a stuck simulation).


static func run_match(seed: int, max_ticks: int = int(Balance.MATCH_LENGTH_S / Balance.TICK) + 10, mode: String = "CONQUEST", red_rolled: bool = false) -> Dictionary:
	var w := World.new()
	w.setup(seed, true, red_rolled)
	w.set_spawn_mode(mode)
	w.configure_match(true)
	var ticks := 0
	var t0 := Time.get_ticks_msec()
	while not w.game_over and ticks < max_ticks:
		w.step(Balance.TICK)
		w.events.clear()
		ticks += 1
	var blue_ai: CommanderAI = w.ais[1]
	var red_ai: CommanderAI = w.ais[0]
	var blue_stats := ""
	for s in w.squads_of(Balance.Team.BLUE):
		blue_stats += s.stats_text().replace(" ", "") + " "
	return {
		"seed": seed,
		"finished": w.game_over,
		"winner": w.winner,
		"duration_s": w.time,
		"blue_tickets": w.tickets[Balance.Team.BLUE],
		"red_tickets": w.tickets[Balance.Team.RED],
		"blue_kills": w.match_stats["kills"][Balance.Team.BLUE],
		"red_kills": w.match_stats["kills"][Balance.Team.RED],
		"assets_used": w.match_stats["assets_used"],
		"walls_destroyed": w.match_stats["walls_destroyed"],
		"blue_flags": w.flag_count(Balance.Team.BLUE),
		"red_flags": w.flag_count(Balance.Team.RED),
		"blue_orders": blue_ai.orders_issued,
		"red_orders": red_ai.orders_issued,
		"blue_stats": blue_stats.strip_edges(),
		"wall_ms": Time.get_ticks_msec() - t0,
	}


static func winner_name(winner: int) -> String:
	if winner == Balance.Team.BLUE:
		return "BLUE"
	if winner == Balance.Team.RED:
		return "RED"
	return "DRAW"


static func format_line(r: Dictionary) -> String:
	return "seed %3d  %-5s  tickets B %3d / R %3d  %5.1f min  kills B %3d / R %3d  assets %2d  walls %3d  flags %d/%d  (%s)  [%d ms]" % [
		r["seed"], winner_name(r["winner"]), r["blue_tickets"], r["red_tickets"], r["duration_s"] / 60.0,
		r["blue_kills"], r["red_kills"], r["assets_used"], r["walls_destroyed"], r["blue_flags"], r["red_flags"],
		r["blue_stats"], r["wall_ms"]]


func _init() -> void:
	var matches := 10
	var seed := 1
	var mode := "CONQUEST"
	var red_rolled := false
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--matches" and i + 1 < args.size():
			matches = int(args[i + 1])
			i += 1
		elif a.begins_with("--matches="):
			matches = int(a.trim_prefix("--matches="))
		elif a == "--seed" and i + 1 < args.size():
			seed = int(args[i + 1])
			i += 1
		elif a.begins_with("--seed="):
			seed = int(a.trim_prefix("--seed="))
		elif a == "--mode" and i + 1 < args.size():
			mode = args[i + 1].to_upper().replace("-", "_")
			i += 1
		elif a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=").to_upper().replace("-", "_")
		elif a == "--red-rolled":
			red_rolled = true
		i += 1
	print("Commander headless: %d AI vs AI match(es) from seed %d, mode %s%s" % [matches, seed, mode, ", RED rolled" if red_rolled else ""])
	var results: Array = []
	var failed := false
	for m in matches:
		var r := run_match(seed + m, int(Balance.MATCH_LENGTH_S / Balance.TICK) + 10, mode, red_rolled)
		results.append(r)
		print(format_line(r))
		if not r["finished"]:
			failed = true
			print("  !! match did not finish")
	var blue_wins := 0
	var draws := 0
	var total_min := 0.0
	for r in results:
		if r["winner"] == Balance.Team.BLUE:
			blue_wins += 1
		elif r["winner"] == Balance.Team.NONE:
			draws += 1
		total_min += r["duration_s"] / 60.0
	if not results.is_empty():
		print("summary: BLUE win rate %.0f%% (%d/%d, %d draws), average duration %.1f min" % [
			100.0 * blue_wins / results.size(), blue_wins, results.size(), draws, total_min / results.size()])
	quit(1 if failed else 0)
