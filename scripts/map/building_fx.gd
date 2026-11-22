class_name BuildingFx
extends Node2D
## Edifícios no mapa (B26c): com bastante zoom, cada província mostra silhuetas vetoriais de suas
## fábricas (chaminés = nível, cor = setor), porto, ferrovia, cidade (casas = mercado/bairros) e
## obras em andamento (guindaste + anel de progresso). Só desenha o que está na tela.

const MIN_ZOOM := 2.2
const MAX_DRAWN := 160

const FACTORY_COL := {
	"textile": Color(0.70, 0.45, 0.80), "smithy": Color(0.55, 0.55, 0.60), "carpentry": Color(0.62, 0.42, 0.25),
	"steel": Color(0.45, 0.50, 0.60), "paper": Color(0.90, 0.86, 0.70), "machinery": Color(0.35, 0.55, 0.75),
	"glassworks": Color(0.45, 0.85, 0.90), "chemical": Color(0.55, 0.85, 0.40),
}

var _timer: Timer
var _works_by_pid: Dictionary = {}     # pid -> progresso (0..100) da obra mais adiantada


func _ready() -> void:
	z_index = 5
	_timer = Timer.new()
	_timer.wait_time = 0.3
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	Events.month_changed.connect(func(_d): _rebuild())
	Events.state_loaded.connect(_rebuild)
	Events.province_updated.connect(func(_pid): queue_redraw())
	_rebuild()


func _rebuild() -> void:
	_works_by_pid.clear()
	if not Game.loaded:
		return
	for c in Game.countries:
		for w in c.works:
			var pct: int = int(w[3]) * 100 / maxi(1, int(w[4]))
			_works_by_pid[int(w[0])] = maxi(pct, int(_works_by_pid.get(int(w[0]), 0)))
	queue_redraw()


func _tick() -> void:
	var mv := get_parent() as MapView
	if mv != null and mv.zoom_level >= MIN_ZOOM and is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if not Game.loaded:
		return
	var mv := get_parent() as MapView
	if mv == null or mv.zoom_level < MIN_ZOOM or AppSettings.gfx_quality() < 2:
		return
	var z: float = mv.zoom_level
	var view: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
	var s: float = 9.0 / z
	var drawn := 0
	for p in Game.provinces:
		if p.owner_id < 0 or not view.has_point(p.center):
			continue
		var fl: int = p.factory_level if p.factory != "" else 0
		var rail: int = int(p.bld.get("railway", 0))
		var port: int = int(p.bld.get("dock", 0)) + int(p.bld.get("shipyard", 0))
		var houses: int = int(p.bld.get("market", 0)) + int(p.bld.get("housing", 0)) + int(p.bld.get("city_hall", 0)) + (2 if p.capital_city else 0)
		var work: int = int(_works_by_pid.get(p.id, -1))
		if fl <= 0 and rail <= 0 and port <= 0 and houses <= 0 and work < 0:
			continue
		var o: Vector2 = p.center + Vector2(0.0, 1.6 * s)
		var x := -0.5 * s * float(_slots(fl, rail, port, houses)) * 1.6
		if houses > 0:
			_houses(o + Vector2(x, 0.0), s, mini(houses, 4))
			x += s * 1.8
		if fl > 0:
			_factory(o + Vector2(x, 0.0), s, fl, FACTORY_COL.get(p.factory, Color(0.6, 0.6, 0.6)))
			x += s * 1.8
		if port > 0:
			_port(o + Vector2(x, 0.0), s)
			x += s * 1.8
		if rail > 0:
			_rail(o + Vector2(-s * 1.2, s * 1.1), s, rail)
		if work >= 0:
			_crane(p.center + Vector2(0.0, -1.6 * s), s, work)
		drawn += 1
		if drawn >= MAX_DRAWN:
			break


func _slots(fl: int, rail: int, port: int, houses: int) -> int:
	return (1 if fl > 0 else 0) + (1 if port > 0 else 0) + (1 if houses > 0 else 0)


