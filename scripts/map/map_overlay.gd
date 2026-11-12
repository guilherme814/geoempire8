class_name MapOverlay
extends Node2D
## Camada DINÂMICA do mapa (filha de MapView, desenhada por cima): destaque da província
## selecionada, marcadores de exércitos e a rota do exército selecionado.
## Redesenha em eventos de exército, seleção, a cada dia (se houver exércitos) e no zoom.

const MARKER_W := 34.0   # tamanho na TELA, em pixels (convertido pelo zoom)
const MARKER_H := 20.0

var selected_province: int = -1
var selected_army: int = -1
var selected_fleet: int = -1
var zoom_level: float = 1.0

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	Events.province_selected.connect(set_selected_province)
	Events.army_selected.connect(set_selected_army)
	Events.fleet_selected.connect(set_selected_fleet)
	Events.fleet_changed.connect(_on_army_event)
	Events.fleet_removed.connect(_on_army_event)
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


func set_selected_fleet(fid: int) -> void:
	selected_fleet = fid
	queue_redraw()


func set_zoom_level(z: float) -> void:
	zoom_level = z
	queue_redraw()


func _on_day_changed(_date: Dictionary) -> void:
	if not Game.armies.is_empty() or not Game.fleets.is_empty():
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


## Retorna o id da frota cujo marcador está sob a posição do mundo, ou -1.
func fleet_at(world_pos: Vector2) -> int:
	var hit := -1
	for m in _fleet_layout():
		var r: Rect2 = m["rect"]
		if r.grow(3.0 / maxf(zoom_level, 0.05)).has_point(world_pos):
			hit = int(m["id"])
	return hit


func _fleet_layout() -> Array:
	var z := maxf(zoom_level, 0.05)
	var w := MARKER_W / z
	var h := MARKER_H / z
	var by_cell := {}
	var ids: Array = Game.fleets.keys()
	ids.sort()
	for id in ids:
		var f: Fleet = Game.fleets[id]
		if not _show_owner(f.owner_id):
			continue
		if not by_cell.has(f.cell):
			by_cell[f.cell] = []
		by_cell[f.cell].append(f.id)
	var out: Array = []
	for cell in by_cell.keys():
		var list: Array = by_cell[cell]
		var center := Game.cell_center(int(cell))
		for i in list.size():
			var off := (float(i) - float(list.size() - 1) * 0.5) * (w + 2.0 / z)
			out.append({"id": int(list[i]), "rect": Rect2(center + Vector2(off - w * 0.5, -h * 0.5), Vector2(w, h))})
	return out


## Silhueta de navio (casco + duas velas) acima do marcador.
func _draw_ship_icon(r: Rect2, col: Color, z: float) -> void:
	var u := r.size.x / 34.0
	var base := Vector2(r.position.x + r.size.x * 0.5, r.position.y)
	var hull := PackedVector2Array([base + Vector2(-11, -2) * u, base + Vector2(11, -2) * u, base + Vector2(7, -7) * u, base + Vector2(-7, -7) * u])
	draw_colored_polygon(hull, Color(0.16, 0.1, 0.06))
	draw_line(base + Vector2(-3, -7) * u, base + Vector2(-3, -16) * u, Color(0.16, 0.1, 0.06), 1.2 / z)
	draw_line(base + Vector2(3, -7) * u, base + Vector2(3, -14) * u, Color(0.16, 0.1, 0.06), 1.2 / z)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-3, -15) * u, base + Vector2(-10, -8) * u, base + Vector2(-3, -8) * u]), Color(0.96, 0.93, 0.82))
	draw_colored_polygon(PackedVector2Array([base + Vector2(3, -13) * u, base + Vector2(9, -8) * u, base + Vector2(3, -8) * u]), col.lightened(0.35))


## De longe, só mostra o que importa (seus exércitos/frotas e os de países em guerra com você).
func _show_owner(owner: int) -> bool:
	if zoom_level >= 2.0:
		return true
	return owner == Game.player_country or Game.at_war(Game.player_country, owner)


