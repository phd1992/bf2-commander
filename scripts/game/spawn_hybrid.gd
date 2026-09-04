class_name SpawnHybrid
extends SpawnBrokenArrow
## Hybrid mode (Section 19.4): Broken Arrow economics and entry points, plus
## every owned capturable flag as a forward entry point.


func entries(team: int) -> Array[Vector2i]:
	var out := super.entries(team)
	for f in world.flags:
		if not f.is_hq and f.owner == team:
			out.append(f.centre)
	return out


func entry_names(team: int) -> Array:
	var out: Array = super.entry_names(team)
	# super() named the edge entries; the rest are flags, in the same order
	var flags_named := 0
	for f in world.flags:
		if not f.is_hq and f.owner == team:
			var i: int = world.entry_points[team].size() + flags_named
			out[i] = "Flag " + f.name
			flags_named += 1
	return out
