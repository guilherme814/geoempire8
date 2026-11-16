class_name PerfMonitor
extends RefCounted
## Medição leve de desempenho (Fase 0 do plano de otimização): tempo por etapa em ms, com média,
## p95 e máximo sobre as últimas amostras. Só mede; não altera a simulação.

const MAX_SAMPLES := 600
static var _samples: Dictionary = {}


static func begin() -> int:
	return Time.get_ticks_usec()


static func record(label: String, t0: int) -> void:
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var arr: Array = _samples.get(label, [])
	arr.append(ms)
	if arr.size() > MAX_SAMPLES:
		arr.remove_at(0)
	_samples[label] = arr


static func clear() -> void:
	_samples.clear()


static func summary(label: String) -> Dictionary:
	var arr: Array = _samples.get(label, [])
	if arr.is_empty():
		return {"n": 0, "avg": 0.0, "p95": 0.0, "max": 0.0}
	var sorted: Array = arr.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += float(v)
	var i95: int = clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, sorted.size() - 1)
	return {"n": sorted.size(), "avg": total / float(sorted.size()), "p95": float(sorted[i95]), "max": float(sorted[-1])}


static func report() -> String:
	var keys: Array = _samples.keys()
	keys.sort()
	var out := ""
	for k in keys:
		var s: Dictionary = summary(str(k))
		out += "PERF %-10s n=%4d  media %.2f ms  p95 %.2f ms  max %.2f ms\n" % [k, s["n"], s["avg"], s["p95"], s["max"]]
	return out
