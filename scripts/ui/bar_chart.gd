class_name BarChart
extends Control
## Gráfico de barras horizontais para rankings. Cada linha: {label, value, text, highlight}.
## Desenha só quando os dados mudam (leve para celular).

var rows: Array = []
var title: String = ""
const ROW_H := 30.0
const HEAD_H := 28.0

var _bg := Color(0.047, 0.063, 0.098)
var _bar := Color(0.16, 0.45, 0.62)
var _bar_me := Color(0.94, 0.75, 0.32)
var _txt := Color(0.86, 0.88, 0.92)
var _dim := Color(0.55, 0.60, 0.68)


func set_rows(new_rows: Array, new_title: String = "") -> void:
	rows = new_rows
	title = new_title
	custom_minimum_size = Vector2(0, HEAD_H + ROW_H * rows.size() + 8.0)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, _bg)
	draw_rect(rect, Color(0.94, 0.75, 0.32, 0.25), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12, 19), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.94, 0.75, 0.32))
	if rows.is_empty():
		return
	var vmax := 1.0
	for r in rows:
		vmax = maxf(vmax, float(r.get("value", 0)))
	var label_w := minf(200.0, size.x * 0.34)
	var val_w := 92.0
	var left := 12.0 + 26.0 + label_w
	var right := maxf(left + 20.0, size.x - val_w - 12.0)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := HEAD_H + ROW_H * float(i)
		var me := bool(r.get("highlight", false))
		draw_string(font, Vector2(12, y + 20), str(r.get("rank", i + 1)), HORIZONTAL_ALIGNMENT_LEFT, 24, 13, _dim)
		draw_string(font, Vector2(38, y + 20), str(r.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, label_w, 14, _bar_me if me else _txt)
		var frac := clampf(float(r.get("value", 0)) / vmax, 0.0, 1.0)
		var w := maxf(3.0, (right - left) * frac)
		draw_rect(Rect2(left, y + 6, right - left, 16), Color(1, 1, 1, 0.05))
		draw_rect(Rect2(left, y + 6, w, 16), _bar_me if me else _bar)
		draw_string(font, Vector2(right + 8, y + 20), str(r.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, val_w, 13, _bar_me if me else _txt)
