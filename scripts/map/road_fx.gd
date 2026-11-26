class_name RoadFx
extends Node2D
## Ferrovias e estradas no mapa (F4): liga os centros de províncias vizinhas do mesmo dono.
## Ferrovia (ambas com ferrovia): trilho duplo com dormentes, mais grosso conforme o nível;
## estrada (ambas com cidade ou mercado/depósito): linha de terra tracejada. O traçado é curvado
## levemente por província para não parecer régua. Trens pequenos percorrem as linhas mais fortes.

const MIN_ZOOM := 1.3
const MAX_EDGES := 600

var _rails: Array = []     # [a, b, nível]
var _roads: Array = []     # [a, b]
var _t: float = 0.0
var _timer: Timer


func _ready() -> void:
	z_index = 3
	_timer = Timer.new()
	_timer.wait_time = 0.12
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	Events.month_changed.connect(func(_d): _rebuild())
	Events.state_loaded.connect(_rebuild)
	Events.province_updated.connect(func(_pid): _rebuild())
	_rebuild()


func _rebuild() -> void:
	_rails.clear()
	_roads.clear()
	if not Game.loaded:
		return
	for p in Game.provinces:
		if p.owner_id < 0:
			continue
		var rl: int = int(p.bld.get("railway", 0))
		var road_a: bool = p.city != "" or int(p.bld.get("market", 0)) + int(p.bld.get("depot", 0)) > 0
		for nid in p.neighbors:
			if nid < p.id:
				continue
			var q: Province = Game.provinces[nid]
			if q.owner_id != p.owner_id:
				continue
			var rq: int = int(q.bld.get("railway", 0))
			if rl > 0 and rq > 0:
				_rails.append([p.id, nid, mini(rl, rq)])
			elif road_a and (q.city != "" or int(q.bld.get("market", 0)) + int(q.bld.get("depot", 0)) > 0):
				_roads.append([p.id, nid])
		if _rails.size() + _roads.size() >= MAX_EDGES:
			break
	queue_redraw()


func _tick() -> void:
	var mv := get_parent() as MapView
	if mv != null and mv.zoom_level >= MIN_ZOOM and (not _rails.is_empty() or not _roads.is_empty()) and is_visible_in_tree():
		_t = float(Time.get_ticks_msec()) * 0.001
		queue_redraw()


func _bend(a: Vector2, b: Vector2, k: int) -> Vector2:
	var m: Vector2 = (a + b) * 0.5
	var d: Vector2 = (b - a)
	var n := Vector2(-d.y, d.x).normalized()
	return m + n * d.length() * 0.08 * (1.0 if k % 2 == 0 else -1.0)


func _draw() -> void:
	if not Game.loaded:
		return
	var mv := get_parent() as MapView
	if mv == null or mv.zoom_level < MIN_ZOOM or AppSettings.gfx_quality() < 1:
		return
	var z: float = mv.zoom_level
	var view: Rect2 = (get_canvas_transform().affine_inverse() * get_viewport_rect()).grow(40.0)
	for e in _roads:
		var a: Vector2 = Game.provinces[int(e[0])].center
		var b: Vector2 = Game.provinces[int(e[1])].center
		if not view.has_point(a) and not view.has_point(b):
			continue
		var m: Vector2 = _bend(a, b, int(e[0]))
		var steps := 8
		var prev: Vector2 = a
		for i in range(1, steps + 1):
			var f: float = float(i) / float(steps)
			var pt: Vector2 = a.lerp(m, f * 2.0) if f <= 0.5 else m.lerp(b, (f - 0.5) * 2.0)
			if i % 2 == 1:
				draw_line(prev, pt, Color(0.50, 0.38, 0.22, 0.75), 1.4 / z)
			prev = pt
	for e in _rails:
		var a: Vector2 = Game.provinces[int(e[0])].center
		var b: Vector2 = Game.provinces[int(e[1])].center
		if not view.has_point(a) and not view.has_point(b):
			continue
		var lv: int = int(e[2])
		var m: Vector2 = _bend(a, b, int(e[0]))
		var pts := PackedVector2Array([a, a.lerp(m, 0.5), m, m.lerp(b, 0.5), b])
		draw_polyline(pts, Color(0.1, 0.1, 0.12, 0.85), (2.2 + 0.5 * float(lv)) / z)
		draw_polyline(pts, Color(0.82, 0.82, 0.85, 0.9), (1.0 + 0.3 * float(lv)) / z)
		if z >= 2.0:                                   # dormentes
			for i in 4:
				var q0: Vector2 = pts[i]
				var q1: Vector2 = pts[i + 1]
				var dir: Vector2 = (q1 - q0).normalized()
				var nn := Vector2(-dir.y, dir.x)
				for k in 3:
					var c: Vector2 = q0.lerp(q1, (float(k) + 0.5) / 3.0)
					draw_line(c - nn * 1.6 / z, c + nn * 1.6 / z, Color(0.28, 0.2, 0.12, 0.9), 0.7 / z)
		if lv >= 2 and z >= 1.8:                       # trem
			var f2: float = fposmod(_t * 0.12 + float(int(e[0]) % 7) * 0.13, 1.0)
			var tp: Vector2 = pts[int(f2 * 4.0)].lerp(pts[mini(int(f2 * 4.0) + 1, 4)], fposmod(f2 * 4.0, 1.0))
			draw_circle(tp, 2.2 / z, Color(0.2, 0.2, 0.24))
			draw_circle(tp + Vector2(0.0, -2.6 / z), 1.4 / z, Color(0.9, 0.9, 0.9, 0.55))
