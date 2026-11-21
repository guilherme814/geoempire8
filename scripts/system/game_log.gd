extends Node
## GameLog (autoload): gerador de logs da sessão.
## - Registra início, aparelho, comandos, avisos do jogo, travadas de quadro, desempenho da
##   simulação e verificações de sanidade do estado (valores impossíveis).
## - Anexa o log nativo do Godot (erros de script) ao relatório.
## - Ao sair (ou ao ir para segundo plano no Android) grava o relatório em user://logs e tenta
##   copiá-lo para a pasta Downloads do aparelho.
## Nada daqui entra no save nem no hash da simulação.

const LOG_DIR := "user://logs"
const GODOT_LOG := "user://logs/godot.log"
const SETTINGS_SECTION := "logs"
const SETTINGS_KEY := "export_downloads"
const AUTOSAVE_SECS := 60.0
const CRUMB_SECS := 3.0
const CRUMB_PATH := "user://logs/breadcrumb.txt"
const SANITY_SECS := 20.0
const HITCH_MS := 120.0
const GODOT_LOG_TAIL := 400

var buf := LogBuffer.new()
var session_stamp := ""
var last_export_status := "Ainda não exportado."
var last_export_path := ""
var _autosave_t := 0.0
var _crumb_t := 0.0
var _sanity_t := 0.0
var _hitch_cool := 0.0
var _last_export_ms := -100000
var _notices: Array = []
var _started := false
var _period_t := 0.0
var _dl_ok := true                       # o último envio para Downloads funcionou (ou nunca foi tentado)
var _prev_session_text := ""             # resumo da sessão anterior, se terminou de forma anormal
var _journal: FileAccess
var _speed_ms: Dictionary = {}           # velocidade -> ms reais de jogo
var _prev_stab: Dictionary = {}
var _prev_overlord: Dictionary = {}
var _month_moves := 0                    # trocas de dono no mês (contexto dos gargalos)
var _month_extinct := 0
const STEP_LIMITS := {"m_aipeace": 100.0, "m_trade": 150.0, "m_record": 200.0, "m_migr": 120.0, "m_events": 120.0, "m_politics": 120.0, "m_econ": 80.0, "m_prov": 40.0, "m_countries": 60.0, "m_emit": 60.0}
var _primed := false                     # a 1ª comparação mensal só guarda a foto inicial
var _prev_wars: Dictionary = {}
var _prev_alive: Dictionary = {}
var _prev_allies: Dictionary = {}
var _prev_tax: Dictionary = {}
var _prev_owner_of: Dictionary = {}
const LOCK_PATH := "user://logs/session.lock"
const PERIOD_EXPORT_SECS := 180.0


func _ready() -> void:
	AppSettings.apply_render_mode(get_tree().root)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var d := Time.get_datetime_dict_from_system()
	session_stamp = "%04d%02d%02d_%02d%02d%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	buf.add(LogBuffer.INFO, "sessao", "Início da sessão %s" % session_stamp)
	buf.add(LogBuffer.INFO, "aparelho", device_summary())
	_check_previous_session()
	_open_journal()
	buf.on_important = _on_important
	_write_lock("running")
	get_tree().node_added.connect(_on_node_added)
	if OS.get_name() == "Android" and downloads_enabled():
		OS.request_permissions()
	if Events != null:
		Events.notice.connect(_on_notice)
		Events.trace.connect(_on_trace)
		Events.command_applied.connect(_on_command)
		Events.month_changed.connect(_on_month)
		Events.state_loaded.connect(func(): buf.add(LogBuffer.INFO, "save", "Save carregado."))
		Events.world_loaded.connect(func(): buf.add(LogBuffer.INFO, "mundo", "Mundo carregado."))
	_started = true


func downloads_enabled() -> bool:
	return AppSettings.get_flag(SETTINGS_SECTION, SETTINGS_KEY, true)


func set_downloads_enabled(on: bool) -> void:
	AppSettings.set_flag(SETTINGS_SECTION, SETTINGS_KEY, on)


## Registro manual a partir de qualquer script do jogo.
func info(tag: String, msg: String) -> void:
	buf.add(LogBuffer.INFO, tag, msg)


func warn(tag: String, msg: String) -> void:
	buf.add(LogBuffer.WARN, tag, msg)


func error(tag: String, msg: String) -> void:
	buf.add(LogBuffer.ERROR, tag, msg)


