class_name MapOverlay
extends Node2D
## Camada DINÂMICA do mapa (filha de MapView, desenhada por cima): destaque da província
## selecionada, marcadores de exércitos e a rota do exército selecionado.
## Redesenha em eventos de exército, seleção, a cada dia (se houver exércitos) e no zoom.

const MARKER_W := 26.0   # tamanho na TELA, em pixels (convertido pelo zoom)
const MARKER_H := 16.0

var selected_province: int = -1
var selected_army: int = -1
var zoom_level: float = 1.0

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	Events.province_selected.connect(set_selected_province)
	Events.army_selected.connect(set_selected_army)
	Events.day_changed.connect(_on_day_changed)
	Events.army_changed.connect(_on_army_event)
	Events.army_removed.connect(_on_army_event)
	Events.state_loaded.connect(queue_redraw)


func set_selected_province(pid: int) -> void:
	selected_province = pid
	queue_redraw()


func set_selected_army(aid: int) -> void:
	selected_army = aid
	queue_redraw()


func set_zoom_level(z: float) -> void:
	zoom_level = z
	queue_redraw()


func _on_day_changed(_date: Dictionary) -> void:
	if not Game.armies.is_empty():
		queue_redraw()


func _on_army_event(_aid: int) -> void:
	queue_redraw()


## Retorna o id do exército cujo marcador está sob a posição do mundo, ou -1.
func army_at(world_pos: Vector2) -> int:
	var hit := -1
	for m in _layout():
		var r: Rect2 = m["rect"]
		if r.grow(2.0 / maxf(zoom_level, 0.05)).has_point(world_pos):
			hit = int(m["id"])   # o último desenhado fica por cima
	return hit


## Posições dos marcadores: exércitos na mesma província ficam lado a lado.
func _layout() -> Array:
	var z := maxf(zoom_level, 0.05)
	var w := MARKER_W / z
	var h := MARKER_H / z
	var by_prov := {}
	for id in Game.armies.keys():
		var a: Army = Game.armies[id]
		if not by_prov.has(a.province_id):
			by_prov[a.province_id] = []
		by_prov[a.province_id].append(a.id)
	var out: Array = []
	for pid in by_prov.keys():
		var ids: Array = by_prov[pid]
		var center := Game.provinces[int(pid)].center
		for i in ids.size():
			var off := (float(i) - float(ids.size() - 1) * 0.5) * (w + 2.0 / z)
			var rect := Rect2(center + Vector2(off - w * 0.5, -h * 0.5), Vector2(w, h))
			out.append({"id": int(ids[i]), "rect": rect})
	return out


func _draw() -> void:
	if not Game.loaded:
		return
	var z := maxf(zoom_level, 0.05)

	# Província selecionada
	if selected_province >= 0 and selected_province < Game.provinces.size():
		var sp := Game.provinces[selected_province]
		draw_colored_polygon(sp.poly, Color(1, 1, 1, 0.25))
		var outline: PackedVector2Array = sp.poly.duplicate()
		outline.append(sp.poly[0])
		draw_polyline(outline, Color(1.0, 0.92, 0.35), 3.0 / z)

	# Rota do exército selecionado
	var sel: Army = Game.armies.get(selected_army)
	if sel != null and sel.is_moving():
		var pts := PackedVector2Array()
		pts.append(Game.provinces[sel.province_id].center)
		for pid in sel.path:
			pts.append(Game.provinces[pid].center)
		draw_polyline(pts, Color(1.0, 0.85, 0.2, 0.9), 2.5 / z)
		draw_circle(pts[pts.size() - 1], 5.0 / z, Color(1.0, 0.85, 0.2))

	# Marcadores
	var fs := maxi(8, int(12.0 / z))
	for m in _layout():
		var a: Army = Game.armies[int(m["id"])]
		var r: Rect2 = m["rect"]
		var col := Color(0.5, 0.5, 0.5)
		if a.owner_id >= 0 and a.owner_id < Game.countries.size():
			col = Game.countries[a.owner_id].color
		draw_rect(r, col)
		var is_sel := a.id == selected_army
		draw_rect(r, Color(1, 1, 0.3) if is_sel else Color(0, 0, 0, 0.85), false, (2.5 if is_sel else 1.2) / z)
		var text := str(a.regiments)
		var lum := col.get_luminance()
		var tcol := Color(0, 0, 0) if lum > 0.55 else Color(1, 1, 1)
		var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(_font, Vector2(r.position.x, r.position.y + (r.size.y + ts.y * 0.7) * 0.5),
			text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, tcol)
