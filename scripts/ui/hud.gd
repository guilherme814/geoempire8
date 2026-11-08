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
var _btn_recruit: Button
var _btn_workshop: Button
var _btn_barracks: Button
var _btn_take: Button
var _btn_annex: Button

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

	Events.game_event_changed.connect(_refresh_event)
	Events.day_changed.connect(_on_day_changed)
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

	_flag = ColorRect.new()
	_flag.custom_minimum_size = Vector2(40, 40)
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

	_btn_take = _make_button("Assumir país", bsize)
	_btn_take.pressed.connect(_on_take_pressed)
	grid.add_child(_btn_take)

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
	_flag.color = c.color
	_country_label.text = c.name
	var e := Game.estimate_monthly(c)
	var net: int = int(e["income"]) - int(e["expense"])
	_treasury_label.text = "Tesouro: %d  (%+d/mês)\nTropas: %d reg.  |  Mão de obra: %s" % [
		c.treasury, net, int(e["regiments"]), _fmt_pop(Game.manpower_of(c.id)),
	]
	_date_label.text = Game.clock.format()
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
	lines.append("Produção: %d/mês   Imposto: %d/mês" % [p.production(), p.monthly_tax(tax) if has_owner else 0])
	lines.append("Mão de obra: %s / %s" % [_fmt_pop(p.manpower), _fmt_pop(p.manpower_max())])
	lines.append("Oficina nív. %d   Quartel nív. %d" % [p.workshop, p.barracks])
	var queued := Game.queued_in(p.id)
	if queued > 0:
		lines.append("Treinando: %d regimento(s)" % queued)
	_info_body.text = "\n".join(lines)

	_btn_recruit.visible = mine
	_btn_workshop.visible = mine
	_btn_barracks.visible = mine
	if mine:
		var me := Game.player_country
		_btn_recruit.text = "Recrutar (%d)" % Game.RECRUIT_COST
		_btn_recruit.disabled = not Game.can_recruit(p.id, me)
		_set_build_button(_btn_workshop, "Oficina", p, "workshop", me)
		_set_build_button(_btn_barracks, "Quartel", p, "barracks", me)
	_btn_take.visible = has_owner and not mine and not Net.is_online()
	_btn_annex.visible = DEBUG_TOOLS and not mine


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
