class_name HUD
extends CanvasLayer
## Interface do jogo, montada 100% por código (sem .tscn para manter o diff limpo).
##
## Layout (inspirado em Victoria 3 e Age of History 3):
##  - barra superior: bandeira, país, indicadores (tesouro, população, alfabetização, padrão
##    de vida, tecnologia, estabilidade, exército), data e velocidade;
##  - barra lateral esquerda: Política, Economia, Mercado, modo do mapa e menu;
##  - dock inferior: construções (Governo, Recursos, Indústria);
##  - canto inferior esquerdo: província selecionada; direito: exército selecionado;
##  - lista de exércitos e guerras no canto superior direito;
##  - janelas centrais para Economia, Mercado, Política e Menu.
##
## A HUD nunca muda o estado: ela chama Game.submit_command().

signal country_select_requested

const DEBUG_TOOLS := true
const MARGIN := 10.0
const SIDE_W := 92.0

const TERRAIN_PT := {
	"plains": "Planície", "hills": "Colinas", "mountains": "Montanhas", "forest": "Floresta",
	"desert": "Deserto", "jungle": "Selva", "tundra": "Tundra",
}
const RESOURCE_PT := {
	"grain": "Grãos", "livestock": "Gado", "fish": "Peixe", "timber": "Madeira",
	"furs": "Peles", "wool": "Lã", "cotton": "Algodão", "coal": "Carvão", "iron": "Ferro",
	"salt": "Sal", "wine": "Vinho", "sugar": "Açúcar", "tobacco": "Tabaco", "coffee": "Café",
	"tea": "Chá", "silk": "Seda", "spices": "Especiarias", "opium": "Ópio", "gold": "Ouro",
	"fabric": "Tecido", "tools": "Ferramentas", "furniture": "Móveis", "steel": "Aço",
}
const CLASS_PT := ["Camponeses", "Operários", "Aristocratas", "Burguesia", "Funcionários", "Soldados"]
const CLASS_WHY := [
	"Camponeses: comida cara ou impostos altos",
	"Operários: custo de vida, baixo padrão de vida ou impostos",
	"Aristocratas: impostos altos e avanço da educação",
	"Burguesia: pouco comércio e indústria, embargos ou bloqueio",
	"Funcionários: tesouro vazio ou pouca instrução",
	"Soldados: soldos atrasados (tesouro negativo)",
]
const IDEO_PT := ["Conservadorismo", "Liberalismo", "Socialismo", "Nacionalismo", "Reacionarismo"]
const IDEO_COLORS := [
	Color(0.38, 0.58, 0.88), Color(0.96, 0.80, 0.30), Color(0.90, 0.30, 0.30),
	Color(0.35, 0.76, 0.46), Color(0.68, 0.46, 0.82),
]
const TAB_PT := {"gov": "Governo", "res": "Recursos", "ind": "Indústria", "inf": "Infra"}
const BUILD_ICON := {
	"school": "book", "university": "cap", "barracks": "tent", "hospital": "cross",
	"mine": "pick", "farm": "wheat", "logging": "tree", "workshop": "hammer",
	"textile": "spool", "carpentry": "logs", "smithy": "anvil", "steel": "ingot",
	"market": "stall", "railway": "rail", "dock": "anchor",
}
const TAB_ICON := {"gov": "building", "res": "pick", "ind": "factory", "inf": "rail"}
const TAB_ORDER := ["gov", "res", "ind", "inf"]

var map_view: MapView

var _root: Control
var _ui: Control              # área segura (recortes e barras do sistema)
var _body: Control            # abaixo da barra superior
var _theme: Theme
var _blockers: Array[Control] = []
var _inset: Vector4 = Vector4.ZERO   # esquerda, topo, direita, base (área segura)

# Barra superior
var _bar: PanelContainer
var _flag: FlagRect
var _country_label: Label
var _country_sub: Label
var _chips: Dictionary = {}
var _date_label: Label
var _speed_buttons: Array[Button] = []

# Barra lateral e janelas
var _side_btns: Dictionary = {}
var _windows: Dictionary = {}
var _win_bodies: Dictionary = {}

# Lista de exércitos / guerras
var _side_panel: PanelContainer
var _side_armies: VBoxContainer
var _side_wars: VBoxContainer
var _side_head: Label
var _army_rows: Dictionary = {}
var _wars_sig: String = ""

# Província
var _info_panel: PanelContainer
var _info_flag: FlagRect
var _info_title: Label
var _info_sub: Label
var _info_body: Label
var _btn_recruit: Button
var _btn_take: Button
var _btn_diplo: Button
var _btn_annex: Button
var _btn_war: Button
var _btn_improve: Button
var _btn_ally: Button
var _btn_embargo: Button
var _btn_ship: Button

# Construções
var _build_tab: String = ""
var _build_panel: PanelContainer
var _build_head: Label
var _build_rows: VBoxContainer
var _build_tab_btns: Dictionary = {}
var _diplo_target: int = -1
var _win_sizes: Dictionary = {}   # janela -> tamanho desejado
var _build_scroll: ScrollContainer
var _build_open: Dictionary = {}   # kind -> detalhes expandidos

# Exército selecionado
var _army_panel: PanelContainer
var _army_model: ArmyModel
var _army_label: Label
var _btn_army_stop: Button
var _btn_army_disband: Button

# Aviso e evento
var _toast_panel: PanelContainer
var _toast: Label
var _toast_seq: int = 0
var _event_panel: PanelContainer
var _event_title: Label
var _event_text: Label
var _event_options: VBoxContainer
var _event_timer: Label
var _event_uid: int = -1

var _selected: int = -1
var _selected_army: int = -1


func _ready() -> void:
	layer = 10
	_compute_safe_area()
	_theme = UIKit.make_theme()

	_root = Control.new()
	_root.theme = _theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.offset_left = _inset.x
	_ui.offset_top = _inset.y
	_ui.offset_right = -_inset.z
	_ui.offset_bottom = -_inset.w
	_root.add_child(_ui)

	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.offset_top = 84
	_ui.add_child(_body)

	_build_top_bar()
	_build_sidebar()
	_build_side_list()
	_build_info_panel()
	_build_army_panel()
	_build_dock()
	_build_toast()
	_build_windows()
	_build_event_popup()
	_build_offer_panel()

	Events.game_event_changed.connect(_refresh_event)
	Events.day_changed.connect(_on_day_changed)
	Events.notice.connect(_show_toast)
	Events.war_changed.connect(_refresh_top)
	Events.war_changed.connect(_refresh_info)
	Events.war_changed.connect(_refresh_offers)
	Events.state_loaded.connect(_refresh_offers)
	Events.month_changed.connect(_on_month_changed)
	Events.treasury_changed.connect(_on_treasury_changed)
	Events.speed_changed.connect(_on_speed_changed)
	Events.province_selected.connect(_on_province_selected)
	Events.province_changed.connect(_on_province_updated)
	Events.province_updated.connect(_on_province_updated)
	Events.player_country_changed.connect(_on_player_changed)
	Events.map_mode_changed.connect(_on_map_mode_changed)
	Events.army_selected.connect(_on_army_selected)
	Events.army_changed.connect(_on_army_changed)
	Events.army_removed.connect(_on_army_removed)
	Events.command_applied.connect(_on_command_applied)
	Events.state_loaded.connect(_refresh_all)
	_refresh_all()


## Usado pela câmera para não tratar toques sobre a UI como toques no mapa.
func is_over_ui(pos: Vector2) -> bool:
	if _root == null or not _root.visible:
		return false
	for c in _blockers:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


func set_ui_visible(v: bool) -> void:
	if _root != null:
		_root.visible = v


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


func _make_button(text: String, min_size: Vector2 = Vector2(64, 46)) -> Button:
	return UIKit.button(text, min_size)


func _build_top_bar() -> void:
	_bar = PanelContainer.new()
	_bar.theme_type_variation = "BarPanel"
	_bar.anchor_right = 1.0
	_ui.add_child(_bar)
	_blockers.append(_bar)
	_bar.resized.connect(_on_bar_resized)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_bar.add_child(row)

	var frame := PanelContainer.new()
	frame.theme_type_variation = "FlagFrame"
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(frame)
	_flag = FlagRect.new()
	_flag.custom_minimum_size = Vector2(66, 44)
	frame.add_child(_flag)

	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", -1)
	row.add_child(names)
	_country_label = UIKit.serif_label("", 23, UIKit.GOLD_BRIGHT)
	_country_label.custom_minimum_size = Vector2(190, 0)
	_country_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(_country_label)
	_country_sub = UIKit.label("", 14, UIKit.TEXT_DIM)
	names.add_child(_country_sub)

	var sep := VSeparator.new()
	row.add_child(sep)

	_add_chip(row, "gold", "coin", "Tesouro e saldo mensal")
	_add_chip(row, "pop", "people", "População total")
	_add_chip(row, "lit", "book", "Alfabetização: aumenta a arrecadação e a pesquisa")
	_add_chip(row, "sol", "star", "Padrão de vida: produção por habitante e instrução")
	_add_chip(row, "tech", "bulb", "Tecnologia: libera indústrias avançadas")
	_add_chip(row, "stab", "shield", "Estabilidade interna: abaixo de 40% a arrecadação cai")
	_add_chip(row, "army", "sword", "Regimentos e mão de obra disponível")

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var dcol := VBoxContainer.new()
	dcol.alignment = BoxContainer.ALIGNMENT_CENTER
	dcol.add_theme_constant_override("separation", 2)
	row.add_child(dcol)
	_date_label = UIKit.serif_label("", 20, UIKit.TEXT)
	_date_label.custom_minimum_size = Vector2(200, 0)
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dcol.add_child(_date_label)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 3)
	dcol.add_child(srow)
	var group := ButtonGroup.new()
	var labels: Array[String] = ["II", ">", ">>", ">>>", ">>>>"]
	for i in labels.size():
		var b := UIKit.button(labels[i], Vector2(38, 30), "SpeedButton")
		b.add_theme_font_size_override("font_size", 14)
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_on_speed_pressed.bind(i))
		srow.add_child(b)
		_speed_buttons.append(b)


func _on_bar_resized() -> void:
	_body.offset_top = _bar.size.y


