class_name BuildingFx
extends Node2D
## Edifícios no mapa (B26c, F1 detalhada): com bastante zoom, cada província mostra silhuetas vetoriais
## de suas construções, com sombra, fumaça animada, janelas acesas e um segundo nível de detalhe
## (tijolos, telhados, bandeiras) com mais zoom. Mostra fábricas (chaminés = nível, cor/forma = setor),
## cidade (casas, prefeitura, torre do banco), porto com navio balançando, ferrovia com trilhos e
## obras em andamento (guindaste girando + anel de progresso). Só desenha o que está na tela.

const MIN_ZOOM := 2.2
const DETAIL_ZOOM := 3.6        # acima disto entram tijolos, janelas e detalhes finos
const MAX_DRAWN := 160

const FACTORY_COL := {
	"textile": Color(0.70, 0.45, 0.80), "smithy": Color(0.55, 0.55, 0.60), "carpentry": Color(0.62, 0.42, 0.25),
	"steel": Color(0.45, 0.50, 0.60), "paper": Color(0.90, 0.86, 0.70), "machinery": Color(0.35, 0.55, 0.75),
	"glassworks": Color(0.45, 0.85, 0.90), "chemical": Color(0.55, 0.85, 0.40),
}
const WALL_COLS := [Color(0.93, 0.88, 0.75), Color(0.90, 0.80, 0.68), Color(0.85, 0.85, 0.80), Color(0.95, 0.90, 0.80)]
const ROOF_COLS := [Color(0.72, 0.30, 0.22), Color(0.55, 0.30, 0.25), Color(0.35, 0.40, 0.50), Color(0.62, 0.40, 0.25)]

var _timer: Timer
var _works_by_pid: Dictionary = {}     # pid -> progresso (0..100) da obra mais adiantada
var _t: float = 0.0                    # relógio de animação (s)
var _detail: bool = false


func _ready() -> void:
	z_index = 5
	_timer = Timer.new()
	_timer.wait_time = 0.1
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
		_t = float(Time.get_ticks_msec()) * 0.001
		queue_redraw()


func _draw() -> void:
	if not Game.loaded:
		return
	var mv := get_parent() as MapView
	if mv == null or mv.zoom_level < MIN_ZOOM or AppSettings.gfx_quality() < 2:
		return
	var z: float = mv.zoom_level
	_detail = z >= DETAIL_ZOOM and AppSettings.gfx_quality() >= 3
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
		var tower: int = int(p.bld.get("bank", 0)) + int(p.bld.get("city_hall", 0))
		var work: int = int(_works_by_pid.get(p.id, -1))
		if fl <= 0 and rail <= 0 and port <= 0 and houses <= 0 and work < 0:
			continue
		var seed_i: int = p.id * 7919
		var o: Vector2 = p.center + Vector2(0.0, 1.6 * s)
		var slots: int = (1 if fl > 0 else 0) + (1 if port > 0 else 0) + (1 if houses > 0 else 0)
		var x: float = -0.5 * s * float(slots) * 1.8
		if rail > 0:
			_rail(o + Vector2(-s * 1.6, s * 1.15), s, rail)
		if houses > 0:
			_houses(o + Vector2(x, 0.0), s, mini(houses, 5), tower, seed_i)
			x += s * 1.9
		if fl > 0:
			_factory(o + Vector2(x, 0.0), s, fl, str(p.factory), seed_i)
			x += s * 1.9
		if port > 0:
			_port(o + Vector2(x, 0.0), s, port, seed_i)
			x += s * 1.9
		if work >= 0:
			_crane(p.center + Vector2(0.0, -1.7 * s), s, work)
		drawn += 1
		if drawn >= MAX_DRAWN:
			break


