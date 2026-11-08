class_name ProvinceGraph
extends AStar2D
## Grafo de províncias para achar caminhos (A*). Custo = dias de marcha.
## Fronteiras terrestres e estreitos (sea_links) são arestas; travessia marítima custa 3x.

const PX_PER_DAY := 12.0   # pixels do mapa percorridos por dia em terreno plano
const SEA_MULT := 3.0

var _provs: Array[Province] = []


## Dias para ir da província `a` à vizinha `b` (inteiro >= 1; determinístico).
static func hop_days(a: Province, b: Province) -> int:
	var d := a.center.distance_to(b.center)
	var mult: float = float(Province.MOVE_MULT.get(b.terrain, 1000)) / 1000.0
	if not a.neighbors.has(b.id):
		mult *= SEA_MULT
	return maxi(1, int(ceil(d / PX_PER_DAY * mult)))


func setup(provs: Array[Province]) -> void:
	_provs = provs
	clear()
	for p in provs:
		add_point(p.id, p.center)
	for p in provs:
		for n in p.neighbors:
			if n > p.id:
				connect_points(p.id, n, true)
		for s in p.sea_links:
			if s > p.id and not p.neighbors.has(s):
				connect_points(p.id, s, true)


func _compute_cost(from_id: int, to_id: int) -> float:
	return float(hop_days(_provs[from_id], _provs[to_id]))


func _estimate_cost(from_id: int, end_id: int) -> float:
	# Limite inferior do custo (dias em terreno plano): heurística admissível.
	return _provs[from_id].center.distance_to(_provs[end_id].center) / PX_PER_DAY
