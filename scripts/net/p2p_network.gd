extends Node
## PRÉ-ESTRUTURA DA CONEXÃO P2P (autoload "Net")
##
## Status: esqueleto funcional, ainda NÃO testado em rede real. Serve de base
## para o modo online; o jogo offline não depende dele (is_online() == false).
##
## ---------------------------------------------------------------------------
## MODELO: LOCKSTEP DETERMINÍSTICO
## ---------------------------------------------------------------------------
## Ninguém envia estado do mundo; todos enviam apenas COMANDOS (veja Cmd).
## Todos os pares rodam a mesma simulação (Game.step) com os mesmos comandos,
## na mesma ordem -> o mesmo mundo. Isso exige determinismo (veja game_state.gd).
##
##   1. A UI chama Game.submit_command(cmd)  ->  Net.send_command(cmd)
##   2. O comando chega ao SEQUENCIADOR (hoje: o host).
##   3. A cada frame de rede o sequenciador empacota os comandos recebidos e
##      envia "commit(frame, comandos)" para todos, e executa Game.step(comandos).
##   4. Cada cliente executa Game.step(comandos) ao receber o commit.
##   5. A cada HASH_EVERY_FRAMES os clientes reportam Game.state_hash(); se
##      divergir do host, o host manda um snapshot (_rpc_resync).
##
## O ritmo do jogo (dias/s) é ditado pelo host: Game.speed vira a frequência de
## commits; pausado, o host continua mandando frames ociosos (IDLE_FRAME_HZ)
## para que comandos (ex.: despausar) sejam processados.
##
## ---------------------------------------------------------------------------
## FASES
## ---------------------------------------------------------------------------
##  A (este arquivo): ENet direto por IP:porta, host sequencia. Funciona em LAN
##     ou com porta aberta/UPnP/VPN (ex.: Tailscale/ZeroTier).
##  B (TODO): WebRTC mesh + servidor de sinalização (WebSocket) para atravessar
##     NAT sem abrir porta. ATENÇÃO: WebRTC fora da web exige a extensão
##     "webrtc-native" no Android. Implementar em host_game_webrtc()/join_game_webrtc()
##     mantendo EXATAMENTE os mesmos RPCs e a mesma lógica de commit.
##  C (TODO): salas/lobby (lista, senha), escolha de país, reconexão com snapshot,
##     jogador desconectado vira IA, chat, ping/latência na UI.
##  D (TODO): host migration (o par de menor id assume o sequenciamento).
##
## SEGURANÇA: RPCs "any_peer" SEMPRE validam o remetente (get_remote_sender_id).
## Nunca confie em "issuer" vindo do cliente sem conferir com players[sender].

signal state_changed(new_state: int)
signal players_changed
signal join_failed(reason: String)
signal desync_detected(frame: int, peer_id: int)

enum State { OFFLINE, HOSTING, CONNECTING, CONNECTED }
enum Transport { ENET_DIRECT, WEBRTC_MESH }   # WEBRTC_MESH: fase B

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const IDLE_FRAME_HZ := 10.0
const HASH_EVERY_FRAMES := 30
const HASH_LOG_SIZE := 600

var state: int = State.OFFLINE
var transport_kind: int = Transport.ENET_DIRECT
var local_name: String = "Jogador"
## peer_id -> {"name": String, "country": int}
var players: Dictionary = {}

var _peer: ENetMultiplayerPeer
var _host_inbox: Array = []       # comandos aguardando o próximo commit (host)
var _commit_queue: Array = []     # commits recebidos aguardando execução (cliente)
var _frame_acc: float = 0.0
var _hash_log: Dictionary = {}    # frame -> hash do host (para comparar com clientes)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------
func is_online() -> bool:
	return state == State.HOSTING or state == State.CONNECTED


func is_host() -> bool:
	return state == State.HOSTING


func local_peer_id() -> int:
	return multiplayer.get_unique_id()


## Cria uma partida. `country` é o país do host.
func host_game(port: int = DEFAULT_PORT, country: int = 0) -> Error:
	if state != State.OFFLINE:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": local_name, "country": country}}
	Game.set_player_country(country)
	_reset_sync()
	Game.lockstep = true
	_set_state(State.HOSTING)
	players_changed.emit()
	return OK


## Entra numa partida. O país é atribuído pelo host.
func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	if state != State.OFFLINE:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_set_state(State.CONNECTING)
	return OK


func host_game_webrtc(_signaling_url: String, _country: int = 0) -> Error:
	push_warning("Net: WebRTC (fase B) ainda não implementado")
	return ERR_UNAVAILABLE


func join_game_webrtc(_signaling_url: String, _room: String) -> Error:
	push_warning("Net: WebRTC (fase B) ainda não implementado")
	return ERR_UNAVAILABLE


func leave() -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	players.clear()
	_reset_sync()
	Game.lockstep = false
	_set_state(State.OFFLINE)
	players_changed.emit()


## Chamado por Game.submit_command quando is_online().
func send_command(cmd: Dictionary) -> void:
	if state == State.HOSTING:
		_host_inbox.append(cmd)
	elif state == State.CONNECTED:
		_rpc_submit.rpc_id(1, cmd)


# ---------------------------------------------------------------------------
# Laço de sincronização
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not Game.loaded:
		return
	if state == State.HOSTING:
		_host_process(delta)
	elif state == State.CONNECTED:
		_client_process()


