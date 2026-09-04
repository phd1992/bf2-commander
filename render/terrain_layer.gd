extends Node2D
## Draws every cell with its terrain colour, elevation shading and contour
## lines. Redraws only when the world marks the terrain dirty.

const RUBBLE_HATCH := Color(0.3, 0.3, 0.3, 0.8)
const CONTOUR := Color(0, 0, 0, 0.35)
const FLAG_RING := Color(1, 1, 1, 0.5)


func _process(_delta: float) -> void:
	if Sim.world != null and Sim.world.terrain_dirty:
		Sim.world.terrain_dirty = false
		queue_redraw()


static func cell_color(t: int, elev: int) -> Color:
	var c: Color = Balance.TERRAIN_COLORS[t]
	var b := 1.0 + Balance.ELEVATION_BRIGHTNESS_PER_LEVEL * elev
	return Color(minf(c.r * b, 1.0), minf(c.g * b, 1.0), minf(c.b * b, 1.0))


func _draw() -> void:
	var w: World = Sim.world
	if w == null:
		return
	var g := w.grid
	var px := float(Balance.CELL_PX)
	for y in g.H:
		for x in g.W:
			var i := y * g.W + x
			var t := g.terrain[i]
			var e := g.elevation[i]
			var rect := Rect2(x * px, y * px, px, px)
			draw_rect(rect, cell_color(t, e))
			if t == Balance.Terrain.RUBBLE:
				draw_line(rect.position, rect.end, RUBBLE_HATCH, 1.5)
				draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), RUBBLE_HATCH, 1.5)
			elif t == Balance.Terrain.WALL:
				var hp := g.wall_hp[i]
				if hp < Balance.WALL_HP:
					var frac := 1.0 - float(hp) / float(Balance.WALL_HP)
					draw_rect(Rect2(rect.position, Vector2(px, px * frac)), Color(0.6, 0.35, 0.2, 0.7))
	# contour lines where elevation changes between neighbours
	for y in g.H:
		for x in g.W:
			var e := g.elevation[y * g.W + x]
			if x + 1 < g.W and g.elevation[y * g.W + x + 1] != e:
				draw_line(Vector2((x + 1) * px, y * px), Vector2((x + 1) * px, (y + 1) * px), CONTOUR, 1.0)
			if y + 1 < g.H and g.elevation[(y + 1) * g.W + x] != e:
				draw_line(Vector2(x * px, (y + 1) * px), Vector2((x + 1) * px, (y + 1) * px), CONTOUR, 1.0)
