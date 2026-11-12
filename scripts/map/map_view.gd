class_name MapView
extends Node2D
## Camada ESTÁTICA do mapa: malha colorida das províncias (GPU), fronteiras, costas e nomes.
## Só é redesenhada quando algo muda (dono, modo de mapa) ou o zoom muda de "faixa";
## seleção, exércitos e marcações dinâmicas ficam em MapOverlay.
##
## A malha é uma única ArrayMesh (todas as províncias, triangulação feita uma vez em
## Province.from_dict), então zoom e pan não custam CPU.

enum Mode { POLITICAL, TERRAIN, POPULATION, RESOURCE }

const MODE_NAMES: Array[String] = ["Político", "Terreno", "População", "Recursos"]
const GRID_SIZE := 100.0
const OCEAN_COLOR := Color(0.055, 0.15, 0.21)   # azul petróleo escuro
const UNOWNED_COLOR := Color(0.86, 0.80, 0.64)  # pergaminho: terra sem dono
const ZOOM_STEP := 1.35   # o zoom é agrupado em faixas deste fator para redesenhar pouco

var mode: int = Mode.POLITICAL
var zoom_level: float = 1.0

var _terrain_colors: Dictionary = {
	"plains": Color("a9c26b"), "hills": Color("8f9a5b"), "mountains": Color("8a7f78"),
	"forest": Color("4f7f4a"), "desert": Color("d9bd7a"), "jungle": Color("2f6b3a"),
	"tundra": Color("c9d1cf"),
}
var _resource_colors: Dictionary = {
	"grain": Color("e3c75a"), "livestock": Color("c98f5a"), "fish": Color("4aa3c7"),
	"timber": Color("5b8a43"), "furs": Color("8a6a4a"), "wool": Color("e8e2d0"),
	"cotton": Color("f1ede0"), "coal": Color("3d3d46"), "iron": Color("8c96a3"),
	"salt": Color("d8d8f0"), "wine": Color("8a2f5a"), "sugar": Color("f4d6e8"),
	"tobacco": Color("9a7a3a"), "coffee": Color("5a3a22"), "tea": Color("7aa84a"),
	"silk": Color("d86aa8"), "spices": Color("d8662a"), "opium": Color("a06ad8"),
	"gold": Color("ffc61a"),
}

var _fills: Array[Color] = []
var _grid: Dictionary = {}        # Vector2i -> Array[int] de ids de províncias
var _prov_lines: PackedVector2Array = PackedVector2Array()
var _country_lines: PackedVector2Array = PackedVector2Array()
var _coast_lines: PackedVector2Array = PackedVector2Array()
var _sea_lines: PackedVector2Array = PackedVector2Array()
var _ocean: Polygon2D
var _mesh_node: MeshInstance2D
var _font: Font
var _max_pop: int = 1
var _bucket: int = 0


func _ready() -> void:
	_font = ThemeDB.fallback_font

	# Filhos "atrás do pai": o oceano e a malha ficam sob o que _draw() desenha.
	_ocean = Polygon2D.new()
	_ocean.color = OCEAN_COLOR
	_ocean.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(Game.map_size.x, 0.0), Game.map_size, Vector2(0.0, Game.map_size.y),
	])
	_ocean.show_behind_parent = true
	add_child(_ocean)
	_mesh_node = MeshInstance2D.new()
	_mesh_node.show_behind_parent = true
	add_child(_mesh_node)

	_build_grid()
	_build_coast_and_sea()
	_refresh_all()
	Events.province_changed.connect(_on_province_changed)
	Events.month_changed.connect(_on_month_changed)
	Events.state_loaded.connect(_refresh_all)


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------
func set_zoom_level(z: float) -> void:
	var b := int(floor(log(maxf(z, 0.01)) / log(ZOOM_STEP)))
	if b == _bucket:
		return
	_bucket = b
	zoom_level = pow(ZOOM_STEP, float(b))
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
		if p.edges.size() == n:
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
		if p.edges.size() != n:
			continue   # polígono substituído pelo casco convexo
		for i in n:
			var nb: int = p.edges[i]
			if nb < 0:
				continue
			# A aresta costuma existir nos dois lados; desenha uma vez só.
			if nb < p.id and Game.provinces[nb].edges.has(p.id):
				continue
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
	_rebuild_mesh()


