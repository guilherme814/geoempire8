class_name MapView
extends Node2D
## Renderização do mapa por províncias + seleção por toque.
##
## Tudo é desenhado em _draw() só quando algo muda (queue_redraw), então o custo
## em repouso é zero. Larguras de linha são divididas pelo zoom para manter a
## espessura constante na tela.

enum Mode { POLITICAL, TERRAIN, POPULATION, RESOURCE }

const MODE_NAMES: Array[String] = ["Político", "Terreno", "População", "Recursos"]
const GRID_SIZE := 120.0
const OCEAN_COLOR := Color(0.13, 0.27, 0.42)

var mode: int = Mode.POLITICAL
var selected_province: int = -1
var zoom_level: float = 1.0

var _terrain_colors: Dictionary = {
	"plains": Color("a9c26b"),
	"hills": Color("8f9a5b"),
	"mountains": Color("8a7f78"),
	"forest": Color("4f7f4a"),
	"desert": Color("d9bd7a"),
}
var _resource_colors: Dictionary = {
	"grain": Color("e3c75a"),
	"iron": Color("8c96a3"),
	"coal": Color("3d3d46"),
	"timber": Color("5b8a43"),
	"cotton": Color("f1ede0"),
	"fish": Color("4aa3c7"),
	"gold": Color("ffc61a"),
	"salt": Color("d8d8f0"),
}

var _fills: Array[Color] = []
var _grid: Dictionary = {}     # Vector2i -> Array[int] de ids de províncias
var _prov_lines: PackedVector2Array = PackedVector2Array()
var _country_lines: PackedVector2Array = PackedVector2Array()
var _coast_lines: PackedVector2Array = PackedVector2Array()
var _sea_lines: PackedVector2Array = PackedVector2Array()
var _font: Font
var _max_pop: int = 1


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_build_grid()
	_build_coast_and_sea()
	_refresh_all()
	Events.province_selected.connect(set_selected)
	Events.province_changed.connect(_on_province_changed)
	Events.month_changed.connect(_on_month_changed)
	Events.state_loaded.connect(_refresh_all)


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------
func set_selected(pid: int) -> void:
	selected_province = pid
	queue_redraw()


func set_zoom_level(z: float) -> void:
	zoom_level = z
	queue_redraw()


func set_mode(m: int) -> void:
	mode = wrapi(m, 0, Mode.size())
	_recolor()
	queue_redraw()
	Events.map_mode_changed.emit(mode)


func cycle_mode() -> void:
	set_mode(mode + 1)


## Retorna o id da província sob a posição do mundo, ou -1 (mar).
func province_at(world_pos: Vector2) -> int:
	var key := Vector2i(int(floor(world_pos.x / GRID_SIZE)), int(floor(world_pos.y / GRID_SIZE)))
	if not _grid.has(key):
		return -1
	for pid in _grid[key]:
		if Geometry2D.is_point_in_polygon(world_pos, Game.provinces[pid].poly):
			return pid
	return -1


# ---------------------------------------------------------------------------
# Construção de dados de desenho
# ---------------------------------------------------------------------------
func _refresh_all() -> void:
	_rebuild_borders()
	_recolor()
	queue_redraw()


func _on_province_changed(_pid: int) -> void:
	_refresh_all()


func _on_month_changed(_date: Dictionary) -> void:
	if mode == Mode.POPULATION:
		_recolor()
		queue_redraw()


func _build_grid() -> void:
	_grid.clear()
	for p in Game.provinces:
		var x0 := int(floor(p.bounds.position.x / GRID_SIZE))
		var x1 := int(floor(p.bounds.end.x / GRID_SIZE))
		var y0 := int(floor(p.bounds.position.y / GRID_SIZE))
		var y1 := int(floor(p.bounds.end.y / GRID_SIZE))
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var key := Vector2i(gx, gy)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(p.id)


func _on_map_boundary(a: Vector2, b: Vector2) -> bool:
	var w := Game.map_size.x
	var h := Game.map_size.y
	if a.x <= 0.5 and b.x <= 0.5:
		return true
	if a.x >= w - 0.5 and b.x >= w - 0.5:
		return true
	if a.y <= 0.5 and b.y <= 0.5:
		return true
	if a.y >= h - 0.5 and b.y >= h - 0.5:
		return true
	return false


