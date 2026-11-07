class_name Country
extends RefCounted
## País. O estado que muda (tesouro, imposto) entra no snapshot de rede.

var id: int = 0
var name: String = ""
var color: Color = Color.GRAY
var capital: int = -1

var treasury: int = 1000
var tax_pct: int = 30
var last_income: int = 0
var last_expense: int = 0

# Derivados (recalculados por Game._refresh_country_geometry)
var province_ids: Array[int] = []
var bounds: Rect2 = Rect2()
var label_pos: Vector2 = Vector2.ZERO
var label_size: int = 16


static func from_dict(d: Dictionary) -> Country:
	var c := Country.new()
	c.id = int(d["id"])
	c.name = str(d["name"])
	c.color = Color.html(str(d["color"]))
	c.capital = int(d["capital"])
	return c


func is_alive() -> bool:
	return not province_ids.is_empty()
