class_name Flag
extends RefCounted
## Bandeiras desenhadas por código (simplificadas, só formas e cores) a partir de
## data/flags.json. Quem não tem entrada usa a cor do país. Serve para qualquer
## CanvasItem: HUD (FlagRect) e marcadores de exército no mapa.

static var _specs: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	_loaded = true
	var f := FileAccess.open("res://data/flags.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_specs = d


static func draw(ci: CanvasItem, r: Rect2, tag: String, fallback: Color) -> void:
	if not _loaded:
		_load()
	var s: Dictionary = _specs.get(tag, {})
	match str(s.get("t", "")):
		"h":
			_stripes(ci, r, s["c"], false)
		"v":
			_stripes(ci, r, s["c"], true)
		"plain":
			ci.draw_rect(r, Color.html(s["c"]))
		"nordic":
			ci.draw_rect(r, Color.html(s["bg"]))
			var t := r.size.y * 0.2
			ci.draw_rect(Rect2(r.position.x + r.size.x * 0.28, r.position.y, t, r.size.y), Color.html(s["fg"]))
			ci.draw_rect(Rect2(r.position.x, r.position.y + (r.size.y - t) * 0.5, r.size.x, t), Color.html(s["fg"]))
		"cross":
			ci.draw_rect(r, Color.html(s["bg"]))
			var arm := r.size.y * 0.62
			var th := r.size.y * 0.22
			var c := r.get_center()
			ci.draw_rect(Rect2(c.x - th * 0.5, c.y - arm * 0.5, th, arm), Color.html(s["fg"]))
			ci.draw_rect(Rect2(c.x - arm * 0.5, c.y - th * 0.5, arm, th), Color.html(s["fg"]))
		"disc":
			ci.draw_rect(r, Color.html(s["bg"]))
			ci.draw_circle(r.get_center(), r.size.y * 0.3, Color.html(s["fg"]))
		"rhomb":
			ci.draw_rect(r, Color.html(s["bg"]))
			var c2 := r.get_center()
			var hx := r.size.x * 0.4
			var hy := r.size.y * 0.4
			ci.draw_colored_polygon(PackedVector2Array([c2 + Vector2(0, -hy), c2 + Vector2(hx, 0), c2 + Vector2(0, hy), c2 + Vector2(-hx, 0)]), Color.html(s["fg"]))
			ci.draw_circle(c2, r.size.y * 0.2, Color.html("#1f3f94"))
		"hc":
			_stripes(ci, r, s["c"], false)
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x * 0.42, r.size.y * 0.55)), Color.html(s["canton"]))
		"us":
			var reds: Array = []
			for i in 13:
				reds.append("#b22234" if i % 2 == 0 else "#ffffff")
			_stripes(ci, r, reds, false)
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x * 0.42, r.size.y * 7.0 / 13.0)), Color.html("#3c3b6e"))
		"uj":
			_union_jack(ci, r)
		_:
			ci.draw_rect(r, fallback)
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.34)), fallback.lightened(0.28))
	ci.draw_rect(r, Color(0, 0, 0, 0.7), false, 1.0)


static func _stripes(ci: CanvasItem, r: Rect2, cols: Array, vertical: bool) -> void:
	var n := cols.size()
	for i in n:
		var rr: Rect2
		if vertical:
			rr = Rect2(r.position.x + r.size.x * i / n, r.position.y, r.size.x / n + 0.5, r.size.y)
		else:
			rr = Rect2(r.position.x, r.position.y + r.size.y * i / n, r.size.x, r.size.y / n + 0.5)
		ci.draw_rect(rr, Color.html(cols[i]))


## Faixa diagonal/reta recortada ao retângulo (evita sobras nos cantos).
static func _band(ci: CanvasItem, r: Rect2, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x) * width * 0.5
	var quad := PackedVector2Array([a - dir * 4 + n, b + dir * 4 + n, b + dir * 4 - n, a - dir * 4 - n])
	var box := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])
	for poly in Geometry2D.intersect_polygons(box, quad):
		ci.draw_colored_polygon(poly, col)


static func _union_jack(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, Color.html("#012169"))
	var tl := r.position
	var tr := r.position + Vector2(r.size.x, 0)
	var bl := r.position + Vector2(0, r.size.y)
	var br := r.end
	var h := r.size.y
	_band(ci, r, tl, br, h * 0.22, Color.WHITE)
	_band(ci, r, tr, bl, h * 0.22, Color.WHITE)
	_band(ci, r, tl, br, h * 0.08, Color.html("#c8102e"))
	_band(ci, r, tr, bl, h * 0.08, Color.html("#c8102e"))
	var c := r.get_center()
	_band(ci, r, Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), h * 0.36, Color.WHITE)
	_band(ci, r, Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), h * 0.36, Color.WHITE)
	_band(ci, r, Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), h * 0.22, Color.html("#c8102e"))
	_band(ci, r, Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), h * 0.22, Color.html("#c8102e"))
