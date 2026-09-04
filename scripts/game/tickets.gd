class_name Tickets
extends RefCounted
## Ticket bleed and victory conditions (Section 5.3).


static func update(w: World, dt: float) -> void:
	w.bleed_timer += dt
	if w.bleed_timer + 0.0001 < Balance.BLEED_INTERVAL_S:
		return
	w.bleed_timer -= Balance.BLEED_INTERVAL_S
	var blue := w.flag_count(Balance.Team.BLUE)
	var red := w.flag_count(Balance.Team.RED)
	if blue < red:
		w.tickets[Balance.Team.BLUE] = maxi(w.tickets[Balance.Team.BLUE] - 1, 0)
	elif red < blue:
		w.tickets[Balance.Team.RED] = maxi(w.tickets[Balance.Team.RED] - 1, 0)


## True when a team currently owns fewer flags than the enemy.
static func is_bleeding(w: World, team: int) -> bool:
	return w.flag_count(team) < w.flag_count(Balance.other_team(team))


static func check_victory(w: World) -> void:
	if w.game_over:
		return
	var blue: int = w.tickets[Balance.Team.BLUE]
	var red: int = w.tickets[Balance.Team.RED]
	if blue <= 0 and red <= 0:
		_end(w, Balance.Team.BLUE if blue > red else (Balance.Team.RED if red > blue else Balance.Team.NONE))
	elif red <= 0:
		_end(w, Balance.Team.BLUE)
	elif blue <= 0:
		_end(w, Balance.Team.RED)
	elif w.time + 0.0001 >= Balance.MATCH_LENGTH_S:
		if blue > red:
			_end(w, Balance.Team.BLUE)
		elif red > blue:
			_end(w, Balance.Team.RED)
		else:
			_end(w, Balance.Team.NONE)


static func _end(w: World, winner: int) -> void:
	w.game_over = true
	w.winner = winner
	w.events.append({ "type": "game_over", "winner": winner })
