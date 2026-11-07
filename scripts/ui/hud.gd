class_name HUD
extends CanvasLayer
## Interface do jogo, montada 100% por código (sem .tscn para manter o diff limpo).
## Barra superior: país, tesouro, data e velocidade.
## Canto inferior esquerdo: informações da província selecionada.
## Canto inferior direito: modo do mapa e impostos.
##
## A HUD nunca muda o estado: ela chama Game.submit_command().

const DEBUG_TOOLS := true
const MARGIN := 10.0

const TERRAIN_PT := {
	"plains": "Planície", "hills": "Colinas", "mountains": "Montanhas",
	"forest": "Floresta", "desert": "Deserto",
}
const RESOURCE_PT := {
	"grain": "Grãos", "iron": "Ferro", "coal": "Carvão", "timber": "Madeira",
	"cotton": "Algodão", "fish": "Peixe", "gold": "Ouro", "salt": "Sal",
}

var map_view: MapView

var _root: Control
var _theme: Theme
var _blockers: Array[Control] = []
var _inset: Vector4 = Vector4.ZERO   # esquerda, topo, direita, base (área segura)

var _flag: ColorRect
var _country_label: Label
var _treasury_label: Label
var _date_label: Label
var _speed_buttons: Array[Button] = []

var _info_panel: PanelContainer
var _info_title: Label
var _info_body: Label
var _btn_take: Button
var _btn_annex: Button

var _mode_button: Button
var _tax_label: Label

var _selected: int = -1


func _ready() -> void:
	layer = 10
	_compute_safe_area()
	_build_theme()

	_root = Control.new()
	_root.theme = _theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_build_top_bar()
	_build_info_panel()
	_build_bottom_right()

	Events.day_changed.connect(_on_day_changed)
	Events.month_changed.connect(_on_month_changed)
	Events.treasury_changed.connect(_on_treasury_changed)
	Events.speed_changed.connect(_on_speed_changed)
	Events.province_selected.connect(_on_province_selected)
	Events.province_changed.connect(_on_province_changed)
	Events.player_country_changed.connect(_on_player_changed)
	Events.map_mode_changed.connect(_on_map_mode_changed)
	Events.state_loaded.connect(_refresh_all)
	_refresh_all()


## Usado pela câmera para não tratar toques sobre a UI como toques no mapa.
func is_over_ui(pos: Vector2) -> bool:
	for c in _blockers:
		if c.visible and c.get_global_rect().has_point(pos):
			return true
	return false


# ---------------------------------------------------------------------------
# Construção
# ---------------------------------------------------------------------------
func _compute_safe_area() -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0:
		return
	var vp := get_viewport().get_visible_rect().size
	var sx := vp.x / float(screen.x)
	var sy := vp.y / float(screen.y)
	_inset = Vector4(
		float(safe.position.x) * sx,
		float(safe.position.y) * sy,
		float(screen.x - safe.end.x) * sx,
		float(screen.y - safe.end.y) * sy
	)


func _build_theme() -> void:
	_theme = Theme.new()
	_theme.default_font_size = 22
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.88)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	_theme.set_stylebox("panel", "PanelContainer", sb)


func _make_button(text: String, min_size: Vector2 = Vector2(64, 52)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	return b


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.anchor_right = 1.0
	bar.offset_left = _inset.x + MARGIN
	bar.offset_right = -(_inset.z + MARGIN)
	bar.offset_top = _inset.y + MARGIN
	_root.add_child(bar)
	_blockers.append(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	_flag = ColorRect.new()
	_flag.custom_minimum_size = Vector2(40, 40)
	_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_flag)

	_country_label = Label.new()
	_country_label.add_theme_font_size_override("font_size", 26)
	row.add_child(_country_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_treasury_label = Label.new()
	row.add_child(_treasury_label)

	_date_label = Label.new()
	_date_label.custom_minimum_size = Vector2(150, 0)
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_date_label)

	var group := ButtonGroup.new()
	var labels: Array[String] = ["II", ">", ">>", ">>>", ">>>>"]
	for i in labels.size():
		var b := _make_button(labels[i], Vector2(58, 48))
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_on_speed_pressed.bind(i))
		row.add_child(b)
		_speed_buttons.append(b)


func _build_info_panel() -> void:
	var width := 400.0
	_info_panel = PanelContainer.new()
	_info_panel.custom_minimum_size = Vector2(width, 0)
	_info_panel.anchor_top = 1.0
	_info_panel.anchor_bottom = 1.0
	_info_panel.offset_left = _inset.x + MARGIN
	_info_panel.offset_right = _inset.x + MARGIN + width
	_info_panel.offset_top = -(_inset.w + MARGIN)
	_info_panel.offset_bottom = -(_inset.w + MARGIN)
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info_panel.visible = false
	_root.add_child(_info_panel)
	_blockers.append(_info_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_info_panel.add_child(col)

	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 30)
	col.add_child(_info_title)

	_info_body = Label.new()
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info_body)

	_btn_take = _make_button("Assumir este país")
	_btn_take.pressed.connect(_on_take_pressed)
	col.add_child(_btn_take)

	_btn_annex = _make_button("Anexar província (debug)")
	_btn_annex.pressed.connect(_on_annex_pressed)
	col.add_child(_btn_annex)


