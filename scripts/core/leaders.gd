class_name Leaders
extends RefCounted
## Governantes históricos (dado estático de data/leaders_1836.json). Não entra no estado da
## simulação nem no hash: é só apresentação, calculada a partir da data do jogo.

const PATH := "res://data/leaders_1836.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_data = parsed


const BRIEF_PATH := "res://data/briefings_1836.json"
static var _brief: Dictionary = {}
static var _brief_loaded: bool = false


## Situação histórica em 1836 e desafio sugerido ({"hist","goal"}); vazio se não houver.
static func briefing(tag: String) -> Dictionary:
	if not _brief_loaded:
		_brief_loaded = true
		if FileAccess.file_exists(BRIEF_PATH):
			var f := FileAccess.open(BRIEF_PATH, FileAccess.READ)
			if f != null:
				var js: Variant = JSON.parse_string(f.get_as_text())
				if js is Dictionary:
					_brief = js
	return _brief.get(tag, {})


static func has_tag(tag: String) -> bool:
	_ensure()
	return _data.has(tag)


static func info(tag: String) -> Dictionary:
	_ensure()
	return _data.get(tag, {})


static func list(tag: String) -> Array:
	_ensure()
	var d: Dictionary = _data.get(tag, {})
	return d.get("leaders", [])


## Índice do governante no poder na data dada (o último cujo início é <= data; 0 se nenhum).
static func index_at(tag: String, year: int, month: int) -> int:
	var l: Array = list(tag)
	var idx: int = 0
	for i in l.size():
		var e: Dictionary = l[i]
		var key: int = int(e["from"]) * 12 + int(e["m"])
		if key <= year * 12 + month:
			idx = i
	return idx


static func current(tag: String, year: int, month: int) -> Dictionary:
	var l: Array = list(tag)
	if l.is_empty():
		return {}
	return l[index_at(tag, year, month)]


## Até n sucessores do governante atual, em ordem cronológica.
static func successors(tag: String, year: int, month: int, n: int = 6) -> Array:
	var l: Array = list(tag)
	var out: Array = []
	var i: int = index_at(tag, year, month) + 1
	while i < l.size() and out.size() < n:
		out.append(l[i])
		i += 1
	return out


## Ano em que o governante deixa o cargo (início do próximo), ou 0 se não há registro.
static func end_year(tag: String, idx: int) -> int:
	var l: Array = list(tag)
	if idx + 1 < l.size():
		var e: Dictionary = l[idx + 1]
		return int(e["from"])
	return 0


static func reign_text(tag: String, idx: int) -> String:
	var l: Array = list(tag)
	if idx < 0 or idx >= l.size():
		return ""
	var e: Dictionary = l[idx]
	var end := end_year(tag, idx)
	return "%d – %s" % [int(e["from"]), str(end) if end > 0 else "…"]