## Posições dos marcadores: exércitos na mesma província ficam lado a lado.
func _layout() -> Array:
	var z := maxf(zoom_level, 0.05)
	var w := MARKER_W / z
	var h := MARKER_H / z
	var by_prov := {}
	for id in Game.armies.keys():
		var a: Army = Game.armies[id]
		if not _show_owner(a.owner_id):
			continue
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

	# Passagens estratégicas (estreitos, cabos)
	for gi in Game.gates.size():
		var g: Dictionary = Game.gates[gi]
		var gp := Vector2(float(g["x"]), float(g["y"]))
		var gctrl := Game.gate_controller(gi)
		var gcol := Color(0.95, 0.85, 0.5, 0.9)
		if gctrl >= 0:
			gcol = Game.countries[gctrl].color.lightened(0.35)
			gcol.a = 0.95
		var gr := 7.0 / z
		draw_arc(gp, gr, 0.0, TAU, 18, gcol, 2.0 / z, true)
		draw_circle(gp, gr * 0.35, gcol)
		if z >= 0.45:
			var gfs := maxi(8, int(12.0 / z))
			draw_string_outline(_font, gp + Vector2(gr + 3.0 / z, 4.0 / z), str(g["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, gfs, 3, Color(0, 0, 0, 0.8))
			draw_string(_font, gp + Vector2(gr + 3.0 / z, 4.0 / z), str(g["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, gfs, Color(0.95, 0.9, 0.7, 0.95))

	# Rota do exército selecionado: linha tracejada com seta e dias restantes
	# Rota da frota selecionada
	var fsel: Fleet = Game.fleets.get(selected_fleet)
	if fsel != null and fsel.is_moving():
		var fpts := PackedVector2Array()
		fpts.append(Game.cell_center(fsel.cell))
		for c in fsel.path:
			fpts.append(Game.cell_center(c))
		draw_polyline(fpts, Color(0.45, 0.85, 1.0, 0.75), 2.0 / z)
		var ftip: Vector2 = fpts[fpts.size() - 1]
		draw_circle(ftip, 5.0 / z, Color(0.45, 0.85, 1.0, 0.95))
		var feta := "%d d" % Game.fleet_eta_days(fsel)
		var fpos := ftip + Vector2(8.0 / z, -8.0 / z)
		draw_string_outline(_font, fpos, feta, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, int(13.0 / z)), 3, Color(0, 0, 0, 0.8))
		draw_string(_font, fpos, feta, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, int(13.0 / z)), Color(0.85, 0.95, 1))

	var sel: Army = Game.armies.get(selected_army)
	if sel != null and sel.is_moving():
		var pts := PackedVector2Array()
		pts.append(Game.provinces[sel.province_id].center)
		for pid in sel.path:
			pts.append(Game.provinces[pid].center)
		var rc := Color(0.55, 0.12, 0.08, 0.95)
		for i in range(pts.size() - 1):
			draw_dashed_line(pts[i], pts[i + 1], rc, 2.5 / z, 7.0 / z)
		var tip: Vector2 = pts[pts.size() - 1]
		var dir: Vector2 = (tip - pts[pts.size() - 2]).normalized()
		var sz := 11.0 / z
		var nrm := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip + dir * sz, tip - dir * sz * 0.6 + nrm * sz * 0.7, tip - dir * sz * 0.6 - nrm * sz * 0.7]), rc)
		var eta := "%d d" % Game.eta_days(sel)
		draw_string_outline(_font, tip + Vector2(sz * 0.8, -sz), eta, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, int(13.0 / z)), 3, Color(0, 0, 0, 0.8))
		draw_string(_font, tip + Vector2(sz * 0.8, -sz), eta, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, int(13.0 / z)), Color(1, 0.95, 0.7))

	# Marcadores
	var fs := maxi(8, int(12.0 / z))
	for m in _layout():
		var a: Army = Game.armies[int(m["id"])]
		var r: Rect2 = m["rect"]
		var col := Color(0.5, 0.5, 0.5)
		if a.owner_id >= 0 and a.owner_id < Game.countries.size():
			col = Game.countries[a.owner_id].color
		draw_rect(r.grow(1.5 / z), Color(0.96, 0.93, 0.82))
		Flag.draw(self, r, Game.countries[a.owner_id].tag if a.owner_id >= 0 and a.owner_id < Game.countries.size() else "", col)
		var is_sel := a.id == selected_army
		draw_rect(r, Color(1, 1, 0.3) if is_sel else Color(0, 0, 0, 0.85), false, (2.5 if is_sel else 1.2) / z)
		var text := str(a.regiments)
		var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var tp := Vector2(r.position.x, r.position.y + (r.size.y + ts.y * 0.7) * 0.5)
		draw_string_outline(_font, tp, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(_font, tp, text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color.WHITE)

	# Frotas
	for m in _fleet_layout():
		var f: Fleet = Game.fleets[int(m["id"])]
		var fr: Rect2 = m["rect"]
		var fcol := Color(0.5, 0.5, 0.5)
		var ftag := ""
		if f.owner_id >= 0 and f.owner_id < Game.countries.size():
			fcol = Game.countries[f.owner_id].color
			ftag = Game.countries[f.owner_id].tag
		_draw_ship_icon(fr, fcol, z)
		draw_rect(fr.grow(1.5 / z), Color(0.96, 0.93, 0.82))
		Flag.draw(self, fr, ftag, fcol)
		var fsel_on := f.id == selected_fleet
		draw_rect(fr, Color(0.3, 0.9, 1) if fsel_on else Color(0, 0, 0, 0.85), false, (2.5 if fsel_on else 1.2) / z)
		var ftext := str(f.ships)
		var fts := _font.get_string_size(ftext, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var ftp := Vector2(fr.position.x, fr.position.y + (fr.size.y + fts.y * 0.7) * 0.5)
		draw_string_outline(_font, ftp, ftext, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(_font, ftp, ftext, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, fs, Color.WHITE)
