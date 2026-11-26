class_name WeatherFx
extends Node2D
## Clima e partículas (F9): neve caindo nas montanhas e na tundra no inverno (e flocos leves na
## tundra o ano todo), chuva tropical na selva e no pântano nos meses úmidos, poeira rodopiando
## no deserto e rajadas de vento nas colinas. Só aparece com zoom, só nas províncias à vista
## (no máximo 24) e some em qualidade gráfica baixa.

const MIN_ZOOM := 2.0
const MAX_PROVS := 24
const PARTICLES := 7

var _timer: Timer
var _t: float = 0.0
var _box: Dictionary = {}      # pid -> Rect2 (caixa da província)


func _ready() -> void:
	z_index = 6
	Events.state_loaded.connect(func(): _box.clear())
	_timer = Timer.new()
	_timer.wait_time = 0.08
	_timer.timeout.connect(func():
		var mv := get_parent() as MapView
		if mv != null and mv.zoom_level >= MIN_ZOOM and AppSettings.gfx_quality() >= 3 and is_visible_in_tree():
			_t = float(Time.get_ticks_msec()) * 0.001
			queue_redraw())
	add_child(_timer)
	_timer.start()


func _bounds(p: Province) -> Rect2:
	if _box.has(p.id):
		return _box[p.id]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in p.poly:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var r := Rect2(lo, hi - lo) if p.poly.size() >= 3 else Rect2(p.center - Vector2(6, 6), Vector2(12, 12))
	_box[p.id] = r
	return r


func _draw() -> void:
	if not Game.loaded:
		return
	var mv := get_parent() as MapView
	if mv == null or mv.zoom_level < MIN_ZOOM or AppSettings.gfx_quality() < 3:
		return
	if mv.mode != MapView.Mode.POLITICAL and mv.mode != MapView.Mode.TERRAIN:
		return
	var z: float = mv.zoom_level
	var month: int = Game.clock.month
	var winter: bool = month >= 11 or month <= 2
	var wet: bool = month >= 10 or month <= 3
	var view: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
	var n := 0
	for p in Game.provinces:
		if not view.has_point(p.center):
			continue
		var kind := ""
		match p.terrain:
			"mountains": kind = "snow" if winter else ""
			"tundra": kind = "snow"
			"jungle", "marsh": kind = "rain" if wet else ""
			"desert": kind = "dust"
			"hills": kind = "wind" if winter else ""
		if kind == "":
			continue
		var b: Rect2 = _bounds(p)
		for k in PARTICLES:
			var ph: float = float((p.id * 13 + k * 29) % 100) / 100.0
			var fx: float = fposmod(ph * 7.3 + float(k) * 0.37, 1.0)
			var f: float = fposmod(_t * (0.25 if kind == "snow" else 0.9) + ph, 1.0)
			var x: float = b.position.x + b.size.x * fx
			var y: float = b.position.y + b.size.y * f
			match kind:
				"snow":
					draw_circle(Vector2(x + sin(_t * 1.4 + float(k)) * 2.0 / z, y), 0.9 / z, Color(1, 1, 1, 0.85))
				"rain":
					draw_line(Vector2(x, y), Vector2(x - 1.2 / z, y + 3.2 / z), Color(0.65, 0.78, 0.95, 0.7), 0.7 / z)
				"dust":
					var ang: float = _t * 1.5 + float(k)
					draw_circle(b.get_center() + Vector2(cos(ang) * b.size.x * 0.25 * fx, sin(ang) * b.size.y * 0.2), 1.1 / z, Color(0.85, 0.7, 0.45, 0.35))
				"wind":
					var wx: float = b.position.x + b.size.x * fposmod(_t * 0.15 + ph, 1.0)
					draw_line(Vector2(wx, b.position.y + b.size.y * fx), Vector2(wx + 5.0 / z, b.position.y + b.size.y * fx - 0.8 / z), Color(1, 1, 1, 0.35), 0.5 / z)
		n += 1
		if n >= MAX_PROVS:
			break
