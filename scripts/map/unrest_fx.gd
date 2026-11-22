class_name UnrestFx
extends Node2D
## Efeitos de agitação sobre o mapa (B18): províncias com rebeldes pulsam em vermelho, as propensas
## à revolução em âmbar, e protestos/greves ganham um marcador laranja. Redesenha ~8x/s só quando
## há algo para mostrar.

const MAX_ITEMS := 500

var _flash: Array = []     # [centro, tipo, idade em meses] de golpes/revoluções recentes
var _items: Array = []     # [pid, tier] tier 1 = protesto, 2 = propensa, 3 = rebelde
var _timer: Timer


func _ready() -> void:
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
	_items.clear()
	_flash.clear()
	if not Game.loaded:
		return
	var now: int = Game.clock.year * 12 + Game.clock.month
	for ce in Game.chronicle:
		var age: int = now - (int(ce[0]) * 12 + int(ce[1]))
		var cc: int = int(ce[2])
		if age >= 0 and age <= 2 and cc >= 0 and cc < Game.countries.size():
			var cap: int = Game.countries[cc].capital
			if cap >= 0 and cap < Game.provinces.size():
				_flash.append([Game.provinces[cap].center, int(ce[3]), age])
	for p in Game.provinces:
		if p.owner_id < 0 or p.unrest < Game.UNREST_PROTEST:
			continue
		var tier := 1
		if p.unrest >= Game.UNREST_REBEL:
			tier = 3
		elif p.unrest >= Game.UNREST_PRONE:
			tier = 2
		_items.append([p.id, tier])
		if _items.size() >= MAX_ITEMS:
			break
	queue_redraw()


func _tick() -> void:
	if (not _items.is_empty() or not _flash.is_empty()) and is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if (_items.is_empty() and _flash.is_empty()) or not Game.loaded:
		return
	var mv := get_parent() as MapView
	var z := maxf(mv.zoom_level if mv != null else 1.0, 0.05)
	var t := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
	for fl in _flash:
		var fc: Vector2 = fl[0]
		var fcol := Color(0.55, 0.62, 0.95, 0.9) if int(fl[1]) == 1 else (Color(0.30, 0.95, 0.70, 0.95) if int(fl[1]) == 3 else (Color(1.0, 0.15, 0.10, 1.0) if int(fl[1]) == 4 else Color(1.0, 0.82, 0.25, 0.95)))
		fcol.a *= 1.0 - float(int(fl[2])) * 0.3
		for k in 3:
			var rr := (14.0 + 16.0 * float(k) + 10.0 * t) / z
			draw_arc(fc, rr, 0.0, TAU, 36, Color(fcol, fcol.a * (1.0 - float(k) * 0.28)), 2.6 / z)
		draw_circle(fc, 5.0 / z, fcol)
	for it in _items:
		var p: Province = Game.provinces[int(it[0])]
		var tier: int = int(it[1])
		var col := Color(0.95, 0.55, 0.12, 0.55)
		var w := 1.6
		if tier == 2:
			col = Color(1.0, 0.80, 0.20, 0.45 + 0.4 * t)
			w = 2.2
		elif tier == 3:
			col = Color(1.0, 0.16, 0.10, 0.55 + 0.45 * t)
			w = 3.0
		if tier >= 2 and p.poly.size() > 2:
			var ring: PackedVector2Array = p.poly.duplicate()
			ring.append(p.poly[0])
			draw_polyline(ring, col, w / z)
		var r := (5.0 + 3.0 * t * float(tier - 1)) / z
		var c := p.center
		if tier == 3:
			draw_circle(c, r * 1.8, Color(1.0, 0.1, 0.05, 0.18 * t + 0.08))
			draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, 2.4 / z)      # espadas cruzadas
			draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, 2.4 / z)
		elif tier == 2:
			draw_arc(c, r, 0.0, TAU, 20, col, 1.8 / z)
		else:
			draw_circle(c, 3.0 / z, col)
