class_name ProvinceScene
extends Control
## Cena ilustrada da província (B26c): céu e solo conforme o terreno, e silhuetas vetoriais de
## cada construção (fábrica com chaminés = nível, mina, fazenda, madeireira, casas, porto, escola,
## hospital, estação, ferrovia) e de obras em andamento (guindaste com anel de progresso).

const SKY := {
	"plains": [Color(0.55, 0.75, 0.92), Color(0.78, 0.88, 0.95)], "forest": [Color(0.45, 0.65, 0.80), Color(0.70, 0.84, 0.88)],
	"hills": [Color(0.60, 0.72, 0.88), Color(0.82, 0.86, 0.90)], "mountains": [Color(0.50, 0.62, 0.82), Color(0.80, 0.84, 0.92)],
	"desert": [Color(0.95, 0.80, 0.55), Color(0.98, 0.90, 0.72)], "jungle": [Color(0.42, 0.68, 0.72), Color(0.68, 0.85, 0.80)],
	"tundra": [Color(0.70, 0.78, 0.88), Color(0.90, 0.93, 0.96)], "marsh": [Color(0.58, 0.72, 0.80), Color(0.80, 0.86, 0.86)],
}
const GROUND := {
	"plains": Color(0.45, 0.62, 0.30), "forest": Color(0.25, 0.45, 0.25), "hills": Color(0.52, 0.55, 0.32),
	"mountains": Color(0.45, 0.45, 0.45), "desert": Color(0.80, 0.68, 0.40), "jungle": Color(0.20, 0.50, 0.28),
	"tundra": Color(0.78, 0.82, 0.85), "marsh": Color(0.38, 0.52, 0.38),
}
const FACTORY_COL := {
	"textile": Color(0.70, 0.45, 0.80), "smithy": Color(0.55, 0.55, 0.60), "carpentry": Color(0.62, 0.42, 0.25),
	"steel": Color(0.45, 0.50, 0.60), "paper": Color(0.90, 0.86, 0.70), "machinery": Color(0.35, 0.55, 0.75),
	"glassworks": Color(0.45, 0.85, 0.90), "chemical": Color(0.55, 0.85, 0.40),
}

var _terrain: String = "plains"
var _sprites: Array = []      # [tipo, nível, cor]
var _work_pct: int = -1
var _rail: int = 0
var _t: float = 0.0
var _winter: bool = false
var _seed: int = 0
var _timer: Timer


func _init() -> void:
	custom_minimum_size = Vector2(0, 124)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 0.1
	_timer.timeout.connect(func():
		if is_visible_in_tree() and AppSettings.gfx_quality() >= 1:
			_t = float(Time.get_ticks_msec()) * 0.001
			queue_redraw())
	add_child(_timer)
	_timer.start()


