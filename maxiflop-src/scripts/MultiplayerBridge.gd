extends Node

signal connected_to_server
signal disconnected_from_server
signal lobby_updated(players: Array, team_scores: Dictionary)
signal player_input_received(payload: Dictionary)
signal player_left(player_id: String)
signal public_url_received(url: String)
signal vote_result_received(song_name: String)
signal vote_update_received(stats: Array)
signal server_debug_received(message: String)

# L'URL qui imite la toute première connexion d'un client HTTP Socket.IO via WebSocket
@export var server_url: String = "ws://127.0.0.1:3000/socket.io/?EIO=4&transport=websocket"

var _socket := WebSocketPeer.new()
var _is_connected := false
var last_public_url: String = ""

# --- Reconnexion automatique ---
var _want_connection := false       # true quand on veut être connecté
var _retry_timer: float = 0.0       # compteur pour les retentatives
const RETRY_INTERVAL: float = 2.0   # réessayer toutes les 2 secondes
const INITIAL_DELAY: float = 3.0    # délai initial avant la première tentative
var _initial_delay_done := false
var _initial_timer: float = 0.0

func connect_as_host() -> void:
	if _is_connected:
		print("[MultiplayerBridge] Déjà connecté, saut du délai et de la connexion.")
		emit_signal("connected_to_server")
		if last_public_url != "":
			emit_signal("public_url_received", last_public_url)
		return

	print("[MultiplayerBridge] Connexion demandée, attente initiale de %.1fs..." % INITIAL_DELAY)
	_want_connection = true
	_initial_delay_done = false
	_initial_timer = 0.0
	_retry_timer = 0.0

func disconnect_socket() -> void:
	_want_connection = false
	if _is_connected:
		_socket.close()
	_is_connected = false

func _process(delta: float) -> void:
	if not _want_connection:
		# Toujours poll si on a une connexion active
		if _is_connected:
			_socket.poll()
			var state := _socket.get_ready_state()
			if state == WebSocketPeer.STATE_CLOSED:
				_is_connected = false
				emit_signal("disconnected_from_server")
		return

	# --- Délai initial avant la première tentative ---
	if not _initial_delay_done:
		_initial_timer += delta
		if _initial_timer < INITIAL_DELAY:
			return
		_initial_delay_done = true
		print("[MultiplayerBridge] Délai initial écoulé, première tentative de connexion...")
		_attempt_connect()
		return

	# --- Poll de la socket active ---
	_socket.poll()
	var state := _socket.get_ready_state()

	# Connexion réussie !
	if state == WebSocketPeer.STATE_OPEN and not _is_connected:
		# On attend le handshake Socket.IO (géré dans _handle_message)
		pass

	# Déconnexion détectée → on réessaie
	if state == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_is_connected = false
			print("[MultiplayerBridge] Connexion perdue, reconnexion en cours...")
			emit_signal("disconnected_from_server")

		_retry_timer += delta
		if _retry_timer >= RETRY_INTERVAL:
			_retry_timer = 0.0
			_attempt_connect()
		return

	# Lecture des messages
	if state == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			var text := packet.get_string_from_utf8()
			_handle_message(text)

func _attempt_connect() -> void:
	# Créer une nouvelle WebSocketPeer pour chaque tentative (nécessaire après STATE_CLOSED)
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(server_url)
	if err != OK:
		push_warning("[MultiplayerBridge] Tentative de connexion échouée (err=%s), nouvelle tentative dans %.0fs..." % [str(err), RETRY_INTERVAL])
	else:
		print("[MultiplayerBridge] Tentative de connexion à %s ..." % server_url)

func send_game_phase(phase: String, remaining: int = 0, extra_data: Dictionary = {}) -> void:
	var payload = {"phase": phase, "remaining": remaining}
	payload.merge(extra_data)
	_emit_socketio("host_phase", payload)

func send_elimination(player_id: String) -> void:
	_emit_socketio("player_eliminated", {"playerId": player_id})

func send_feedback(player_id: String, result: String, points: int, combo: int, score: int, rank: int) -> void:
	_emit_socketio("feedback", {
		"playerId": player_id,
		"result": result,
		"points": points,
		"combo": combo,
		"score": score,
		"rank": rank
	})

func send_scoreboard(players: Array, team_scores: Dictionary) -> void:
	_emit_socketio("scoreboard", {
		"players": players,
		"teamScores": team_scores
	})

func send_music_list(musics: Array) -> void:
	_emit_socketio("music_list", {"musics": musics})

func send_vote(song_name: String) -> void:
	_emit_socketio("vote", {"songName": song_name})

func request_lobby() -> void:
	_emit_socketio("get_lobby", {})

# Traduction du JSON en trame Socket.IO (code '42') !
func _emit_socketio(event_name: String, payload: Dictionary = {}) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg = "42" + JSON.stringify([event_name, payload])
	_socket.send_text(msg)

func _handle_message(text: String) -> void:
	# === LOGIQUE INTERNE ENGINE.IO & SOCKET.IO DÉCODÉE EN GDSCRIPT ===
	
	if text.begins_with("0"):
		# Message 0: Engine.IO Open -> On demande tout de suite la connexion Socket.IO (Message 40)
		_socket.send_text("40")
	
	elif text.begins_with("2"):
		# Message 2: Engine.IO Ping -> On répond avec un Pong (Message 3) pour ne pas être kické !
		_socket.send_text("3")
		
	elif text.begins_with("40"):
		# Message 40: Socket.IO nous accepte officiellement ! On envoie 'host_join'
		if not _is_connected:
			_is_connected = true
			print("[MultiplayerBridge] ✓ Connecté au serveur Node.js !")
			_emit_socketio("host_join", {})
			emit_signal("connected_to_server")
			
	elif text.begins_with("42"):
		# Message 42: C'est un événement Socket.IO. On traite le JSON "magique" de la forme ["mon_event", {data}]
		var json_str = text.substr(2)
		var parsed = JSON.parse_string(json_str)
		if typeof(parsed) == TYPE_ARRAY and parsed.size() >= 2:
			var event_name = str(parsed[0])
			var msg = parsed[1]
			
			match event_name:
				"lobby_update":
					var players: Array = msg.get("players", [])
					var team_scores: Dictionary = msg.get("teamScores", {})
					if msg.has("publicUrl") and msg.get("publicUrl") != null:
						var pu = str(msg.get("publicUrl"))
						if pu != "":
							last_public_url = pu
							emit_signal("public_url_received", pu)
					emit_signal("lobby_updated", players, team_scores)
				"player_input":
					emit_signal("player_input_received", msg)
				"player_left":
					emit_signal("player_left", str(msg.get("playerId", "")))
				"public_url":
					var pu := str(msg.get("url", ""))
					print("[MultiplayerBridge] ✓ URL publique reçue : %s" % pu)
					last_public_url = pu
					emit_signal("public_url_received", pu)
				"vote_result":
					emit_signal("vote_result_received", str(msg.get("winner", "")))
				"server_debug":
					print("[SERVER] ", msg)
				"vote_update":
					print("[DEBUG] Bridge received vote_update: ", msg)
					emit_signal("vote_update_received", msg if typeof(msg) == TYPE_ARRAY else [])