func device_summary() -> String:
	var renderer := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	var scr := DisplayServer.screen_get_size()
	var gpu := "%s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()]
	var mem := OS.get_memory_info()
	return "%s | modelo %s | CPU %s | Godot %s | %s | GPU %s | tela %dx%d @%.0f Hz, %d dpi | CPUs %d | RAM %.0f MB (livre %.0f) | debug=%s | idioma %s" % [
		OS.get_name(), OS.get_model_name(), OS.get_processor_name(), Engine.get_version_info().get("string", "?"),
		renderer, gpu, scr.x, scr.y, DisplayServer.screen_get_refresh_rate(), DisplayServer.screen_get_dpi(),
		OS.get_processor_count(), float(mem.get("physical", 0)) / 1048576.0, float(mem.get("free", 0)) / 1048576.0,
		str(OS.is_debug_build()), OS.get_locale()]


func _process(dt: float) -> void:
	if not _started:
		return
	buf.frame(dt)
	buf.frame_ctx(_ctx(), dt)
	var spd := -1 if (Game == null or not Game.loaded) else Game.speed
	_speed_ms[spd] = int(_speed_ms.get(spd, 0)) + int(dt * 1000.0)
	_hitch_cool = maxf(0.0, _hitch_cool - dt)
	if dt * 1000.0 > HITCH_MS and _hitch_cool <= 0.0:
		_hitch_cool = 1.0
		buf.add(LogBuffer.WARN, "quadro", "Quadro lento: %.0f ms (%s)" % [dt * 1000.0, _game_stamp()])
	_sanity_t += dt
	if _sanity_t >= SANITY_SECS:
		_sanity_t = 0.0
		_sample_resources()
		check_sanity()
	_crumb_t += dt
	if _crumb_t >= CRUMB_SECS:
		_crumb_t = 0.0
		_write_crumb()
	_autosave_t += dt
	if _autosave_t >= AUTOSAVE_SECS:
		_autosave_t = 0.0
		write_local()
	_period_t += dt
	if _period_t >= PERIOD_EXPORT_SECS:
		_period_t = 0.0
		if _dl_ok and downloads_enabled():
			export_now("periódico")


## "Caixa-preta": a cada poucos segundos grava as últimas ações e o estado do motor. Se o app
## morrer sem avisar, a próxima sessão lê isto e sabe o que acontecia nos últimos segundos.
func _write_crumb() -> void:
	var f := FileAccess.open(CRUMB_PATH, FileAccess.WRITE)
	if f == null:
		return
	var tw := -1
	if get_tree() != null and get_tree().has_method("get_processed_tweens"):
		tw = get_tree().get_processed_tweens().size()
	var stage := -1
	var pend := false
	if Game != null and Game.loaded:
		stage = Game._month_stage
		pend = Game.month_pending()
	f.store_string("sessão %s | log %s | %s | mês pendente %s (etapa %d) | mem %.1f MB | nós %d | tweens %d\n%s" % [
		session_stamp, LogBuffer.fmt_time(Time.get_ticks_msec()), _game_stamp(), str(pend), stage,
		float(OS.get_static_memory_usage()) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), tw,
		buf.tail(30)])
	f.close()


func _game_stamp() -> String:
	if Game == null or not Game.loaded:
		return "sem jogo"
	return "%02d/%02d/%d vel %d" % [Game.clock.day, Game.clock.month, Game.clock.year, Game.speed]


func _sample_resources() -> void:
	var mem := float(OS.get_static_memory_usage()) / 1048576.0
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var fps := int(Performance.get_monitor(Performance.TIME_FPS))
	var peak := float(OS.get_static_memory_peak_usage()) / 1048576.0
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var vram := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
	var tweens := -1
	if get_tree() != null and get_tree().has_method("get_processed_tweens"):
		tweens = get_tree().get_processed_tweens().size()
	buf.add(LogBuffer.INFO, "recursos", "tweens %d | mem %.1f MB (pico %.1f) | nós %d (órfãos %d) | objetos %d | fps %d | draw calls %d | primitivas %d | vram %.1f MB | gfx %s | %s" % [
		tweens, mem, peak, nodes, orphans, objs, fps, draws, prims, vram, AppSettings.GFX_NAMES[AppSettings.gfx_quality()], _game_stamp()])


func _on_notice(text: String) -> void:
	buf.bump("avisos_jogo")
	buf.add(LogBuffer.INFO, "aviso", text)
	_notices.append(text)
	if _notices.size() > 60:
		_notices.remove_at(0)


func _on_command(cmd: Dictionary) -> void:
	var t := str(cmd.get("type", "?"))
	buf.bump("cmd_" + t)
	if t != "set_speed":
		buf.add(LogBuffer.INFO, "comando", "%s %s" % [t, _compact(cmd)])