func set_province(p: Province) -> void:
	_terrain = p.terrain
	_seed = p.id * 31
	_winter = Game.loaded and (Game.clock.month >= 11 or Game.clock.month <= 2)
	_sprites.clear()
	_rail = int(p.bld.get("railway", 0))
	if p.factory != "" and p.factory_level > 0:
		_sprites.append(["factory", p.factory_level, FACTORY_COL.get(p.factory, Color(0.6, 0.6, 0.6))])
	for k in ["mine", "farm", "logging"]:
		if int(p.bld.get(k, 0)) > 0:
			_sprites.append([k, int(p.bld[k]), Color.WHITE])
	var houses: int = int(p.bld.get("market", 0)) + int(p.bld.get("housing", 0)) + int(p.bld.get("city_hall", 0)) + int(p.bld.get("bank", 0)) + (2 if p.capital_city else 0)
	if houses > 0:
		_sprites.append(["houses", houses, Color.WHITE])
	if int(p.bld.get("school", 0)) + int(p.bld.get("university", 0)) > 0:
		_sprites.append(["school", int(p.bld.get("school", 0)) + int(p.bld.get("university", 0)), Color.WHITE])
	if int(p.bld.get("hospital", 0)) > 0:
		_sprites.append(["hospital", int(p.bld["hospital"]), Color.WHITE])
	if int(p.bld.get("dock", 0)) + int(p.bld.get("shipyard", 0)) > 0:
		_sprites.append(["port", int(p.bld.get("dock", 0)) + int(p.bld.get("shipyard", 0)), Color.WHITE])
	if int(p.bld.get("station", 0)) > 0:
		_sprites.append(["station", int(p.bld["station"]), Color.WHITE])
	_work_pct = -1
	if p.owner_id >= 0 and p.owner_id < Game.countries.size():
		for w in Game.countries[p.owner_id].works:
			if int(w[0]) == p.id:
				_work_pct = maxi(_work_pct, int(w[3]) * 100 / maxi(1, int(w[4])))
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 10.0:
		return
	var sky: Array = SKY.get(_terrain, SKY["plains"])
	var top: Color = sky[0]
	var bot: Color = sky[1]
	for i in 8:
		var f: float = float(i) / 7.0
		draw_rect(Rect2(0.0, h * 0.72 * float(i) / 8.0, w, h * 0.72 / 8.0 + 1.0), top.lerp(bot, f))
	var base: float = h * 0.74
	# Sol (dia) com raios que giram devagar e nuvens que derivam.
	var sun := Vector2(w * (0.82 - 0.04 * float(_seed % 3)), h * 0.17)
	draw_circle(sun, h * 0.075, Color(1.0, 0.95, 0.65, 0.95))
	draw_circle(sun, h * 0.115, Color(1.0, 0.95, 0.65, 0.22))
	for k in 8:
		var a: float = _t * 0.2 + TAU * float(k) / 8.0
		draw_line(sun + Vector2(cos(a), sin(a)) * h * 0.13, sun + Vector2(cos(a), sin(a)) * h * 0.17, Color(1.0, 0.95, 0.65, 0.35), 1.5)
	for k in 3:
		var cx: float = fposmod(w * (0.2 + 0.33 * float(k)) + _t * (5.0 + 3.0 * float(k)), w + 80.0) - 40.0
		var cy: float = h * (0.12 + 0.08 * float(k))
		for q in 3:
			draw_circle(Vector2(cx + float(q) * 12.0 - 12.0, cy + (3.0 if q == 1 else 0.0)), 8.0 + float(q % 2) * 3.0, Color(1, 1, 1, 0.55))
	# Relevo em duas camadas (fundo azulado, frente mais escura), com neve no inverno.
	if _terrain == "mountains" or _terrain == "hills" or _terrain == "tundra":
		var amp: float = 0.34 if _terrain == "mountains" else 0.2
		var far := PackedVector2Array([Vector2(0.0, base)])
		for k in 9:
			far.append(Vector2(w * float(k) / 8.0, base - h * amp * (0.45 + 0.55 * absf(sin(float(k) * 1.7 + float(_seed % 5))))))
		far.append(Vector2(w, base))
		draw_colored_polygon(far, Color(0.55, 0.60, 0.72, 0.55))
		var near := PackedVector2Array([Vector2(0.0, base)])
		for k in 7:
			near.append(Vector2(w * float(k) / 6.0, base - h * amp * 0.75 * (0.35 + 0.65 * absf(sin(float(k) * 2.3 + 1.0 + float(_seed % 7))))))
		near.append(Vector2(w, base))
		draw_colored_polygon(near, Color(0.42, 0.45, 0.50, 0.75))
		if _winter or _terrain == "tundra":
			for k in 7:
				var pk: Vector2 = near[k + 1]
				draw_colored_polygon(PackedVector2Array([pk, pk + Vector2(-9.0, 12.0), pk + Vector2(9.0, 12.0)]), Color(1, 1, 1, 0.85))
	draw_rect(Rect2(0.0, base, w, h - base), GROUND.get(_terrain, Color(0.45, 0.6, 0.3)))
	draw_line(Vector2(0.0, base), Vector2(w, base), Color(0, 0, 0, 0.25), 1.5)
	if _winter and _terrain != "desert" and _terrain != "jungle":
		draw_rect(Rect2(0.0, base, w, h * 0.05), Color(1, 1, 1, 0.55))
	# Relva, pedras e uma estradinha de terra ao longo da base.
	draw_line(Vector2(0.0, base + h * 0.075), Vector2(w, base + h * 0.075), Color(0.55, 0.45, 0.30, 0.55), 5.0)
	for k in 14:
		var gx: float = w * float((k * 37 + _seed) % 100) / 100.0
		var gy: float = base + h * (0.1 + 0.015 * float(k % 4))
		draw_line(Vector2(gx, gy), Vector2(gx + sin(_t * 1.5 + float(k)) * 1.5, gy - 5.0), Color(0.25, 0.45, 0.18, 0.8), 1.4)
	# Pássaros.
	var bx: float = fposmod(_t * 14.0 + float(_seed % 50), w + 40.0) - 20.0
	var by: float = h * 0.28 + sin(_t * 1.1) * 4.0
	var fl: float = 3.0 * sin(_t * 9.0)
	draw_line(Vector2(bx - 5.0, by - fl), Vector2(bx, by), Color(0.15, 0.15, 0.2, 0.8), 1.4)
	draw_line(Vector2(bx + 5.0, by - fl), Vector2(bx, by), Color(0.15, 0.15, 0.2, 0.8), 1.4)
	if _rail > 0:
		draw_line(Vector2(0.0, base + h * 0.12), Vector2(w, base + h * 0.12), Color(0.2, 0.2, 0.2, 0.9), 2.0)
		var n: int = int(w / 14.0)
		for k in n:
			draw_line(Vector2(float(k) * 14.0, base + h * 0.09), Vector2(float(k) * 14.0, base + h * 0.15), Color(0.4, 0.28, 0.16, 0.9), 2.0)
	var count: int = _sprites.size() + (1 if _work_pct >= 0 else 0)
	if count == 0:
		for k in 5:
			var tx: float = w * (0.15 + 0.17 * float(k))
			draw_line(Vector2(tx, base + 2.0), Vector2(tx, base - 8.0), Color(0.3, 0.5, 0.2, 0.9), 2.0)
		return
	var slot: float = w / float(count)
	var s: float = minf(h * 0.30, slot * 0.34)
	var i := 0
	for sp in _sprites:
		var o := Vector2(slot * (float(i) + 0.5), base)
		match str(sp[0]):
			"factory": _factory(o, s, int(sp[1]), sp[2])
			"mine": _mine(o, s)
			"farm": _farm(o, s, int(sp[1]))
			"logging": _trees(o, s)
			"houses": _houses(o, s, mini(int(sp[1]), 5))
			"school": _school(o, s)
			"hospital": _hospital(o, s)
			"port": _port(o, s)
			"station": _station(o, s)
		i += 1
	if _work_pct >= 0:
		_crane(Vector2(slot * (float(i) + 0.5), base), s, _work_pct)


