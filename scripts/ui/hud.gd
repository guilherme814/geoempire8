class_name HUD
extends CanvasLayer
## Interface do jogo, montada 100% por código (sem .tscn para manter o diff limpo).
## Barra superior: país, tesouro, tropas, data e velocidade.
## Canto inferior esquerdo: província selecionada (recrutar, construir).
## Canto inferior direito: exército selecionado, modo do mapa e impostos.
##
## A HUD nunca muda o estado: ela chama Game.submit_command().

const DEBUG_TOOLS := true
const MARGIN := 10.0

const TERRAIN_PT := {
	"plains": "Planície", "hills": "Colinas", "mountains": "Montanhas", "forest": "Floresta",
	"desert": "Deserto", "jungle": "Selva", "tundra": "Tundra",
}
const RESOURCE_PT := {
	"grain": "Grãos", "livestock": "Gado", "fish": "Peixe", "timber": "Madeira",
	"furs": "Peles", "wool": "Lã", "cotton": "Algodão", "coal": "Carvão", "iron": "Ferro",
	"salt": "Sal", "wine": "Vinho", "sugar": "Açúcar", "tobacco": "Tabaco", "coffee": "Café",
	"tea": "Chá", "silk": "Seda", "spices": "Especiarias", "opium": "Ópio", "gold": "Ouro",
	"fabric": "Tecido", "tools": "Ferramentas", "furniture": "Móveis",
}

var map_view: MapView

var _root: Control
var _theme: Theme
var _blockers: Array[Control] = []
var _inset: Vector4 = Vector4.ZERO   # esquerda, topo, direita, base (área segura)

var _flag: FlagRect
var _country_label: Label
var _treasury_label: Label
var _eco_panel: PanelContainer
var _eco_label: Label
var _market_panel: PanelContainer
var _market_grid: GridContainer
var _toast: Label
var _stats_label: Label
var _date_label: Label
var _speed_buttons: Array[Button] = []

var _info_panel: PanelContainer
var _info_title: Label
var _info_body: Label
var _btn_recruit: Button
var _btn_workshop: Button
var _btn_barracks: Button
var _btn_fact: Array[Button] = []
const FACTORY_PT := {"textile": "Tecelagem", "smithy": "Ferraria", "carpentry": "Marcenaria"}
var _btn_take: Button
var _btn_annex: Button
var _btn_war: Button
var _btn_improve: Button
var _btn_ally: Button
var _btn_embargo: Button
var _btn_ship: Button

var _army_box: VBoxContainer
var _army_label: Label
var _btn_army_stop: Button
var _btn_army_disband: Button

var _mode_button: Button
var _tax_label: Label

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
	_build_theme()

	_root = Control.new()
	_root.theme = _theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_build_top_bar()
	_build_info_panel()
	_build_bottom_right()
	_build_event_popup()
	_build_stats_bar()
	_build_economy_panel()
	_build_market_panel()

	Events.game_event_changed.connect(_refresh_event)
	Events.day_changed.connect(_on_day_changed)
	Events.notice.connect(_show_toast)
	Events.war_changed.connect(_refresh_top)
	Events.war_changed.connect(_refresh_info)
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
	_theme.default_font_size = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.88)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	_theme.set_stylebox("panel", "PanelContainer", sb)


func _make_button(text: String, min_size: Vector2 = Vector2(64, 48)) -> Button:
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

	_flag = FlagRect.new()
	_flag.custom_minimum_size = Vector2(60, 40)
	_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_flag)

	_country_label = Label.new()
	_country_label.add_theme_font_size_override("font_size", 24)
	row.add_child(_country_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_treasury_label = Label.new()
	row.add_child(_treasury_label)

	var eco_btn := _make_button("Economia", Vector2(110, 46))
	eco_btn.pressed.connect(_on_economy_pressed)
	row.add_child(eco_btn)

	var mkt_btn := _make_button("Mercado", Vector2(100, 46))
	mkt_btn.pressed.connect(_on_market_pressed)
	row.add_child(mkt_btn)

	_date_label = Label.new()
	_date_label.custom_minimum_size = Vector2(130, 0)
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_date_label)

	var group := ButtonGroup.new()
	var labels: Array[String] = ["II", ">", ">>", ">>>", ">>>>"]
	for i in labels.size():
		var b := _make_button(labels[i], Vector2(54, 46))
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_on_speed_pressed.bind(i))
		row.add_child(b)
		_speed_buttons.append(b)


