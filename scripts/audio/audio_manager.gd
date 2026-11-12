class_name AudioManager
extends Node
## Som do jogo, 100% sintetizado em código (sem arquivos de áudio):
##  - efeitos: clique, moeda, construção, lei, sino, tambor de guerra, evento;
##  - música: tema orquestral em Ré menor (pad + baixo + arpejo + melodia), gerado numa thread
##    ao iniciar e tocado em loop.
## Não toca na simulação: só escuta Events.

const RATE_SFX := 22050
const RATE_MUSIC := 16000
const BPM := 70.0

static var instance: AudioManager
static var music_on: bool = true
static var sfx_on: bool = true

var _sfx: Dictionary = {}
var _players: Array = []
var _next_player: int = 0
var _music_player: AudioStreamPlayer
var _music_stream: AudioStreamWAV
var _thread: Thread
var _last_click_ms: int = 0


func _ready() -> void:
	instance = self
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)
	_build_sfx()
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -14.0
	add_child(_music_player)

	Events.command_applied.connect(_on_command)
	Events.notice.connect(func(_t: String) -> void: play("notice"))
	Events.game_event_changed.connect(_on_game_event)
	Events.war_changed.connect(func() -> void: play("war"))
	Events.province_selected.connect(func(_p: int) -> void: play("tick"))
	get_tree().node_added.connect(_on_node_added)

	if DisplayServer.get_name() != "headless":
		_thread = Thread.new()
		_thread.start(_render_music)
		set_process(true)
	else:
		set_process(false)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _process(_delta: float) -> void:
	if _music_stream == null and _thread != null and _thread.is_started() and not _thread.is_alive():
		_music_stream = _thread.wait_to_finish() as AudioStreamWAV
		_music_player.stream = _music_stream
	if _music_stream != null:
		if music_on and not _music_player.playing:
			_music_player.play()
		elif not music_on and _music_player.playing:
			_music_player.stop()


static func set_music(on: bool) -> void:
	music_on = on


static func set_sfx(on: bool) -> void:
	sfx_on = on
	if on and instance != null:
		instance.play("click")


# ---------------------------------------------------------------------------
# Efeitos
# ---------------------------------------------------------------------------
func play(sfx_name: String) -> void:
	if not sfx_on or not _sfx.has(sfx_name) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sfx[sfx_name]
	p.play()


func _on_node_added(n: Node) -> void:
	if n is Button:
		(n as Button).pressed.connect(_on_button)


func _on_button() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_click_ms < 40:
		return
	_last_click_ms = now
	play("click")


func _on_game_event() -> void:
	play("event")


func _on_command(cmd: Dictionary) -> void:
	if int(cmd.get("issuer", -1)) != Game.player_country:
		return
	var map := {Cmd.BUILD: "build", Cmd.ENACT_LAW: "law", Cmd.RECRUIT: "drum", Cmd.BUILD_SHIP: "build",
		Cmd.DECLARE_WAR: "war", Cmd.MAKE_PEACE: "bell", Cmd.MOVE_ARMY: "tick", Cmd.MOVE_FLEET: "tick",
		Cmd.SET_TAX: "coin"}
	var k: String = str(cmd.get("type", ""))
	if map.has(k):
		play(str(map[k]))


func _build_sfx() -> void:
	_sfx["click"] = _make_sfx(_tone(900.0, 0.05, 0.35, 0.0, 60.0))
	_sfx["tick"] = _make_sfx(_tone(520.0, 0.04, 0.22, 0.0, 70.0))
	_sfx["coin"] = _make_sfx(_cat([_tone(1319.0, 0.07, 0.3, 0.1, 25.0), _tone(1760.0, 0.18, 0.3, 0.1, 14.0)]))
	_sfx["build"] = _make_sfx(_cat([_thud(0.12, 140.0), _thud(0.12, 120.0), _thud(0.2, 100.0)]))
	_sfx["drum"] = _make_sfx(_cat([_thud(0.1, 90.0), _thud(0.1, 90.0), _thud(0.2, 70.0)]))
	_sfx["law"] = _make_sfx(_mix([_tone(262.0, 0.7, 0.3, 0.15, 5.0), _tone(330.0, 0.7, 0.25, 0.15, 5.0),
		_tone(392.0, 0.7, 0.25, 0.15, 5.0), _thud(0.25, 80.0)]))
	_sfx["bell"] = _make_sfx(_mix([_tone(880.0, 1.1, 0.3, 0.4, 3.5), _tone(1318.0, 0.9, 0.18, 0.2, 4.5)]))
	_sfx["notice"] = _make_sfx(_cat([_tone(660.0, 0.1, 0.3, 0.1, 18.0), _tone(880.0, 0.22, 0.3, 0.1, 10.0)]))
	_sfx["event"] = _make_sfx(_cat([_tone(523.0, 0.12, 0.28, 0.2, 12.0), _tone(659.0, 0.12, 0.28, 0.2, 12.0),
		_tone(784.0, 0.35, 0.3, 0.2, 7.0)]))
	_sfx["war"] = _make_sfx(_cat([_mix([_tone(110.0, 0.5, 0.35, 0.5, 3.0), _tone(165.0, 0.5, 0.25, 0.5, 3.0)]),
		_thud(0.15, 70.0), _thud(0.3, 60.0)]))


