class_name TerrainFx
extends Node2D
## Símbolos de terreno (F7): com zoom, cada província ganha pequenas ilustrações do seu relevo
## (montanhas com neve, colinas, florestas, selva, dunas, juncos de pântano, tufos de planície,
## neve na tundra) espalhadas dentro do seu polígono. As posições são calculadas uma vez por
## província (determinísticas) e só o que está na tela é desenhado.

const MIN_ZOOM := 1.8
const PER_PROV := 5

var _cache: Dictionary = {}      # pid -> PackedVector2Array de posições
var _timer: Timer


func _ready() -> void:
	z_index = 1
	Events.state_loaded.connect(func():
		_cache.clear()
		queue_redraw())
	_timer = Timer.new()
	_timer.wait_time = 0.4
	_timer.timeout.connect(func():
		var mv := get_parent() as MapView
		if mv != null and mv.zoom_level >= MIN_ZOOM and is_visible_in_tree():
			queue_redraw())
	add_child(_timer)
	_timer.start()


func _spots(p: Province) -> PackedVector2Array:
	if _cache.has(p.id):
		return _cache[p.id]
	var out := PackedVector2Array()
	if p.poly.size() >= 3:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for v in p.poly:
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
		var rng := RandomNumberGenerator.new()
		rng.seed = p.id * 2654435761 + 17
		var tries := 0
		while out.size() < PER_PROV and tries < 40:
			tries += 1
			var q := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
			if Geometry2D.is_point_in_polygon(q, p.poly) and q.distance_to(p.center) > 1.0:
				out.append(q)
	_cache[p.id] = out
	return out


func _draw() -> void:
	if not Game.loaded:
		return
	var mv := get_parent() as MapView
	if mv == null or mv.zoom_level < MIN_ZOOM or AppSettings.gfx_quality() < 2 or (mv.mode != MapView.Mode.POLITICAL and mv.mode != MapView.Mode.TERRAIN):
		return
	var z: float = mv.zoom_level
	var s: float = 5.0 / z
	var view: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
	var a: float = clampf((z - 1.8) / 1.2, 0.0, 1.0) * 0.8
	for p in Game.provinces:
		if p.owner_id < 0 or not view.has_point(p.center):
			continue
		for q in _spots(p):
			match p.terrain:
				"mountains": _mountain(q, s, a)
				"hills": _hill(q, s, a)
				"forest": _tree(q, s, a, Color(0.12, 0.38, 0.18))
				"jungle": _jungle(q, s, a)
				"desert": _dune(q, s, a)
				"tundra": _snow(q, s, a)
				"marsh": _reeds(q, s, a)
				_: _tuft(q, s, a)


func _mountain(q: Vector2, s: float, a: float) -> void:
	draw_colored_polygon(PackedVector2Array([q + Vector2(-1.2 * s, 0), q + Vector2(1.2 * s, 0), q + Vector2(0, -1.7 * s)]), Color(0.36, 0.34, 0.36, a))
	draw_colored_polygon(PackedVector2Array([q + Vector2(0, -1.7 * s), q + Vector2(1.2 * s, 0), q + Vector2(0.25 * s, 0)]), Color(0.2, 0.2, 0.24, a * 0.6))
	draw_colored_polygon(PackedVector2Array([q + Vector2(0, -1.7 * s), q + Vector2(-0.4 * s, -1.05 * s), q + Vector2(0.4 * s, -1.05 * s)]), Color(1, 1, 1, a))


func _hill(q: Vector2, s: float, a: float) -> void:
	draw_arc(q, 1.1 * s, PI, TAU, 10, Color(0.30, 0.38, 0.18, a), 0.35 * s)
	draw_arc(q + Vector2(1.0 * s, 0.2 * s), 0.7 * s, PI, TAU, 8, Color(0.30, 0.38, 0.18, a * 0.8), 0.3 * s)


func _tree(q: Vector2, s: float, a: float, col: Color) -> void:
	draw_line(q, q + Vector2(0, -0.5 * s), Color(0.3, 0.2, 0.1, a), 0.25 * s)
	draw_colored_polygon(PackedVector2Array([q + Vector2(-0.6 * s, -0.4 * s), q + Vector2(0.6 * s, -0.4 * s), q + Vector2(0, -1.6 * s)]), Color(col, a))


func _jungle(q: Vector2, s: float, a: float) -> void:
	draw_line(q, q + Vector2(0, -0.8 * s), Color(0.3, 0.2, 0.1, a), 0.25 * s)
	draw_circle(q + Vector2(0, -1.1 * s), 0.7 * s, Color(0.1, 0.45, 0.2, a))
	draw_circle(q + Vector2(0.4 * s, -0.9 * s), 0.45 * s, Color(0.16, 0.55, 0.25, a))


func _dune(q: Vector2, s: float, a: float) -> void:
	draw_arc(q, 1.3 * s, PI * 1.1, PI * 1.9, 10, Color(0.62, 0.48, 0.22, a), 0.3 * s)
	draw_arc(q + Vector2(0.6 * s, 0.5 * s), 0.9 * s, PI * 1.1, PI * 1.9, 8, Color(0.62, 0.48, 0.22, a * 0.7), 0.25 * s)


func _snow(q: Vector2, s: float, a: float) -> void:
	for k in 3:
		draw_circle(q + Vector2(float(k - 1) * 0.7 * s, float(k % 2) * 0.4 * s), 0.35 * s, Color(1, 1, 1, a))


func _reeds(q: Vector2, s: float, a: float) -> void:
	for k in 3:
		var x: float = float(k - 1) * 0.35 * s
		draw_line(q + Vector2(x, 0), q + Vector2(x + 0.1 * s, -1.2 * s), Color(0.28, 0.45, 0.22, a), 0.18 * s)
	draw_arc(q + Vector2(0, 0.25 * s), 1.0 * s, 0.2, PI - 0.2, 8, Color(0.4, 0.6, 0.8, a * 0.8), 0.2 * s)


func _tuft(q: Vector2, s: float, a: float) -> void:
	for k in 3:
		draw_line(q, q + Vector2(float(k - 1) * 0.5 * s, -0.9 * s), Color(0.28, 0.5, 0.2, a), 0.2 * s)
