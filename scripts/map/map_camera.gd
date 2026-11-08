class_name MapCamera
extends Camera2D
## Câmera do mapa: arrastar com 1 dedo, pinça com 2, toque curto = seleção.
## Também funciona no PC: botão esquerdo arrasta, roda do mouse dá zoom.
##
## Eventos de mouse "emulados" a partir do toque são ignorados (device == -1);
## o toque real é tratado por InputEventScreenTouch/ScreenDrag.

signal tapped(world_pos: Vector2)
signal zoom_changed(zoom_value: float)

const TAP_MAX_MOVE := 14.0       # px; acima disso vira arrasto
const TAP_MAX_TIME_MS := 350
const ZOOM_MAX := 6.0
const WHEEL_STEP := 1.15

var map_size: Vector2 = Vector2(2400.0, 1200.0)
## Callable(screen_pos: Vector2) -> bool. Se true, o toque pertence à UI e é ignorado.
var ui_blocker: Callable = Callable()
var zoom_min: float = 0.4

var _touches: Dictionary = {}    # índice do dedo -> posição na tela
var _blocked: Dictionary = {}    # dedos que começaram sobre a UI
var _tap_pos: Vector2 = Vector2.ZERO
var _tap_time: int = 0
var _tap_moved: bool = false
var _pinch_dist: float = 0.0
var _mouse_down: bool = false
var _mouse_blocked: bool = false
var _vel: Vector2 = Vector2.ZERO          # inércia, em unidades do mundo / s
var _last_drag_us: int = 0
var _last_zoom: float = -1.0
var _tween: Tween


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_resized)
	_update_zoom_limits()
	position = map_size * 0.5
	zoom = Vector2.ONE * zoom_min
	position = _clamped(position, zoom.x)


func _process(delta: float) -> void:
	if absf(zoom.x - _last_zoom) > 0.0001:
		_last_zoom = zoom.x
		zoom_changed.emit(zoom.x)
	# Inércia após soltar o dedo/mouse
	if _touches.is_empty() and not _mouse_down and _vel.length_squared() > 4.0:
		position = _clamped(position + _vel * delta, zoom.x)
		_vel *= pow(0.02, delta)   # perde ~98% da velocidade por segundo
	elif _touches.is_empty() and not _mouse_down:
		_vel = Vector2.ZERO


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var half := get_viewport_rect().size * 0.5
	return position + (screen_pos - half) / zoom.x


## Enquadra um retângulo do mundo com animação suave.
func focus_rect(rect: Rect2, margin: float = 1.5) -> void:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var vs := get_viewport_rect().size
	var target_zoom := clampf(minf(vs.x / (rect.size.x * margin), vs.y / (rect.size.y * margin)), zoom_min, ZOOM_MAX)
	var target_pos := _clamped(rect.get_center(), target_zoom)
	_stop_tween()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "zoom", Vector2.ONE * target_zoom, 0.6)
	_tween.tween_property(self, "position", target_pos, 0.6)


# ---------------------------------------------------------------------------
# Entrada
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_on_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_at(g.position, zoom.x * g.factor)


func _is_over_ui(pos: Vector2) -> bool:
	return ui_blocker.is_valid() and bool(ui_blocker.call(pos))


func _begin_tap(pos: Vector2) -> void:
	_tap_pos = pos
	_tap_time = Time.get_ticks_msec()
	_tap_moved = false
	_last_drag_us = Time.get_ticks_usec()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _is_over_ui(e.position):
			_blocked[e.index] = true
			return
		_stop_tween()
		_vel = Vector2.ZERO
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_begin_tap(e.position)
		else:
			_tap_moved = true   # segundo dedo cancela o toque
			_pinch_dist = _current_pinch_distance()
	else:
		if _blocked.has(e.index):
			_blocked.erase(e.index)
			return
		var was_single := _touches.size() == 1
		_touches.erase(e.index)
		if was_single and not _tap_moved and Time.get_ticks_msec() - _tap_time <= TAP_MAX_TIME_MS:
			tapped.emit(screen_to_world(e.position))
		if Time.get_ticks_usec() - _last_drag_us > 80000:
			_vel = Vector2.ZERO   # parou antes de soltar: sem arremesso
		if _touches.size() == 1:
			_tap_moved = true     # o dedo restante continua arrastando
			_pinch_dist = 0.0


