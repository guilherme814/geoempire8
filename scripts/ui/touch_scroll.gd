class_name TouchScroll
extends ScrollContainer
## ScrollContainer com rolagem por toque estilo celular: arrastar em QUALQUER lugar do conteúdo
## (inclusive sobre botões e cartões) rola, com inércia; um toque rápido ainda aciona o botão.
## O ScrollContainer padrão perde o arrasto quando ele começa sobre um botão.

const DRAG_START_PX := 12.0
const FRICTION := 0.92
const MIN_SPEED := 0.6

var _pressing := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _speed := 0.0
var _carry := 0.0


func _ready() -> void:
	set_process(false)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = false


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_speed = 0.0
			set_process(false)
			if get_global_rect().has_point(mb.position):
				_pressing = true
				_dragging = false
				_press_pos = mb.position
				_last_pos = mb.position
		else:
			if _dragging:
				get_viewport().set_input_as_handled()
				if absf(_speed) > MIN_SPEED * 3.0:
					set_process(true)
			_pressing = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressing:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_pressing = false
			_dragging = false
			return
		if not _dragging and absf(mm.position.y - _press_pos.y) > DRAG_START_PX:
			_dragging = true
			_cancel_pressed_buttons(self)
		if _dragging:
			var dy: float = mm.position.y - _last_pos.y
			_last_pos = mm.position
			_speed = lerpf(_speed, dy, 0.5)
			scroll_vertical -= int(dy)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_carry += _speed
	var step := int(_carry)
	_carry -= step
	scroll_vertical -= step
	_speed *= FRICTION
	if absf(_speed) < MIN_SPEED:
		_speed = 0.0
		set_process(false)


## Ao começar a arrastar, cancela o "pressionado" do botão sob o dedo (para não disparar ao soltar).
func _cancel_pressed_buttons(n: Node) -> void:
	for ch in n.get_children():
		if ch is BaseButton:
			var b := ch as BaseButton
			var mode := b.get_draw_mode()
			if mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED:
				var was_disabled := b.disabled
				b.disabled = true
				b.set_deferred("disabled", was_disabled)
		_cancel_pressed_buttons(ch)
