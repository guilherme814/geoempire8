class_name Fleet
extends RefCounted
## Frota: pilha de navios numa célula da grade marítima (Game.sea_*), que pode navegar.
## Estado inteiro e simples para entrar no snapshot e no hash de rede.

var id: int = 0
var owner_id: int = 0
var ships: int = 0
var cell: int = 0                 # célula atual (y * sea_w + x)
var path: Array[int] = []         # próximas células, sem incluir a atual


func is_moving() -> bool:
	return not path.is_empty()


func to_dict() -> Dictionary:
	var pth: Array = []
	for v in path:
		pth.append(v)
	return {"id": id, "owner": owner_id, "ships": ships, "cell": cell, "path": pth}


static func from_dict(d: Dictionary) -> Fleet:
	var f := Fleet.new()
	f.id = int(d["id"])
	f.owner_id = int(d["owner"])
	f.ships = int(d["ships"])
	f.cell = int(d["cell"])
	for v in d.get("path", []):
		f.path.append(int(v))
	return f
