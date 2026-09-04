class_name Weapons
extends RefCounted
## Weapon table helpers (Section 8.1). The numbers live in balance.gd.


static func spec(name: String) -> Dictionary:
	return Balance.WEAPONS[name]


static func range_of(name: String) -> float:
	return Balance.WEAPONS[name]["range"]


static func interval(name: String) -> float:
	return Balance.WEAPONS[name]["interval"]


## 1.0 within half range, linear down to RANGE_MIN_FACTOR at max range.
static func range_factor(name: String, dist: float) -> float:
	var r: float = Balance.WEAPONS[name]["range"]
	if r <= 0.0 or dist <= r * 0.5:
		return 1.0
	var t := clampf((dist - r * 0.5) / (r * 0.5), 0.0, 1.0)
	return lerpf(1.0, Balance.RANGE_MIN_FACTOR, t)


## Targeting preference: "INF_FIRST", "VEH_FIRST", "ANY", "VEH_ONLY", "INF_ONLY".
static func preference(name: String, infantry_only: bool = false) -> String:
	if infantry_only:
		return "INF_ONLY"
	match name:
		"RIFLE", "HMG":
			return "INF_FIRST"
		"AT":
			return "VEH_ONLY"
		"AUTOCANNON":
			return "ANY"
		"CANNON":
			return "VEH_FIRST"
	return "ANY"