func _host_process(delta: float) -> void:
	var hz: float = IDLE_FRAME_HZ
	if Game.speed > 0:
		hz = Game.SPEED_TPS[Game.speed]
	var interval := 1.0 / hz
	_frame_acc += delta
	var guard := 0
	while _frame_acc >= interval and guard < 4:
		_frame_acc -= interval
		guard += 1
		_commit_frame()
	if guard >= 4:
		_frame_acc = 0.0


func _commit_frame() -> void:
	var cmds: Array = _host_inbox.duplicate()
	_host_inbox.clear()
	var frame_id := Game.frame
	_rpc_commit.rpc(frame_id, cmds)   # call_remote: só para os outros pares
	Game.step(cmds)
	_hash_log[Game.frame] = Game.state_hash()
	_hash_log.erase(Game.frame - HASH_LOG_SIZE)


func _client_process() -> void:
	while not _commit_queue.is_empty():
		var c: Dictionary = _commit_queue.pop_front()
		if int(c["frame"]) != Game.frame:
			push_warning("Net: frame fora de ordem (esperado %d, veio %d); pedindo resync" % [Game.frame, int(c["frame"])])
			_commit_queue.clear()
			_rpc_request_resync.rpc_id(1)
			return
		Game.step(c["cmds"])
		if Game.frame % HASH_EVERY_FRAMES == 0:
			_rpc_report_hash.rpc_id(1, Game.frame, Game.state_hash())


# ---------------------------------------------------------------------------
# RPCs  (as assinaturas precisam ser idênticas em todos os pares)
# ---------------------------------------------------------------------------
## Cliente -> host: apresentação logo após conectar.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(version: int, player_name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_kick(id, "Versão do protocolo incompatível")
		return
	if players.size() >= MAX_PLAYERS:
		_kick(id, "Sala cheia")
		return
	var country := _pick_free_country()
	if country < 0:
		_kick(id, "Sem países livres")
		return
	players[id] = {"name": player_name, "country": country}
	_rpc_welcome.rpc_id(id, players, Game.serialize_state(), country)
	_rpc_players.rpc(players)
	players_changed.emit()


## Host -> cliente: aceita a entrada e envia o snapshot inicial.
@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(player_list: Dictionary, snapshot: Dictionary, country: int) -> void:
	if not Game.load_state(snapshot):
		leave()
		join_failed.emit("Snapshot incompatível com este mapa")
		return
	players = player_list
	_reset_sync()
	Game.lockstep = true
	Game.set_player_country(country)
	_set_state(State.CONNECTED)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_players(player_list: Dictionary) -> void:
	players = player_list
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	leave()
	join_failed.emit(reason)


## Cliente -> host: comando de jogo.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit(cmd: Dictionary) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	# O emissor só pode agir pelo próprio país.
	if int(cmd.get("issuer", -1)) != int(players[sender]["country"]):
		return
	var t := str(cmd.get("type", ""))
	if t == Cmd.SET_SPEED and sender != 1:
		return   # só o host controla a velocidade (por enquanto)
	if t == Cmd.TRANSFER_PROVINCE:
		return   # comando de debug nunca vem de clientes
	_host_inbox.append(cmd)


## Host -> clientes: comandos de um frame.
@rpc("authority", "call_remote", "reliable")
func _rpc_commit(frame_id: int, cmds: Array) -> void:
	_commit_queue.append({"frame": frame_id, "cmds": cmds})


## Cliente -> host: hash do estado para detectar dessincronização.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_hash(frame_id: int, state_hash: int) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _hash_log.has(frame_id) and int(_hash_log[frame_id]) != state_hash:
		push_warning("Net: DESYNC do par %d no frame %d" % [sender, frame_id])
		desync_detected.emit(frame_id, sender)
		_rpc_resync.rpc_id(sender, Game.serialize_state())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_resync() -> void:
	if is_host():
		_rpc_resync.rpc_id(multiplayer.get_remote_sender_id(), Game.serialize_state())


## Host -> cliente: substitui o estado local pelo do host.
@rpc("authority", "call_remote", "reliable")
func _rpc_resync(snapshot: Dictionary) -> void:
	_commit_queue.clear()
	Game.load_state(snapshot)


# ---------------------------------------------------------------------------
# Conexão
# ---------------------------------------------------------------------------
func _on_peer_connected(_id: int) -> void:
	pass   # o host só registra o jogador quando chega o _rpc_hello


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	players.erase(id)
	_rpc_players.rpc(players)
	players_changed.emit()
	# TODO: transformar o país do jogador desconectado em IA.


func _on_connected_to_server() -> void:
	_rpc_hello.rpc_id(1, PROTOCOL_VERSION, local_name)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Não foi possível conectar ao host")


func _on_server_disconnected() -> void:
	leave()
	join_failed.emit("O host encerrou a partida")


func _kick(id: int, reason: String) -> void:
	_rpc_rejected.rpc_id(id, reason)
	await get_tree().create_timer(0.25).timeout   # deixa a mensagem chegar
	if _peer != null:
		_peer.disconnect_peer(id)


func _pick_free_country() -> int:
	var taken: Array[int] = []
	for pid in players:
		taken.append(int(players[pid]["country"]))
	for c in Game.countries:
		if c.is_alive() and not taken.has(c.id):
			return c.id
	return -1


func _reset_sync() -> void:
	_host_inbox.clear()
	_commit_queue.clear()
	_hash_log.clear()
	_frame_acc = 0.0


func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)
