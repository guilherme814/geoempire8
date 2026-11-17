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
	# Cinco camadas do fundo para a costa: gradiente mais suave (sem degraus visíveis) e um
	# filete claro junto à terra. A metade que cai sobre a terra fica coberta pela malha.
	draw_multiline(lines, Color(0.24, 0.52, 0.70, 0.06), 30.0 / z)
	draw_multiline(lines, Color(0.27, 0.58, 0.75, 0.08), 22.0 / z)
	draw_multiline(lines, Color(0.30, 0.64, 0.80, 0.12), 14.0 / z)
	draw_multiline(lines, Color(0.42, 0.74, 0.88, 0.20), 8.0 / z)
	draw_multiline(lines, Color(0.62, 0.88, 0.96, 0.34), 3.6 / z)