func _factory(o: Vector2, s: float, level: int, col: Color) -> void:
	draw_rect(Rect2(o + Vector2(-0.8 * s, -0.7 * s), Vector2(1.6 * s, 1.0 * s)), Color(col, 0.95))
	draw_rect(Rect2(o + Vector2(-0.8 * s, -0.7 * s), Vector2(1.6 * s, 1.0 * s)), Color(0, 0, 0, 0.55), false, 0.12 * s)
	for k in clampi(level, 1, 3):
		var cx: float = (-0.5 + 0.5 * float(k)) * s
		draw_rect(Rect2(o + Vector2(cx - 0.12 * s, -1.5 * s), Vector2(0.24 * s, 0.8 * s)), Color(0.25, 0.22, 0.2, 0.95))
		draw_circle(o + Vector2(cx + 0.1 * s, -1.75 * s), 0.2 * s, Color(0.85, 0.85, 0.85, 0.55))


func _houses(o: Vector2, s: float, n: int) -> void:
	for k in n:
		var hx: float = (float(k) - float(n - 1) * 0.5) * 0.75 * s
		var roof := PackedVector2Array([o + Vector2(hx - 0.35 * s, -0.2 * s), o + Vector2(hx + 0.35 * s, -0.2 * s), o + Vector2(hx, -0.75 * s)])
		draw_rect(Rect2(o + Vector2(hx - 0.3 * s, -0.2 * s), Vector2(0.6 * s, 0.5 * s)), Color(0.93, 0.88, 0.75, 0.95))
		draw_colored_polygon(roof, Color(0.72, 0.30, 0.22, 0.95))


func _port(o: Vector2, s: float) -> void:
	var hull := PackedVector2Array([o + Vector2(-0.8 * s, 0.0), o + Vector2(0.8 * s, 0.0), o + Vector2(0.5 * s, 0.4 * s), o + Vector2(-0.5 * s, 0.4 * s)])
	draw_colored_polygon(hull, Color(0.25, 0.35, 0.55, 0.95))
	draw_line(o + Vector2(0.0, 0.0), o + Vector2(0.0, -1.0 * s), Color(0.2, 0.2, 0.2, 0.95), 0.12 * s)
	draw_colored_polygon(PackedVector2Array([o + Vector2(0.05 * s, -1.0 * s), o + Vector2(0.7 * s, -0.3 * s), o + Vector2(0.05 * s, -0.3 * s)]), Color(0.95, 0.95, 0.9, 0.95))


func _rail(o: Vector2, s: float, level: int) -> void:
	var len: float = (1.6 + 0.8 * float(level)) * s
	draw_line(o, o + Vector2(len, 0.0), Color(0.15, 0.15, 0.15, 0.9), 0.14 * s)
	for k in int(len / (0.35 * s)):
		draw_line(o + Vector2(float(k) * 0.35 * s, -0.12 * s), o + Vector2(float(k) * 0.35 * s, 0.12 * s), Color(0.35, 0.25, 0.15, 0.9), 0.1 * s)


func _crane(o: Vector2, s: float, pct: int) -> void:
	var col := Color(1.0, 0.78, 0.15, 0.95)
	draw_line(o + Vector2(0.0, 0.8 * s), o + Vector2(0.0, -0.9 * s), col, 0.16 * s)
	draw_line(o + Vector2(-0.3 * s, -0.9 * s), o + Vector2(1.0 * s, -0.9 * s), col, 0.16 * s)
	draw_line(o + Vector2(0.9 * s, -0.9 * s), o + Vector2(0.9 * s, -0.2 * s), Color(0.2, 0.2, 0.2, 0.9), 0.08 * s)
	draw_rect(Rect2(o + Vector2(0.75 * s, -0.2 * s), Vector2(0.3 * s, 0.25 * s)), col)
	draw_arc(o + Vector2(0.0, 0.1 * s), 1.2 * s, -PI * 0.5, -PI * 0.5 + TAU * float(clampi(pct, 0, 100)) / 100.0, 24, Color(0.4, 0.95, 0.5, 0.9), 0.2 * s)
