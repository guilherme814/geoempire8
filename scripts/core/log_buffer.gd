class_name LogBuffer
extends RefCounted
## Registro de sessão em memória (sem dependência de autoloads, para ser testável).
## Guarda eventos com data/hora, agrupa repetições, mede tempo de quadro e monta o relatório
## de texto que o aparelho exporta ao sair do jogo. Só observa: nunca altera a simulação.

const MAX_LINES := 3000
const MAX_FRAMES := 1200
const LEVELS := ["INFO", "AVISO", "ERRO"]
const INFO := 0
const WARN := 1
const ERROR := 2

var lines: Array = []                  # [{t, lvl, tag, msg, n}]
var counts: Array = [0, 0, 0]          # por nível
var dropped: int = 0                   # linhas antigas descartadas
var _frames: Array = []                # dt em ms
var hitches_50: int = 0
var hitches_100: int = 0
var worst_ms: float = 0.0
var total_frames: int = 0
var tag_counts: Dictionary = {}        # contagem por etiqueta (ex.: comandos por tipo)


## Adiciona uma linha. Mensagens idênticas e consecutivas (mesma etiqueta) viram "xN".
func add(level: int, tag: String, msg: String, t_ms: int = -1) -> void:
	var lvl := clampi(level, 0, 2)
	counts[lvl] = int(counts[lvl]) + 1
	var t := t_ms if t_ms >= 0 else Time.get_ticks_msec()
	if not lines.is_empty():
		var last: Dictionary = lines[-1]
		if str(last["tag"]) == tag and str(last["msg"]) == msg and int(last["lvl"]) == lvl:
			last["n"] = int(last["n"]) + 1
			return
	lines.append({"t": t, "lvl": lvl, "tag": tag, "msg": msg, "n": 1})
	if lines.size() > MAX_LINES:
		# descarta as mais antigas que não sejam erros, para não perder o que importa
		var cut := 0
		for i in lines.size():
			if int(lines[i]["lvl"]) < ERROR:
				cut = i
				break
		lines.remove_at(cut)
		dropped += 1


func bump(tag: String) -> void:
	tag_counts[tag] = int(tag_counts.get(tag, 0)) + 1


## Registra o tempo de um quadro (segundos).
func frame(dt: float) -> void:
	var ms := dt * 1000.0
	total_frames += 1
	worst_ms = maxf(worst_ms, ms)
	if ms > 50.0:
		hitches_50 += 1
	if ms > 100.0:
		hitches_100 += 1
	_frames.append(ms)
	if _frames.size() > MAX_FRAMES:
		_frames.remove_at(0)


## p50/p95/p99/máximo dos últimos quadros e FPS médio equivalente.
func frame_stats() -> Dictionary:
	if _frames.is_empty():
		return {"n": 0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0, "fps": 0.0}
	var s: Array = _frames.duplicate()
	s.sort()
	var total := 0.0
	for v in s:
		total += float(v)
	return {
		"n": s.size(), "p50": _pct(s, 0.50), "p95": _pct(s, 0.95), "p99": _pct(s, 0.99),
		"max": float(s[-1]), "fps": 1000.0 / maxf(0.001, total / float(s.size())),
	}


static func _pct(sorted: Array, q: float) -> float:
	var i := clampi(int(ceil(float(sorted.size()) * q)) - 1, 0, sorted.size() - 1)
	return float(sorted[i])


@warning_ignore("integer_division")
static func fmt_time(ms: int) -> String:
	var s := ms / 1000
	return "%02d:%02d:%02d.%03d" % [s / 3600, (s / 60) % 60, s % 60, ms % 1000]


## Relatório completo. `header`: pares chave→valor do aparelho/jogo; `sections`: título→texto.
func render(header: Dictionary, sections: Dictionary) -> String:
	var out := "=== GEOEMPIRE — RELATÓRIO DE SESSÃO ===\n"
	for k in header.keys():
		out += "%s: %s\n" % [k, str(header[k])]
	var fs := frame_stats()
	out += "\n--- RESUMO ---\n"
	out += "Erros: %d | Avisos: %d | Info: %d | Linhas descartadas: %d\n" % [counts[2], counts[1], counts[0], dropped]
	out += "Quadros: %d | p50 %.1f ms | p95 %.1f ms | p99 %.1f ms | pior %.1f ms | ~%.0f FPS\n" % [
		total_frames, fs["p50"], fs["p95"], fs["p99"], worst_ms, fs["fps"]]
	out += "Travadas: >50 ms = %d, >100 ms = %d\n" % [hitches_50, hitches_100]
	if not tag_counts.is_empty():
		var keys: Array = tag_counts.keys()
		keys.sort()
		var parts := PackedStringArray()
		for k in keys:
			parts.append("%s=%d" % [k, int(tag_counts[k])])
		out += "Contagens: " + ", ".join(parts) + "\n"
	for title in sections.keys():
		out += "\n--- %s ---\n%s\n" % [str(title).to_upper(), str(sections[title]).strip_edges()]
	out += "\n--- EVENTOS (mais antigos primeiro) ---\n"
	for ln in lines:
		var rep := "" if int(ln["n"]) <= 1 else "  (x%d)" % int(ln["n"])
		out += "[%s] %-5s %-9s %s%s\n" % [fmt_time(int(ln["t"])), LEVELS[int(ln["lvl"])], str(ln["tag"]), str(ln["msg"]), rep]
	return out