func _shadow(o: Vector2, w: float, h: float) -> void:
	draw_colored_polygon(_ellipse(o + Vector2(w * 0.15, h * 0.1), w, h), Color(0, 0, 0, 0.22))


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Fumaça animada: três baforadas que sobem, crescem e somem; o vento desvia levemente.
func _smoke(o: Vector2, s: float, phase: float) -> void:
	for k in 3:
		var f: float = fposmod(_t * 0.55 + phase + float(k) / 3.0, 1.0)
		var pos: Vector2 = o + Vector2(f * 0.9 * s + sin(_t + phase) * 0.1 * s, -f * 1.9 * s)
		draw_circle(pos, (0.18 + 0.38 * f) * s, Color(0.86, 0.86, 0.88, 0.62 * (1.0 - f)))


func _factory(o: Vector2, s: float, level: int, key: String, seed_i: int) -> void:
	var col: Color = FACTORY_COL.get(key, Color(0.6, 0.6, 0.6))
	_shadow(o, 1.5 * s, 0.35 * s)
	var body := Rect2(o + Vector2(-1.1 * s, -1.0 * s), Vector2(2.2 * s, 1.0 * s))
	draw_rect(body, col)
	# Telhado: dente de serra (têxtil, máquinas), plano (resto) ou cúpula (química/vidro).
	if key == "textile" or key == "machinery":
		for k in 3:
			var rx: float = -1.1 * s + 0.73 * s * float(k)
			draw_colored_polygon(PackedVector2Array([o + Vector2(rx, -1.0 * s), o + Vector2(rx + 0.73 * s, -1.0 * s), o + Vector2(rx + 0.73 * s, -1.35 * s)]), col.darkened(0.25))
	elif key == "chemical" or key == "glassworks":
		draw_colored_polygon(_ellipse(o + Vector2(0.0, -1.0 * s), 0.9 * s, 0.4 * s), col.lightened(0.15))
	else:
		draw_rect(Rect2(o + Vector2(-1.2 * s, -1.12 * s), Vector2(2.4 * s, 0.14 * s)), col.darkened(0.35))
	draw_rect(body, Color(0, 0, 0, 0.5), false, 0.1 * s)
	# Janelas acesas (piscam levemente).
	var glow: float = 0.75 + 0.25 * sin(_t * 2.0 + float(seed_i % 7))
	for k in 3:
		draw_rect(Rect2(o + Vector2((-0.85 + 0.55 * float(k)) * s, -0.75 * s), Vector2(0.28 * s, 0.3 * s)), Color(1.0, 0.92, 0.55, glow))
	draw_rect(Rect2(o + Vector2(-0.2 * s, -0.35 * s), Vector2(0.4 * s, 0.35 * s)), Color(0.15, 0.1, 0.08))     # portão
	if _detail:
		for k in 5:
			draw_line(o + Vector2(-1.1 * s, (-0.92 + 0.19 * float(k)) * s), o + Vector2(1.1 * s, (-0.92 + 0.19 * float(k)) * s), Color(0, 0, 0, 0.12), 0.04 * s)
	# Chaminés: uma por nível, cada uma com sua fumaça.
	for k in clampi(level, 1, 3):
		var cx: float = (-0.7 + 0.7 * float(k - 1)) * s
		draw_rect(Rect2(o + Vector2(cx - 0.14 * s, -2.1 * s), Vector2(0.28 * s, 1.1 * s)), Color(0.32, 0.26, 0.24))
		draw_rect(Rect2(o + Vector2(cx - 0.18 * s, -2.14 * s), Vector2(0.36 * s, 0.1 * s)), Color(0.2, 0.17, 0.16))
		_smoke(o + Vector2(cx, -2.15 * s), s, float(k) * 0.37 + float(seed_i % 5) * 0.11)


