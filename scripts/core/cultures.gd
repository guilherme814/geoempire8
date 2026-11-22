class_name Cultures
extends RefCounted
## Culturas e religiões (B22). Os dados ficam em data/cultures_1836.json: lista de culturas
## (id, nome, grupo, cor), religiões e regras geográficas em ordem de prioridade (caixa de
## longitude/latitude, opcionalmente restrita a donos). A atribuição é determinística.

const PATH := "res://data/cultures_1836.json"

static var _d: Dictionary = {}
static var _groups: Array = []


static func _data() -> Dictionary:
	if _d.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_d = parsed if parsed is Dictionary else {"cultures": [], "religions": [], "rules": []}
		var names: Array = []
		_groups = []
		for c in _d["cultures"]:
			var g: String = str(c["group"])
			if not names.has(g):
				names.append(g)
			_groups.append(names.find(g))
	return _d


static func count() -> int:
	return (_data()["cultures"] as Array).size()


static func religion_count() -> int:
	return (_data()["religions"] as Array).size()


static func cname(i: int) -> String:
	var a: Array = _data()["cultures"]
	return str(a[i]["name"]) if i >= 0 and i < a.size() else "?"


static func cid(i: int) -> String:
	var a: Array = _data()["cultures"]
	return str(a[i]["id"]) if i >= 0 and i < a.size() else "?"


## Identificador do grupo cultural (culturas do mesmo grupo se atritam menos).
static func group_of(i: int) -> int:
	_data()
	return int(_groups[i]) if i >= 0 and i < _groups.size() else -1


static func color(i: int) -> Color:
	var a: Array = _data()["cultures"]
	return Color(str(a[i]["color"])) if i >= 0 and i < a.size() else Color(0.5, 0.5, 0.5)


static func rname(i: int) -> String:
	var a: Array = _data()["religions"]
	return str(a[i]["name"]) if i >= 0 and i < a.size() else "?"


static func rcolor(i: int) -> Color:
	var a: Array = _data()["religions"]
	return Color(str(a[i]["color"])) if i >= 0 and i < a.size() else Color(0.5, 0.5, 0.5)


## Cultura (x) e religião (y) de um ponto; `tag` é o dono de origem (regras com "tags").
static func assign(lon: float, lat: float, tag: String) -> Vector2i:
	var rules: Array = _data()["rules"]
	for ru in rules:
		if ru.has("tags") and not (ru["tags"] as Array).has(tag):
			continue
		var lo: Array = ru["lon"]
		var la: Array = ru["lat"]
		if lon >= float(lo[0]) and lon <= float(lo[1]) and lat >= float(la[0]) and lat <= float(la[1]):
			return Vector2i(int(ru["c"]), int(ru["r"]))
	return Vector2i(count() - 1, 0)
