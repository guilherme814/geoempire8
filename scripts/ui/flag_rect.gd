class_name FlagRect
extends Control
## Controle que desenha a bandeira de um país (ver Flag).

var tag: String = ""
var fallback: Color = Color.GRAY


func set_country(t: String, c: Color) -> void:
	tag = t
	fallback = c
	queue_redraw()


func _draw() -> void:
	Flag.draw(self, Rect2(Vector2.ZERO, size), tag, fallback)
