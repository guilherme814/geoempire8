class_name PerfProbe
extends Node
## Teste de desempenho do mapa: mede o tempo médio de quadro com camadas ligadas/desligadas,
## para descobrir o que custa caro no aparelho. Resultado vai para o log (evento "perf").

const FRAMES := 90

var _running := false


func run(main_node: Node, on_done: Callable) -> void:
	if _running:
		return
	_running = true
	var mv: MapView = main_node.get("map_view")
	var ov: MapOverlay = main_node.get("overlay")
	if mv == null:
		_running = false
		on_done.call("Mapa não encontrado.")
		return
	var res := PackedStringArray()
	var variants := [
		["base", {}],
		["sem costa (halo)", {"halo": false}],
		["sem malha das províncias", {"mesh": false}],
		["sem oceano/vinheta", {"ocean": false}],
		["sem linhas/rótulos (_draw)", {"draw": false}],
		["sem sobreposição (exércitos)", {"overlay": false}],
		["mapa todo oculto (só interface)", {"halo": false, "mesh": false, "ocean": false, "draw": false, "overlay": false}],
	]
	for v in variants:
		_apply(mv, ov, v[1])
		await get_tree().process_frame
		await get_tree().process_frame
		var times: Array = []
		var last := Time.get_ticks_usec()
		for i in FRAMES:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append(float(now - last) / 1000.0)
			last = now
		times.sort()
		var sum := 0.0
		for t in times:
			sum += float(t)
		var line := "%s: média %.1f ms | p50 %.1f | p95 %.1f" % [v[0], sum / times.size(), times[times.size() / 2], times[int(times.size() * 0.95)]]
		res.append(line)
		Events.trace.emit("perf", line)
	_apply(mv, ov, {})
	var head := "vsync %d | max_fps %d | resolução %s" % [DisplayServer.window_get_vsync_mode(), Engine.max_fps, AppSettings.RENDER_NAMES[AppSettings.render_mode()]]
	Events.trace.emit("perf", head)
	_running = false
	on_done.call(head + "\n" + "\n".join(res))


func _apply(mv: MapView, ov: MapOverlay, d: Dictionary) -> void:
	mv.debug_layers(bool(d.get("halo", true)), bool(d.get("mesh", true)), bool(d.get("ocean", true)), bool(d.get("draw", true)))
	if ov != null:
		ov.visible = bool(d.get("overlay", true))
