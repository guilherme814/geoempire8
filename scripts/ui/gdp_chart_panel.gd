class_name GDPChartPanel
extends Control
## Gráfico reutilizável de histórico econômico. Recebe números ou snapshots
## de EconomyManager.get_history(country_id).

@export var history_data: Array = []
@export var metric: String = "gdp_real"
@export var chart_title: String = "EVOLUÇÃO ECONÔMICA"
@export var show_grid: bool = true

var line_color_pos: Color = Color("#5dba7a")
var line_color_neg: Color = Color("#e05a5a")
var line_color_warn: Color = Color("#e0a85a")
var bg_color: Color = Color("#0c0f14")
var panel_border: Color = Color(0.7, 0.6, 0.4, 0.25)
var text_color: Color = Color("#9a9488")
var grid_color: Color = Color(1, 1, 1, 0.075)
var _last_value: float = 0.0
var _current_change: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(280, 170)
	resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func update_chart(new_history_array: Array) -> void:
	history_data = new_history_array.duplicate(true)
	queue_redraw()


func set_metric(metric_name: String, title: String = "") -> void:
	metric = metric_name
	if title != "":
		chart_title = title
	queue_redraw()


func _value_at(item: Variant) -> float:
	if item is Dictionary:
		return float(item.get(metric, item.get("gdp_real", 0)))
	return float(item)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, bg_color)
	draw_rect(rect, panel_border, false, 1.0)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(14, 20), chart_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d4b46a"))

	if history_data.size() < 2:
		draw_string(font, Vector2(14, 48), "Aguardando histórico mensal...", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color)
		_draw_grid(rect, 42.0, rect.size.y - 24.0)
		return

	var values: Array[float] = []
	for item in history_data:
		values.append(_value_at(item))

	var min_value: float = values[0]
	var max_value: float = values[0]
	for value in values:
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)

	if is_equal_approx(max_value, min_value):
		var padding := maxf(1.0, absf(max_value) * 0.05)
		max_value += padding
		min_value -= padding
	else:
		var padding := (max_value - min_value) * 0.12
		max_value += padding
		min_value -= padding

	var left := 58.0
	var right := maxf(left + 20.0, rect.size.x - 14.0)
	var top := 34.0
	var bottom := rect.size.y - 25.0
	if bottom <= top:
		return
	_draw_grid(rect, top, bottom)

	var points := PackedVector2Array()
	var step_x := (right - left) / float(values.size() - 1)
	for i in values.size():
		var y := remap(values[i], min_value, max_value, bottom, top)
		points.append(Vector2(left + float(i) * step_x, y))

	# Área discreta sob a curva.
	var polygon := PackedVector2Array()
	polygon.append(Vector2(points[0].x, bottom))
	for point in points:
		polygon.append(point)
	polygon.append(Vector2(points[points.size() - 1].x, bottom))
	var fill_color := Color("#5dba7a")
	if metric == "monthly_balance" and values.back() < 0.0:
		fill_color = Color("#e05a5a")
	draw_colored_polygon(polygon, Color(fill_color.r, fill_color.g, fill_color.b, 0.10))

	for i in range(points.size() - 1):
		var trend_color := line_color_pos
		if values[i + 1] < values[i]:
			trend_color = line_color_warn
		if metric == "monthly_balance" and values[i + 1] < 0.0:
			trend_color = line_color_neg
		draw_line(points[i], points[i + 1], trend_color, 2.2, true)

	var latest := points[points.size() - 1]
	var latest_color := line_color_pos
	if metric == "monthly_balance" and values.back() < 0.0:
		latest_color = line_color_neg
	draw_circle(latest, 4.0, latest_color)
	draw_circle(latest, 6.0, Color(latest_color.r, latest_color.g, latest_color.b, 0.18))

	draw_string(font, Vector2(8, top + 4), _format_value(max_value), HORIZONTAL_ALIGNMENT_LEFT, 48, 9, text_color)
	draw_string(font, Vector2(8, bottom), _format_value(min_value), HORIZONTAL_ALIGNMENT_LEFT, 48, 9, text_color)

	_last_value = values.back()
	_current_change = values.back() - values[values.size() - 2]
	var latest_label := _format_value(_last_value)
	var label_width := font.get_string_size(latest_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var label_x := clampf(latest.x - label_width - 8.0, left, right - label_width)
	draw_string(font, Vector2(label_x, maxf(top + 12.0, latest.y - 8.0)), latest_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, latest_color)

	var first_label := ""
	var last_label := ""
	if history_data[0] is Dictionary:
		first_label = str(history_data[0].get("date_label", ""))
	if history_data.back() is Dictionary:
		last_label = str(history_data.back().get("date_label", ""))
	if first_label != "":
		draw_string(font, Vector2(left, rect.size.y - 7), first_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, text_color)
	if last_label != "":
		draw_string(font, Vector2(right - 54, rect.size.y - 7), last_label, HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, text_color)


func _draw_grid(rect: Rect2, top: float, bottom: float) -> void:
	if not show_grid:
		return
	for i in 5:
		var y := lerpf(top, bottom, float(i) / 4.0)
		draw_line(Vector2(54, y), Vector2(rect.size.x - 12, y), grid_color, 1.0)


func _format_value(value: float) -> String:
	var sgn := "-" if value < 0.0 else ""
	var n := absf(value)
	if n >= 1000000000.0:
		return "%s%.1f bi" % [sgn, n / 1000000000.0]
	if n >= 1000000.0:
		return "%s%.1f mi" % [sgn, n / 1000000.0]
	if n >= 1000.0:
		return "%s%.1f mil" % [sgn, n / 1000.0]
	return "%s%d" % [sgn, int(n)]
