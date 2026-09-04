extends TestCase
## Test 16: three AI-vs-AI matches (seeds 1-3) complete without error and
## each ends with a winner or a draw. Also checks determinism: the same seed
## replays to the same result.

const Runner := preload("res://sim/run_headless.gd")


func test_three_matches_complete() -> void:
	for seed in range(1, 4):
		var r: Dictionary = Runner.run_match(seed)
		check(r["finished"], "seed %d finished (%.1f min)" % [seed, r["duration_s"] / 60.0])
		check(r["winner"] in [Balance.Team.BLUE, Balance.Team.RED, Balance.Team.NONE], "seed %d has a winner or a draw" % seed)
		check(r["blue_tickets"] <= 0 or r["red_tickets"] <= 0 or r["duration_s"] >= Balance.MATCH_LENGTH_S - 0.01, "seed %d ended by tickets or by the clock" % seed)
		check(r["blue_kills"] + r["red_kills"] > 0, "seed %d saw combat" % seed)
		check(r["assets_used"] > 0, "seed %d used assets" % seed)
		print("    " + Runner.format_line(r))


func test_same_seed_replays_identically() -> void:
	var a: Dictionary = Runner.run_match(5, 1500)   # 2.5 minutes is enough to diverge if it would
	var b: Dictionary = Runner.run_match(5, 1500)
	for key in ["blue_tickets", "red_tickets", "blue_kills", "red_kills", "assets_used", "walls_destroyed", "blue_flags", "red_flags", "blue_stats"]:
		check_eq(b[key], a[key], "%s identical on replay" % key)
