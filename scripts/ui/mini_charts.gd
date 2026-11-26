class_name MiniCharts
extends Control
## Gráficos pequenos para os cartões (F10): barra empilhada com legenda (`stack`) e medidor em
## arco (`gauge`). Desenho vetorial, sem texturas.

var _kind: String = "stack"
var _vals: Array = []          # stack: [[rótulo, valor, cor], ...]; gauge: [valor, máximo, cor, rótulo]


static func stack(parts: Array) -> MiniCharts:
	var c := MiniCharts.new()
	c._kind = "stack"
	c._vals = parts
	c.custom_minimum_size = Vector2(0, 46)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func gauge(value: float, maximum: float, col: Color, label: String) -> MiniCharts:
	var c := MiniCharts.new()
	c._kind = "gauge"
	c._vals = [value, maximum, col, label]
	c.custom_minimum_size = Vector2(120, 78)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if _kind == "stack":
		var total := 0.0
		for p in _vals:
			total += maxf(0.0, float(p[1]))
		if total <= 0.0:
			return
		var x := 0.0
		var w := size.x
		for p in _vals:
			var sw: float = w * maxf(0.0, float(p[1])) / total
			draw_rect(Rect2(x, 0.0, sw, 18.0), p[2])
			draw_rect(Rect2(x, 0.0, sw, 18.0), Color(0, 0, 0, 0.35), false, 1.0)
			x += sw
		var lx := 0.0
		for p in _vals:
			var pct: int = int(round(100.0 * maxf(0.0, float(p[1])) / total))
			if pct < 1:
				continue
			draw_rect(Rect2(lx, 28.0, 10.0, 10.0), p[2])
			var txt := "%s %d%%" % [str(p[0]), pct]
			draw_string(font, Vector2(lx + 14.0, 38.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.88, 0.8))
			lx += 14.0 + font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0
			if lx > size.x - 40.0:
				break
	else:
		var v: float = float(_vals[0])
		var m: float = maxf(1.0, float(_vals[1]))
		var col: Color = _vals[2]
		var c := Vector2(size.x * 0.5, size.y - 8.0)
		var r := minf(size.x * 0.45, size.y - 14.0)
		draw_arc(c, r, PI, TAU, 32, Color(1, 1, 1, 0.15), 9.0)
		draw_arc(c, r, PI, PI + PI * clampf(v / m, 0.0, 1.0), 32, col, 9.0)
		var txt := str(_vals[3])
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(font, c + Vector2(-ts.x * 0.5, -r * 0.25), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.92, 0.82))
