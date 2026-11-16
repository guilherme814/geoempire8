class_name ModalCard
extends CanvasLayer
## Janela modal reutilizável (boas-vindas, tutorial em páginas, notas de versão): fundo
## escurecido, cartão central com entrada suave (Tween curto), rolagem por toque no corpo.

signal closed

var _root: Control
var _panel: PanelContainer
var _col: VBoxContainer
var _pages: Array = []
var _page_i: int = 0
var _on_finish: Callable = Callable()
var _closing: bool = false


func _ready() -> void:
	layer = 70
	_root = Control.new()
	_root.theme = UIKit.make_theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var vw: float = get_viewport().get_visible_rect().size.x
	_panel.custom_minimum_size = Vector2(minf(660.0, vw - 40.0), 0)
	_root.add_child(_panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	_panel.add_child(_col)
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Texto único: título, subtítulo opcional, corpo em BBCode e botões
## [{"text", "primary": bool, "cb": Callable, "keep": bool (não fecha)}].
func show_text(title: String, subtitle: String, bbcode: String, buttons: Array) -> void:
	UIKit.clear(_col)
	_col.add_child(UIKit.serif_label(title, 30, UIKit.GOLD_BRIGHT))
	if subtitle != "":
		_col.add_child(UIKit.label(subtitle, 16, UIKit.TEXT_DIM))
	_col.add_child(HSeparator.new())
	_col.add_child(_body(bbcode))
	_add_buttons(buttons)


## Tutorial em páginas [{"title", "body"}]; `on_finish` roda ao concluir ou pular.
func show_pages(pages: Array, on_finish: Callable) -> void:
	_pages = pages
	_page_i = 0
	_on_finish = on_finish
	_render_page()


func _render_page() -> void:
	UIKit.clear(_col)
	var pg: Dictionary = _pages[_page_i]
	_col.add_child(UIKit.label("Passo %d de %d" % [_page_i + 1, _pages.size()], 15, UIKit.TEXT_DIM))
	_col.add_child(UIKit.serif_label(str(pg["title"]), 30, UIKit.GOLD_BRIGHT))
	_col.add_child(HSeparator.new())
	_col.add_child(_body(str(pg["body"])))
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 6)
	for i in _pages.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(18 if i == _page_i else 8, 6)
		d.color = UIKit.GOLD_BRIGHT if i == _page_i else Color(UIKit.GOLD_DIM, 0.5)
		dots.add_child(d)
	_col.add_child(dots)
	var last: bool = _page_i == _pages.size() - 1
	var btns: Array = []
	btns.append({"text": "Pular", "cb": _finish_pages})
	if _page_i > 0:
		btns.append({"text": "‹ Voltar", "keep": true, "cb": func():
			_page_i -= 1
			_render_page()})
	btns.append({"text": "Concluir" if last else "Próximo ›", "primary": true, "keep": not last, "cb": func():
		if last:
			_finish_pages()
		else:
			_page_i += 1
			_render_page()})
	_add_buttons(btns)


func _finish_pages() -> void:
	if _on_finish.is_valid():
		_on_finish.call()


func _body(bbcode: String) -> Control:
	var sc := TouchScroll.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 190)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", UIKit.TEXT)
	rt.add_theme_font_size_override("normal_font_size", 19)
	rt.add_theme_font_size_override("bold_font_size", 19)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.text = bbcode
	sc.add_child(rt)
	return sc


func _add_buttons(buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_col.add_child(row)
	for b in buttons:
		var btn := UIKit.button(str(b["text"]), Vector2(0, 54), "PrimaryButton" if bool(b.get("primary", false)) else "")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb: Callable = b.get("cb", Callable())
		var keep: bool = bool(b.get("keep", false))
		btn.pressed.connect(func():
			if cb.is_valid():
				cb.call()
			if not keep:
				close())
		row.add_child(btn)


func close() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func():
		closed.emit()
		queue_free())