func _compact(cmd: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cmd.keys():
		if str(k) != "type":
			parts.append("%s=%s" % [str(k), str(cmd[k])])
	return " ".join(parts)


func _on_month(_date: Dictionary) -> void:
	buf.bump("meses")
	_world_diff()
	_state_audit()
	_integrity_audit()
	# o tempo do mês só é gravado no PerfMonitor depois deste sinal: lê no fim do quadro
	_after_month.call_deferred()


func _after_month() -> void:
	_timeline_line()
	_month_profile()
	_month_moves = 0
	_month_extinct = 0


## Gargalos do turno mensal: cada etapa acima do seu orçamento é registrada com o contexto
## (guerras ativas, extinções e trocas de província no mês) para apontar a causa.
func _month_profile() -> void:
	if Game == null or not Game.loaded:
		return
	var ctx := "guerras %d, países %d, extinções no mês %d, províncias trocadas %d" % [Game.wars.size(), _prev_alive.size(), _month_extinct, _month_moves]
	for step in STEP_LIMITS.keys():
		var v := PerfMonitor.last(str(step))
		if v >= float(STEP_LIMITS[step]):
			buf.add(LogBuffer.WARN, "gargalo", "%s levou %.0f ms (limite %.0f) | %s | %s" % [step, v, float(STEP_LIMITS[step]), ctx, _game_stamp()])
	var m := PerfMonitor.last("month")
	if m >= 1500.0:
		buf.add(LogBuffer.WARN, "gargalo", "Turno mensal inteiro levou %.0f ms | piores: %s | %s" % [m, PerfMonitor.slowest("m_", 4), ctx])


## Auditoria de transições (ideia do PDF de telemetria): quedas bruscas de estabilidade,
## mudanças de suserania e morte do país do jogador, comparando com o mês anterior.
func _state_audit() -> void:
	if Game == null or not Game.loaded:
		return
	var stab_now: Dictionary = {}
	var ov_now: Dictionary = {}
	for c in Game.countries:
		if not c.is_alive():
			continue
		stab_now[c.tag] = c.stability
		ov_now[c.tag] = c.overlord
		if _prev_stab.has(c.tag) and int(_prev_stab[c.tag]) - c.stability >= 10:
			buf.add(LogBuffer.WARN, "auditoria", "Queda brusca de estabilidade em %s: %d -> %d (%s)" % [c.tag, int(_prev_stab[c.tag]), c.stability, _game_stamp()])
		if _prev_overlord.has(c.tag) and int(_prev_overlord[c.tag]) != c.overlord:
			var from_tag := "independente" if int(_prev_overlord[c.tag]) < 0 else Game.countries[int(_prev_overlord[c.tag])].tag
			var to_tag := "independente" if c.overlord < 0 else Game.countries[c.overlord].tag
			buf.add(LogBuffer.INFO, "auditoria", "Suserania de %s: %s -> %s (%s)" % [c.tag, from_tag, to_tag, _game_stamp()])
	_prev_stab = stab_now
	_prev_overlord = ov_now


## Integridade estrutural mensal (ideia do PDF): países vivos sem província, extintos com província,
## exércitos fantasmas e rotas de exército anormalmente longas.
func _integrity_audit() -> int:
	if Game == null or not Game.loaded:
		return 0
	var bad := 0
	var owned: Dictionary = {}
	for p in Game.provinces:
		owned[p.owner_id] = int(owned.get(p.owner_id, 0)) + 1
	for c in Game.countries:
		var n := int(owned.get(c.id, 0))
		if c.is_alive() and n == 0:
			bad += 1
			buf.add(LogBuffer.ERROR, "integridade", "%s está vivo com 0 províncias (%s)" % [c.tag, _game_stamp()])
		elif not c.is_alive() and n > 0:
			bad += 1
			buf.add(LogBuffer.ERROR, "integridade", "%s extinto ainda controla %d províncias (%s)" % [c.tag, n, _game_stamp()])
	for id in Game.armies.keys():
		var a: Army = Game.armies[id]
		if a.path.size() > 40:
			bad += 1
			buf.add(LogBuffer.WARN, "integridade", "Exército %d (dono %d) com rota de %d passos: possível laço (%s)" % [id, a.owner_id, a.path.size(), _game_stamp()])
	return bad


func _open_journal() -> void:
	_journal = FileAccess.open("%s/journal_%s.log" % [LOG_DIR, session_stamp], FileAccess.WRITE)
	_prune_journals()


## Diário à prova de falha: avisos e erros vão para o disco na hora (flush), para sobreviver a um crash.
func _on_important(lvl: int, tag: String, msg: String, t_ms: int) -> void:
	if _journal == null:
		return
	_journal.store_line("[%s] %s %s %s" % [LogBuffer.fmt_time(t_ms), LogBuffer.LEVELS[lvl], tag, msg])
	_journal.flush()


func _prune_journals() -> void:
	var mine: Array = []
	for fn in DirAccess.get_files_at(LOG_DIR):
		if fn.begins_with("journal_") and fn.ends_with(".log"):
			mine.append(fn)
	mine.sort()
	while mine.size() > 6:
		DirAccess.remove_absolute(LOG_DIR.path_join(str(mine[0])))
		mine.remove_at(0)


## Log nativo: no Android o arquivo do Godot pode não existir; então lê o logcat do próprio app.
func _logcat_tail() -> String:
	if OS.get_name() != "Android":
		return ""
	var out: Array = []
	var code := OS.execute("logcat", ["-d", "-t", "2500", "-v", "time", "godot:V", "AndroidRuntime:E", "*:S"], out, true)
	if code != 0 or out.is_empty():
		return "logcat indisponível (código %d)." % code
	var lines := str(out[0]).split("\n")
	# Cada erro vira um bloco: a linha do erro + as linhas seguintes de pilha ("at:", GDScript backtrace…).
	# Blocos iguais (ignorando a hora) são agrupados com contagem; guardamos a primeira e a última hora.
	var blocks: Dictionary = {}
	var order: Array = []
	var i := 0
	while i < lines.size():
		var ln: String = lines[i]
		if _is_err_line(ln):
			var blk := PackedStringArray([ln.substr(19) if ln.length() > 19 else ln])
			var j := i + 1
			while j < lines.size() and j < i + 9 and _is_stack_line(lines[j]):
				blk.append(lines[j].substr(19) if lines[j].length() > 19 else lines[j])
				j += 1
			var key := "\n".join(blk)
			var stamp := ln.substr(0, 18) if ln.length() > 18 else ""
			if blocks.has(key):
				blocks[key]["n"] = int(blocks[key]["n"]) + 1
				blocks[key]["last"] = stamp
				if (blocks[key]["stamps"] as Array).size() < 80:
					blocks[key]["stamps"].append(stamp.substr(6))
			else:
				blocks[key] = {"n": 1, "first": stamp, "last": stamp, "stamps": [stamp.substr(6)]}
				order.append(key)
			i = j
		else:
			i += 1
	if order.is_empty():
		return "logcat lido (%d linhas): nenhum erro/aviso do Godot." % lines.size()
	var res := "logcat: %d erro(s) distinto(s) com pilha:\n" % order.size()
	for k in order.slice(0, 40):
		var d: Dictionary = blocks[k]
		res += "[%s → %s] x%d\n%s\n  horas: %s\n" % [d["first"], d["last"], d["n"], k, " ".join(PackedStringArray(d["stamps"]))]
	return res


## Procura no logcat sinais de queda nativa (sinal fatal, falta de memória, ANR, morte do processo).
func _crash_forensics() -> String:
	if OS.get_name() != "Android":
		return "(só no Android)"
	var out: Array = []
	var code := OS.execute("logcat", ["-b", "crash,main,events", "-d", "-t", "8000", "-v", "time", "*:I"], out, true)
	if code != 0 or out.is_empty():
		out.clear()
		code = OS.execute("logcat", ["-d", "-t", "8000", "-v", "time", "*:W"], out, true)
		if code != 0 or out.is_empty():
			return "logcat indisponível (código %d)." % code
	var lines := str(out[0]).split("\n")
	var pats := ["Fatal signal", "SIGSEGV", "SIGABRT", "backtrace", "FATAL EXCEPTION", "am_crash", "am_kill", "am_proc_died", "am_anr", "Out of memory", "OutOfMemory", "lowmemorykiller", "has died", "Stack overflow", "stack overflow"]
	var hits := PackedStringArray()
	var last_end := -1
	for i in lines.size():
		var hit := false
		for p in pats:
			if lines[i].contains(p):
				hit = true
				break
		if hit and i > last_end:
			var a := maxi(0, i - 3)
			var b := mini(lines.size() - 1, i + 14)
			hits.append("--- linha %d ---" % i)
			for k in range(a, b + 1):
				hits.append(lines[k])
			last_end = b
			if hits.size() > 120:
				break
	if hits.is_empty():
		return "Nenhum sinal fatal/memória/ANR no logcat (%d linhas lidas)." % lines.size()
	return "\n".join(hits)


func _is_err_line(ln: String) -> bool:
	return ln.contains("ERROR") or ln.contains("SCRIPT") or ln.contains("WARNING") or ln.contains("Failed") or ln.contains("FATAL") or ln.contains("Exception")


func _is_stack_line(ln: String) -> bool:
	var t := ln.strip_edges()
	if _is_err_line(ln):
		return false
	return t.contains("at:") or t.contains("GDScript") or t.contains("<C++") or t.contains("<Stack") or t.contains("Source>") or t.contains("Error>") or t.begins_with("[")


func _ctx() -> String:
	if Game == null or not Game.loaded:
		return "menu_ou_carregando|gfx%d" % AppSettings.gfx_quality()
	return ("jogo_pausado" if Game.speed == 0 else "jogo_vel%d" % Game.speed) + "|gfx%d" % AppSettings.gfx_quality()


func _on_trace(tag: String, msg: String) -> void:
	var lvl := LogBuffer.WARN if msg.begins_with("FALHA") else LogBuffer.INFO
	buf.add(lvl, tag, msg)


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		(n as BaseButton).pressed.connect(_on_button.bind(n))


func _on_button(b: BaseButton) -> void:
	if not is_instance_valid(b):
		return
	var label := ""
	if b is Button:
		label = (b as Button).text
	if label == "":
		label = b.tooltip_text
	buf.bump("botoes")
	var parent_name := str(b.get_parent().name) if b.get_parent() != null else "?"
	buf.add(LogBuffer.INFO, "botao", "'%s' (%s em %s)" % [label.replace("\n", " ").strip_edges(), b.name, parent_name])


## Marca de sessão: "running" em primeiro plano, "background" ao pausar; apagada ao sair normalmente.
func _write_lock(state: String) -> void:
	var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("%s|%s" % [session_stamp, state])


func _check_previous_session() -> void:
	if not FileAccess.file_exists(LOCK_PATH):
		return
	var parts := FileAccess.get_file_as_string(LOCK_PATH).split("|")
	if parts.size() < 2:
		return
	var prev := parts[0]
	if parts[1] == "running":
		buf.add(LogBuffer.ERROR, "sessao", "A sessão anterior (%s) terminou SEM fechar normalmente, com o app em primeiro plano: possível travamento, falta de memória ou fechamento forçado." % prev)
		var path := "%s/session_%s.txt" % [LOG_DIR, prev]
		if FileAccess.file_exists(path):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			var from := maxi(0, lines.size() - 80)
			_prev_session_text = "Sessão %s (últimas 80 linhas):\n%s" % [prev, "\n".join(lines.slice(from))]
		else:
			_prev_session_text = "Sessão %s: sem arquivo salvo." % prev
		if FileAccess.file_exists(CRUMB_PATH):
			_prev_session_text += "\n\nCAIXA-PRETA (últimos segundos antes do fechamento):\n%s" % FileAccess.get_file_as_string(CRUMB_PATH)
		_prev_session_text += "\n\nFORENSE NATIVA (logcat):\n%s" % _crash_forensics()
		var jpath := "%s/journal_%s.log" % [LOG_DIR, prev]
		if FileAccess.file_exists(jpath):
			var jl := FileAccess.get_file_as_string(jpath).split("\n")
			_prev_session_text += "\n\nDIÁRIO (avisos/erros gravados na hora, últimas 60):\n%s" % "\n".join(jl.slice(maxi(0, jl.size() - 60)))
	else:
		buf.add(LogBuffer.INFO, "sessao", "A sessão anterior (%s) foi encerrada em segundo plano (comum no Android)." % prev)


func _timeline_line() -> void:
	if Game == null or not Game.loaded:
		return
	var me: Country = Game.countries[clampi(Game.player_country, 0, Game.countries.size() - 1)]
	var alive := 0
	for c in Game.countries:
		if c.is_alive():
			alive += 1
	var line := "%02d/%02d/%d | %s: tesouro %d (renda %+d) dívida %d estab %d imp %d%% exérc %d | mundo: %d países, %d guerras, %d alianças | mês %.0f ms [%s]" % [
		Game.clock.day, Game.clock.month, Game.clock.year, me.tag, me.treasury, me.last_income, me.debt,
		me.stability, me.tax_pct, Game.regiments_of(me.id), alive, Game.wars.size(), Game.alliances.size(),
		PerfMonitor.last("month"), PerfMonitor.slowest("m_", 3)]
	if Game.clock.month % 6 == 0:
		line += " | hash %d" % Game.state_hash()
	buf.add_timeline(line)


## Compara com o mês anterior e registra o que mudou no mundo (guerras, alianças, países, impostos da IA).
func _world_diff() -> void:
	if Game == null or not Game.loaded:
		return
	var wars_now: Dictionary = {}
	for w in Game.wars:
		wars_now["%d-%d" % [int(w["a"]), int(w["b"])]] = true
	for k in wars_now.keys():
		if _primed and not _prev_wars.has(k):
			buf.add(LogBuffer.INFO, "mundo", "Guerra iniciada: %s (%s)" % [_pair_names(k), _game_stamp()])
			buf.bump("guerras_iniciadas")
	for k in _prev_wars.keys():
		if not wars_now.has(k):
			buf.add(LogBuffer.INFO, "mundo", "Guerra encerrada: %s (%s)" % [_pair_names(k), _game_stamp()])
			buf.bump("guerras_encerradas")
	_prev_wars = wars_now
	var al_now: Dictionary = {}
	for p in Game.alliances:
		al_now[str(p)] = p
	if _primed:
		for k in al_now.keys():
			if not _prev_allies.has(k):
				buf.add(LogBuffer.INFO, "mundo", "Nova aliança %s (%s)" % [k, _game_stamp()])
		for k in _prev_allies.keys():
			if not al_now.has(k):
				buf.add(LogBuffer.INFO, "mundo", "Aliança desfeita %s (%s)" % [k, _game_stamp()])
	_prev_allies = al_now
	var alive_now: Dictionary = {}
	var tax_changes := 0
	var owner_changes := 0
	var tax_now: Dictionary = {}
	for c in Game.countries:
		if c.is_alive():
			alive_now[c.tag] = true
			tax_now[c.tag] = c.tax_pct
			if _prev_tax.has(c.tag) and int(_prev_tax[c.tag]) != c.tax_pct and c.id != Game.player_country:
				tax_changes += 1
	for t in _prev_alive.keys():
		if not alive_now.has(t):
			_month_extinct += 1
			var dead_lvl := LogBuffer.ERROR if (Game.player_country >= 0 and Game.countries[Game.player_country].tag == t) else LogBuffer.INFO
			var who := "PAÍS DO JOGADOR DEIXOU DE EXISTIR: " if dead_lvl == LogBuffer.ERROR else "País deixou de existir: "
			buf.add(dead_lvl, "mundo", "%s%s (%s)" % [who, t, _game_stamp()])
			buf.bump("paises_extintos")
	for t in alive_now.keys():
		if _primed and not _prev_alive.has(t):
			buf.add(LogBuffer.INFO, "mundo", "País surgiu: %s (%s)" % [t, _game_stamp()])
	var owner_now: Dictionary = {}
	for p in Game.provinces:
		owner_now[p.id] = p.owner_id
		if _prev_owner_of.has(p.id) and int(_prev_owner_of[p.id]) != p.owner_id:
			owner_changes += 1
	_month_moves = owner_changes
	if owner_changes > 0:
		buf.add(LogBuffer.INFO, "mundo", "%d província(s) trocaram de dono no mês (%s)" % [owner_changes, _game_stamp()])
		buf.bump("trocas_de_dono")
	if tax_changes > 0:
		buf.bump("ia_ajustou_imposto")
	_prev_alive = alive_now
	_prev_tax = tax_now
	_prev_owner_of = owner_now
	_primed = true


func _pair_names(key: String) -> String:
	var ids := key.split("-")
	if ids.size() < 2:
		return key
	var a := int(ids[0])
	var b := int(ids[1])
	if a < 0 or b < 0 or a >= Game.countries.size() or b >= Game.countries.size():
		return key
	return "%s x %s" % [Game.countries[a].tag, Game.countries[b].tag]


## Erros do log nativo do Godot (arquivo inteiro, até 60 distintos, com a linha seguinte de contexto).
func _godot_errors() -> String:
	if not FileAccess.file_exists(GODOT_LOG):
		var lc := _logcat_tail()
		var files := ", ".join(PackedStringArray(DirAccess.get_files_at(LOG_DIR)))
		return "Arquivo do log nativo não existe. Arquivos em user://logs: %s\n%s" % [files, lc]
	var all := FileAccess.get_file_as_string(GODOT_LOG).split("\n")
	var seen: Dictionary = {}
	var order: Array = []
	for i in all.size():
		var ln := all[i]
		if ln.contains("ERROR") or ln.contains("SCRIPT ERROR") or ln.contains("Parse Error") or ln.contains("Failed to"):
			var ctx := ln + ("\n    " + all[i + 1].strip_edges() if i + 1 < all.size() else "")
			if seen.has(ln):
				seen[ln] = int(seen[ln]) + 1
			else:
				seen[ln] = 1
				order.append([ln, ctx])
	if order.is_empty():
		return "Nenhum erro encontrado no log nativo."
	var out := ""
	for i in mini(60, order.size()):
		out += "%s%s\n" % [order[i][1], "" if int(seen[order[i][0]]) <= 1 else "   (x%d)" % int(seen[order[i][0]])]
	return "%d erro(s) distinto(s):\n%s" % [order.size(), out]


## Verificações leves de valores impossíveis; cada problema distinto é registrado uma vez.
func check_sanity() -> int:
	if Game == null or not Game.loaded:
		return 0
	var found := 0
	for c in Game.countries:
		if not c.is_alive():
			continue
		var bad := ""
		if absi(c.treasury) > 1000000000:
			bad = "tesouro absurdo (%d)" % c.treasury
		elif c.stability < 0 or c.stability > 100:
			bad = "estabilidade fora de 0..100 (%d)" % c.stability
		elif c.tax_pct < 0 or c.tax_pct > 100:
			bad = "imposto fora de 0..100 (%d)" % c.tax_pct
		elif c.debt < 0:
			bad = "dívida negativa (%d)" % c.debt
		elif c.drill < 0 or c.drill > 2:
			bad = "instrução inválida (%d)" % c.drill
		if bad != "":
			found += 1
			buf.add(LogBuffer.ERROR, "sanidade", "%s: %s (%s)" % [c.tag, bad, _game_stamp()])
	for p in Game.provinces:
		if p.population < 0:
			found += 1
			buf.add(LogBuffer.ERROR, "sanidade", "província %d (%s) com população negativa (%d)" % [p.id, p.name, p.population])
		elif p.owner_id >= Game.countries.size():
			found += 1
			buf.add(LogBuffer.ERROR, "sanidade", "província %d com dono inexistente (%d)" % [p.id, p.owner_id])
	for id in Game.armies.keys():
		var a: Army = Game.armies[id]
		if a.province_id < 0 or a.province_id >= Game.provinces.size() or a.regiments <= 0 or a.supply < 0 or a.supply > 100:
			found += 1
			buf.add(LogBuffer.ERROR, "sanidade", "exército %d inválido (prov %d, regs %d, sup %d)" % [id, a.province_id, a.regiments, a.supply])
	if Game.player_country < 0 or Game.player_country >= Game.countries.size():
		found += 1
		buf.add(LogBuffer.ERROR, "sanidade", "país do jogador inválido (%d)" % Game.player_country)
	return found


## Texto completo do relatório.
func build_report(reason: String) -> String:
	var header := {
		"Versão": str(ProjectSettings.get_setting("application/config/version", "?")),
		"Sessão": session_stamp,
		"Relógio (hora do aparelho = tempo do log + deslocamento)": "log 00:00:00.000 = %s − %d ms" % [Time.get_time_string_from_system(), Time.get_ticks_msec()],
		"Motivo da exportação": reason,
		"Tempo de sessão": LogBuffer.fmt_time(Time.get_ticks_msec()),
		"Aparelho": device_summary(),
	}
	var sections := {}
	sections["Estado do jogo"] = _game_state_text()
	sections["Tempo real por velocidade"] = _speed_report()
	sections["Tempo de quadro por contexto"] = buf.ctx_report()
	sections["Linha do tempo (uma linha por mês de jogo)"] = "\n".join(PackedStringArray(buf.timeline)) if not buf.timeline.is_empty() else "Nenhum mês simulado nesta sessão."
	if _prev_session_text != "":
		sections["SESSÃO ANTERIOR ENCERRADA DE FORMA ANORMAL"] = _prev_session_text
	sections["Erros do log nativo do Godot"] = _godot_errors()
	var perf := PerfMonitor.report()
	sections["Desempenho da simulação (ms)"] = perf if perf != "" else "Sem amostras."
	sections["Últimos avisos do jogo"] = "\n".join(PackedStringArray(_notices)) if not _notices.is_empty() else "Nenhum."
	sections["Log nativo do Godot (final)"] = _godot_log_tail()
	return buf.render(header, sections)


func _speed_report() -> String:
	var keys: Array = _speed_ms.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		var name_k := "menu/carregando" if int(k) < 0 else ("pausado" if int(k) == 0 else "vel %d" % int(k))
		parts.append("%s: %.1f s" % [name_k, float(_speed_ms[k]) / 1000.0])
	return " | ".join(parts) if not parts.is_empty() else "Sem dados."


func _game_state_text() -> String:
	if Game == null or not Game.loaded:
		return "Nenhum jogo carregado."
	var alive := 0
	for c in Game.countries:
		if c.is_alive():
			alive += 1
	var me: Country = Game.countries[clampi(Game.player_country, 0, Game.countries.size() - 1)]
	return "Data: %s\nPaís do jogador: %s (%s) | tesouro %d | dívida %d | estabilidade %d | impostos %d%%\nPaíses vivos: %d | Províncias: %d | Exércitos: %d | Guerras: %d\nHash do estado: %d" % [
		_game_stamp(), me.name, me.tag, me.treasury, me.debt, me.stability, me.tax_pct,
		alive, Game.provinces.size(), Game.armies.size(), Game.wars.size(), Game.state_hash()]


func _godot_log_tail() -> String:
	if not FileAccess.file_exists(GODOT_LOG):
		return "Arquivo %s não existe (log nativo desligado ou ainda vazio)." % GODOT_LOG
	var f := FileAccess.open(GODOT_LOG, FileAccess.READ)
	if f == null:
		return "Não foi possível abrir o log nativo."
	var all := f.get_as_text().split("\n")
	var start := maxi(0, all.size() - GODOT_LOG_TAIL)
	var out := PackedStringArray()
	var flagged := 0
	for i in range(start, all.size()):
		var ln := all[i]
		if ln.contains("ERROR") or ln.contains("SCRIPT") or ln.contains("WARNING"):
			flagged += 1
		out.append(ln)
	return "(%d linhas sinalizadas de %d)\n%s" % [flagged, out.size(), "\n".join(out)]


## Grava o relatório em user://logs (sempre). Retorna o texto gravado.
func write_local(reason: String = "autosave") -> String:
	var text := build_report(reason)
	var path := "%s/session_%s.txt" % [LOG_DIR, session_stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	_prune_old()
	return text


## Grava local e tenta copiar para Downloads. Devolve o texto do status.
func export_now(reason: String = "manual") -> String:
	_last_export_ms = Time.get_ticks_msec()
	var text := write_local(reason)
	if not downloads_enabled():
		last_export_status = "Cópia para Downloads desligada. Log salvo só dentro do app."
		return last_export_status
	var fname := "GeoEmpire_log_%s.txt" % session_stamp
	var tried := PackedStringArray()
	for dir in _download_dirs():
		var full: String = dir.path_join(fname)
		var f := FileAccess.open(full, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			last_export_path = full
			_dl_ok = true
			last_export_status = "Log salvo em: " + full
			buf.add(LogBuffer.INFO, "exportar", last_export_status)
			return last_export_status
		tried.append("%s (erro %d)" % [dir, FileAccess.get_open_error()])
	last_export_path = ""
	_dl_ok = false
	last_export_status = "Não consegui gravar em Downloads (%s). O log ficou em %s." % [", ".join(tried), ProjectSettings.globalize_path(LOG_DIR)]
	buf.add(LogBuffer.WARN, "exportar", last_export_status)
	return last_export_status


func _download_dirs() -> Array:
	var dirs: Array = []
	var sys := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if sys != "":
		dirs.append(sys)
	if OS.get_name() == "Android":
		for extra in ["/storage/emulated/0/Download", "/sdcard/Download"]:
			if not dirs.has(extra):
				dirs.append(extra)
	return dirs


## Mantém só as 10 sessões mais recentes dentro do app.
func _prune_old() -> void:
	var files := DirAccess.get_files_at(LOG_DIR)
	var mine: Array = []
	for fn in files:
		if fn.begins_with("session_") and fn.ends_with(".txt"):
			mine.append(fn)
	mine.sort()
	while mine.size() > 10:
		DirAccess.remove_absolute(LOG_DIR.path_join(str(mine[0])))
		mine.remove_at(0)


## get_tree().quit() não envia pedido de fechamento: cobre também a saída pelo menu.
func _exit_tree() -> void:
	if _started and Time.get_ticks_msec() - _last_export_ms > 3000:
		buf.add(LogBuffer.INFO, "sessao", "Encerramento do aplicativo")
		export_now("encerramento")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))


func _notification(what: int) -> void:
	if not _started:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		buf.add(LogBuffer.INFO, "sessao", "Saída do jogo")
		export_now("saída do jogo")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		buf.add(LogBuffer.INFO, "sessao", "App em segundo plano")
		_write_lock("background")
		# evita regravar em sequência (ex.: pausa seguida de fechamento)
		if Time.get_ticks_msec() - _last_export_ms > 3000:
			export_now("app em segundo plano")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		buf.add(LogBuffer.INFO, "sessao", "App voltou ao primeiro plano")
		_write_lock("running")
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		buf.add(LogBuffer.INFO, "sessao", "Botão voltar")
	elif what == 2012:   # NOTIFICATION_CRASH
		buf.add(LogBuffer.ERROR, "sessao", "Falha fatal detectada")
		export_now("falha fatal")