func _houses(o: Vector2, s: float, n: int, tower: int, seed_i: int) -> void:
	_shadow(o, 1.3 * s, 0.3 * s)
	for k in n:
		var v: int = (seed_i + k * 13) % 4
		var hx: float = (float(k) - float(n - 1) * 0.5) * 0.85 * s
		var hh: float = (0.7 + 0.18 * float((seed_i + k) % 3)) * s
		draw_rect(Rect2(o + Vector2(hx - 0.35 * s, -hh), Vector2(0.7 * s, hh)), WALL_COLS[v])
		draw_colored_polygon(PackedVector2Array([o + Vector2(hx - 0.46 * s, -hh), o + Vector2(hx + 0.46 * s, -hh), o + Vector2(hx, -hh - 0.48 * s)]), ROOF_COLS[v])
		draw_rect(Rect2(o + Vector2(hx - 0.08 * s, -0.35 * s), Vector2(0.16 * s, 0.35 * s)), Color(0.4, 0.26, 0.16))
		if _detail:
			draw_rect(Rect2(o + Vector2(hx + 0.12 * s, -hh + 0.15 * s), Vector2(0.14 * s, 0.14 * s)), Color(0.55, 0.75, 0.9))
			draw_rect(Rect2(o + Vector2(hx - 0.27 * s, -hh + 0.15 * s), Vector2(0.14 * s, 0.14 * s)), Color(0.55, 0.75, 0.9))
			draw_rect(Rect2(o + Vector2(hx + 0.18 * s, -hh - 0.5 * s), Vector2(0.08 * s, 0.22 * s)), Color(0.3, 0.25, 0.22))    # chaminé
	if tower > 0:
		var tx: float = float(n) * 0.5 * 0.85 * s + 0.25 * s
		draw_rect(Rect2(o + Vector2(tx - 0.2 * s, -1.6 * s), Vector2(0.4 * s, 1.6 * s)), Color(0.82, 0.78, 0.70))
		draw_colored_polygon(PackedVector2Array([o + Vector2(tx - 0.28 * s, -1.6 * s), o + Vector2(tx + 0.28 * s, -1.6 * s), o + Vector2(tx, -2.1 * s)]), Color(0.35, 0.40, 0.50))
		draw_circle(o + Vector2(tx, -1.3 * s), 0.12 * s, Color(1.0, 1.0, 0.9))                       # relógio
		draw_line(o + Vector2(tx, -1.3 * s), o + Vector2(tx, -1.2 * s), Color(0.1, 0.1, 0.1), 0.03 * s + 0.4)


func _port(o: Vector2, s: float, level: int, seed_i: int) -> void:
	var bob: float = sin(_t * 1.6 + float(seed_i % 9)) * 0.08 * s
	draw_rect(Rect2(o + Vector2(-1.2 * s, 0.05 * s), Vector2(2.4 * s, 0.4 * s)), Color(0.18, 0.34, 0.58, 0.9))
	for k in 3:                                                                                    # ondas
		var wx: float = (-0.8 + 0.8 * float(k)) * s
		draw_arc(o + Vector2(wx, 0.28 * s + bob), 0.25 * s, PI * 1.1, PI * 1.9, 6, Color(1, 1, 1, 0.45), 0.05 * s + 0.3)
	draw_rect(Rect2(o + Vector2(-1.2 * s, -0.05 * s), Vector2(0.5 * s, 0.14 * s)), Color(0.45, 0.32, 0.2))     # cais
	var hull := PackedVector2Array([o + Vector2(-0.6 * s, bob), o + Vector2(0.9 * s, bob), o + Vector2(0.6 * s, 0.4 * s + bob), o + Vector2(-0.4 * s, 0.4 * s + bob)])
	draw_colored_polygon(hull, Color(0.30, 0.22, 0.18))
	draw_line(o + Vector2(0.1 * s, bob), o + Vector2(0.1 * s, -1.3 * s + bob), Color(0.25, 0.2, 0.15), 0.1 * s + 0.3)
	for m in mini(level, 2):
		var mx: float = 0.1 * s + float(m) * 0.45 * s
		draw_colored_polygon(PackedVector2Array([o + Vector2(mx + 0.05 * s, -1.25 * s + bob), o + Vector2(mx + 0.55 * s, -0.4 * s + bob), o + Vector2(mx + 0.05 * s, -0.4 * s + bob)]), Color(0.96, 0.95, 0.9))
		if m == 1:
			draw_line(o + Vector2(mx, bob), o + Vector2(mx, -0.9 * s + bob), Color(0.25, 0.2, 0.15), 0.08 * s + 0.2)
	if _detail:
		draw_rect(Rect2(o + Vector2(-1.15 * s, -0.55 * s), Vector2(0.35 * s, 0.5 * s)), Color(0.6, 0.45, 0.28))   # caixotes
		draw_rect(Rect2(o + Vector2(-0.95 * s, -0.8 * s), Vector2(0.3 * s, 0.25 * s)), Color(0.7, 0.55, 0.35))