func _on_drag(e: InputEventScreenDrag) -> void:
	if _blocked.has(e.index) or not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _touches.size() == 1:
		if not _tap_moved and e.position.distance_to(_tap_pos) > TAP_MAX_MOVE:
			_tap_moved = true
		if _tap_moved:
			_pan_by(e.relative)
	else:
		_tap_moved = true
		var keys := _touches.keys()
		var a: Vector2 = _touches[keys[0]]
		var b: Vector2 = _touches[keys[1]]
		var dist := a.distance_to(b)
		if _pinch_dist > 1.0 and dist > 1.0:
			_zoom_at((a + b) * 0.5, zoom.x * dist / _pinch_dist)
		_pinch_dist = dist
		_pan_by(e.relative * 0.5)   # cada evento move um dedo; o ponto médio anda metade


func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if _is_over_ui(e.position):
				_mouse_blocked = true
				return
			_mouse_blocked = false
			_stop_tween()
			_vel = Vector2.ZERO
			_mouse_down = true
			_begin_tap(e.position)
		else:
			if _mouse_blocked:
				_mouse_blocked = false
				return
			if _mouse_down and not _tap_moved and Time.get_ticks_msec() - _tap_time <= TAP_MAX_TIME_MS:
				tapped.emit(screen_to_world(e.position))
			if Time.get_ticks_usec() - _last_drag_us > 80000:
				_vel = Vector2.ZERO
			_mouse_down = false
	elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(e.position, zoom.x * WHEEL_STEP)
	elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(e.position, zoom.x / WHEEL_STEP)


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if not _mouse_down:
		return
	if not _tap_moved and e.position.distance_to(_tap_pos) > TAP_MAX_MOVE:
		_tap_moved = true
	if _tap_moved:
		_pan_by(e.relative)


# ---------------------------------------------------------------------------
# Movimento
# ---------------------------------------------------------------------------
func _pan_by(screen_delta: Vector2) -> void:
	position = _clamped(position - screen_delta / zoom.x, zoom.x)
	var now := Time.get_ticks_usec()
	var dt := maxf(float(now - _last_drag_us) / 1000000.0, 0.004)
	_last_drag_us = now
	_vel = (-screen_delta / zoom.x / dt).limit_length(4000.0)


## Zoom mantendo fixo o ponto do mundo sob `screen_pos`.
func _zoom_at(screen_pos: Vector2, new_zoom: float) -> void:
	var z := clampf(new_zoom, zoom_min, ZOOM_MAX)
	var before := screen_to_world(screen_pos)
	zoom = Vector2.ONE * z
	var after := screen_to_world(screen_pos)
	position = _clamped(position + before - after, z)


func _current_pinch_distance() -> float:
	var keys := _touches.keys()
	if keys.size() < 2:
		return 0.0
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	return a.distance_to(b)


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## Mantém a visão dentro do mapa (centraliza se o mapa for menor que a tela).
func _clamped(pos: Vector2, z: float) -> Vector2:
	var half := get_viewport_rect().size * 0.5 / z
	var out := pos
	if map_size.x <= half.x * 2.0:
		out.x = map_size.x * 0.5
	else:
		out.x = clampf(pos.x, half.x, map_size.x - half.x)
	if map_size.y <= half.y * 2.0:
		out.y = map_size.y * 0.5
	else:
		out.y = clampf(pos.y, half.y, map_size.y - half.y)
	return out


## O zoom mínimo é o que faz o mapa cobrir a tela (sem bordas vazias).
func _update_zoom_limits() -> void:
	var vs := get_viewport_rect().size
	zoom_min = maxf(vs.x / map_size.x, vs.y / map_size.y)


func _on_viewport_resized() -> void:
	_update_zoom_limits()
	if zoom.x < zoom_min:
		zoom = Vector2.ONE * zoom_min
	position = _clamped(position, zoom.x)
