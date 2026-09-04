class_name Flag
extends RefCounted
## A capturable control point, or an uncapturable HQ (Section 5).

var id := 0
var name := ""
var centre := Vector2i()
var is_hq := false
var owner: int = Balance.Team.NONE
## +1 = fully BLUE, -1 = fully RED, 0 = neutral.
var progress := 0.0


func radius() -> float:
	return Balance.HQ_RADIUS if is_hq else Balance.FLAG_RADIUS


func centre_pos() -> Vector2:
	return Grid.centre_of(centre)


func contains(pos: Vector2) -> bool:
	return pos.distance_to(centre_pos()) <= radius()


func is_spawnable_for(team: int) -> bool:
	return owner == team


## Advances capture progress for one tick (Section 5.2). Returns the team
## that just completed a capture, or Team.NONE.
func update_capture(blue_count: int, red_count: int, dt: float) -> int:
	if is_hq:
		return Balance.Team.NONE
	var nb := mini(blue_count, Balance.CAPTURE_MAX_COUNT)
	var nr := mini(red_count, Balance.CAPTURE_MAX_COUNT)
	var n := nb - nr
	if n == 0:
		return Balance.Team.NONE
	var before := progress
	progress = clampf(progress + float(n) * dt / Balance.CAPTURE_TIME_S, -1.0, 1.0)
	# Neutralisation: crossing 0 from the owner's side.
	if owner == Balance.Team.BLUE and before > 0.0 and progress <= 0.0:
		owner = Balance.Team.NONE
	elif owner == Balance.Team.RED and before < 0.0 and progress >= 0.0:
		owner = Balance.Team.NONE
	if progress >= 1.0 and owner != Balance.Team.BLUE:
		owner = Balance.Team.BLUE
		return Balance.Team.BLUE
	if progress <= -1.0 and owner != Balance.Team.RED:
		owner = Balance.Team.RED
		return Balance.Team.RED
	return Balance.Team.NONE