func _build_bottom_right() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -(_inset.z + MARGIN)
	panel.offset_right = -(_inset.z + MARGIN)
	panel.offset_top = -(_inset.w + MARGIN)
	panel.offset_bottom = -(_inset.w + MARGIN)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	_blockers.append(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	_mode_button = _make_button("Mapa: Político", Vector2(250, 52))
	_mode_button.pressed.connect(_on_mode_pressed)
	col.add_child(_mode_button)

	var tax_row := HBoxContainer.new()
	tax_row.add_theme_constant_override("separation", 8)
	col.add_child(tax_row)

	var tax_title := Label.new()
	tax_title.text = "Impostos"
	tax_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tax_row.add_child(tax_title)

	var minus := _make_button("-", Vector2(52, 52))
	minus.pressed.connect(_on_tax_pressed.bind(-5))
	tax_row.add_child(minus)

	_tax_label = Label.new()
	_tax_label.custom_minimum_size = Vector2(60, 0)
	_tax_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tax_row.add_child(_tax_label)

	var plus := _make_button("+", Vector2(52, 52))
	plus.pressed.connect(_on_tax_pressed.bind(5))
	tax_row.add_child(plus)


# ---------------------------------------------------------------------------
# Atualização
# ---------------------------------------------------------------------------
func _refresh_all() -> void:
	_refresh_top()
	_refresh_info()
	_on_map_mode_changed(map_view.mode if map_view != null else 0)


func _refresh_top() -> void:
	var c := Game.countries[Game.player_country]
	_flag.color = c.color
	_country_label.text = c.name
	var e := Game.estimate_monthly(c)
	var net: int = int(e["income"]) - int(e["expense"])
	_treasury_label.text = "Tesouro: %d  (%+d/mês)" % [c.treasury, net]
	_date_label.text = Game.clock.format()
	_tax_label.text = "%d%%" % c.tax_pct
	var s := clampi(Game.speed, 0, _speed_buttons.size() - 1)
	_speed_buttons[s].set_pressed_no_signal(true)


func _refresh_info() -> void:
	if _selected < 0 or _selected >= Game.provinces.size():
		_info_panel.visible = false
		return
	var p := Game.provinces[_selected]
	var owner_c := Game.countries[p.owner_id]
	_info_panel.visible = true
	_info_title.text = p.name
	_info_title.add_theme_color_override("font_color", owner_c.color.lightened(0.4))
	var coast_txt := "sim" if p.coastal else "não"
	_info_body.text = "País: %s\nTerreno: %s\nRecurso: %s\nPopulação: %.1f mil\nRenda mensal: +%d\nLitoral: %s\nVizinhas: %d" % [
		owner_c.name,
		TERRAIN_PT.get(p.terrain, p.terrain),
		RESOURCE_PT.get(p.resource_type, p.resource_type),
		float(p.population) / 1000.0,
		p.monthly_income(owner_c.tax_pct),
		coast_txt,
		p.neighbors.size(),
	]
	var foreign := p.owner_id != Game.player_country
	_btn_take.visible = foreign and not Net.is_online()
	_btn_annex.visible = DEBUG_TOOLS and foreign


# ---------------------------------------------------------------------------
# Eventos do jogo
# ---------------------------------------------------------------------------
func _on_day_changed(_date: Dictionary) -> void:
	_date_label.text = Game.clock.format()


func _on_month_changed(_date: Dictionary) -> void:
	_refresh_top()
	_refresh_info()


func _on_treasury_changed(cid: int) -> void:
	if cid == Game.player_country:
		_refresh_top()
		_refresh_info()


func _on_speed_changed(s: int) -> void:
	_speed_buttons[clampi(s, 0, _speed_buttons.size() - 1)].set_pressed_no_signal(true)


func _on_province_selected(pid: int) -> void:
	_selected = pid
	_refresh_info()


func _on_province_changed(_pid: int) -> void:
	_refresh_top()
	_refresh_info()


func _on_player_changed(_cid: int) -> void:
	_refresh_top()
	_refresh_info()


func _on_map_mode_changed(mode: int) -> void:
	_mode_button.text = "Mapa: %s" % MapView.MODE_NAMES[mode]


# ---------------------------------------------------------------------------
# Ações do jogador
# ---------------------------------------------------------------------------
func _on_speed_pressed(index: int) -> void:
	Game.submit_command(Cmd.set_speed(index))


func _on_tax_pressed(delta: int) -> void:
	var c := Game.countries[Game.player_country]
	Game.submit_command(Cmd.set_tax(c.id, clampi(c.tax_pct + delta, 0, 100)))


func _on_mode_pressed() -> void:
	if map_view != null:
		map_view.cycle_mode()


func _on_take_pressed() -> void:
	if _selected >= 0:
		Game.set_player_country(Game.provinces[_selected].owner_id)


func _on_annex_pressed() -> void:
	if _selected >= 0:
		Game.submit_command(Cmd.transfer_province(_selected, Game.player_country))
