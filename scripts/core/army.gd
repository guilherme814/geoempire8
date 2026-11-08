class_name Army
extends RefCounted
## Exército: pilha de regimentos numa província, que pode estar em marcha.
## Estado inteiro e simples para entrar no snapshot e no hash de rede.

var id: int = 0
var owner_id: int = 0
var province_id: int = 0          # província onde está (ou de onde partiu)
var regiments: int = 0
var path: Array[int] = []         # próximas províncias, sem incluir a atual
var move_left: int = 0            # dias até chegar a path[0]


func is_moving() -> bool:
	return not path.is_empty()


func men() -> int:
	return regiments * 1000


func to_dict() -> Dictionary:
	var pth: Array = []
	for v in path:
		pth.append(v)
	return {"id": id, "owner": owner_id, "prov": province_id, "regs": regiments, "path": pth, "left": move_left}


static func from_dict(d: Dictionary) -> Army:
	var a := Army.new()
	a.id = int(d["id"])
	a.owner_id = int(d["owner"])
	a.province_id = int(d["prov"])
	a.regiments = int(d["regs"])
	a.move_left = int(d.get("left", 0))
	var raw: Array = d.get("path", [])
	for v in raw:
		a.path.append(int(v))
	return a
