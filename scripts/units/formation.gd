class_name Formation
extends RefCounted
## Formation slot tables and helpers (Section 6.5). Slots are offsets in the
## leader's local frame: x forward, y right.


static func pick(terrain: int) -> String:
	match terrain:
		Balance.Terrain.ROAD:
			return "COLUMN"
		Balance.Terrain.OPEN:
			return "WEDGE"
	return "CLUSTER"


static func slot(formation: String, index: int) -> Vector2:
	var slots: Array = Balance.FORMATIONS[formation]
	return slots[clampi(index, 0, slots.size() - 1)]


## Rotates a local offset into world space for a leader facing `heading`.
static func world_offset(offset: Vector2, heading: Vector2) -> Vector2:
	var fwd := heading.normalized() if heading.length_squared() > 0.0001 else Vector2.RIGHT
	var right := Vector2(-fwd.y, fwd.x)
	return fwd * offset.x + right * offset.y
