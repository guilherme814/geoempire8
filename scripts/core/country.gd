class_name Country
extends RefCounted
## País. O estado que muda (tesouro, imposto) entra no snapshot de rede.

var id: int = 0
var tag: String = ""
var name: String = ""
var color: Color = Color.GRAY
var capital: int = -1
var pop_total: float = 0.0   # milhões, dado histórico (define o exército inicial)

var treasury: int = 0
var tax_pct: int = 30
var last_income: int = 0
var last_expense: int = 0

# Derivados (recalculados por Game._refresh_country_geometry)
var province_ids: Array[int] = []
var bounds: Rect2 = Rect2()       # do maior bloco contínuo de províncias
var label_pos: Vector2 = Vector2.ZERO
var label_size: int = 16


static func from_dict(d: Dictionary) -> Country:
	var c := Country.new()
	c.id = int(d["id"])
	c.tag = str(d.get("tag", ""))
	c.name = str(d["name"])
	c.color = Color.html(str(d["color"]))
	c.capital = int(d["capital"])
	c.pop_total = float(d.get("pop_total", 1.0))
	return c


func is_alive() -> bool:
	return not province_ids.is_empty()
