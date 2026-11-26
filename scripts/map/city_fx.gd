class_name CityFx
extends Node2D
## Cidades no mapa (F3): províncias com cidade ganham uma silhueta cuja altura e largura crescem
## com a população (4 portes); capitais têm cúpula de palácio e bandeira do país. Aparece a partir
## de zoom médio; só desenha o que está na tela.

const MIN_ZOOM := 1.5
const MAX_DRAWN := 140
const TIER_POP := [700000, 1500000, 3000000]

var _timer: Timer
var _t: float = 0.0


func _ready() -> void:
	z_index = 4
	_timer = Timer.new()
	_timer.wait_time = 0.2
	_timer.timeout.connect(func():
		var mv := get_parent() as MapView
		if mv != null and mv.zoom_level >= MIN_ZOOM and is_visible_in_tree():
			_t = float(Time.get_ticks_msec()) * 0.001
			queue_redraw())
	add_child(_timer)
	_timer.start()
	Events.state_loaded.connect(queue_redraw)
	Events.month_changed.connect(func(_d): queue_redraw())


func tier_of(pop: int) -> int:
	var t := 0
	for lim in TIER_POP:
		if pop >= int(lim):
			t += 1
	return t


func _draw() -> void:
	if not Game.loaded:
		return
	var mv := get_parent() as MapView
	if mv == null or mv.zoom_level < MIN_ZOOM or AppSettings.gfx_quality() < 2:
		return
	var z: float = mv.zoom_level
	var s: float = 7.0 / z
	var view: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
	var drawn := 0
	for p in Game.provinces:
		if p.city == "" or p.owner_id < 0 or not view.has_point(p.center):
			continue
		var tier: int = tier_of(p.population)
		var o: Vector2 = p.center + Vector2(0.0, -2.6 * s if z >= 2.2 else 0.9 * s)
		var n: int = 3 + tier * 2
		draw_colored_polygon(_ell(o + Vector2(0.0, 0.05 * s), (0.45 * float(n) + 0.5) * s * 0.8, 0.28 * s), Color(0, 0, 0, 0.22))
		for k in n:
			var hh: float = (0.6 + 0.35 * float((p.id * 5 + k * 3) % 4) + 0.25 * float(tier)) * s
			if k == n / 2:
				hh += 0.5 * s
			var bx: float = (float(k) - float(n - 1) * 0.5) * 0.62 * s
			var wall := Color(0.86, 0.82, 0.74).darkened(0.05 * float(k % 3))
			draw_rect(Rect2(o + Vector2(bx - 0.27 * s, -hh), Vector2(0.54 * s, hh)), wall)
			draw_rect(Rect2(o + Vector2(bx - 0.27 * s, -hh), Vector2(0.54 * s, hh)), Color(0, 0, 0, 0.35), false, 0.04 * s + 0.2)
			var roof := Color(0.62, 0.28, 0.22) if k % 2 == 0 else Color(0.34, 0.38, 0.48)
			draw_colored_polygon(PackedVector2Array([o + Vector2(bx - 0.31 * s, -hh), o + Vector2(bx + 0.31 * s, -hh), o + Vector2(bx, -hh - 0.3 * s)]), roof)
			if tier >= 1 and z >= 2.0:
				draw_rect(Rect2(o + Vector2(bx - 0.08 * s, -hh + 0.2 * s), Vector2(0.16 * s, 0.16 * s)), Color(1.0, 0.92, 0.55, 0.85))
		if p.capital_city:
			var cc: Color = Game.countries[p.owner_id].color
			draw_colored_polygon(_ell(o + Vector2(0.0, -1.6 * s), 0.55 * s, 0.5 * s), Color(0.88, 0.80, 0.45))
			draw_rect(Rect2(o + Vector2(-0.55 * s, -1.6 * s), Vector2(1.1 * s, 0.7 * s)), Color(0.93, 0.9, 0.8))
			draw_line(o + Vector2(0.0, -2.1 * s), o + Vector2(0.0, -2.9 * s), Color(0.2, 0.2, 0.2), 0.05 * s + 0.3)
			var wave: float = sin(_t * 3.0) * 0.08 * s
			draw_colored_polygon(PackedVector2Array([o + Vector2(0.02 * s, -2.9 * s), o + Vector2(0.75 * s, -2.7 * s + wave), o + Vector2(0.02 * s, -2.45 * s)]), cc)
		drawn += 1
		if drawn >= MAX_DRAWN:
			break


func _ell(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