func _add_chip(row: HBoxContainer, key: String, icon_kind: String, tip: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(box)
	box.add_child(UiIcon.make(icon_kind, 26))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var v := UIKit.label("", 19, UIKit.TEXT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(v)
	var s := UIKit.label("", 13, UIKit.TEXT_DIM)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(s)
	_chips[key] = {"value": v, "sub": s}


func _set_chip(key: String, value: String, sub: String, sub_color: Color = UIKit.TEXT_DIM, value_color: Color = UIKit.TEXT) -> void:
	var ch: Dictionary = _chips[key]
	var v: Label = ch["value"]
	var s: Label = ch["sub"]
	v.text = value
	v.add_theme_color_override("font_color", value_color)
	s.text = sub
	s.add_theme_color_override("font_color", sub_color)


func _build_sidebar() -> void:
	var panel := PanelContainer.new()
	panel.offset_left = MARGIN
	panel.offset_top = MARGIN
	_body.add_child(panel)
	_blockers.append(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var defs: Array = [
		["politics", "scales", "Política: classes sociais e ideologias"],
		["laws", "scroll", "Leis: estrutura de poder, economia e direitos"],
		["diplo", "flag", "Diplomacia: relações, alianças, guerra, paz e vassalos"],
		["tech", "bulb", "Pesquisa: tecnologia, financiamento e desbloqueios"],
		["eco", "coin", "Economia: orçamento e impostos"],
		["market", "bars", "Mercado: oferta, demanda e preços"],
		["map", "globe", "Modo do mapa"],
		["menu", "menu", "Menu: salvar, carregar e trocar de país"],
	]
	for d in defs:
		var key: String = d[0]
		var b := UIKit.icon_button(str(d[1]), "", Vector2(58, 58), "DockButton")
		b.tooltip_text = str(d[2])
		b.toggle_mode = key != "map"
		b.pressed.connect(_on_side_pressed.bind(key))
		col.add_child(b)
		_side_btns[key] = b


func _build_side_list() -> void:
	_side_panel = PanelContainer.new()
	_side_panel.theme_type_variation = "CardPanel"
	_side_panel.anchor_left = 1.0
	_side_panel.anchor_right = 1.0
	_side_panel.offset_left = -(MARGIN + 290)
	_side_panel.offset_right = -MARGIN
	_side_panel.offset_top = MARGIN
	_side_panel.visible = false
	_body.add_child(_side_panel)
	_blockers.append(_side_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_side_panel.add_child(col)
	_side_head = UIKit.serif_label("Exércitos", 19, UIKit.GOLD)
	col.add_child(_side_head)
	_side_armies = VBoxContainer.new()
	_side_armies.add_theme_constant_override("separation", 2)
	col.add_child(_side_armies)
	_side_wars = VBoxContainer.new()
	_side_wars.add_theme_constant_override("separation", 2)
	col.add_child(_side_wars)


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.theme_type_variation = "BannerPanel"
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.offset_top = MARGIN
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_toast_panel)
	_toast = UIKit.label("", 19, UIKit.TEXT)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size = Vector2(minf(520.0, get_viewport().get_visible_rect().size.x * 0.72), 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast)


func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast_panel.visible = true
	_toast_seq += 1
	var mine := _toast_seq
	await get_tree().create_timer(4.0).timeout
	if mine == _toast_seq and is_instance_valid(_toast_panel):
		_toast_panel.visible = false


# ---------------------------------------------------------------------------
# Dock de construções
# ---------------------------------------------------------------------------
func _build_dock() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	var dock_half := minf(290.0, get_viewport().get_visible_rect().size.x * 0.4)
	box.offset_left = -dock_half
	box.offset_right = dock_half
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.offset_top = -MARGIN
	box.offset_bottom = -MARGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 6)
	_body.add_child(box)
	_blockers.append(box)

	_build_panel = PanelContainer.new()
	_build_panel.visible = false
	box.add_child(_build_panel)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 6)
	_build_panel.add_child(pcol)
	_build_head = UIKit.label("", 17, UIKit.TEXT_DIM)
	_build_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pcol.add_child(_build_head)
	pcol.add_child(HSeparator.new())
	_build_scroll = ScrollContainer.new()
	_build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_scroll.custom_minimum_size = Vector2(0, 300)
	pcol.add_child(_build_scroll)
	_build_rows = VBoxContainer.new()
	_build_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_rows.add_theme_constant_override("separation", 6)
	_build_scroll.add_child(_build_rows)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for tab in TAB_ORDER:
		var b := UIKit.icon_button(str(TAB_ICON[tab]), str(TAB_PT[tab]), Vector2(120, 60), "DockButton")
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_build_tab_pressed.bind(tab))
		row.add_child(b)
		_build_tab_btns[tab] = b


func _on_build_tab_pressed(tab: String) -> void:
	_build_tab = "" if _build_tab == tab else tab
	_refresh_build_panel()


func _buildings_summary(p: Province) -> String:
	var parts: Array[String] = []
	for k in Province.BUILDINGS.keys():
		var lv := p.building_level(k)
		if lv > 0:
			parts.append("%s %d" % [Province.BUILDINGS[k]["name"], lv])
	return "Construções: " + ", ".join(parts) if not parts.is_empty() else ""


## Linhas de detalhe de um edifício: obra, produção, consumo e finanças mensais.
func _building_detail(p: Province, kind: String, lv: int, me: int) -> String:
	var tax: int = Game.countries[me].tax_pct
	var nxt := mini(Province.MAX_BUILDING, lv + 1)
	var rep := p.building_report(kind, nxt, tax)
	var parts: Array[String] = []
	if lv < Province.MAX_BUILDING:
		var mats: Array[String] = []
		for m in p.material_list(kind, nxt):
			mats.append("%d %s" % [int(m["amount"]), str(RESOURCE_PT.get(m["good"], m["good"])).to_lower()])
		parts.append("Obra: %d ouro + materiais %d (%s)" % [Game.build_cost(p, kind), Game.build_material_cost(p, kind), ", ".join(mats)])
	var lbl := "Nível %d" % nxt
	if Province.FACTORIES.has(kind) or Province.WAGE_PCT.has(kind):
		parts.append("%s: produz %d %s/mês · receita %d" % [lbl, int(rep["units"]), str(RESOURCE_PT.get(rep["product"], rep["product"])).to_lower(), int(rep["revenue"])])
		if Province.FACTORIES.has(kind):
			var ins: Array[String] = []
			for i in rep["inputs"]:
				ins.append("%d %s" % [int(i["amount"]), str(RESOURCE_PT.get(i["good"], i["good"])).to_lower()])
			parts.append("Consome %s (custo %d)" % [", ".join(ins), int(rep["inputs_cost"])])
		parts.append("Salários -%d · impostos -%d · líquido %+d/mês · %d empregos" % [int(rep["wages"]), int(rep["tax"]), int(rep["net"]), int(rep["jobs"])])
	elif kind == "market":
		parts.append("%s: +%d de imposto extra/mês · manutenção -%d · %d empregos" % [lbl, int(rep["revenue"]), int(rep["wages"]), int(rep["jobs"])])
	else:
		parts.append("%s: custo mensal -%d (salários) · %d empregos" % [lbl, int(rep["wages"]), int(rep["jobs"])])
	return "\n".join(parts)