func _factory(o: Vector2, s: float, level: int, col: Color) -> void:
	draw_rect(Rect2(o + Vector2(-1.1 * s, -1.0 * s), Vector2(2.2 * s, 1.0 * s)), col)
	draw_rect(Rect2(o + Vector2(-1.1 * s, -1.0 * s), Vector2(2.2 * s, 1.0 * s)), Color(0, 0, 0, 0.5), false, 1.2)
	for k in 3:
		draw_rect(Rect2(o + Vector2((-0.8 + 0.5 * float(k)) * s, -0.75 * s), Vector2(0.28 * s, 0.3 * s)), Color(1.0, 0.92, 0.55, 0.75 + 0.25 * sin(_t * 2.0 + float(k))))
	for k in clampi(level, 1, 3):
		var cx: float = (-0.7 + 0.7 * float(k - 1)) * s
		draw_rect(Rect2(o + Vector2(cx - 0.14 * s, -2.1 * s), Vector2(0.28 * s, 1.1 * s)), Color(0.28, 0.24, 0.22))
		for q in 4:
			var f: float = fposmod(_t * 0.5 + float(k) * 0.31 + float(q) / 4.0, 1.0)
			draw_circle(o + Vector2(cx + (0.15 + 0.9 * f) * s + sin(_t + float(q)) * 0.1 * s, -2.2 * s - f * 1.6 * s), (0.2 + 0.35 * f) * s, Color(0.9, 0.9, 0.92, 0.65 * (1.0 - f)))