func _build_stats_bar() -> void:
	var bar := PanelContainer.new()
	bar.offset_left = _inset.x + MARGIN
	bar.offset_top = _inset.y + MARGIN + 78
	_root.add_child(bar)
	_blockers.append(bar)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 19)
	bar.add_child(_stats_label)


func _build_economy_panel() -> void:
	_eco_panel = PanelContainer.new()
	_eco_panel.anchor_left = 1.0
	_eco_panel.anchor_right = 1.0
	_eco_panel.offset_left = -(_inset.z + MARGIN)
	_eco_panel.offset_right = -(_inset.z + MARGIN)
	_eco_panel.offset_top = _inset.y + MARGIN + 80
	_eco_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_eco_panel.visible = false
	_root.add_child(_eco_panel)
	_blockers.append(_eco_panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	_eco_panel.add_child(col)
	_eco_label = Label.new()
	_eco_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_eco_label)
	var close := _make_button("Fechar", Vector2(100, 44))
	close.pressed.connect(_on_economy_pressed)
	col.add_child(close)


func _refresh_economy() -> void:
	if _eco_panel == null or not _eco_panel.visible:
		return
	var c := Game.countries[Game.player_country]
	var e := Game.estimate_monthly(c)
	var net: int = int(e["income"]) - int(e["expense"])
	var lines: Array[String] = []
	lines.append("ECONOMIA - %s" % c.name)
	lines.append("Taxa de imposto: %d%%   Províncias: %d" % [c.tax_pct, c.province_ids.size()])
	lines.append("")
	lines.append("Produção bruta: %d/mês" % int(e["production"]))
	lines.append("Receita: %+d  (impostos %d%% + base %d, indústria %+d, comércio %+d)" % [int(e["income"]), c.tax_pct, int(e["flat"]), int(e["industry"]), int(e["trade"])])
	lines.append("Manutenção de províncias: -%d" % int(e["upkeep_prov"]))
	lines.append("Manutenção de exércitos: -%d  (%d reg.)" % [int(e["upkeep_army"]), int(e["regiments"])])
	lines.append("Manutenção da frota: -%d  (%d navios)" % [int(e["upkeep_navy"]), c.ships])
	var cap := Game.sea_capacity(c.id)
	lines.append("Capacidade de comércio marítimo: %d/mês%s" % [cap, "  (BLOQUEADO)" if Game.is_blockaded(c.id) else ""])
	var emb := PackedStringArray()
	for k in Game.embargoes:
		var a: int = int(k) / 1000
		var t: int = int(k) % 1000
		if a == c.id:
			emb.append("você -> %s" % Game.countries[t].name)
		elif t == c.id:
			emb.append("%s -> você" % Game.countries[a].name)
	if not emb.is_empty():
		lines.append("Embargos: " + ", ".join(emb))
	lines.append("SALDO: %+d/mês" % net)
	if net < 0 and c.treasury > 0:
		lines.append("Tesouro acaba em ~%d meses" % (c.treasury / -net))
	lines.append("")
	lines.append("Províncias que mais rendem:")
	for r in Game.top_provinces(c, 5):
		var p := Game.provinces[int(r["id"])]
		lines.append("  %s%s: +%d" % [p.name, "" if p.city == "" else " (%s)" % p.city, int(r["tax"])])
	_eco_label.text = "\n".join(lines)


