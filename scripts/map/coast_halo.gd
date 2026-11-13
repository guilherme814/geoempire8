class_name CoastHalo
extends Node2D
## Faixa de "águas rasas" ao longo da costa (estilo Age of History 3): três traços claros e
## translúcidos sob a malha das terras; a metade que cai sobre a terra fica coberta.

var lines: PackedVector2Array = PackedVector2Array()
var zoom: float = 1.0


func set_data(l: PackedVector2Array) -> void:
	lines = l
	queue_redraw()


func set_zoom(z: float) -> void:
	zoom = z
	queue_redraw()


func _draw() -> void:
	if lines.is_empty():
		return
	var z := maxf(zoom, 0.05)
	draw_multiline(lines, Color(0.28, 0.60, 0.76, 0.10), 20.0 / z)
	draw_multiline(lines, Color(0.30, 0.64, 0.80, 0.16), 11.0 / z)
	draw_multiline(lines, Color(0.50, 0.80, 0.92, 0.30), 5.0 / z)