func _mine(o: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([o + Vector2(-0.9 * s, 0.0), o + Vector2(0.0, -1.0 * s), o + Vector2(0.9 * s, 0.0)]), Color(0.42, 0.40, 0.40))
	draw_rect(Rect2(o + Vector2(-0.25 * s, -0.5 * s), Vector2(0.5 * s, 0.5 * s)), Color(0.1, 0.08, 0.08))
	draw_line(o + Vector2(0.5 * s, -0.4 * s), o + Vector2(0.9 * s, -1.3 * s), Color(0.3, 0.22, 0.12), 2.0)
	draw_circle(o + Vector2(0.9 * s, -1.3 * s), 0.2 * s, Color(0.3, 0.22, 0.12))


func _farm(o: Vector2, s: float, level: int) -> void:
	for k in clampi(level, 1, 3) + 2:
		var fx: float = (-1.0 + 0.5 * float(k)) * s
		draw_rect(Rect2(o + Vector2(fx, -0.35 * s), Vector2(0.42 * s, 0.35 * s)), Color(0.86, 0.75, 0.30) if k % 2 == 0 else Color(0.62, 0.75, 0.30))
	draw_rect(Rect2(o + Vector2(-0.3 * s, -1.0 * s), Vector2(0.6 * s, 0.6 * s)), Color(0.72, 0.30, 0.22))
	draw_colored_polygon(PackedVector2Array([o + Vector2(-0.4 * s, -1.0 * s), o + Vector2(0.4 * s, -1.0 * s), o + Vector2(0.0, -1.4 * s)]), Color(0.4, 0.2, 0.15))


func _trees(o: Vector2, s: float) -> void:
	for k in 3:
		var tx: float = (-0.7 + 0.7 * float(k)) * s
		draw_rect(Rect2(o + Vector2(tx - 0.07 * s, -0.4 * s), Vector2(0.14 * s, 0.4 * s)), Color(0.35, 0.22, 0.1))
		var sw: float = sin(_t * 1.3 + float(k) * 1.7) * 0.07 * s
		draw_colored_polygon(PackedVector2Array([o + Vector2(tx - 0.4 * s, -0.35 * s), o + Vector2(tx + 0.4 * s, -0.35 * s), o + Vector2(tx + sw, -1.3 * s)]), Color(0.95, 0.97, 1.0) if _winter else Color(0.15, 0.42, 0.2))
		draw_colored_polygon(PackedVector2Array([o + Vector2(tx - 0.3 * s, -0.75 * s), o + Vector2(tx + 0.3 * s, -0.75 * s), o + Vector2(tx + sw, -1.5 * s)]), Color(0.18, 0.5, 0.24) if not _winter else Color(0.9, 0.93, 0.97))


func _houses(o: Vector2, s: float, n: int) -> void:
	for k in n:
		var hx: float = (float(k) - float(n - 1) * 0.5) * 0.85 * s
		var hh: float = (0.7 + 0.15 * float(k % 2)) * s
		draw_rect(Rect2(o + Vector2(hx - 0.35 * s, -hh), Vector2(0.7 * s, hh)), Color(0.93, 0.88, 0.75))
		draw_colored_polygon(PackedVector2Array([o + Vector2(hx - 0.45 * s, -hh), o + Vector2(hx + 0.45 * s, -hh), o + Vector2(hx, -hh - 0.45 * s)]), Color(0.72, 0.30, 0.22))
		draw_rect(Rect2(o + Vector2(hx - 0.08 * s, -0.35 * s), Vector2(0.16 * s, 0.35 * s)), Color(0.4, 0.26, 0.16))


func _school(o: Vector2, s: float) -> void:
	draw_rect(Rect2(o + Vector2(-0.8 * s, -0.8 * s), Vector2(1.6 * s, 0.8 * s)), Color(0.85, 0.78, 0.62))
	draw_colored_polygon(PackedVector2Array([o + Vector2(-0.9 * s, -0.8 * s), o + Vector2(0.9 * s, -0.8 * s), o + Vector2(0.0, -1.35 * s)]), Color(0.55, 0.35, 0.25))
	draw_line(o + Vector2(0.0, -1.35 * s), o + Vector2(0.0, -1.9 * s), Color(0.2, 0.2, 0.2), 1.5)
	draw_rect(Rect2(o + Vector2(0.0, -1.9 * s), Vector2(0.5 * s, 0.3 * s)), Color(0.8, 0.2, 0.2))


