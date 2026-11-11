class_name UIKit
extends RefCounted
## Tema e peças de interface compartilhadas (cores, estilos, botões, janelas).
## Visual: painéis escuros com moldura dourada, cabeçalhos vinho e botões verde-azulados,
## inspirado em Victoria 3 e Age of History 3, mas com identidade própria.

const BG := Color(0.055, 0.078, 0.102, 0.96)
const BG_LIGHT := Color(0.085, 0.12, 0.155, 0.97)
const BG_BAR := Color(0.04, 0.058, 0.078, 0.98)
const GOLD := Color(0.79, 0.66, 0.36)
const GOLD_BRIGHT := Color(0.96, 0.85, 0.55)
const GOLD_DIM := Color(0.43, 0.37, 0.22)
const TEAL := Color(0.10, 0.25, 0.26)
const TEAL_HOVER := Color(0.15, 0.36, 0.36)
const TEAL_DOWN := Color(0.06, 0.15, 0.16)
const MAROON := Color(0.33, 0.09, 0.13)
const MAROON_LIGHT := Color(0.50, 0.15, 0.20)
const TEXT := Color(0.91, 0.89, 0.82)
const TEXT_DIM := Color(0.62, 0.66, 0.68)
const POS := Color(0.50, 0.82, 0.54)
const NEG := Color(0.92, 0.50, 0.44)
const WARN := Color(0.95, 0.78, 0.35)

static var _serif: Font


static func serif() -> Font:
	if _serif == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Noto Serif", "Georgia", "Times New Roman", "serif"])
		f.font_weight = 700
		_serif = f
	return _serif


static func box(bg: Color, border: Color, radius: int = 6, border_w: int = 1, margin: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 19
	t.set_color("font_color", "Label", TEXT)

	# Painéis
	var p := box(BG, GOLD_DIM, 6, 2, 10)
	p.shadow_color = Color(0, 0, 0, 0.5)
	p.shadow_size = 8
	t.set_stylebox("panel", "PanelContainer", p)

	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", box(BG_LIGHT, Color(0.24, 0.30, 0.33), 5, 1, 10))

	t.set_type_variation("BannerPanel", "PanelContainer")
	var ban := box(MAROON, GOLD_DIM, 4, 0, 10)
	ban.border_width_bottom = 2
	ban.border_color = GOLD
	t.set_stylebox("panel", "BannerPanel", ban)

	t.set_type_variation("BarPanel", "PanelContainer")
	var topbar := box(BG_BAR, GOLD_DIM, 0, 0, 8)
	topbar.border_width_bottom = 3
	topbar.shadow_color = Color(0, 0, 0, 0.55)
	topbar.shadow_size = 6
	t.set_stylebox("panel", "BarPanel", topbar)

	t.set_type_variation("FlagFrame", "PanelContainer")
	t.set_stylebox("panel", "FlagFrame", box(Color(0, 0, 0, 0.5), GOLD, 3, 2, 3))

	# Botões
	_button_styles(t, "Button", TEAL, TEAL_HOVER, TEAL_DOWN, GOLD_DIM, 5, 1, 8)

	t.set_type_variation("DockButton", "Button")
	_button_styles(t, "DockButton", TEAL, TEAL_HOVER, TEAL_DOWN, GOLD, 10, 2, 6)

	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", MAROON_LIGHT, Color(0.62, 0.2, 0.26), Color(0.36, 0.1, 0.15), GOLD, 6, 2, 10)

	t.set_type_variation("SpeedButton", "Button")
	_button_styles(t, "SpeedButton", Color(0.08, 0.16, 0.18), TEAL_HOVER, MAROON_LIGHT, GOLD_DIM, 4, 1, 2)

	t.set_type_variation("FlatButton", "Button")
	_button_styles(t, "FlatButton", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.08), Color(0.79, 0.66, 0.36, 0.22), Color(0, 0, 0, 0), 4, 0, 6)
	var flat_down := box(Color(0.79, 0.66, 0.36, 0.22), GOLD, 4, 1, 6)
	t.set_stylebox("pressed", "FlatButton", flat_down)
	t.set_stylebox("hover_pressed", "FlatButton", flat_down)

	# Barras de progresso
	t.set_stylebox("background", "ProgressBar", box(Color(0.03, 0.04, 0.05, 0.95), Color(0.28, 0.31, 0.33), 3, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOLD, GOLD, 3, 0, 0))

	# Campo de texto
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.05, 0.07), GOLD_DIM, 4, 1, 8))
	t.set_stylebox("focus", "LineEdit", box(Color(0.04, 0.07, 0.09), GOLD, 4, 2, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", GOLD_BRIGHT)

	# Separador e dicas
	var sl := StyleBoxLine.new()
	sl.color = GOLD_DIM
	sl.thickness = 1
	t.set_stylebox("separator", "HSeparator", sl)
	t.set_constant("separation", "HSeparator", 8)
	t.set_stylebox("panel", "TooltipPanel", box(BG, GOLD, 4, 1, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


static func _button_styles(t: Theme, type: String, normal: Color, hover: Color, down: Color,
		border: Color, radius: int, border_w: int, margin: int) -> void:
	t.set_stylebox("normal", type, box(normal, border, radius, border_w, margin))
	t.set_stylebox("hover", type, box(hover, GOLD, radius, maxi(border_w, 1), margin))
	t.set_stylebox("pressed", type, box(down, GOLD_BRIGHT, radius, maxi(border_w, 1), margin))
	t.set_stylebox("hover_pressed", type, box(down.lightened(0.1), GOLD_BRIGHT, radius, maxi(border_w, 1), margin))
	t.set_stylebox("disabled", type, box(Color(0.09, 0.11, 0.13, 0.9), Color(0.22, 0.24, 0.26), radius, 1, margin))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, GOLD_BRIGHT)
	t.set_color("font_pressed_color", type, GOLD_BRIGHT)
	t.set_color("font_hover_pressed_color", type, GOLD_BRIGHT)
	t.set_color("font_disabled_color", type, Color(0.45, 0.48, 0.5))


# ---------------------------------------------------------------------------
# Peças prontas
# ---------------------------------------------------------------------------
static func label(text: String, size: int = 19, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func serif_label(text: String, size: int = 24, color: Color = GOLD_BRIGHT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", serif())
	return l


static func button(text: String, min_size: Vector2 = Vector2(64, 46), variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	if variation != "":
		b.theme_type_variation = variation
	return b


## Botão com ícone vetorial (e texto opcional ao lado).
static func icon_button(icon_kind: String, text: String, min_size: Vector2, variation: String = "") -> Button:
	var b := button("", min_size, variation)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var px := minf(min_size.y - 18.0, 34.0)
	row.add_child(UiIcon.make(icon_kind, px))
	if text != "":
		var l := label(text, 18)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	return b


## Linha "chave ........ valor" para listas de números.
static func kv_row(key: String, value: String, color: Color = TEXT, size: int = 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	var k := label(key, size, TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(k)
	var v := label(value, size, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


static func bar(value: float, max_value: float, color: Color, height: float = 14.0, width: float = 0.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = max_value
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, height)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if width <= 0.0:
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.add_theme_stylebox_override("fill", box(color, color.lightened(0.25), 3, 1, 0))
	return pb
