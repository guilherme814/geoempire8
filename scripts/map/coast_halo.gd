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
	var q := AppSettings.gfx_quality()
	if q >= 2:
		# Alta: cinco camadas, gradiente suave e um filete claro junto à terra.
		draw_multiline(lines, Color(0.24, 0.52, 0.70, 0.06), 30.0 / z)
		draw_multiline(lines, Color(0.27, 0.58, 0.75, 0.08), 22.0 / z)
		draw_multiline(lines, Color(0.30, 0.64, 0.80, 0.12), 14.0 / z)
		draw_multiline(lines, Color(0.42, 0.74, 0.88, 0.20), 8.0 / z)
		draw_multiline(lines, Color(0.62, 0.88, 0.96, 0.34), 3.6 / z)
	elif q == 1:
		# Média: três camadas (visual original, bem mais leve para a GPU).
		draw_multiline(lines, Color(0.28, 0.60, 0.76, 0.10), 20.0 / z)
		draw_multiline(lines, Color(0.30, 0.64, 0.80, 0.16), 11.0 / z)
		draw_multiline(lines, Color(0.50, 0.80, 0.92, 0.30), 5.0 / z)
	else:
		# Baixa: um único traço.
		draw_multiline(lines, Color(0.40, 0.72, 0.88, 0.28), 8.0 / z)
