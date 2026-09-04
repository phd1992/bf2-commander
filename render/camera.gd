extends Camera2D
## Pan with WASD / arrows / middle-mouse drag, zoom with the wheel (0.5x-2x),
## clamped to the map edges.

const PAN_SPEED := 900.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 1.15

var _dragging := false


func _ready() -> void:
	var map_px := Vector2(Balance.MAP_W, Balance.MAP_H) * Balance.CELL_PX
	limit_left = 0
	limit_top = 0
	limit_right = int(map_px.x)
	limit_bottom = int(map_px.y)
	position = map_px * 0.5
	zoom = Vector2(0.6, 0.6)
	make_current()


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x
		_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(ZOOM_STEP, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / ZOOM_STEP, event.position)
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom.x
		_clamp()


func _zoom_at(factor: float, _screen_pos: Vector2) -> void:
	var before := get_global_mouse_position()
	var z := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	var after := get_global_mouse_position()
	position += before - after
	_clamp()


func _clamp() -> void:
	var half := get_viewport_rect().size * 0.5 / zoom.x
	var map_px := Vector2(Balance.MAP_W, Balance.MAP_H) * Balance.CELL_PX
	position.x = clampf(position.x, minf(half.x, map_px.x * 0.5), maxf(map_px.x - half.x, map_px.x * 0.5))
	position.y = clampf(position.y, minf(half.y, map_px.y * 0.5), maxf(map_px.y - half.y, map_px.y * 0.5))
