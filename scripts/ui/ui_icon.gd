class_name UiIcon
extends Control
## Ícone vetorial desenhado em código (sem arquivos de imagem): leve, nítido em qualquer
## resolução e na cor que a interface pedir. Coordenadas internas em 0..1.

const DEFAULT_COLOR := Color(0.79, 0.66, 0.36)

var kind: String = "coin"
var color: Color = DEFAULT_COLOR

var _s: float = 1.0
var _o: Vector2 = Vector2.ZERO


static func make(icon_kind: String, px: float = 28.0, col: Color = DEFAULT_COLOR) -> UiIcon:
	var i := UiIcon.new()
	i.kind = icon_kind
	i.color = col
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return i


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _s


func _poly(pts: Array, col: Color) -> void:
	var v := PackedVector2Array()
	for q in pts:
		var pt: Vector2 = q
		v.append(_p(pt.x, pt.y))
	draw_colored_polygon(v, col)


func _line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(_p(a.x, a.y), _p(b.x, b.y), col, maxf(1.0, w * _s), true)


func _draw() -> void:
	_s = minf(size.x, size.y)
	if _s <= 0.0:
		return
	_o = (size - Vector2(_s, _s)) * 0.5
	var dark := color.darkened(0.45)
	match kind:
		"coin":
			draw_circle(_p(0.5, 0.5), 0.44 * _s, color)
			draw_circle(_p(0.5, 0.5), 0.32 * _s, dark)
			_poly([Vector2(0.5, 0.28), Vector2(0.7, 0.5), Vector2(0.5, 0.72), Vector2(0.3, 0.5)], color)
		"people":
			draw_circle(_p(0.36, 0.3), 0.13 * _s, color)
			_poly([Vector2(0.1, 0.86), Vector2(0.14, 0.62), Vector2(0.28, 0.5), Vector2(0.46, 0.5),
				Vector2(0.58, 0.62), Vector2(0.62, 0.86)], color)
			draw_circle(_p(0.7, 0.36), 0.11 * _s, dark)
			_poly([Vector2(0.52, 0.86), Vector2(0.56, 0.68), Vector2(0.66, 0.58), Vector2(0.78, 0.58),
				Vector2(0.88, 0.68), Vector2(0.92, 0.86)], dark)
		"book":
			_poly([Vector2(0.08, 0.24), Vector2(0.47, 0.32), Vector2(0.47, 0.86), Vector2(0.08, 0.78)], color)
			_poly([Vector2(0.92, 0.24), Vector2(0.53, 0.32), Vector2(0.53, 0.86), Vector2(0.92, 0.78)], color)
			_line(Vector2(0.16, 0.42), Vector2(0.39, 0.47), 0.04, dark)
			_line(Vector2(0.16, 0.56), Vector2(0.39, 0.61), 0.04, dark)
			_line(Vector2(0.84, 0.42), Vector2(0.61, 0.47), 0.04, dark)
			_line(Vector2(0.84, 0.56), Vector2(0.61, 0.61), 0.04, dark)
		"bulb":
			draw_circle(_p(0.5, 0.4), 0.28 * _s, color)
			_poly([Vector2(0.36, 0.58), Vector2(0.64, 0.58), Vector2(0.6, 0.78), Vector2(0.4, 0.78)], color)
			_line(Vector2(0.4, 0.86), Vector2(0.6, 0.86), 0.07, color)
			_line(Vector2(0.44, 0.4), Vector2(0.5, 0.52), 0.04, dark)
			_line(Vector2(0.56, 0.4), Vector2(0.5, 0.52), 0.04, dark)
		"shield":
			_poly([Vector2(0.14, 0.14), Vector2(0.5, 0.06), Vector2(0.86, 0.14), Vector2(0.86, 0.5),
				Vector2(0.5, 0.94), Vector2(0.14, 0.5)], color)
			draw_polyline(PackedVector2Array([_p(0.32, 0.48), _p(0.46, 0.62), _p(0.7, 0.32)]), dark, maxf(1.0, 0.08 * _s), true)
		"star":
			var pts: Array = []
			for i in 10:
				var r := 0.46 if i % 2 == 0 else 0.2
				var a := -PI / 2.0 + float(i) * PI / 5.0
				pts.append(Vector2(0.5 + r * cos(a), 0.54 + r * sin(a)))
			_poly(pts, color)
		"sword":
			_line(Vector2(0.18, 0.82), Vector2(0.82, 0.18), 0.1, color)
			_line(Vector2(0.82, 0.82), Vector2(0.18, 0.18), 0.1, color)
			_line(Vector2(0.24, 0.5), Vector2(0.5, 0.76), 0.07, dark)
			_line(Vector2(0.76, 0.5), Vector2(0.5, 0.76), 0.07, dark)
		"ship":
			_poly([Vector2(0.08, 0.64), Vector2(0.92, 0.64), Vector2(0.74, 0.86), Vector2(0.26, 0.86)], color)
			_line(Vector2(0.5, 0.64), Vector2(0.5, 0.1), 0.05, color)
			_poly([Vector2(0.46, 0.14), Vector2(0.46, 0.58), Vector2(0.16, 0.58)], color)
			_poly([Vector2(0.54, 0.22), Vector2(0.54, 0.58), Vector2(0.84, 0.58)], dark)
		"hammer":
			_line(Vector2(0.3, 0.86), Vector2(0.62, 0.42), 0.1, color)
			_poly([Vector2(0.4, 0.26), Vector2(0.78, 0.12), Vector2(0.88, 0.36), Vector2(0.52, 0.5)], color)
		"scales":
			_line(Vector2(0.5, 0.16), Vector2(0.5, 0.86), 0.06, color)
			_line(Vector2(0.3, 0.88), Vector2(0.7, 0.88), 0.07, color)
			_line(Vector2(0.14, 0.28), Vector2(0.86, 0.28), 0.06, color)
			_line(Vector2(0.14, 0.28), Vector2(0.08, 0.44), 0.03, color)
			_line(Vector2(0.14, 0.28), Vector2(0.36, 0.44), 0.03, color)
			_line(Vector2(0.86, 0.28), Vector2(0.64, 0.44), 0.03, color)
			_line(Vector2(0.86, 0.28), Vector2(0.92, 0.44), 0.03, color)
			draw_arc(_p(0.22, 0.44), 0.14 * _s, 0.0, PI, 10, color, maxf(1.0, 0.06 * _s), true)
			draw_arc(_p(0.78, 0.44), 0.14 * _s, 0.0, PI, 10, color, maxf(1.0, 0.06 * _s), true)
		"bars":
			draw_rect(Rect2(_p(0.12, 0.56), Vector2(0.22, 0.3) * _s), color)
			draw_rect(Rect2(_p(0.39, 0.38), Vector2(0.22, 0.48) * _s), color)
			draw_rect(Rect2(_p(0.66, 0.16), Vector2(0.22, 0.7) * _s), color)
			_line(Vector2(0.06, 0.9), Vector2(0.94, 0.9), 0.04, dark)
		"globe":
			draw_arc(_p(0.5, 0.5), 0.42 * _s, 0.0, TAU, 28, color, maxf(1.0, 0.06 * _s), true)
			var mer := PackedVector2Array()
			for i in 25:
				var a2 := float(i) / 24.0 * TAU
				mer.append(_p(0.5 + 0.17 * cos(a2), 0.5 + 0.42 * sin(a2)))
			draw_polyline(mer, color, maxf(1.0, 0.04 * _s), true)
			_line(Vector2(0.08, 0.5), Vector2(0.92, 0.5), 0.04, color)
			_line(Vector2(0.16, 0.3), Vector2(0.84, 0.3), 0.03, color)
			_line(Vector2(0.16, 0.7), Vector2(0.84, 0.7), 0.03, color)
		"menu":
			_line(Vector2(0.18, 0.28), Vector2(0.82, 0.28), 0.1, color)
			_line(Vector2(0.18, 0.5), Vector2(0.82, 0.5), 0.1, color)
			_line(Vector2(0.18, 0.72), Vector2(0.82, 0.72), 0.1, color)
		"building":
			_poly([Vector2(0.5, 0.1), Vector2(0.92, 0.38), Vector2(0.08, 0.38)], color)
			for i in 4:
				draw_rect(Rect2(_p(0.16 + 0.2 * float(i), 0.44), Vector2(0.1, 0.32) * _s), color)
			draw_rect(Rect2(_p(0.08, 0.8), Vector2(0.84, 0.1) * _s), color)
		"pick":
			_line(Vector2(0.24, 0.88), Vector2(0.64, 0.34), 0.09, color)
			draw_arc(_p(0.58, 0.5), 0.34 * _s, PI * 1.08, PI * 1.92, 14, color, maxf(1.0, 0.1 * _s), true)
		"factory":
			draw_rect(Rect2(_p(0.1, 0.5), Vector2(0.8, 0.38) * _s), color)
			for i in 3:
				var x0 := 0.1 + 0.2 * float(i)
				_poly([Vector2(x0, 0.5), Vector2(x0, 0.3), Vector2(x0 + 0.2, 0.5)], color)
			draw_rect(Rect2(_p(0.74, 0.14), Vector2(0.12, 0.4) * _s), color)
			draw_rect(Rect2(_p(0.2, 0.62), Vector2(0.14, 0.12) * _s), dark)
			draw_rect(Rect2(_p(0.44, 0.62), Vector2(0.14, 0.12) * _s), dark)
		"flag":
			_line(Vector2(0.24, 0.1), Vector2(0.24, 0.92), 0.07, color)
			_poly([Vector2(0.28, 0.14), Vector2(0.86, 0.26), Vector2(0.28, 0.5)], color)
		"scroll":
			_poly([Vector2(0.2, 0.12), Vector2(0.8, 0.12), Vector2(0.8, 0.78), Vector2(0.2, 0.78)], color)
			draw_circle(_p(0.2, 0.84), 0.1 * _s, color)
			draw_circle(_p(0.8, 0.84), 0.1 * _s, color)
			draw_rect(Rect2(_p(0.2, 0.78), Vector2(0.6, 0.12) * _s), color)
			for i in 3:
				_line(Vector2(0.3, 0.28 + 0.16 * float(i)), Vector2(0.7, 0.28 + 0.16 * float(i)), 0.045, dark)
		"close":
			_line(Vector2(0.24, 0.24), Vector2(0.76, 0.76), 0.1, color)
			_line(Vector2(0.76, 0.24), Vector2(0.24, 0.76), 0.1, color)
		_:
			draw_circle(_p(0.5, 0.5), 0.4 * _s, color)
