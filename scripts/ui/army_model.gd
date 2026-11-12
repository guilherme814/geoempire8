class_name ArmyModel
extends Control
## Pequeno molde 3D de um exército: soldados em formação, marchando, com o estandarte da
## bandeira do país ondulando. Renderiza numa SubViewport própria (só gira quando visível).
## Protótipo: formas simples (cápsulas e esferas). Dá para trocar por modelos reais depois.

const VIEW_SIZE := Vector2i(300, 150)
const MAX_SOLDIERS := 24
const COLS := 6

const FLAG_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color;
void vertex() {
	float k = UV.x;
	VERTEX.y += sin(UV.x * 9.0 - TIME * 5.0) * 0.07 * k;
	VERTEX.x += cos(UV.x * 7.0 - TIME * 4.0) * 0.02 * k;
}
void fragment() {
	ALBEDO = texture(tex, UV).rgb;
}
"""

var _container: SubViewportContainer
var _view: SubViewport
var _world: Node3D
var _stage: Node3D
var _formation: Node3D
var _soldiers: Array = []          # Node3D por soldado
var _phases: Array = []
var _flag_view: SubViewport
var _flag_rect: FlagRect
var _flag_mat: ShaderMaterial
var _tag: String = ""
var _count: int = -1
var _moving: bool = false
var _color: Color = Color.GRAY
var _t: float = 0.0
var _ready_ok: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(VIEW_SIZE.x, VIEW_SIZE.y)
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	_view = SubViewport.new()
	_view.size = VIEW_SIZE
	_view.transparent_bg = true
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_DISABLED
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_view)

	# Textura da bandeira: um FlagRect 2D desenhado numa viewport pequena.
	_flag_view = SubViewport.new()
	_flag_view.size = Vector2i(96, 64)
	_flag_view.transparent_bg = false
	_flag_view.disable_3d = true
	_flag_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_flag_view)
	_flag_rect = FlagRect.new()
	_flag_rect.custom_minimum_size = Vector2(96, 64)
	_flag_rect.size = Vector2(96, 64)
	_flag_view.add_child(_flag_rect)


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return   # sem renderização (teste automático): não monta a cena 3D
	_build_world()
	_ready_ok = true


func _build_world() -> void:
	_world = Node3D.new()
	_view.add_child(_world)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.1
	_world.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(0.0, 2.3, 4.3)
	cam.rotation_degrees = Vector3(-20.4, 0.0, 0.0)
	_world.add_child(cam)

	_stage = Node3D.new()
	_world.add_child(_stage)

	# Chão
	var ground := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 2.6
	gm.bottom_radius = 2.6
	gm.height = 0.08
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.20, 0.30, 0.17)
	gm.material = gmat
	ground.mesh = gm
	ground.position = Vector3(0.0, -0.04, 0.0)
	_stage.add_child(ground)

	_formation = Node3D.new()
	_stage.add_child(_formation)

	# Estandarte: mastro + bandeira ondulante
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.03
	pm.bottom_radius = 0.035
	pm.height = 2.3
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.45, 0.32, 0.18)
	pm.material = pmat
	pole.mesh = pm
	pole.position = Vector3(-0.9, 1.15, -0.3)
	_stage.add_child(pole)

	var flag := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(1.05, 0.7)
	fm.subdivide_width = 12
	fm.subdivide_depth = 2
	_flag_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLAG_SHADER
	_flag_mat.shader = sh
	_flag_mat.set_shader_parameter("tex", _flag_view.get_texture())
	fm.material = _flag_mat
	flag.mesh = fm
	flag.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	flag.position = Vector3(-0.9 + 0.55, 1.85, -0.3)
	_stage.add_child(flag)
	var cap := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.06
	cm.height = 0.12
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.9, 0.78, 0.35)
	cm.material = cmat
	cap.mesh = cm
	cap.position = Vector3(-0.9, 2.33, -0.3)
	_stage.add_child(cap)

	set_process(false)


## Atualiza o modelo. Só reconstrói os soldados se o país ou o tamanho mudarem.
func show_army(tag: String, color: Color, regiments: int, moving: bool) -> void:
	if not _ready_ok:
		return
	_moving = moving
	var n := clampi(regiments * 2, 4, MAX_SOLDIERS)
	if tag != _tag or color != _color:
		_tag = tag
		_color = color
		_flag_rect.set_country(tag, color)
		_count = -1
	if n != _count:
		_count = n
		_rebuild_soldiers(n)
	set_process(is_visible_in_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree() and _count > 0)


func _rebuild_soldiers(n: int) -> void:
	for ch in _formation.get_children():
		_formation.remove_child(ch)
		ch.queue_free()
	_soldiers.clear()
	_phases.clear()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = _color.darkened(0.15)
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.88, 0.7, 0.55)
	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = Color(0.12, 0.12, 0.14)
	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.3, 0.22, 0.14)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.12
	body_mesh.height = 0.5
	body_mesh.material = body_mat
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.09
	head_mesh.height = 0.18
	head_mesh.material = skin_mat
	var hat_mesh := CylinderMesh.new()
	hat_mesh.top_radius = 0.07
	hat_mesh.bottom_radius = 0.09
	hat_mesh.height = 0.14
	hat_mesh.material = hat_mat
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.03, 0.55, 0.03)
	gun_mesh.material = gun_mat

	var rows := int(ceil(float(n) / float(COLS)))
	for i in n:
		var cx := i % COLS
		var cy := i / COLS
		var s := Node3D.new()
		s.position = Vector3((float(cx) - float(COLS - 1) * 0.5) * 0.46 + 0.35, 0.0, (float(cy) - float(rows - 1) * 0.5) * 0.5 + 0.1)
		var b := MeshInstance3D.new()
		b.mesh = body_mesh
		b.position = Vector3(0.0, 0.33, 0.0)
		s.add_child(b)
		var h := MeshInstance3D.new()
		h.mesh = head_mesh
		h.position = Vector3(0.0, 0.69, 0.0)
		s.add_child(h)
		var ht := MeshInstance3D.new()
		ht.mesh = hat_mesh
		ht.position = Vector3(0.0, 0.8, 0.0)
		s.add_child(ht)
		var g := MeshInstance3D.new()
		g.mesh = gun_mesh
		g.position = Vector3(0.14, 0.45, 0.0)
		g.rotation_degrees = Vector3(0.0, 0.0, -8.0)
		s.add_child(g)
		_formation.add_child(s)
		_soldiers.append(s)
		_phases.append(float((cx * 7 + cy * 3) % 10) * 0.35)


func _process(delta: float) -> void:
	if _stage == null:
		return
	_t += delta
	# Câmera "gira" levemente: balança a formação em vez de mover a câmera.
	_stage.rotation.y = sin(_t * 0.35) * 0.35
	var speed := 7.0 if _moving else 1.6
	var amp := 0.06 if _moving else 0.012
	for i in _soldiers.size():
		var s: Node3D = _soldiers[i]
		var ph: float = _phases[i]
		s.position.y = absf(sin(_t * speed + ph)) * amp
		s.rotation.z = sin(_t * speed * 0.5 + ph) * (0.06 if _moving else 0.015)