func _refresh_build_panel() -> void:
	for t in _build_tab_btns.keys():
		_build_tab_btns[t].set_pressed_no_signal(t == _build_tab)
	_build_panel.visible = _build_tab != ""
	if _build_tab == "":
		return
	UIKit.clear(_build_rows)
	var me := Game.player_country
	var tech: int = Game.countries[me].tech_level()
	var p: Province = null
	if _selected >= 0 and _selected < Game.provinces.size():
		p = Game.provinces[_selected]
	var head := "%s  ·  Tecnologia nível %d" % [TAB_PT[_build_tab], tech]
	if p == null or p.owner_id != me:
		_build_head.text = head + "\nSelecione uma província sua para construir."
		return
	_build_head.text = head + "\nem %s" % p.name
	_build_scroll.custom_minimum_size = Vector2(0, clampf(_root.size.y * 0.42, 220.0, 420.0))
	for k in Province.BUILDINGS.keys():
		var b: Dictionary = Province.BUILDINGS[k]
		if b["tab"] != _build_tab or not p.can_host(k):
			continue
		var lv := p.building_level(k)
		var rep_next := p.building_report(k, mini(Province.MAX_BUILDING, lv + 1), Game.countries[me].tax_pct)
		var pc := PanelContainer.new()
		pc.theme_type_variation = "CardPanel"
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_build_rows.add_child(pc)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		pc.add_child(box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		row.add_child(UiIcon.make(str(BUILD_ICON.get(k, "building")), 44.0, UIKit.GOLD_BRIGHT if lv > 0 else UiIcon.DEFAULT_COLOR))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		var title := HBoxContainer.new()
		title.add_theme_constant_override("separation", 8)
		info.add_child(title)
		title.add_child(UIKit.label(str(b["name"]), 19, UIKit.TEXT))
		for i in Province.MAX_BUILDING:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(16, 7)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.color = UIKit.GOLD_BRIGHT if i < lv else Color(1, 1, 1, 0.15)
			title.add_child(pip)
		var dl := UIKit.label(str(b["desc"]), 14, UIKit.TEXT_DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(dl)
		var stats := PackedStringArray()
		stats.append("%d empregos" % int(rep_next["jobs"]))
		if int(rep_next["revenue"]) != 0 or Province.WAGE_PCT.has(k):
			stats.append("líquido %+d/mês" % int(rep_next["net"]))
		elif int(rep_next["wages"]) > 0:
			stats.append("custo -%d/mês" % int(rep_next["wages"]))
		var sl := UIKit.label(" · ".join(stats), 14, UIKit.GOLD)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(sl)
		var btn := _make_button("", Vector2(140, 52))
		btn.add_theme_font_size_override("font_size", 16)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)
		if lv >= Province.MAX_BUILDING:
			btn.text = "Máximo"
			btn.disabled = true
		elif tech < int(b["tech"]):
			btn.text = "Tecnologia %d" % int(b["tech"])
			btn.disabled = true
		elif Province.FACTORIES.has(k) and p.factory != "" and p.factory != k:
			btn.text = "Outra fábrica"
			btn.disabled = true
		else:
			btn.text = "Construir\n%d" % Game.build_total_cost(p, k)
			btn.disabled = not Game.can_build(p.id, me, k)
			btn.pressed.connect(_on_build_pressed.bind(k))
		var tog := Button.new()
		tog.flat = true
		tog.text = "Ocultar detalhes" if bool(_build_open.get(k, false)) else "Ver detalhes"
		tog.add_theme_font_size_override("font_size", 14)
		tog.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tog.pressed.connect(_on_build_details.bind(k))
		box.add_child(tog)
		if bool(_build_open.get(k, false)):
			var detail := UIKit.label(_building_detail(p, k, lv, me), 14, UIKit.TEXT_DIM)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(detail)


func _on_build_details(kind: String) -> void:
	_build_open[kind] = not bool(_build_open.get(kind, false))
	_refresh_build_panel()


# ---------------------------------------------------------------------------
# Janelas (Economia, Mercado, Política, Menu)
# ---------------------------------------------------------------------------
func _make_window(key: String, title: String, win_size: Vector2, icon_kind: String) -> VBoxContainer:
	var w := PanelContainer.new()
	w.anchor_left = 0.5
	w.anchor_right = 0.5
	w.anchor_top = 0.5
	w.anchor_bottom = 0.5
	w.grow_horizontal = Control.GROW_DIRECTION_BOTH
	w.grow_vertical = Control.GROW_DIRECTION_BOTH
	w.custom_minimum_size = win_size
	_win_sizes[w] = win_size
	w.visible = false
	_body.add_child(w)
	_blockers.append(w)
	_windows[key] = w

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	w.add_child(col)

	var head := PanelContainer.new()
	head.theme_type_variation = "BannerPanel"
	col.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	head.add_child(hrow)
	hrow.add_child(UiIcon.make(icon_kind, 30, UIKit.GOLD_BRIGHT))
	var t := UIKit.serif_label(title, 25, UIKit.GOLD_BRIGHT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(t)
	var x := UIKit.icon_button("close", "", Vector2(46, 40))
	x.pressed.connect(_toggle_window.bind(key))
	hrow.add_child(x)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	_win_bodies[key] = body
	return body


## Ajusta as janelas ao espaço útil: tamanho desejado, no máximo 92% da largura e 94% da altura.
func _fit_windows() -> void:
	var area := _body.size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	for w in _win_sizes.keys():
		var want: Vector2 = _win_sizes[w]
		(w as Control).custom_minimum_size = Vector2(minf(want.x, area.x * 0.92), minf(want.y, area.y * 0.94))
	if _toast != null:
		_toast.custom_minimum_size = Vector2(minf(520.0, area.x * 0.72), 0)


func _build_windows() -> void:
	_body.resized.connect(_fit_windows)
	_make_window("politics", "Política interna", Vector2(900, 540), "scales")
	_make_window("laws", "Leis", Vector2(1040, 560), "scroll")
	_make_window("diplo", "Diplomacia", Vector2(980, 600), "flag")
	_make_window("tech", "Pesquisa tecnológica", Vector2(900, 580), "bulb")
	_make_window("eco", "Economia", Vector2(860, 520), "coin")
	_make_window("market", "Mercado nacional", Vector2(760, 540), "bars")
	var menu := _make_window("menu", "Menu", Vector2(420, 480), "menu")
	var b_save := _make_button("Salvar jogo", Vector2(0, 52))
	b_save.pressed.connect(_on_save_pressed)
	menu.add_child(b_save)
	var b_load := _make_button("Carregar jogo salvo", Vector2(0, 52))
	b_load.pressed.connect(_on_load_pressed)
	menu.add_child(b_load)
	var b_swap := _make_button("Trocar de país", Vector2(0, 52))
	b_swap.pressed.connect(_on_swap_pressed)
	menu.add_child(b_swap)
	var b_music := _make_button("", Vector2(0, 52))
	b_music.text = "Música: ligada"
	b_music.pressed.connect(_on_music_pressed.bind(b_music))
	menu.add_child(b_music)
	var b_sfx := _make_button("", Vector2(0, 52))
	b_sfx.text = "Efeitos sonoros: ligados"
	b_sfx.pressed.connect(_on_sfx_pressed.bind(b_sfx))
	menu.add_child(b_sfx)
	menu.add_child(UIKit.label("Atalhos: Espaço pausa, + e - mudam a velocidade.", 15, UIKit.TEXT_DIM))


func _toggle_window(key: String) -> void:
	for k in _windows.keys():
		var w: PanelContainer = _windows[k]
		w.visible = (not w.visible) if k == key else false
	for k in _windows.keys():
		var sb: Button = _side_btns.get(k)
		if sb != null:
			sb.set_pressed_no_signal(_windows[k].visible)
	_refresh_windows()


func _refresh_windows() -> void:
	if _windows.is_empty():
		return
	if _windows["tech"].visible:
		_refresh_tech()
	if _windows["eco"].visible:
		_refresh_economy()
	if _windows["market"].visible:
		_refresh_market()
	if _windows["politics"].visible:
		_refresh_politics()
	if _windows["laws"].visible:
		_refresh_laws()
	if _windows["diplo"].visible:
		_refresh_diplomacy()


func _on_side_pressed(key: String) -> void:
	if key == "map":
		if map_view != null:
			map_view.cycle_mode()
			_show_toast("Mapa: %s" % MapView.MODE_NAMES[map_view.mode])
		return
	_toggle_window(key)


func _card(parent: Control, title: String, icon_kind: String = "") -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.theme_type_variation = "CardPanel"
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(pc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pc.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	if icon_kind != "":
		head.add_child(UiIcon.make(icon_kind, 24))
	head.add_child(UIKit.serif_label(title, 20, UIKit.GOLD))
	col.add_child(HSeparator.new())
	return col


func _signed_color(v: int) -> Color:
	return UIKit.POS if v > 0 else (UIKit.NEG if v < 0 else UIKit.TEXT)


func _refresh_tech() -> void:
	var body: VBoxContainer = _win_bodies["tech"]
	UIKit.clear(body)
	var c := Game.countries[Game.player_country]
	var lvl: int = mini(c.tech_level(), Game.MAX_TECH)
	var e := Game.estimate_monthly(c)
	var gain: int = Game.tech_gain(c)
	var base: int = Game.tech_gain_base(c)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	_big_number(top, "Nível", "%d / %d" % [lvl, Game.MAX_TECH], UIKit.GOLD_BRIGHT)
	_big_number(top, "Era", str(Game.TECH_ERAS[lvl]["name"]), UIKit.TEXT)
	_big_number(top, "Pontos por mês", "+%d" % gain, UIKit.POS)
	_big_number(top, "Custo da pesquisa", "-%d" % int(e["upkeep_research"]), UIKit.NEG if int(e["upkeep_research"]) > 0 else UIKit.TEXT_DIM)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	body.add_child(cols)
	var left := _card(cols, "Progresso e financiamento", "bulb")
	if lvl >= Game.MAX_TECH:
		left.add_child(UIKit.label("Nível máximo alcançado.", 17, UIKit.GOLD_BRIGHT))
	else:
		var into: int = c.tech_pts % Country.TECH_STEP
		left.add_child(UIKit.kv_row("Próximo: %s" % str(Game.TECH_ERAS[lvl + 1]["name"]), "%d / %d" % [into, Country.TECH_STEP]))
		left.add_child(UIKit.bar(float(into), float(Country.TECH_STEP), UIKit.GOLD))
		var months: int = (Country.TECH_STEP - into + maxi(1, gain) - 1) / maxi(1, gain)
		left.add_child(UIKit.label("Previsão: ~%d meses (%d anos e %d meses)." % [months, months / 12, months % 12], 15, UIKit.TEXT_DIM))
	left.add_child(HSeparator.new())
	left.add_child(UIKit.label("De onde vêm os pontos (sem financiamento: %d)" % base, 16, UIKit.GOLD_BRIGHT))
	var edu := Game.edu_levels(c)
	left.add_child(UIKit.kv_row("Base + alfabetização (%.1f%%)" % (c.literacy / 10.0), "+%d" % (6 + c.literacy / 50)))
	left.add_child(UIKit.kv_row("Escolas (%d)" % edu.x, "+%d" % (3 * edu.x)))
	left.add_child(UIKit.kv_row("Universidades (%d)" % edu.y, "+%d" % (10 * edu.y)))
	var lm := Game.law_mods(c)
	left.add_child(UIKit.kv_row("Leis", "%+d" % int(lm["tech"]), _signed_color(int(lm["tech"]))))
	left.add_child(UIKit.kv_row("Financiamento (%d%% da renda)" % c.research_pct, "+%d" % (gain - base), UIKit.POS if gain > base else UIKit.TEXT_DIM))
	left.add_child(HSeparator.new())
	left.add_child(UIKit.label("Investimento em pesquisa: cada 20%% da renda dobra os pontos.", 15, UIKit.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	left.add_child(grid)
	var gross: int = int(e["income"]) + int(e["upkeep_research"])
	for pct in range(0, Game.RESEARCH_MAX_PCT + 1, 5):
		var b := _info_button("%d%%" % pct, Vector2(60, 44), _on_research_pct.bind(pct), grid)
		b.tooltip_text = "Custa ~%d por mês" % (gross * pct / 100)
		b.disabled = pct == c.research_pct

	var right := _card(cols, "Eras tecnológicas", "scroll")
	for i in range(Game.MAX_TECH + 1):
		var era: Dictionary = Game.TECH_ERAS[i]
		var unlocks: Array = []
		for k in Province.BUILDINGS.keys():
			if int(Province.BUILDINGS[k]["tech"]) == i and i > 0:
				unlocks.append(str(Province.BUILDINGS[k]["name"]))
		var state: String = "[OK]" if i <= lvl else "[ ]"
		var col: Color = UIKit.GOLD_BRIGHT if i == lvl else (UIKit.TEXT if i < lvl else UIKit.TEXT_DIM)
		right.add_child(UIKit.kv_row("%s  %d. %s" % [state, i, str(era["name"])], "atual" if i == lvl else "", col, 17))
		var txt: String = str(era["extra"])
		if not unlocks.is_empty():
			txt = "Libera: %s. %s" % [", ".join(unlocks), txt]
		var lab := UIKit.label(txt, 14, UIKit.TEXT_DIM)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(320, 0)
		right.add_child(lab)


func _on_research_pct(pct: int) -> void:
	Game.submit_command(Cmd.set_research(pct))
	_refresh_tech()


func _refresh_economy() -> void:
	var body: VBoxContainer = _win_bodies["eco"]
	UIKit.clear(body)
	var c := Game.countries[Game.player_country]
	var e := Game.estimate_monthly(c)
	var income: int = int(e["income"])
	var expense: int = int(e["expense"])
	var net: int = income - expense

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	_big_number(top, "Receita mensal", "%+d" % income, UIKit.POS)
	_big_number(top, "Despesa mensal", "-%d" % expense, UIKit.NEG)
	_big_number(top, "Saldo mensal", "%+d" % net, _signed_color(net))
	_big_number(top, "Tesouro", str(c.treasury), UIKit.NEG if c.treasury < 0 else UIKit.GOLD_BRIGHT)

	_economy_dashboard(body, c)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	body.add_child(cols)

	var left := _card(cols, "Orçamento", "coin")
	left.add_child(UIKit.kv_row("Impostos (%d%%) + base %d" % [c.tax_pct, int(e["flat"])], "%+d" % (income - int(e["industry_state"]) - int(e["trade"])), UIKit.POS))
	left.add_child(UIKit.kv_row("Impostos das fábricas" if Province.FACTORIES_PRIVATE else "Lucro das fábricas", "%+d" % int(e["industry_state"]), _signed_color(int(e["industry_state"]))))
	if int(e["factory_revenue"]) > 0:
		left.add_child(UIKit.kv_row("   vendas %+d, insumos -%d, salários -%d%s" % [int(e["factory_revenue"]), int(e["factory_inputs"]), int(e["factory_wages"]), (", impostos -%d" % int(e["factory_tax"])) if int(e["factory_tax"]) > 0 else ""], "pagos pelas fábricas", UIKit.TEXT_DIM, 14))
	left.add_child(UIKit.kv_row("Comércio exterior", "%+d" % int(e["trade"]), _signed_color(int(e["trade"]))))
	left.add_child(HSeparator.new())
	left.add_child(UIKit.kv_row("Manutenção das províncias", "-%d" % int(e["upkeep_prov"]), UIKit.NEG))
	left.add_child(UIKit.kv_row("Exércitos (%d reg.)" % int(e["regiments"]), "-%d" % int(e["upkeep_army"]), UIKit.NEG))
	left.add_child(UIKit.kv_row("Frota (%d navios)" % c.ships, "-%d" % int(e["upkeep_navy"]), UIKit.NEG))
	left.add_child(UIKit.kv_row("Escolas e universidades (salários)", "-%d" % int(e["upkeep_edu"]), UIKit.NEG))
	if int(e["upkeep_research"]) > 0:
		left.add_child(UIKit.kv_row("Pesquisa (%d%% da renda)" % c.research_pct, "-%d" % int(e["upkeep_research"]), UIKit.NEG))
	if int(e["upkeep_infra"]) > 0:
		left.add_child(UIKit.kv_row("Hospitais, mercados e cais", "-%d" % int(e["upkeep_infra"]), UIKit.NEG))
	if int(e["upkeep_barracks"]) > 0:
		left.add_child(UIKit.kv_row("Quartéis (instrutores)", "-%d" % int(e["upkeep_barracks"]), UIKit.NEG))
	if net < 0 and c.treasury > 0:
		left.add_child(UIKit.label("Tesouro acaba em ~%d meses." % (c.treasury / -net), 16, UIKit.WARN))

	var right := _card(cols, "Impostos e comércio", "bars")
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	right.add_child(trow)
	var tl := UIKit.label("Taxa de imposto", 18, UIKit.TEXT_DIM)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tl)
	var minus := _make_button("-", Vector2(52, 44))
	minus.pressed.connect(_on_tax_pressed.bind(-5))
	trow.add_child(minus)
	var tv := UIKit.label("%d%%" % c.tax_pct, 22, UIKit.GOLD_BRIGHT)
	tv.custom_minimum_size = Vector2(64, 0)
	tv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trow.add_child(tv)
	var plus := _make_button("+", Vector2(52, 44))
	plus.pressed.connect(_on_tax_pressed.bind(5))
	trow.add_child(plus)
	right.add_child(UIKit.kv_row("Produção bruta", "%d/mês" % int(e["production"])))
	var cap := Game.sea_capacity(c.id)
	var blocked := Game.is_blockaded(c.id)
	right.add_child(UIKit.kv_row("Comércio marítimo", "%d/mês%s" % [cap, "  BLOQUEADO" if blocked else ""], UIKit.NEG if blocked else UIKit.TEXT))
	var emb := PackedStringArray()
	for k in Game.embargoes:
		var a: int = int(k) / 1000
		var t: int = int(k) % 1000
		if a == c.id:
			emb.append("você -> %s" % Game.countries[t].name)
		elif t == c.id:
			emb.append("%s -> você" % Game.countries[a].name)
	if not emb.is_empty():
		var el := UIKit.label("Embargos: " + ", ".join(emb), 15, UIKit.WARN)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(el)
	right.add_child(HSeparator.new())
	right.add_child(UIKit.label("Províncias que mais rendem", 17, UIKit.GOLD))
	for r in Game.top_provinces(c, 5):
		var p := Game.provinces[int(r["id"])]
		right.add_child(UIKit.kv_row("%s%s" % [p.name, "" if p.city == "" else " (%s)" % p.city], "+%d" % int(r["tax"]), UIKit.POS, 16))
	if not Game.gates.is_empty():
		var gcard := _card(body, "Estreitos e rotas")
		for gi in Game.gates.size():
			var g: Dictionary = Game.gates[gi]
			var gc := Game.gate_controller(gi)
			var who := "ninguém" if gc < 0 else ("você" if gc == c.id else Game.countries[gc].name)
			var toll := int(g.get("toll", 0))
			var info := "%s · pedágio %d%% · fluxo %d" % [who, toll, int(Game.gate_flow[gi])]
			gcard.add_child(UIKit.kv_row(str(g["name"]), info, UIKit.GOLD_BRIGHT if gc == c.id else UIKit.TEXT, 16))
		var gnote := UIKit.label("Quem controla um estreito cobra pedágio e pode fechá-lo a países em guerra ou embargo com ele.", 14, UIKit.TEXT_DIM)
		gnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gcard.add_child(gnote)


## Painel de indicadores: PIB (valor agregado), inflação, comércio, emprego, gráficos e rankings.
func _economy_dashboard(body: VBoxContainer, c: Country) -> void:
	var r: Dictionary = EconomyManager.country_report(Game, c.id)
	if r.is_empty():
		return
	var hist: Array = EconomyManager.get_history(c.id)
	var infl := 0
	var growth := 0
	if not hist.is_empty():
		infl = int(hist.back().get("inflation_pct", 0))
		growth = int(hist.back().get("gdp_growth_pct", 0))
	var unemp := Game.unemployment_pct(c)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	body.add_child(row1)
	_big_number(row1, "PIB (valor agregado)", str(int(r["gdp_nominal"])), UIKit.GOLD_BRIGHT)
	_big_number(row1, "Crescimento mensal", "%+d%%" % growth, _signed_color(growth))
	_big_number(row1, "Inflação mensal", "%+d%%" % infl, UIKit.NEG if infl > 1 else (UIKit.POS if infl < 0 else UIKit.TEXT))
	_big_number(row1, "Desemprego", "%d%%" % unemp, UIKit.NEG if unemp >= 16 else (UIKit.WARN if unemp >= 10 else UIKit.POS))

	var charts := HBoxContainer.new()
	charts.add_theme_constant_override("separation", 12)
	body.add_child(charts)
	var g1 := GDPChartPanel.new()
	g1.custom_minimum_size = Vector2(0, 170)
	g1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g1.set_metric("gdp_real", "PIB REAL — EVOLUÇÃO MENSAL")
	g1.update_chart(hist)
	charts.add_child(g1)
	var g2 := GDPChartPanel.new()
	g2.custom_minimum_size = Vector2(0, 170)
	g2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g2.set_metric("monthly_balance", "SALDO FISCAL MENSAL")
	g2.update_chart(hist)
	charts.add_child(g2)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	body.add_child(cols)
	var ind := _card(cols, "Indicadores", "bars")
	ind.add_child(UIKit.kv_row("PIB por habitante", "%.2f" % (float(int(r["gdp_per_capita_x100"])) / 100.0)))
	ind.add_child(UIKit.kv_row("Índice de preços", "%d" % int(r["price_index"]), UIKit.WARN if int(r["price_index"]) > 115 else UIKit.TEXT))
	ind.add_child(UIKit.kv_row("Valor agregado industrial", str(int(r["industry_value_added"]))))
	ind.add_child(UIKit.kv_row("Balança comercial", "%+d" % int(r["trade_balance"]), _signed_color(int(r["trade_balance"]))))
	ind.add_child(UIKit.kv_row("Investimento privado (fluxo)", "%d" % int(r["investment_flow"])))
	ind.add_child(UIKit.kv_row("Empregos formais (capacidade)", str(int(r["estimated_jobs"]) * Game.JOB_SCALE)))
	var un := UIKit.label("Desemprego alto derruba a satisfação de trabalhadores e camponeses; construa minas, fazendas e fábricas para gerar empregos.", 14, UIKit.TEXT_DIM)
	un.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ind.add_child(un)

	var rk := _card(cols, "Maiores economias", "coin")
	var ranking: Array = _ranking_cached()
	var shown := 0
	var my_pos := -1
	for i in ranking.size():
		var row: Dictionary = ranking[i]
		if int(row["id"]) == c.id:
			my_pos = i
		if i < 5:
			rk.add_child(UIKit.kv_row("%d. %s" % [i + 1, str(row["name"])], str(int(row["gdp_nominal"])), UIKit.GOLD_BRIGHT if int(row["id"]) == c.id else UIKit.TEXT, 16))
			shown += 1
	if my_pos >= shown:
		rk.add_child(UIKit.kv_row("%d. %s" % [my_pos + 1, c.name], str(int(ranking[my_pos]["gdp_nominal"])), UIKit.GOLD_BRIGHT, 16))
	rk.add_child(HSeparator.new())
	rk.add_child(UIKit.label("Gargalos e excedentes", 17, UIKit.GOLD))
	var alerts: Array = EconomyManager.bottlenecks(Game, c.id)
	var na := 0
	for a in alerts:
		if na >= 4:
			break
		var surplus := str(a["severity"]) == "surplus"
		rk.add_child(UIKit.kv_row("%s %s" % ["Excesso de" if surplus else "Falta de", str(a["good"])], "preço %d%%" % int(a["price_pct"]), UIKit.POS if surplus else (UIKit.NEG if str(a["severity"]) == "critical" else UIKit.WARN), 16))
		na += 1
	if na == 0:
		rk.add_child(UIKit.label("Mercado equilibrado.", 15, UIKit.TEXT_DIM))


var _rank_cache: Array = []
var _rank_stamp: int = -1


func _ranking_cached() -> Array:
	var stamp: int = Game.clock.year * 12 + Game.clock.month
	if stamp != _rank_stamp:
		_rank_stamp = stamp
		_rank_cache = EconomyManager.global_rankings(Game)
	return _rank_cache


func _big_number(parent: Control, title: String, value: String, color: Color) -> void:
	var pc := PanelContainer.new()
	pc.theme_type_variation = "CardPanel"
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(pc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	pc.add_child(col)
	var t := UIKit.label(title, 15, UIKit.TEXT_DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var v := UIKit.serif_label(value, 28, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(v)


func _refresh_market() -> void:
	var body: VBoxContainer = _win_bodies["market"]
	UIKit.clear(body)
	var pc := Game.player_country
	var tb := Game.market_tables()
	var sup: Dictionary = tb[0][pc]
	var dem: Dictionary = tb[1][pc]
	var card := _card(body, "Preço = % do valor base  ·  + falta (sobe)  ·  - sobra (cai)", "bars")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	card.add_child(grid)
	_market_row(grid, ["Bem", "Oferta", "Demanda", "Preço", "Importa", "Exporta"], true, UIKit.TEXT)
	for g in Game.goods_list():
		var s: int = int(sup[g])
		var d: int = int(dem[g])
		var arrow := " "
		var col := UIKit.TEXT
		if d > s * 102 / 100:
			arrow = " +"
			col = UIKit.NEG
		elif d * 102 / 100 < s:
			arrow = " -"
			col = UIKit.POS
		var im: int = int(Game.trade_imp[pc].get(g, 0)) if pc < Game.trade_imp.size() else 0
		var ex: int = int(Game.trade_exp[pc].get(g, 0)) if pc < Game.trade_exp.size() else 0
		_market_row(grid, [RESOURCE_PT.get(g, g), str(s), str(d), "%d%%%s" % [int(Game.local_price[pc][g]), arrow], str(im), str(ex)], false, col)


func _market_row(grid: GridContainer, cells: Array, header: bool, price_color: Color) -> void:
	for i in cells.size():
		var l := UIKit.label(str(cells[i]), 17, UIKit.GOLD if header else UIKit.TEXT)
		if i == 3 and not header:
			l.add_theme_color_override("font_color", price_color)
		if i > 0:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(130 if i == 0 else 90, 0)
		grid.add_child(l)


func _sat_color(v: int) -> Color:
	if v >= 60:
		return UIKit.POS
	if v >= 40:
		return UIKit.WARN
	return UIKit.NEG


func _stability_text(v: int) -> String:
	if v >= 70:
		return "Estável"
	if v >= 50:
		return "Tranquilo"
	if v >= 40:
		return "Inquieto"
	if v >= Game.REVOLT_STABILITY:
		return "Instável: a arrecadação cai"
	return "Revolta iminente"


func _refresh_laws() -> void:
	var body: VBoxContainer = _win_bodies["laws"]
	UIKit.clear(body)
	var c := Game.countries[Game.player_country]
	if c.laws.size() != Laws.group_count():
		return
	var lm := Game.law_mods(c)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	body.add_child(head)
	var info := UIKit.label("Cada lei só muda a cada %d meses e abala a satisfação das classes. Tesouro: %d" % [Laws.COOLDOWN_MONTHS, c.treasury], 16, UIKit.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	head.add_child(UIKit.label("Estabilidade %d%%" % c.stability, 18, _sat_color(c.stability)))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var colv: Array = []
	for ci in 3:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		v.add_theme_constant_override("separation", 10)
		cols.add_child(v)
		var t := UIKit.serif_label(str(Laws.COLUMN_NAMES[ci]), 21, UIKit.GOLD_BRIGHT)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		colv.append(v)
	for gi in Laws.group_count():
		var g: Dictionary = Laws.group(gi)
		var card := _card(colv[int(g["col"])], str(g["name"]))
		var opts: Array = g["opts"]
		for oi in opts.size():
			card.add_child(_law_option_row(c, gi, oi, opts[oi], int(c.laws[gi]) == oi))
		if int(c.law_cd[gi]) > 0:
			card.add_child(UIKit.label("Mudança bloqueada por %d meses" % int(c.law_cd[gi]), 15, UIKit.WARN))
	if int(lm["tax"]) != 0 or int(lm["trade"]) != 0 or int(lm["army"]) != 0:
		body.add_child(UIKit.label("Efeito acumulado das leis: arrecadação %+d%%, comércio %+d%%, custo do exército %+d%%." % [int(lm["tax"]), int(lm["trade"]), int(lm["army"])], 16, UIKit.TEXT_DIM))


func _law_option_row(c: Country, gi: int, oi: int, o: Dictionary, active: bool) -> Control:
	var pc := PanelContainer.new()
	var sb := UIKit.box(Color(0.79, 0.66, 0.36, 0.16) if active else Color(0, 0, 0, 0.18),
		UIKit.GOLD if active else Color(0.24, 0.30, 0.33), 4, 2 if active else 1, 8)
	pc.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	pc.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var nm := UIKit.label(str(o["name"]), 18, UIKit.GOLD_BRIGHT if active else UIKit.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(nm)
	var d := UIKit.label(str(o["desc"]), 14, UIKit.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 10)
	col.add_child(fl)
	for ln in Laws.effect_lines(o["fx"]):
		fl.add_child(UIKit.label(str(ln["text"]), 14, UIKit.POS if bool(ln["good"]) else UIKit.NEG))
	if active:
		row.add_child(UIKit.label("EM VIGOR", 14, UIKit.GOLD))
		return pc
	var why := Game.law_block_reason(c, gi, oi)
	var b := UIKit.button("Aprovar (%d)" % int(o["cost"]), Vector2(0, 38))
	b.disabled = why != ""
	b.pressed.connect(_on_law_pressed.bind(gi, oi))
	row.add_child(b)
	if why != "":
		col.add_child(UIKit.label(why, 14, UIKit.WARN))
	return pc


func _on_law_pressed(gi: int, oi: int) -> void:
	Game.submit_command(Cmd.enact_law(gi, oi))
	_refresh_windows()


func _refresh_politics() -> void:
	var body: VBoxContainer = _win_bodies["politics"]
	UIKit.clear(body)
	var c := Game.countries[Game.player_country]
	var pol := Game.politics_of(c)
	var sh: Array = pol["share"]
	var pw: Array = pol["power"]
	var ideo: Array = pol["ideo"]
	var tot: int = maxi(1, int(pol["power_total"]))

	var scard := _card(body, "Estabilidade", "shield")
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	scard.add_child(srow)
	srow.add_child(UIKit.serif_label("%d%%" % c.stability, 30, _sat_color(c.stability)))
	srow.add_child(UIKit.bar(float(c.stability), 100.0, _sat_color(c.stability), 18.0))
	var st := UIKit.label(_stability_text(c.stability), 18, _sat_color(c.stability))
	st.custom_minimum_size = Vector2(230, 0)
	srow.add_child(st)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	body.add_child(cols)

	var ccard := _card(cols, "Classes sociais", "people")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	ccard.add_child(grid)
	for h in ["Classe", "População", "Satisfação", "Influência"]:
		var hl := UIKit.label(h, 15, UIKit.GOLD)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if h == "Classe" else HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(hl)
	for i in 6:
		var name_l := UIKit.label(CLASS_PT[i], 17, UIKit.TEXT)
		name_l.custom_minimum_size = Vector2(112, 0)
		grid.add_child(name_l)
		var pop_l := UIKit.label("%.1f%%" % (float(sh[i]) / 10.0), 17, UIKit.TEXT)
		pop_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(pop_l)
		var sat: int = int(c.sat[i])
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(UIKit.bar(float(sat), 100.0, _sat_color(sat), 12.0, 70.0))
		var sv := UIKit.label(str(sat), 16, _sat_color(sat))
		sv.custom_minimum_size = Vector2(30, 0)
		sv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(sv)
		grid.add_child(cell)
		var inf_l := UIKit.label("%d%%" % (int(pw[i]) * 100 / tot), 17, UIKit.TEXT)
		inf_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(inf_l)

	var icard := _card(cols, "Correntes políticas", "flag")
	var best := 0
	for j in 5:
		if int(ideo[j]) > int(ideo[best]):
			best = j
	for j in 5:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		icard.add_child(row)
		var nl := UIKit.label(IDEO_PT[j], 17, UIKit.GOLD_BRIGHT if j == best else UIKit.TEXT)
		nl.custom_minimum_size = Vector2(150, 0)
		row.add_child(nl)
		row.add_child(UIKit.bar(float(ideo[j]), 1000.0, IDEO_COLORS[j], 14.0))
		var pl := UIKit.label("%.1f%%" % (float(ideo[j]) / 10.0), 17, UIKit.TEXT)
		pl.custom_minimum_size = Vector2(62, 0)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pl)
	var dom := UIKit.label("Corrente dominante: %s" % IDEO_PT[best], 16, UIKit.GOLD)
	icard.add_child(dom)

	var gcard := _card(body, "Queixas da população", "book")
	var any := false
	for i in 6:
		if int(c.sat[i]) < 45:
			any = true
			var gl := UIKit.label("• " + str(CLASS_WHY[i]), 16, UIKit.NEG)
			gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gcard.add_child(gl)
	if not any:
		gcard.add_child(UIKit.label("Nenhuma queixa relevante no momento.", 16, UIKit.POS))
	var hint := UIKit.label("Preços de comida, impostos, indústria e instrução mudam a satisfação. Abaixo de %d%% de estabilidade há risco de revoltas." % Game.REVOLT_STABILITY, 15, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gcard.add_child(hint)


func _on_save_pressed() -> void:
	_show_toast("Jogo salvo." if Game.save_game() else "Falha ao salvar.")


func _on_load_pressed() -> void:
	if Net.is_online():
		_show_toast("Indisponível online.")
		return
	_show_toast("Jogo carregado." if Game.load_game() else "Nenhum save encontrado.")


func _on_auto_front_pressed() -> void:
	Game.submit_command(Cmd.set_auto_front(not Game.countries[Game.player_country].auto_front))
	_wars_sig = ""
	_refresh_side()


func _on_music_pressed(b: Button) -> void:
	AudioManager.set_music(not AudioManager.music_on)
	b.text = "Música: ligada" if AudioManager.music_on else "Música: desligada"


func _on_sfx_pressed(b: Button) -> void:
	AudioManager.set_sfx(not AudioManager.sfx_on)
	b.text = "Efeitos sonoros: ligados" if AudioManager.sfx_on else "Efeitos sonoros: desligados"


func _on_swap_pressed() -> void:
	if Net.is_online():
		_show_toast("Indisponível online.")
		return
	_toggle_window("menu")
	country_select_requested.emit()


# ---------------------------------------------------------------------------
# Painel da província
# ---------------------------------------------------------------------------
func _build_info_panel() -> void:
	var width := 330.0
	_info_panel = PanelContainer.new()
	_info_panel.custom_minimum_size = Vector2(width, 0)
	_info_panel.anchor_left = 0.0
	_info_panel.anchor_right = 0.0
	_info_panel.anchor_top = 1.0
	_info_panel.anchor_bottom = 1.0
	_info_panel.offset_left = SIDE_W + MARGIN
	_info_panel.offset_right = SIDE_W + MARGIN + width
	_info_panel.offset_top = -MARGIN
	_info_panel.offset_bottom = -MARGIN
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info_panel.visible = false
	_body.add_child(_info_panel)
	_blockers.append(_info_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_info_panel.add_child(col)

	var head := PanelContainer.new()
	head.theme_type_variation = "BannerPanel"
	col.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	head.add_child(hrow)
	var fframe := PanelContainer.new()
	fframe.theme_type_variation = "FlagFrame"
	fframe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(fframe)
	_info_flag = FlagRect.new()
	_info_flag.custom_minimum_size = Vector2(52, 34)
	fframe.add_child(_info_flag)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", -2)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(tcol)
	_info_title = UIKit.serif_label("", 22, UIKit.GOLD_BRIGHT)
	_info_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tcol.add_child(_info_title)
	_info_sub = UIKit.label("", 15, UIKit.TEXT)
	tcol.add_child(_info_sub)

	_info_body = UIKit.label("", 17, UIKit.TEXT)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info_body)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)

	var bsize := Vector2(164, 44)
	_btn_recruit = _info_button("Recrutar", bsize, _on_recruit_pressed, grid)
	_btn_take = _info_button("Assumir país", bsize, _on_take_pressed, grid)
	_btn_war = _info_button("Declarar guerra", bsize, _on_war_pressed, grid)
	_btn_improve = _info_button("Melhorar rel. (%d)" % Game.IMPROVE_COST, bsize, _on_improve_pressed, grid)
	_btn_embargo = _info_button("Embargar", bsize, _on_embargo_pressed, grid)
	_btn_ship = _info_button("%s (%d)" % [Game.ship_class_name(Game.countries[Game.player_country]), Game.SHIP_COST], bsize, _on_ship_pressed, grid)
	_btn_ally = _info_button("Propor aliança", bsize, _on_ally_pressed, grid)
	_btn_diplo = _info_button("Diplomacia", bsize, _on_diplo_pressed, grid)
	_btn_annex = _info_button("Anexar (debug)", bsize, _on_annex_pressed, grid)


func _info_button(text: String, size: Vector2, cb: Callable, parent: Control) -> Button:
	var b := _make_button(text, size)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_army_panel() -> void:
	_army_panel = PanelContainer.new()
	_army_panel.anchor_left = 1.0
	_army_panel.anchor_right = 1.0
	_army_panel.anchor_top = 1.0
	_army_panel.anchor_bottom = 1.0
	_army_panel.offset_left = -326.0
	_army_panel.offset_right = -MARGIN
	_army_panel.offset_top = -MARGIN
	_army_panel.offset_bottom = -MARGIN
	_army_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_army_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_army_panel.visible = false
	_body.add_child(_army_panel)
	_blockers.append(_army_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(300, 0)
	_army_panel.add_child(col)

	var head := PanelContainer.new()
	head.theme_type_variation = "BannerPanel"
	col.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	head.add_child(hrow)
	hrow.add_child(UiIcon.make("sword", 24, UIKit.GOLD_BRIGHT))
	hrow.add_child(UIKit.serif_label("Exército", 20, UIKit.GOLD_BRIGHT))

	_army_model = ArmyModel.new()
	col.add_child(_army_model)

	_army_label = UIKit.label("", 17, UIKit.TEXT)
	_army_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_army_label.custom_minimum_size = Vector2(300, 0)
	col.add_child(_army_label)

	var army_row := HBoxContainer.new()
	army_row.add_theme_constant_override("separation", 6)
	col.add_child(army_row)
	_btn_army_stop = _make_button("Parar", Vector2(90, 44))
	_btn_army_stop.pressed.connect(_on_army_stop_pressed)
	army_row.add_child(_btn_army_stop)
	_btn_army_disband = _make_button("Dissolver", Vector2(110, 44))
	_btn_army_disband.pressed.connect(_on_army_disband_pressed)
	army_row.add_child(_btn_army_disband)
	var close := _make_button("Fechar", Vector2(90, 44))
	close.pressed.connect(_on_army_close_pressed)
	army_row.add_child(close)


# ---------------------------------------------------------------------------
# Propostas de paz da IA
# ---------------------------------------------------------------------------
var _offer_panel: PanelContainer
var _offer_col: VBoxContainer


func _build_offer_panel() -> void:
	_offer_panel = PanelContainer.new()
	_offer_panel.theme_type_variation = "CardPanel"
	_offer_panel.anchor_left = 0.5
	_offer_panel.anchor_right = 0.5
	_offer_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_offer_panel.offset_top = 130
	_offer_panel.custom_minimum_size = Vector2(560, 0)
	_offer_panel.visible = false
	_ui.add_child(_offer_panel)
	_blockers.append(_offer_panel)
	_offer_col = VBoxContainer.new()
	_offer_col.add_theme_constant_override("separation", 10)
	_offer_panel.add_child(_offer_col)


func _refresh_offers() -> void:
	if _offer_panel == null:
		return
	UIKit.clear(_offer_col)
	var me: int = Game.player_country
	var shown := 0
	for o in Game.peace_offers:
		if int(o["to"]) != me:
			continue
		shown += 1
		var from: int = int(o["from"])
		var winner: int = int(o["winner"])
		var loser: int = from if winner == me else me
		var head := UIKit.serif_label("%s propõe a paz" % Game.countries[from].name, 22)
		_offer_col.add_child(head)
		var term: String = str(o["term"])
		_offer_col.add_child(UIKit.label(Game.peace_term_text(winner, loser, term, me), 18))
		_offer_col.add_child(UIKit.kv_row("Pontuação de guerra",
			"você %d  x  %d %s" % [Game.war_score(me, from), Game.war_score(from, me), Game.countries[from].name], UIKit.TEXT, 16))
		var left: int = maxi(0, AiDiplomacy.OFFER_DAYS - (Game.tick - int(o["tick"])))
		_offer_col.add_child(UIKit.label("A proposta expira em %d dias." % left, 15, UIKit.TEXT_DIM))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_offer_col.add_child(row)
		var yes := _make_button("Aceitar", Vector2(140, 46))
		yes.pressed.connect(_on_offer_answer.bind(from, true))
		row.add_child(yes)
		var no := _make_button("Recusar", Vector2(140, 46))
		no.pressed.connect(_on_offer_answer.bind(from, false))
		row.add_child(no)
		if shown >= 1:
			break   # uma proposta por vez; as demais aparecem depois
	_offer_panel.visible = shown > 0


func _on_offer_answer(from: int, accept: bool) -> void:
	if accept:
		Game.submit_command(Cmd.accept_peace(from))
	else:
		Game.submit_command(Cmd.reject_peace(from))
	_refresh_offers()


# ---------------------------------------------------------------------------
# Evento político
# ---------------------------------------------------------------------------
func _build_event_popup() -> void:
	_event_panel = PanelContainer.new()
	_event_panel.anchor_left = 0.5
	_event_panel.anchor_right = 0.5
	_event_panel.anchor_top = 0.5
	_event_panel.anchor_bottom = 0.5
	_event_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_event_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_event_panel.custom_minimum_size = Vector2(580, 0)
	_event_panel.visible = false
	_ui.add_child(_event_panel)
	_blockers.append(_event_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_event_panel.add_child(col)

	var head := PanelContainer.new()
	head.theme_type_variation = "BannerPanel"
	col.add_child(head)
	_event_title = UIKit.serif_label("", 28, UIKit.GOLD_BRIGHT)
	_event_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_event_title)

	_event_text = UIKit.label("", 19, UIKit.TEXT)
	_event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_text.custom_minimum_size = Vector2(540, 0)
	col.add_child(_event_text)

	_event_options = VBoxContainer.new()
	_event_options.add_theme_constant_override("separation", 8)
	col.add_child(_event_options)

	_event_timer = UIKit.label("", 15, UIKit.TEXT_DIM)
	col.add_child(_event_timer)


## Mostra o evento pendente do país do jogador (se houver) com um botão por opção.
func _refresh_event() -> void:
	var e := Game.pending_event_for(Game.player_country)
	var d := Game.find_event_def(str(e.get("event", ""))) if not e.is_empty() else {}
	if e.is_empty() or d.is_empty():
		_event_uid = -1
		_event_panel.visible = false
		return
	if int(e["uid"]) == _event_uid and _event_panel.visible:
		_update_event_timer()
		return
	_event_uid = int(e["uid"])
	_event_title.text = str(d["title"])
	_event_text.text = str(d["text"])
	UIKit.clear(_event_options)
	var options: Array = d["options"]
	for i in options.size():
		var opt: Dictionary = options[i]
		var b := UIKit.button("%s  %s" % [str(opt["label"]), _effects_text(opt.get("effects", {}))], Vector2(540, 52), "PrimaryButton" if i == 0 else "")
		b.pressed.connect(_on_event_option_pressed.bind(i))
		_event_options.add_child(b)
	_update_event_timer()
	_event_panel.visible = true


func _update_event_timer() -> void:
	var e := Game.pending_event_for(Game.player_country)
	if e.is_empty():
		return
	_event_timer.text = "Sem escolha em %d dias, vale a primeira opção." % int(e["days"])


static func _effects_text(fx: Dictionary) -> String:
	var parts: Array[String] = []
	if fx.has("gold"):
		parts.append("%+d ouro" % int(fx["gold"]))
	if fx.has("manpower"):
		parts.append("%+d mão de obra" % int(fx["manpower"]))
	if fx.has("pop_pct"):
		parts.append("%+d%% população" % int(fx["pop_pct"]))
	if fx.has("literacy"):
		parts.append("%+.1f%% alfabetização" % (float(fx["literacy"]) / 10.0))
	if fx.has("sat"):
		var sd: Dictionary = fx["sat"]
		for k in sd.keys():
			var ci: int = Game.CLASSES.find(str(k))
			if ci >= 0:
				parts.append("%s %+d" % [CLASS_PT[ci], int(sd[k])])
	if parts.is_empty():
		return ""
	return "(" + ", ".join(parts) + ")"


# ---------------------------------------------------------------------------
# Atualização
# ---------------------------------------------------------------------------
static func _fmt_pop(n: int) -> String:
	if n >= 1000000:
		return "%.2f mi" % (float(n) / 1000000.0)
	return "%.1f mil" % (float(n) / 1000.0)


func _refresh_all() -> void:
	_refresh_top()
	_refresh_info()
	_refresh_army()
	_refresh_event()
	_on_map_mode_changed(map_view.mode if map_view != null else 0)


func _refresh_top() -> void:
	var c := Game.countries[Game.player_country]
	_flag.set_country(c.tag, c.color)
	_country_label.text = c.name
	var wars: int = Game.wars_of(c.id).size()
	_country_sub.text = "%d províncias" % c.province_ids.size() if wars == 0 else "EM GUERRA (%d)" % wars
	_country_sub.add_theme_color_override("font_color", UIKit.TEXT_DIM if wars == 0 else UIKit.NEG)
	var e := Game.estimate_monthly(c)
	var net: int = int(e["income"]) - int(e["expense"])
	_set_chip("gold", str(c.treasury), "%+d/mês" % net, UIKit.POS if net >= 0 else UIKit.NEG, UIKit.NEG if c.treasury < 0 else UIKit.TEXT)
	_set_chip("pop", _fmt_pop(Game.population_of(c)), "habitantes")
	_set_chip("lit", "%d,%d%%" % [c.literacy / 10, c.literacy % 10], "alfabetização")
	_set_chip("sol", "%.1f" % (float(Game.standard_of_living_x10(c, e)) / 10.0), "padrão de vida")
	_set_chip("tech", "Nível %d" % c.tech_level(), "%d%% p/ o próximo" % ((c.tech_pts % Country.TECH_STEP) * 100 / Country.TECH_STEP))
	var sc: Color = _sat_color(c.stability)
	_set_chip("stab", "%d%%" % c.stability, "estabilidade", UIKit.TEXT_DIM, sc)
	_set_chip("army", "%d reg." % int(e["regiments"]), "MO %s" % _fmt_pop(Game.manpower_of(c.id)))
	_date_label.text = Game.clock.format()
	var s := clampi(Game.speed, 0, _speed_buttons.size() - 1)
	_speed_buttons[s].set_pressed_no_signal(true)
	_refresh_windows()
	_refresh_side()


func _refresh_side() -> void:
	var me := Game.player_country
	var ids: Array = []
	for a in Game.armies.values():
		var army: Army = a
		if army.owner_id == me:
			ids.append(army.id)
	ids.sort()
	var shown: Array = ids.slice(0, 6)
	for aid in _army_rows.keys():
		if not shown.has(aid):
			(_army_rows[aid] as Button).queue_free()
			_army_rows.erase(aid)
	for aid in shown:
		var army: Army = Game.armies[aid]
		var b: Button = _army_rows.get(aid)
		if b == null:
			b = UIKit.button("", Vector2(0, 36), "FlatButton")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(_on_army_row_pressed.bind(aid))
			_side_armies.add_child(b)
			_army_rows[aid] = b
		b.text = "#%d · %d reg. · %s%s" % [army.id, army.regiments, Game.provinces[army.province_id].name, "  >>" if army.is_moving() else ""]
	_side_head.text = "Exércitos (%d)" % ids.size()
	_side_head.visible = not ids.is_empty()

	var war_ids: Array = Game.wars_of(me)
	var sig := ",".join(PackedStringArray(war_ids.map(func(x): return str(x)))) + ("|A" if Game.countries[me].auto_front else "|M")
	if sig != _wars_sig:
		_wars_sig = sig
		UIKit.clear(_side_wars)
		if not war_ids.is_empty():
			_side_wars.add_child(UIKit.serif_label("MODO DE GUERRA", 19, UIKit.NEG))
		for wid in war_ids:
			var oc: Country = Game.countries[int(wid)]
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 8)
			var fl := FlagRect.new()
			fl.custom_minimum_size = Vector2(34, 22)
			fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			fl.set_country(oc.tag, oc.color)
			r.add_child(fl)
			r.add_child(UIKit.label(oc.name, 16, UIKit.TEXT))
			_side_wars.add_child(r)
		if not war_ids.is_empty():
			var af := Game.countries[me].auto_front
			var ab := UIKit.button("Frente automática (exército e frota): %s" % ("LIGADA" if af else "desligada"), Vector2(0, 40), "PrimaryButton" if af else "")
			ab.add_theme_font_size_override("font_size", 16)
			ab.pressed.connect(_on_auto_front_pressed)
			_side_wars.add_child(ab)
	_side_panel.visible = not ids.is_empty() or not war_ids.is_empty()


func _on_army_row_pressed(aid: int) -> void:
	var a: Army = Game.armies.get(aid)
	if a == null:
		return
	Events.army_selected.emit(aid)
	Events.province_selected.emit(a.province_id)
	Events.focus_province.emit(a.province_id)


func _refresh_info() -> void:
	if _selected < 0 or _selected >= Game.provinces.size():
		_info_panel.visible = false
		_refresh_build_panel()
		return
	var p := Game.provinces[_selected]
	var has_owner := p.owner_id >= 0 and p.owner_id < Game.countries.size()
	var mine := has_owner and p.owner_id == Game.player_country
	_info_panel.visible = true
	_info_title.text = p.name
	var sub := "%s%s" % ["★ " if p.capital_city else "", p.city] if p.city != "" else ""
	if has_owner and p.core_owner >= 0 and p.core_owner != p.owner_id and p.core_owner < Game.countries.size():
		sub = ("%s · " % sub if sub != "" else "") + "Conquistada de %s" % Game.countries[p.core_owner].name
	if p.region != "" and p.region != p.name:
		sub = ("%s · " % sub if sub != "" else "") + "Prov. de %s" % p.region

	var owner_name := "Sem dono"
	var tax := 0
	if has_owner:
		var oc := Game.countries[p.owner_id]
		owner_name = oc.name
		tax = oc.tax_pct
		_info_flag.set_country(oc.tag, oc.color)
	else:
		_info_flag.set_country("", Color(0.4, 0.4, 0.4))
	_info_sub.text = sub if sub != "" else owner_name

	var lines: Array[String] = []
	lines.append("País: %s" % owner_name)
	lines.append("%s  ·  %s" % [TERRAIN_PT.get(p.terrain, p.terrain), RESOURCE_PT.get(p.resource_type, p.resource_type)])
	lines.append("População: %s" % _fmt_pop(p.population))
	lines.append("Preço do recurso: %d%%" % p.price_of(p.resource_type))
	lines.append("Produção: %d/mês   Imposto: %d/mês" % [p.production(), p.monthly_tax(tax) if has_owner else 0])
	lines.append("Mão de obra: %s / %s" % [_fmt_pop(p.manpower), _fmt_pop(p.manpower_max())])
	var bl := _buildings_summary(p)
	if bl != "":
		lines.append(bl)
	if Game.sieges.has(p.id):
		lines.append("CERCO: %d/%d dias (%s)" % [int(Game.sieges[p.id]["days"]), Game.SIEGE_DAYS, Game.countries[int(Game.sieges[p.id]["by"])].name])
	if has_owner and not mine:
		var me4 := Game.player_country
		if Game.at_war(me4, p.owner_id):
			lines.append("Em GUERRA com este país")
		else:
			var rel := "Opinião: %+d" % Game.opinion(me4, p.owner_id)
			if Game.allied(me4, p.owner_id):
				rel += "  (ALIADO)"
			var tl := Game.truce_left(me4, p.owner_id)
			if tl > 0:
				rel += "  (trégua: %d dias)" % tl
			lines.append(rel)
	if p.factory != "":
		var fr := p.building_report(p.factory, p.factory_level, tax)
		lines.append("Indústria: %s nív. %d  (líquido %+d/mês, imposto %d)" % [Province.BUILDINGS[p.factory]["name"], p.factory_level, int(fr["net"]), int(fr["tax"])])
	var queued := Game.queued_in(p.id)
	if queued > 0:
		lines.append("Treinando: %d regimento(s)" % queued)
	_info_body.text = "\n".join(lines)

	_btn_recruit.visible = mine
	if mine:
		var me := Game.player_country
		_btn_recruit.text = "Recrutar (%d)" % Game.RECRUIT_COST
		_btn_recruit.disabled = not Game.can_recruit(p.id, me)
	_refresh_build_panel()
	_btn_take.visible = has_owner and not mine and not Net.is_online()
	_btn_annex.visible = DEBUG_TOOLS and not mine
	_btn_war.visible = has_owner and not mine
	_btn_diplo.visible = has_owner and not mine
	_btn_improve.visible = has_owner and not mine
	_btn_ally.visible = has_owner and not mine
	_btn_embargo.visible = has_owner and not mine
	_btn_ship.visible = mine and p.port >= 0
	if mine and p.port >= 0:
		_btn_ship.disabled = not Game.can_build_ship(p.id, Game.player_country)
		_btn_ship.text = "%s (%d)" % [Game.ship_class_name(Game.countries[Game.player_country]), Game.SHIP_COST]
	if has_owner and not mine:
		var has_emb := Game.embargoes.has(Game.player_country * 1000 + p.owner_id)
		_btn_embargo.text = "Suspender embargo" if has_emb else "Embargar"
		_btn_embargo.disabled = not has_emb and not Game.can_embargo(Game.player_country, p.owner_id)
		var me3 := Game.player_country
		_btn_improve.disabled = not Game.can_improve(me3, p.owner_id)
		var is_ally := Game.allied(me3, p.owner_id)
		_btn_ally.text = "Romper aliança" if is_ally else "Propor aliança"
		_btn_ally.disabled = not is_ally and not Game.can_ally(me3, p.owner_id)
		if Game.at_war(me3, p.owner_id):
			var left := Game.WAR_MIN_DAYS - Game.war_days(me3, p.owner_id)
			_btn_war.text = "Negociar paz" if left <= 0 else "Paz em %d dias" % left
			_btn_war.disabled = left > 0
		else:
			_btn_war.text = "Declarar guerra"
			_btn_war.disabled = not Game.can_declare_war(me3, p.owner_id)


func _refresh_army() -> void:
	var a: Army = Game.armies.get(_selected_army)
	if a == null:
		_army_panel.visible = false
		return
	_army_panel.visible = true
	var mine := a.owner_id == Game.player_country
	var oc := Game.countries[a.owner_id]
	var txt := "%s\n%d regimento(s)  (%d homens)\nEm: %s" % [
		oc.name, a.regiments, a.men(), Game.provinces[a.province_id].name,
	]
	if a.is_moving():
		txt += "\nDestino: %s (%d dias)" % [Game.provinces[a.path.back()].name, Game.eta_days(a)]
	elif mine:
		txt += "\nToque numa província para marchar."
	_army_label.text = txt
	_army_model.show_army(oc.tag, oc.color, a.regiments, a.is_moving())
	_btn_army_stop.visible = mine and a.is_moving()
	_btn_army_disband.visible = mine


# ---------------------------------------------------------------------------
# Eventos do jogo
# ---------------------------------------------------------------------------
func _on_day_changed(_date: Dictionary) -> void:
	_date_label.text = Game.clock.format()
	if _selected_army >= 0:
		_refresh_army()
	if _event_uid >= 0:
		_update_event_timer()   # só o contador: refazer os botões todo dia atrapalharia o toque


func _input(event: InputEvent) -> void:
	if _root == null or not _root.visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k == KEY_SPACE:
		Game.submit_command(Cmd.set_speed(0 if Game.speed > 0 else 1))
	elif k == KEY_EQUAL or k == KEY_KP_ADD:
		Game.submit_command(Cmd.set_speed(clampi(Game.speed + 1, 1, Game.MAX_SPEED)))
	elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
		Game.submit_command(Cmd.set_speed(clampi(Game.speed - 1, 1, Game.MAX_SPEED)))


func _on_month_changed(_date: Dictionary) -> void:
	if int(_date.get("month", 0)) == 1 and not Net.is_online() and _root.visible:
		Game.save_game("user://autosave.json")   # autosave anual (só local)
	_refresh_top()
	_refresh_info()
	_refresh_windows()
	_refresh_offers()


func _on_treasury_changed(cid: int) -> void:
	if cid == Game.player_country:
		_refresh_top()
		_refresh_info()


func _on_speed_changed(s: int) -> void:
	_speed_buttons[clampi(s, 0, _speed_buttons.size() - 1)].set_pressed_no_signal(true)


func _on_province_selected(pid: int) -> void:
	_selected = pid
	_refresh_info()


func _on_province_updated(_pid: int) -> void:
	_refresh_top()
	_refresh_info()


func _on_player_changed(_cid: int) -> void:
	_refresh_top()
	_refresh_info()
	_refresh_army()
	_refresh_event()


func _on_map_mode_changed(mode: int) -> void:
	var b: Button = _side_btns.get("map")
	if b != null:
		b.tooltip_text = "Modo do mapa: %s (toque para alternar)" % MapView.MODE_NAMES[mode]


func _on_army_selected(aid: int) -> void:
	_selected_army = aid
	_refresh_army()


func _on_army_changed(aid: int) -> void:
	if aid == _selected_army:
		_refresh_army()


func _on_army_removed(aid: int) -> void:
	if aid == _selected_army:
		Events.army_selected.emit(-1)


func _on_command_applied(_cmd: Dictionary) -> void:
	_refresh_windows()
	_refresh_top()
	_refresh_info()
	_refresh_army()


# ---------------------------------------------------------------------------
# Ações do jogador
# ---------------------------------------------------------------------------
func _on_speed_pressed(index: int) -> void:
	Game.submit_command(Cmd.set_speed(index))


func _on_tax_pressed(delta: int) -> void:
	var c := Game.countries[Game.player_country]
	Game.submit_command(Cmd.set_tax(c.id, clampi(c.tax_pct + delta, 0, 100)))


func _on_recruit_pressed() -> void:
	if _selected >= 0:
		Game.submit_command(Cmd.recruit(_selected))


func _on_build_pressed(kind: String) -> void:
	if _selected >= 0:
		Game.submit_command(Cmd.build(_selected, kind))


func _on_take_pressed() -> void:
	if _selected >= 0:
		Game.set_player_country(Game.provinces[_selected].owner_id)


func _on_diplo_pressed() -> void:
	if _selected >= 0 and Game.provinces[_selected].owner_id >= 0:
		_open_diplomacy(Game.provinces[_selected].owner_id)


func _open_diplomacy(target: int) -> void:
	_diplo_target = target
	if not _windows["diplo"].visible:
		_toggle_window("diplo")
	else:
		_refresh_diplomacy()


func _on_war_pressed() -> void:
	if _selected < 0:
		return
	var target := Game.provinces[_selected].owner_id
	if Game.at_war(Game.player_country, target):
		_open_diplomacy(target)   # a paz agora tem termos: escolha na janela de Diplomacia
	else:
		Game.submit_command(Cmd.declare_war(target))


func _on_embargo_pressed() -> void:
	if _selected < 0:
		return
	var target := Game.provinces[_selected].owner_id
	if Game.embargoes.has(Game.player_country * 1000 + target):
		Game.submit_command(Cmd.lift_embargo(target))
	else:
		Game.submit_command(Cmd.embargo(target))


func _on_ship_pressed() -> void:
	if _selected >= 0:
		Game.submit_command(Cmd.build_ship(_selected))


func _on_improve_pressed() -> void:
	if _selected >= 0:
		Game.submit_command(Cmd.improve_relations(Game.provinces[_selected].owner_id))


func _on_ally_pressed() -> void:
	if _selected < 0:
		return
	var target := Game.provinces[_selected].owner_id
	if Game.allied(Game.player_country, target):
		Game.submit_command(Cmd.break_alliance(target))
	else:
		Game.submit_command(Cmd.propose_alliance(target))


# ---------------------------------------------------------------------------
# Diplomacia: relações, alianças, guerra, paz com termos, vassalos e anexação
# ---------------------------------------------------------------------------
func _diplo_status(me: int, t: int) -> Array:
	var tc := Game.countries[t]
	if Game.at_war(me, t):
		return ["Em guerra", UIKit.NEG]
	if tc.overlord == me:
		return ["Seu vassalo", UIKit.GOLD_BRIGHT]
	if Game.countries[me].overlord == t:
		return ["Seu suserano", UIKit.GOLD_BRIGHT]
	if tc.overlord >= 0:
		return ["Vassalo de %s" % Game.countries[tc.overlord].name, UIKit.GOLD]
	if Game.allied(me, t):
		return ["Aliado", UIKit.POS]
	if Game.embargoes.has(me * 1000 + t) or Game.embargoes.has(t * 1000 + me):
		return ["Embargo", UIKit.WARN]
	if Game.truce_left(me, t) > 0:
		return ["Trégua (%d dias)" % Game.truce_left(me, t), UIKit.TEXT_DIM]
	return ["Neutro", UIKit.TEXT]


func _war_block_reason(me: int, t: int) -> String:
	if Game.countries[me].overlord >= 0:
		return "Vassalos não declaram guerra."
	if Game.countries[t].overlord == me:
		return "Não se ataca o próprio vassalo."
	if Game.allied(me, t):
		return "Rompa a aliança antes."
	if Game.truce_left(me, t) > 0:
		return "Trégua por mais %d dias." % Game.truce_left(me, t)
	return ""


func _refresh_diplomacy() -> void:
	var body: VBoxContainer = _win_bodies["diplo"]
	UIKit.clear(body)
	var me := Game.player_country
	var mc := Game.countries[me]
	var line := PackedStringArray()
	if mc.overlord >= 0:
		line.append("Vassalo de %s (tributo de %d%% da renda)" % [Game.countries[mc.overlord].name, Game.VASSAL_TRIBUTE_PCT])
	var vs := Game.vassals_of(me)
	if not vs.is_empty():
		line.append("%d vassalo(s)" % vs.size())
	line.append("%d aliado(s)" % Game.allies_of(me).size())
	line.append("%d guerra(s)" % Game.wars_of(me).size())
	body.add_child(UIKit.label(" · ".join(line), 16, UIKit.TEXT_DIM))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cols)

	var left := _card(cols, "Países", "globe")
	left.get_parent().custom_minimum_size = Vector2(330, 0)
	var rows: Array = []
	for c in Game.countries:
		if c.id == me or not c.is_alive():
			continue
		var st := _diplo_status(me, c.id)
		var pr := 3
		if Game.at_war(me, c.id):
			pr = 0
		elif c.overlord == me or mc.overlord == c.id:
			pr = 1
		elif Game.allied(me, c.id):
			pr = 2
		rows.append({"id": c.id, "pr": pr, "op": Game.opinion(me, c.id), "st": st})
	rows.sort_custom(_diplo_less)
	if _diplo_target < 0 or _diplo_target == me or not Game.countries[_diplo_target].is_alive():
		_diplo_target = int(rows[0]["id"]) if not rows.is_empty() else -1
	for r in rows:
		var rc := Game.countries[int(r["id"])]
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s — %s (%+d)" % [rc.name, str((r["st"] as Array)[0]), int(r["op"])]
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", (r["st"] as Array)[1])
		if int(r["id"]) == _diplo_target:
			b.add_theme_color_override("font_color", UIKit.GOLD_BRIGHT)
			b.text = "▶ " + b.text
		b.pressed.connect(_on_diplo_pick.bind(int(r["id"])))
		left.add_child(b)

	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 10)
	cols.add_child(right_box)
	if _diplo_target >= 0:
		_diplo_detail(right_box, me, _diplo_target)


func _diplo_less(x: Dictionary, y: Dictionary) -> bool:
	if int(x["pr"]) != int(y["pr"]):
		return int(x["pr"]) < int(y["pr"])
	if int(x["op"]) != int(y["op"]):
		return int(x["op"]) > int(y["op"])
	return int(x["id"]) < int(y["id"])


func _on_diplo_pick(id: int) -> void:
	_diplo_target = id
	_refresh_diplomacy()


func _diplo_detail(parent: VBoxContainer, me: int, t: int) -> void:
	var tc := Game.countries[t]
	var st := _diplo_status(me, t)
	var card := _card(parent, tc.name, "flag")
	card.add_child(UIKit.kv_row("Situação", str(st[0]), st[1]))
	var op := Game.opinion(me, t)
	card.add_child(UIKit.kv_row("Opinião sobre você", "%+d" % op, UIKit.POS if op > 10 else (UIKit.NEG if op < -10 else UIKit.TEXT)))
	card.add_child(UIKit.kv_row("Províncias · exércitos · navios", "%d · %d · %d" % [tc.province_ids.size(), Game.regiments_of(t), tc.ships]))
	card.add_child(UIKit.kv_row("Seu exército · navios", "%d · %d" % [Game.regiments_of(me), Game.countries[me].ships]))
	if tc.overlord == me:
		var left_days := maxi(0, Game.ANNEX_MIN_DAYS - (Game.tick - tc.overlord_since))
		card.add_child(UIKit.kv_row("Tributo mensal", "%d" % (maxi(0, tc.last_income) * Game.VASSAL_TRIBUTE_PCT / 100), UIKit.POS))
		card.add_child(UIKit.kv_row("Anexação", "pronta" if left_days == 0 else "em %d dias" % left_days))

	var acts := _card(parent, "Ações", "scroll")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	acts.add_child(grid)
	var bs := Vector2(210, 46)
	var at_war := Game.at_war(me, t)
	var b1 := _info_button("Melhorar relações (%d)" % Game.IMPROVE_COST, bs, _diplo_cmd.bind(Cmd.improve_relations(t)), grid)
	b1.disabled = not Game.can_improve(me, t)
	var is_ally := Game.allied(me, t)
	var vassal_pair := tc.overlord == me or Game.countries[me].overlord == t
	var b2 := _info_button("Romper aliança" if is_ally else "Propor aliança", bs,
		_diplo_cmd.bind(Cmd.break_alliance(t) if is_ally else Cmd.propose_alliance(t)), grid)
	b2.disabled = vassal_pair or (not is_ally and not Game.can_ally(me, t))
	var has_emb := Game.embargoes.has(me * 1000 + t)
	var b3 := _info_button("Suspender embargo" if has_emb else "Embargar", bs,
		_diplo_cmd.bind(Cmd.lift_embargo(t) if has_emb else Cmd.embargo(t)), grid)
	b3.disabled = not has_emb and not Game.can_embargo(me, t)
	if not at_war:
		var b4 := _info_button("Declarar guerra", bs, _diplo_cmd.bind(Cmd.declare_war(t)), grid)
		b4.disabled = not Game.can_declare_war(me, t)
		var why := _war_block_reason(me, t)
		if why != "":
			acts.add_child(UIKit.label(why, 14, UIKit.TEXT_DIM))
	if tc.overlord == me:
		var b5 := _info_button("Anexar vassal (%d)" % Game.annex_cost(t), bs, _diplo_cmd.bind(Cmd.annex_vassal(t)), grid)
		b5.disabled = not Game.can_annex_vassal(me, t)
		_info_button("Libertar vassal", bs, _diplo_cmd.bind(Cmd.release_vassal(t)), grid)

	if at_war:
		var wc := _card(parent, "Guerra e paz", "sword")
		var mine_sc := Game.war_score(me, t)
		var their_sc := Game.war_score(t, me)
		wc.add_child(UIKit.kv_row("Pontuação de guerra (você × eles)", "%d × %d" % [mine_sc, their_sc], UIKit.POS if mine_sc > their_sc else UIKit.NEG))
		if not Game.is_human(t):
			var wl: String = AiDiplomacy.willingness(Game, t, me)
			wc.add_child(UIKit.kv_row("Disposição a negociar", wl.capitalize(), UIKit.POS if wl == "alta" else (UIKit.TEXT if wl == "média" else UIKit.NEG)))
		var left_d := Game.WAR_MIN_DAYS - Game.war_days(me, t)
		if left_d > 0:
			wc.add_child(UIKit.label("Paz possível em %d dias." % left_d, 15, UIKit.TEXT_DIM))
		var wg := GridContainer.new()
		wg.columns = 2
		wg.add_theme_constant_override("h_separation", 8)
		wg.add_theme_constant_override("v_separation", 8)
		wc.add_child(wg)
		for o in Game.peace_options(me, t):
			var need := int(o["need"])
			var label := str(o["label"]) + ("" if need == 0 else " (≥%d)" % need)
			var pb := _info_button(label, bs, _diplo_cmd.bind(Cmd.make_peace(t, str(o["id"]))), wg)
			pb.disabled = not bool(o["ok"])
		wc.add_child(UIKit.label("Conquistar províncias, cercar e tomar a capital aumenta a pontuação.", 14, UIKit.TEXT_DIM))


func _diplo_cmd(cmd: Dictionary) -> void:
	Game.submit_command(cmd)
	_refresh_diplomacy()


func _on_annex_pressed() -> void:
	if _selected >= 0:
		Game.submit_command(Cmd.transfer_province(_selected, Game.player_country))


func _on_army_stop_pressed() -> void:
	if _selected_army >= 0:
		Game.submit_command(Cmd.stop_army(_selected_army))


func _on_army_disband_pressed() -> void:
	if _selected_army >= 0:
		Game.submit_command(Cmd.disband_army(_selected_army))


func _on_army_close_pressed() -> void:
	Events.army_selected.emit(-1)


func _on_event_option_pressed(option: int) -> void:
	if _event_uid >= 0:
		Game.submit_command(Cmd.choose_event(_event_uid, option))