func _rail(o: Vector2, s: float, level: int) -> void:
	var len: float = (1.8 + 0.9 * float(level)) * s
	draw_line(o + Vector2(0.0, -0.06 * s), o + Vector2(len, -0.06 * s), Color(0.55, 0.55, 0.58, 0.95), 0.07 * s + 0.3)
	draw_line(o + Vector2(0.0, 0.07 * s), o + Vector2(len, 0.07 * s), Color(0.55, 0.55, 0.58, 0.95), 0.07 * s + 0.3)
	for k in int(len / (0.32 * s)):
		var tx: float = float(k) * 0.32 * s
		draw_line(o + Vector2(tx, -0.13 * s), o + Vector2(tx, 0.13 * s), Color(0.38, 0.26, 0.15, 0.95), 0.07 * s + 0.2)
	if _detail:                                                                                    # trem passando
		var f: float = fposmod(_t * 0.18 + float(level) * 0.3, 1.0)
		var tp: Vector2 = o + Vector2(f * len, -0.3 * s)
		draw_rect(Rect2(tp + Vector2(-0.3 * s, -0.12 * s), Vector2(0.6 * s, 0.34 * s)), Color(0.28, 0.28, 0.32))
		draw_rect(Rect2(tp + Vector2(0.1 * s, -0.32 * s), Vector2(0.14 * s, 0.22 * s)), Color(0.2, 0.2, 0.22))
		draw_circle(tp + Vector2(0.17 * s, -0.4 * s - f * 0.2 * s), 0.12 * s, Color(0.9, 0.9, 0.9, 0.5))


func _crane(o: Vector2, s: float, pct: int) -> void:
	var col := Color(1.0, 0.78, 0.15, 0.97)
	var sw: float = sin(_t * 0.7) * 0.25 * s                                  # a lança gira devagar
	draw_rect(Rect2(o + Vector2(-0.55 * s, 0.55 * s), Vector2(1.1 * s, 0.25 * s)), Color(0.4, 0.4, 0.42, 0.9))
	draw_line(o + Vector2(0.0, 0.55 * s), o + Vector2(0.0, -0.95 * s), col, 0.16 * s + 0.3)
	for k in 4:                                                               # treliça da torre
		var ty: float = 0.55 * s - float(k) * 0.38 * s
		draw_line(o + Vector2(-0.12 * s, ty), o + Vector2(0.12 * s, ty - 0.38 * s), col.darkened(0.25), 0.04 * s + 0.2)
	draw_line(o + Vector2(-0.4 * s, -0.95 * s), o + Vector2(1.1 * s + sw, -0.95 * s), col, 0.14 * s + 0.3)
	draw_line(o + Vector2(0.0, -1.3 * s), o + Vector2(1.1 * s + sw, -0.95 * s), col.darkened(0.2), 0.04 * s + 0.2)
	draw_line(o + Vector2(1.0 * s + sw, -0.95 * s), o + Vector2(1.0 * s + sw, -0.3 * s), Color(0.2, 0.2, 0.2, 0.9), 0.05 * s + 0.2)
	draw_rect(Rect2(o + Vector2(0.86 * s + sw, -0.3 * s), Vector2(0.28 * s, 0.22 * s)), Color(0.7, 0.45, 0.2))
	draw_arc(o + Vector2(0.0, -0.2 * s), 1.3 * s, -PI * 0.5, -PI * 0.5 + TAU * float(clampi(pct, 0, 100)) / 100.0, 28, Color(0.4, 0.95, 0.5, 0.95), 0.18 * s + 0.5)
	if _detail:
		draw_string(ThemeDB.fallback_font, o + Vector2(-0.35 * s, 1.3 * s), "%d%%" % pct, HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(2.0, 1.6 * s)), Color(1, 1, 1, 0.95))