## Tom com decaimento exponencial; `harm` mistura o 2º harmônico.
func _tone(freq: float, dur: float, vol: float, harm: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE_SFX)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE_SFX
		var env := exp(-decay * t) * minf(1.0, t * 400.0)
		var s := sin(TAU * freq * t) + harm * sin(TAU * freq * 2.0 * t)
		out[i] = s * env * vol / (1.0 + harm)
	return out


## Pancada grave (tambor/martelo): seno que cai de frequência + ruído curto.
func _thud(dur: float, freq: float) -> PackedFloat32Array:
	var n := int(dur * RATE_SFX)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed_v := 12345
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE_SFX
		var f := freq * (1.0 + 1.5 * exp(-30.0 * t))
		phase += TAU * f / RATE_SFX
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v % 2000) / 1000.0 - 1.0
		out[i] = (sin(phase) * 0.8 + noise * 0.25 * exp(-60.0 * t)) * exp(-14.0 * t) * 0.9
	return out


func _cat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p as PackedFloat32Array)
	return out


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, (p as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var a := p as PackedFloat32Array
		for i in a.size():
			out[i] += a[i]
	return out


func _make_sfx(samples: PackedFloat32Array) -> AudioStreamWAV:
	return _to_wav(samples, RATE_SFX, false)


static func _to_wav(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


# ---------------------------------------------------------------------------
# Música (roda em thread; usa só funções estáticas e dados locais)
# ---------------------------------------------------------------------------
static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)


## Soma uma nota ao buffer (com wrap-around para o loop não ter emenda).
static func _note(buf: PackedFloat32Array, start_s: float, dur_s: float, midi: int, vol: float,
		attack: float, decay: float, harm: float) -> void:
	var total := buf.size()
	var n := int(dur_s * RATE_MUSIC)
	var s0 := int(start_s * RATE_MUSIC)
	var f := _hz(midi)
	for i in n:
		var t := float(i) / RATE_MUSIC
		var env := minf(1.0, t / maxf(attack, 0.002))
		env *= exp(-decay * t)
		var tail := dur_s - t
		if tail < 0.25:
			env *= tail / 0.25
		var ph := TAU * f * t
		var v := (sin(ph) + harm * sin(2.0 * ph) + harm * 0.4 * sin(3.0 * ph)) * env * vol
		var idx := (s0 + i) % total
		buf[idx] += v


func _render_music() -> AudioStreamWAV:
	var beat := 60.0 / BPM
	var bar := beat * 4.0
	var bars := 8
	var total := int(bar * float(bars) * RATE_MUSIC)
	var buf := PackedFloat32Array()
	buf.resize(total)
	# Dm | Bb | F | C | Dm | Gm | A | Dm
	var chords: Array = [[62, 65, 69], [58, 62, 65], [60, 65, 69], [60, 64, 67],
		[62, 65, 69], [58, 62, 67], [57, 61, 64], [62, 65, 69]]
	var roots: Array = [38, 34, 41, 36, 38, 43, 33, 38]
	for b in bars:
		var t0 := float(b) * bar
		var ch: Array = chords[b]
		for m in ch:
			_note(buf, t0, bar + 0.6, int(m), 0.10, 0.9, 0.0, 0.35)
		_note(buf, t0, bar, int(roots[b]), 0.22, 0.12, 0.25, 0.25)
		# Arpejo em colcheias
		var pat: Array = [0, 1, 2, 1, 2, 1, 2, 1]
		for k in 8:
			_note(buf, t0 + float(k) * beat * 0.5, 0.9, int(ch[int(pat[k])]) + 12, 0.07, 0.008, 4.5, 0.2)
	# Melodia esparsa: [compasso, tempo, nota, duração em tempos]
	var mel: Array = [
		[0, 0, 74, 2], [0, 2, 72, 1], [0, 3, 69, 1],
		[1, 0, 70, 2], [1, 2, 72, 2],
		[2, 0, 69, 3], [2, 3, 72, 1],
		[3, 0, 67, 2], [3, 2, 69, 2],
		[4, 0, 74, 2], [4, 2, 77, 1], [4, 3, 76, 1],
		[5, 0, 74, 2], [5, 2, 70, 2],
		[6, 0, 73, 2], [6, 2, 76, 1], [6, 3, 73, 1],
		[7, 0, 74, 4]]
	for m in mel:
		var st := float(int(m[0])) * bar + float(int(m[1])) * beat
		_note(buf, st, float(int(m[3])) * beat + 0.2, int(m[2]) + 12, 0.11, 0.06, 0.9, 0.18)
	# Normaliza
	var peak := 0.001
	for i in total:
		peak = maxf(peak, absf(buf[i]))
	var g := 0.8 / peak
	for i in total:
		buf[i] *= g
	return _to_wav(buf, RATE_MUSIC, true)