## Costa e rotas marítimas não mudam durante o jogo: calculadas uma vez.
func _build_coast_and_sea() -> void:
	_coast_lines.clear()
	_sea_lines.clear()
	for p in Game.provinces:
		var n := p.poly.size()
		for i in n:
			if p.edges[i] >= 0:
				continue
			var a := p.poly[i]
			var b := p.poly[(i + 1) % n]
			if not _on_map_boundary(a, b):
				_coast_lines.append(a)
				_coast_lines.append(b)
		for s in p.sea_links:
			if s > p.id:
				_sea_lines.append(p.center)
				_sea_lines.append(Game.provinces[s].center)


## Fronteiras mudam quando uma província troca de dono.
func _rebuild_borders() -> void:
	_prov_lines.clear()
	_country_lines.clear()
	for p in Game.provinces:
		var n := p.poly.size()
		for i in n:
			var nb: int = p.edges[i]
			if nb <= p.id:
				continue   # mar (-1) ou já desenhada pelo vizinho de id menor
			var a := p.poly[i]
			var b := p.poly[(i + 1) % n]
			if Game.provinces[nb].owner_id != p.owner_id:
				_country_lines.append(a)
				_country_lines.append(b)
			else:
				_prov_lines.append(a)
				_prov_lines.append(b)


func _recolor() -> void:
	_fills.clear()
	_max_pop = 1
	for p in Game.provinces:
		_max_pop = maxi(_max_pop, p.population)
	for p in Game.provinces:
		_fills.append(_province_color(p))


func _province_color(p: Province) -> Color:
	var shade := float((p.id * 7) % 5) * 0.02   # variação sutil para distinguir províncias
	if mode == Mode.TERRAIN:
		var tc: Color = _terrain_colors.get(p.terrain, Color.GRAY)
		return tc.darkened(shade)
	if mode == Mode.RESOURCE:
		var rc: Color = _resource_colors.get(p.resource_type, Color.GRAY)
		return rc.darkened(shade)
	if mode == Mode.POPULATION:
		var t := sqrt(float(p.population) / float(_max_pop))
		return Color(0.95, 0.92, 0.80).lerp(Color(0.62, 0.12, 0.08), t)
	# Político
	if p.owner_id < 0 or p.owner_id >= Game.countries.size():
		return Color(0.6, 0.6, 0.6)
	return Game.countries[p.owner_id].color.darkened(shade)


# ---------------------------------------------------------------------------
# Desenho
# ---------------------------------------------------------------------------
func _draw() -> void:
	if not Game.loaded or _fills.size() != Game.provinces.size():
		return
	var z := maxf(zoom_level, 0.05)

	draw_rect(Rect2(Vector2.ZERO, Game.map_size), OCEAN_COLOR)

	for p in Game.provinces:
		draw_colored_polygon(p.poly, _fills[p.id])

	draw_multiline(_prov_lines, Color(0, 0, 0, 0.28), 1.0 / z)
	draw_multiline(_country_lines, Color(0.04, 0.04, 0.06, 0.95), 2.4 / z)
	draw_multiline(_coast_lines, Color(0.05, 0.10, 0.16, 0.9), 1.8 / z)
	if mode == Mode.POLITICAL:
		draw_multiline(_sea_lines, Color(0.85, 0.92, 1.0, 0.35), 1.5 / z)

	if selected_province >= 0 and selected_province < Game.provinces.size():
		var sp := Game.provinces[selected_province]
		draw_colored_polygon(sp.poly, Color(1, 1, 1, 0.25))
		var outline: PackedVector2Array = sp.poly.duplicate()
		outline.append(sp.poly[0])
		draw_polyline(outline, Color(1.0, 0.92, 0.35), 3.0 / z)

	if mode == Mode.POLITICAL and z <= 3.0:
		_draw_country_labels(z)


func _draw_country_labels(z: float) -> void:
	for c in Game.countries:
		if not c.is_alive():
			continue
		# Mantém o texto com no máximo ~64 px na tela; some se ficar minúsculo.
		var fs := mini(c.label_size, int(64.0 / z))
		if float(fs) * z < 9.0:
			continue
		var text := c.name.to_upper()
		var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := c.label_pos - Vector2(ts.x * 0.5, -ts.y * 0.3)
		draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.12)), Color(0, 0, 0, 0.65))
		draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