func _hospital(o: Vector2, s: float) -> void:
	draw_rect(Rect2(o + Vector2(-0.8 * s, -1.0 * s), Vector2(1.6 * s, 1.0 * s)), Color(0.95, 0.95, 0.95))
	draw_rect(Rect2(o + Vector2(-0.12 * s, -0.85 * s), Vector2(0.24 * s, 0.6 * s)), Color(0.85, 0.15, 0.15))
	draw_rect(Rect2(o + Vector2(-0.3 * s, -0.67 * s), Vector2(0.6 * s, 0.24 * s)), Color(0.85, 0.15, 0.15))


func _port(o: Vector2, s: float) -> void:
	draw_rect(Rect2(o + Vector2(-1.1 * s, 0.0), Vector2(2.2 * s, 0.35 * s)), Color(0.2, 0.38, 0.62))
	for k in 3:
		draw_arc(o + Vector2((-0.7 + 0.7 * float(k)) * s, 0.17 * s), 0.22 * s, PI * 1.1, PI * 1.9, 6, Color(1, 1, 1, 0.5), 1.2)
	o.y += sin(_t * 1.6) * 0.07 * s
	draw_colored_polygon(PackedVector2Array([o + Vector2(-0.7 * s, -0.1 * s), o + Vector2(0.8 * s, -0.1 * s), o + Vector2(0.5 * s, 0.3 * s), o + Vector2(-0.5 * s, 0.3 * s)]), Color(0.3, 0.22, 0.18))
	draw_line(o + Vector2(0.0, -0.1 * s), o + Vector2(0.0, -1.3 * s), Color(0.25, 0.2, 0.15), 2.0)
	draw_colored_polygon(PackedVector2Array([o + Vector2(0.06 * s, -1.25 * s), o + Vector2(0.7 * s, -0.4 * s), o + Vector2(0.06 * s, -0.4 * s)]), Color(0.96, 0.95, 0.9))


func _station(o: Vector2, s: float) -> void:
	draw_rect(Rect2(o + Vector2(-1.0 * s, -0.7 * s), Vector2(2.0 * s, 0.7 * s)), Color(0.55, 0.4, 0.3))
	draw_rect(Rect2(o + Vector2(-1.15 * s, -0.8 * s), Vector2(2.3 * s, 0.14 * s)), Color(0.3, 0.2, 0.15))
	draw_circle(o + Vector2(0.0, -1.1 * s), 0.3 * s, Color(0.95, 0.95, 0.9))
	draw_line(o + Vector2(0.0, -1.1 * s), o + Vector2(0.0, -1.3 * s), Color(0.2, 0.2, 0.2), 1.2)


func _crane(o: Vector2, s: float, pct: int) -> void:
	var col := Color(1.0, 0.78, 0.15)
	draw_rect(Rect2(o + Vector2(-0.6 * s, -0.35 * s), Vector2(1.2 * s, 0.35 * s)), Color(0.62, 0.5, 0.35))
	draw_line(o + Vector2(0.0, 0.0), o + Vector2(0.0, -1.9 * s), col, 3.0)
	var swc: float = sin(_t * 0.8) * 0.25 * s
	draw_line(o + Vector2(-0.5 * s, -1.9 * s), o + Vector2(1.2 * s + swc, -1.9 * s), col, 3.0)
	draw_line(o + Vector2(1.0 * s + swc, -1.9 * s), o + Vector2(1.0 * s + swc, -1.2 * s), Color(0.2, 0.2, 0.2), 1.2)
	draw_rect(Rect2(o + Vector2(0.85 * s + swc, -1.2 * s), Vector2(0.3 * s, 0.25 * s)), col)
	draw_arc(o + Vector2(0.0, -0.9 * s), 1.2 * s, -PI * 0.5, -PI * 0.5 + TAU * float(clampi(pct, 0, 100)) / 100.0, 28, Color(0.35, 0.95, 0.5, 0.95), 3.0)