func _build_market_panel() -> void:
	_market_panel = PanelContainer.new()
	_market_panel.anchor_left = 1.0
	_market_panel.anchor_right = 1.0
	_market_panel.offset_left = -(_inset.z + MARGIN)
	_market_panel.offset_right = -(_inset.z + MARGIN)
	_market_panel.offset_top = _inset.y + MARGIN + 80
	_market_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_market_panel.visible = false
	_root.add_child(_market_panel)
	_blockers.append(_market_panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(520, 0)
	_market_panel.add_child(col)
	var title := Label.new()
	title.text = "MERCADO DO SEU PAÍS  (preço = % do base; + falta, - sobra)"
	col.add_child(title)
	_market_grid = GridContainer.new()
	_market_grid.columns = 6
	_market_grid.add_theme_constant_override("h_separation", 14)
	_market_grid.add_theme_constant_override("v_separation", 1)
	col.add_child(_market_grid)
	var close := _make_button("Fechar", Vector2(100, 40))
	close.pressed.connect(_on_market_pressed)
	col.add_child(close)


func _refresh_market() -> void:
	if _market_panel == null or not _market_panel.visible:
		return
	var pc := Game.player_country
	var tb := Game.market_tables()
	var sup: Dictionary = tb[0][pc]
	var dem: Dictionary = tb[1][pc]
	for c in _market_grid.get_children():
		c.queue_free()
	_market_row(["Bem", "Oferta", "Demanda", "Preço", "Importa", "Exporta"], true)
	for g in Game.goods_list():
		var s: int = int(sup[g])
		var d: int = int(dem[g])
		var arrow := " "
		if d > s * 102 / 100:
			arrow = " +"      # falta: preço sobe
		elif d * 102 / 100 < s:
			arrow = " -"      # sobra: preço cai
		var im: int = int(Game.trade_imp[pc].get(g, 0)) if pc < Game.trade_imp.size() else 0
		var ex: int = int(Game.trade_exp[pc].get(g, 0)) if pc < Game.trade_exp.size() else 0
		_market_row([RESOURCE_PT.get(g, g), str(s), str(d), "%d%%%s" % [int(Game.local_price[pc][g]), arrow], str(im), str(ex)], false)


func _market_row(cells: Array, header: bool) -> void:
	for i in cells.size():
		var l := Label.new()
		l.text = str(cells[i])
		l.add_theme_font_size_override("font_size", 16)
		if header:
			l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		if i > 0:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(100 if i == 0 else 66, 0)
		_market_grid.add_child(l)


func _on_market_pressed() -> void:
	_market_panel.visible = not _market_panel.visible
	_refresh_market()


func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(_toast):
		_toast.visible = false


func _on_save_pressed() -> void:
	_show_toast("Jogo salvo." if Game.save_game() else "Falha ao salvar.")


func _on_load_pressed() -> void:
	if Net.is_online():
		_show_toast("Indisponível online.")
		return
	_show_toast("Jogo carregado." if Game.load_game() else "Nenhum save encontrado.")


func _on_economy_pressed() -> void:
	_eco_panel.visible = not _eco_panel.visible
	_refresh_economy()


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
	col.add_theme_constant_override("separation", 6)
	_info_panel.add_child(col)

	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 28)
	col.add_child(_info_title)

	_info_body = Label.new()
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info_body)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)

	var bsize := Vector2(190, 46)
	_btn_recruit = _make_button("Recrutar", bsize)
	_btn_recruit.pressed.connect(_on_recruit_pressed)
	grid.add_child(_btn_recruit)

	_btn_workshop = _make_button("Oficina", bsize)
	_btn_workshop.pressed.connect(_on_build_pressed.bind("workshop"))
	grid.add_child(_btn_workshop)

	_btn_barracks = _make_button("Quartel", bsize)
	_btn_barracks.pressed.connect(_on_build_pressed.bind("barracks"))
	grid.add_child(_btn_barracks)

	for k in Province.FACTORIES.keys():
		var fb := _make_button(FACTORY_PT[k], bsize)
		fb.pressed.connect(_on_build_pressed.bind(k))
		grid.add_child(fb)
		_btn_fact.append(fb)

	_btn_take = _make_button("Assumir país", bsize)
	_btn_take.pressed.connect(_on_take_pressed)
	grid.add_child(_btn_take)

	_btn_war = _make_button("Declarar guerra", bsize)
	_btn_war.pressed.connect(_on_war_pressed)
	grid.add_child(_btn_war)

	_btn_improve = _make_button("Melhorar relações (%d)" % Game.IMPROVE_COST, bsize)
	_btn_improve.pressed.connect(_on_improve_pressed)
	grid.add_child(_btn_improve)

	_btn_embargo = _make_button("Embargar", bsize)
	_btn_embargo.pressed.connect(_on_embargo_pressed)
	grid.add_child(_btn_embargo)

	_btn_ship = _make_button("Navio (%d)" % Game.SHIP_COST, bsize)
	_btn_ship.pressed.connect(_on_ship_pressed)
	grid.add_child(_btn_ship)

	_btn_ally = _make_button("Propor aliança", bsize)
	_btn_ally.pressed.connect(_on_ally_pressed)
	grid.add_child(_btn_ally)

	_btn_annex = _make_button("Anexar (debug)", bsize)
	_btn_annex.pressed.connect(_on_annex_pressed)
	grid.add_child(_btn_annex)


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
	col.custom_minimum_size = Vector2(300, 0)
	panel.add_child(col)

	# Exército selecionado (some quando não há seleção)
	_army_box = VBoxContainer.new()
	_army_box.add_theme_constant_override("separation", 6)
	_army_box.visible = false
	col.add_child(_army_box)

	_army_label = Label.new()
	_army_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_army_label.custom_minimum_size = Vector2(300, 0)
	_army_box.add_child(_army_label)

	var army_row := HBoxContainer.new()
	army_row.add_theme_constant_override("separation", 6)
	_army_box.add_child(army_row)

	_btn_army_stop = _make_button("Parar", Vector2(90, 44))
	_btn_army_stop.pressed.connect(_on_army_stop_pressed)
	army_row.add_child(_btn_army_stop)

	_btn_army_disband = _make_button("Dissolver", Vector2(110, 44))
	_btn_army_disband.pressed.connect(_on_army_disband_pressed)
	army_row.add_child(_btn_army_disband)

	var close := _make_button("Fechar", Vector2(90, 44))
	close.pressed.connect(_on_army_close_pressed)
	army_row.add_child(close)

	# Modo do mapa e impostos
	_mode_button = _make_button("Mapa: Político", Vector2(300, 48))
	_mode_button.pressed.connect(_on_mode_pressed)
	col.add_child(_mode_button)

	var tax_row := HBoxContainer.new()
	tax_row.add_theme_constant_override("separation", 8)
	col.add_child(tax_row)

	var tax_title := Label.new()
	tax_title.text = "Impostos"
	tax_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tax_row.add_child(tax_title)

	var minus := _make_button("-", Vector2(52, 48))
	minus.pressed.connect(_on_tax_pressed.bind(-5))
	tax_row.add_child(minus)

	_tax_label = Label.new()
	_tax_label.custom_minimum_size = Vector2(60, 0)
	_tax_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tax_row.add_child(_tax_label)

	var plus := _make_button("+", Vector2(52, 48))
	plus.pressed.connect(_on_tax_pressed.bind(5))
	tax_row.add_child(plus)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	col.add_child(save_row)
	var b_save := _make_button("Salvar", Vector2(140, 44))
	b_save.pressed.connect(_on_save_pressed)
	save_row.add_child(b_save)
	var b_load := _make_button("Carregar", Vector2(140, 44))
	b_load.pressed.connect(_on_load_pressed)
	save_row.add_child(b_load)
	_toast = Label.new()
	_toast.custom_minimum_size = Vector2(300, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	col.add_child(_toast)


func _build_event_popup() -> void:
	_event_panel = PanelContainer.new()
	_event_panel.anchor_left = 0.5
	_event_panel.anchor_right = 0.5
	_event_panel.anchor_top = 0.5
	_event_panel.anchor_bottom = 0.5
	_event_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_event_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_event_panel.custom_minimum_size = Vector2(560, 0)
	_event_panel.visible = false
	_root.add_child(_event_panel)
	_blockers.append(_event_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_event_panel.add_child(col)

	_event_title = Label.new()
	_event_title.add_theme_font_size_override("font_size", 30)
	_event_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	col.add_child(_event_title)

	_event_text = Label.new()
	_event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_text.custom_minimum_size = Vector2(540, 0)
	col.add_child(_event_text)

	_event_options = VBoxContainer.new()
	_event_options.add_theme_constant_override("separation", 8)
	col.add_child(_event_options)

	_event_timer = Label.new()
	_event_timer.add_theme_font_size_override("font_size", 16)
	_event_timer.modulate = Color(1, 1, 1, 0.65)
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
	for child in _event_options.get_children():
		child.queue_free()
	var options: Array = d["options"]
	for i in options.size():
		var opt: Dictionary = options[i]
		var b := _make_button("%s  %s" % [str(opt["label"]), _effects_text(opt.get("effects", {}))], Vector2(520, 50))
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
	var e := Game.estimate_monthly(c)
	var net: int = int(e["income"]) - int(e["expense"])
	_treasury_label.text = "Tesouro: %d  (%+d/mês)\nTropas: %d reg.  |  Mão de obra: %s%s" % [
		c.treasury, net, int(e["regiments"]), _fmt_pop(Game.manpower_of(c.id)),
		"" if Game.wars_of(c.id).is_empty() else "  |  GUERRAS: %d" % Game.wars_of(c.id).size(),
	]
	var lit: int = c.literacy
	_stats_label.text = "População: %s   |   Alfabetização: %d,%d%%   |   Padrão de vida: %.1f" % [
		_fmt_pop(Game.population_of(c)), lit / 10, lit % 10, float(Game.standard_of_living_x10(c, e)) / 10.0,
	]
	_date_label.text = Game.clock.format()
	_refresh_economy()
	_tax_label.text = "%d%%" % c.tax_pct
	var s := clampi(Game.speed, 0, _speed_buttons.size() - 1)
	_speed_buttons[s].set_pressed_no_signal(true)


func _refresh_info() -> void:
	if _selected < 0 or _selected >= Game.provinces.size():
		_info_panel.visible = false
		return
	var p := Game.provinces[_selected]
	var has_owner := p.owner_id >= 0 and p.owner_id < Game.countries.size()
	var mine := has_owner and p.owner_id == Game.player_country
	_info_panel.visible = true
	_info_title.text = p.name
	if p.city != "":
		_info_title.text += "\n%s%s" % ["★ " if p.capital_city else "", p.city]

	var owner_name := "Sem dono"
	var tint := Color(0.85, 0.85, 0.85)
	var tax := 0
	if has_owner:
		var oc := Game.countries[p.owner_id]
		owner_name = oc.name
		tint = oc.color.lightened(0.4)
		tax = oc.tax_pct
	_info_title.add_theme_color_override("font_color", tint)

	var lines: Array[String] = []
	lines.append("País: %s" % owner_name)
	lines.append("%s  ·  %s" % [TERRAIN_PT.get(p.terrain, p.terrain), RESOURCE_PT.get(p.resource_type, p.resource_type)])
	lines.append("População: %s" % _fmt_pop(p.population))
	lines.append("Preço do recurso: %d%%" % p.price_of(p.resource_type))
	lines.append("Produção: %d/mês   Imposto: %d/mês" % [p.production(), p.monthly_tax(tax) if has_owner else 0])
	lines.append("Mão de obra: %s / %s" % [_fmt_pop(p.manpower), _fmt_pop(p.manpower_max())])
	lines.append("Oficina nív. %d   Quartel nív. %d" % [p.workshop, p.barracks])
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
		lines.append("Indústria: %s nív. %d  (lucro %+d/mês)" % [FACTORY_PT[p.factory], p.factory_level, p.factory_profit()])
	var queued := Game.queued_in(p.id)
	if queued > 0:
		lines.append("Treinando: %d regimento(s)" % queued)
	_info_body.text = "\n".join(lines)

	_btn_recruit.visible = mine
	_btn_workshop.visible = mine
	_btn_barracks.visible = mine
	for fb in _btn_fact:
		fb.visible = mine
	if mine:
		var me := Game.player_country
		_btn_recruit.text = "Recrutar (%d)" % Game.RECRUIT_COST
		_btn_recruit.disabled = not Game.can_recruit(p.id, me)
		_set_build_button(_btn_workshop, "Oficina", p, "workshop", me)
		_set_build_button(_btn_barracks, "Quartel", p, "barracks", me)
		var fkeys: Array = Province.FACTORIES.keys()
		for i in fkeys.size():
			_set_build_button(_btn_fact[i], FACTORY_PT[fkeys[i]], p, fkeys[i], me)
	_btn_take.visible = has_owner and not mine and not Net.is_online()
	_btn_annex.visible = DEBUG_TOOLS and not mine
	_btn_war.visible = has_owner and not mine
	_btn_improve.visible = has_owner and not mine
	_btn_ally.visible = has_owner and not mine
	_btn_embargo.visible = has_owner and not mine
	_btn_ship.visible = mine and p.port >= 0
	if mine and p.port >= 0:
		_btn_ship.disabled = not Game.can_build_ship(p.id, Game.player_country)
	if has_owner and not mine:
		var has_emb := Game.embargoes.has(Game.player_country * 1000 + p.owner_id)
		_btn_embargo.text = "Suspender embargo" if has_emb else "Embargar"
		_btn_embargo.disabled = not has_emb and not Game.can_embargo(Game.player_country, p.owner_id)
	if has_owner and not mine:
		var me3 := Game.player_country
		_btn_improve.disabled = not Game.can_improve(me3, p.owner_id)
		var is_ally := Game.allied(me3, p.owner_id)
		_btn_ally.text = "Romper aliança" if is_ally else "Propor aliança"
		_btn_ally.disabled = not is_ally and not Game.can_ally(me3, p.owner_id)
	if has_owner and not mine:
		var me2 := Game.player_country
		if Game.at_war(me2, p.owner_id):
			var left := Game.WAR_MIN_DAYS - Game.war_days(me2, p.owner_id)
			_btn_war.text = "Propor paz" if left <= 0 else "Paz em %d dias" % left
			_btn_war.disabled = left > 0
		else:
			_btn_war.text = "Declarar guerra"
			_btn_war.disabled = not Game.can_declare_war(me2, p.owner_id)


func _set_build_button(btn: Button, label: String, p: Province, kind: String, me: int) -> void:
	if p.building_level(kind) >= Province.MAX_BUILDING:
		btn.text = "%s (máx.)" % label
		btn.disabled = true
	else:
		btn.text = "%s (%d)" % [label, Game.build_cost(p, kind)]
		btn.disabled = not Game.can_build(p.id, me, kind)


func _refresh_army() -> void:
	var a: Army = Game.armies.get(_selected_army)
	if a == null:
		_army_box.visible = false
		return
	_army_box.visible = true
	var mine := a.owner_id == Game.player_country
	var oc := Game.countries[a.owner_id]
	var txt := "Exército #%d - %s\n%d regimento(s)  (%d homens)\nEm: %s" % [
		a.id, oc.name, a.regiments, a.men(), Game.provinces[a.province_id].name,
	]
	if a.is_moving():
		txt += "\nDestino: %s (%d dias)" % [Game.provinces[a.path.back()].name, Game.eta_days(a)]
	elif mine:
		txt += "\nToque numa província para marchar."
	_army_label.text = txt
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
	if int(_date.get("month", 0)) == 1 and not Net.is_online():
		Game.save_game("user://autosave.json")   # autosave anual (só local)
	_refresh_market()
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


func _on_province_updated(_pid: int) -> void:
	_refresh_top()
	_refresh_info()


func _on_player_changed(_cid: int) -> void:
	_refresh_top()
	_refresh_info()
	_refresh_army()
	_refresh_event()


func _on_map_mode_changed(mode: int) -> void:
	_mode_button.text = "Mapa: %s" % MapView.MODE_NAMES[mode]


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


func _on_mode_pressed() -> void:
	if map_view != null:
		map_view.cycle_mode()


func _on_recruit_pressed() -> void:
	if _selected >= 0:
		Game.submit_command(Cmd.recruit(_selected))


func _on_build_pressed(kind: String) -> void:
	if _selected >= 0:
		Game.submit_command(Cmd.build(_selected, kind))


func _on_take_pressed() -> void:
	if _selected >= 0:
		Game.set_player_country(Game.provinces[_selected].owner_id)


func _on_war_pressed() -> void:
	if _selected < 0:
		return
	var target := Game.provinces[_selected].owner_id
	if Game.at_war(Game.player_country, target):
		Game.submit_command(Cmd.make_peace(target))
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