func _province_color(p: Province) -> Color:
	var shade := float((p.id * 7) % 5) * 0.02   # variação sutil para distinguir províncias
	if mode == Mode.TERRAIN:
		var tc: Color = _terrain_colors.get(p.terrain, Color.GRAY)
		return tc.darkened(shade)
	if mode == Mode.RESOURCE:
		var rc: Color = _resource_colors.get(p.resource_type, Color.GRAY)
		return rc.darkened(shade)
	if mode == Mode.POPULATION:
		var t := pow(float(p.population) / float(_max_pop), 0.3)   # curva suave: realça diferenças
		return Color(0.95, 0.92, 0.80).lerp(Color(0.62, 0.12, 0.08), t)
	# Político
	if p.owner_id < 0 or p.owner_id >= Game.countries.size():
		return UNOWNED_COLOR.darkened(shade)
	return Game.countries[p.owner_id].color.darkened(shade)


## Uma única malha com todas as províncias (cor por vértice).
func _rebuild_mesh() -> void:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for p in Game.provinces:
		var base := verts.size()
		var col := _fills[p.id]
		verts.append_array(p.poly)
		for i in p.poly.size():
			colors.append(col)
		for t in p.tris:
			indices.append(base + t)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_node.mesh = mesh


# ---------------------------------------------------------------------------
# Desenho
# ---------------------------------------------------------------------------
func _draw() -> void:
	if not Game.loaded:
		return
	var z := maxf(zoom_level, 0.05)

	if mode == Mode.POLITICAL:
		_draw_graticule(z)
		_draw_ocean_labels(z)
	# Divisões internas só aparecem com zoom (fade entre 1,2x e 2,4x): mapa limpo de longe.
	var prov_alpha := clampf((z - 1.2) / 1.2, 0.0, 1.0) * 0.35
	if prov_alpha > 0.01:
		draw_multiline(_prov_lines, Color(0.25, 0.17, 0.08, prov_alpha), -1.0)          # 1 px fixo na tela
	draw_multiline(_country_lines, Color(0.22, 0.12, 0.05, 0.95), 2.2 / z)
	draw_multiline(_coast_lines, Color(0.20, 0.14, 0.08, 0.9), 1.6 / z)
	if mode == Mode.POLITICAL:
		if z >= 2.0:
			draw_multiline(_sea_lines, Color(0.85, 0.92, 1.0, 0.35), -1.0)
		if z <= 3.0:
			_draw_country_labels(z)


const OCEAN_NAMES := [
	["ATLÂNTICO", 0.41, 0.34], ["ATLÂNTICO", 0.47, 0.72],
	["PACÍFICO", 0.115, 0.60], ["PACÍFICO", 0.955, 0.50],
	["ÍNDICO", 0.69, 0.66], ["ÁRTICO", 0.5, 0.03],
]


## Grade de meridianos (30°) e paralelos (30°, projeção Miller), como nos mapas antigos.
func _draw_graticule(z: float) -> void:
	var w := Game.map_size.x
	var h := Game.map_size.y
	var col := Color(0.55, 0.78, 0.88, 0.10)
	for lon in range(-150, 180, 30):
		var x := (float(lon) + 180.0) / 360.0 * w
		draw_line(Vector2(x, 0), Vector2(x, h), col, -1.0)
	var top := _miller(85.0)
	var bot := _miller(-85.0)
	for lat in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var y := (top - _miller(lat)) / (top - bot) * h
		draw_line(Vector2(0, y), Vector2(w, y), col, -1.0)


static func _miller(lat_deg: float) -> float:
	return 1.25 * log(tan(PI / 4.0 + 0.4 * deg_to_rad(lat_deg)))


func _draw_ocean_labels(z: float) -> void:
	if z > 2.5:
		return
	var fs := clampi(int(22.0 / z), 12, 44)
	for o in OCEAN_NAMES:
		var text: String = o[0]
		var pos := Vector2(float(o[1]) * Game.map_size.x, float(o[2]) * Game.map_size.y)
		var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(_font, pos - Vector2(ts.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.60, 0.80, 0.90, 0.42))


func _draw_country_labels(z: float) -> void:
	for c in Game.countries:
		if not c.is_alive():
			continue
		var fs := mini(c.label_size, int(40.0 / z))
		var text := c.name.to_upper()
		var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		# Cabe dentro do país: reduz a fonte; se ficar ilegível, tenta a sigla; senão some.
		var max_w := maxf(c.bounds.size.x * 0.85, 1.0)
		if ts.x > max_w:
			fs = int(float(fs) * max_w / ts.x)
			if float(fs) * z < 11.0:
				text = c.tag
				fs = mini(c.label_size, int(40.0 / z))
				ts = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				if ts.x > max_w:
					fs = int(float(fs) * max_w / ts.x)
			else:
				ts = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		if float(fs) * z < 9.0:
			continue
		ts = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := c.label_pos - Vector2(ts.x * 0.5, -ts.y * 0.3)
		draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.12)), Color(0, 0, 0, 0.65))
		draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
