extends Node

# PID du processus node lancé, -1 si pas démarré
var _server_pid: int = -1
var _node_path: String = ""
var _npm_path: String = ""

func _ready() -> void:
	# Détecter node et npm (compatible nvm)
	_detect_node_npm()
	# NETTOYAGE : Tuer tout ancien serveur resté bloqué sur le port 3000
	_cleanup_port_3000()
	_start_server()
	# Arrêter le serveur proprement à la fermeture du jeu
	get_tree().root.close_requested.connect(stop_server)

func _detect_node_npm() -> void:
	# NVM charge node/npm uniquement dans les shells interactifs (bash -l).
	# On utilise bash -lc pour sourcer .bashrc/.profile qui contiennent nvm.
	var output: Array = []
	
	# Chercher node
	if OS.get_name() == "Windows":
		_node_path = "node.exe"
		_npm_path = "npm.cmd"
		return
	
	# Tentative 1 : bash login shell (gère nvm, fnm, etc.)
	OS.execute("bash", ["-lc", "which node"], output)
	var node_result := "".join(output).strip_edges()
	if node_result != "" and not node_result.contains("not found"):
		_node_path = node_result
		print("[ServerManager] Node trouvé (bash -l) : %s" % _node_path)
	else:
		# Tentative 2 : chercher dans les chemins NVM courants
		var home := OS.get_environment("HOME")
		var nvm_dir := OS.get_environment("NVM_DIR")
		if nvm_dir.is_empty():
			nvm_dir = home.path_join(".nvm")
		
		# Scanner les versions installées via nvm
		var nvm_versions := nvm_dir.path_join("versions/node")
		var nvm_scan := DirAccess.open(nvm_versions)
		if nvm_scan:
			nvm_scan.list_dir_begin()
			var version_dir := nvm_scan.get_next()
			var latest_version := ""
			while version_dir != "":
				if nvm_scan.current_is_dir() and version_dir.begins_with("v"):
					latest_version = version_dir  # Prend la dernière (ordre alpha)
				version_dir = nvm_scan.get_next()
			if latest_version != "":
				var candidate := nvm_versions.path_join(latest_version).path_join("bin/node")
				if FileAccess.file_exists(candidate):
					_node_path = candidate
					print("[ServerManager] Node trouvé (scan nvm) : %s" % _node_path)
		
		# Tentative 3 : chemins système classiques
		if _node_path.is_empty():
			for path in ["/usr/bin/node", "/usr/local/bin/node", "/snap/bin/node"]:
				if FileAccess.file_exists(path):
					_node_path = path
					print("[ServerManager] Node trouvé (système) : %s" % _node_path)
					break
	
	if _node_path.is_empty():
		push_error("[ServerManager] ERREUR : node introuvable ! Installez Node.js ou vérifiez votre PATH.")
		_node_path = "node"  # Fallback, tentera quand même
	
	# Déduire npm du même dossier que node
	_npm_path = _node_path.get_base_dir().path_join("npm")
	if not FileAccess.file_exists(_npm_path):
		_npm_path = "npm"  # Fallback
	print("[ServerManager] npm déduit : %s" % _npm_path)

func _cleanup_port_3000() -> void:
	print("[ServerManager] Nettoyage du port 3000...")
	if OS.get_name() == "Windows":
		var cmd = "for /f \"tokens=5\" %a in ('netstat -aon ^| findstr :3000') do taskkill /F /PID %a"
		OS.execute("cmd.exe", ["/c", cmd])
	else:
		OS.execute("sh", ["-c", "lsof -ti:3000 | xargs kill -9 2>/dev/null; true"])
	print("[ServerManager] Port 3000 nettoyé.")

func _start_server() -> void:
	# Chemin vers server.js, relatif à l'exécutable du jeu
	var exe_dir := OS.get_executable_path().get_base_dir()
	var server_path := exe_dir.path_join("maxiflop-server/server.js")

	# En mode éditeur Godot, chercher dans le dossier du projet
	if OS.has_feature("editor"):
		server_path = ProjectSettings.globalize_path("res://").path_join("../maxiflop-server/server.js")

	# Normaliser le chemin selon l'OS
	server_path = server_path.simplify_path()
	
	# Vérifier que le fichier existe, sinon tenter un chemin alternatif
	if not FileAccess.file_exists(server_path):
		var alt_path := exe_dir.path_join("maxiflop/maxiflop-server/server.js").simplify_path()
		if FileAccess.file_exists(alt_path):
			push_warning("[ServerManager] server.js introuvable à '%s', utilisation du chemin alternatif '%s'" % [server_path, alt_path])
			server_path = alt_path
		else:
			push_error("[ServerManager] ERREUR : server.js introuvable !")
			push_error("[ServerManager]   Chemin principal testé : %s" % server_path)
			push_error("[ServerManager]   Chemin alternatif testé : %s" % alt_path)
			push_error("[ServerManager]   Placez l'exécutable dans le même dossier que maxiflop-server/")
			return
	
	var server_dir := server_path.get_base_dir()
	print("[ServerManager] server.js trouvé : %s" % server_path)

	# Vérifier que les packages sont à jour (npm install)
	# Utiliser bash -l pour que nvm soit disponible
	print("[ServerManager] Vérification des packages (npm install)...")
	if OS.get_name() == "Windows":
		OS.execute("cmd.exe", ["/c", "cd /d \"" + server_dir + "\" && npm install"])
	else:
		# Utiliser le npm trouvé, avec bash login pour l'environnement complet
		var npm_cmd := "cd \"%s\" && \"%s\" install" % [server_dir, _npm_path]
		OS.execute("bash", ["-lc", npm_cmd])

	print("[ServerManager] Lancement : %s %s" % [_node_path, server_path])

	# Lancement en arrière-plan avec le chemin complet vers node
	var pid := OS.create_process(_node_path, [server_path])

	if pid > 0:
		_server_pid = pid
		print("[ServerManager] Serveur démarré (PID %d)" % pid)
	else:
		push_error("[ServerManager] Impossible de démarrer le serveur Node.js !")
		push_error("[ServerManager]   node = %s" % _node_path)
		push_error("[ServerManager]   server.js = %s" % server_path)
		push_error("[ServerManager]   Lancez manuellement : %s %s" % [_node_path, server_path])

func stop_server() -> void:
	if _server_pid > 0:
		print("[ServerManager] Arrêt du serveur (PID %d)" % _server_pid)
		
		if OS.get_name() == "Windows":
			# /F = force, /T = tree (tue les enfants comme cloudflared)
			OS.execute("taskkill", ["/F", "/T", "/PID", str(_server_pid)])
		else:
			OS.kill(_server_pid)
			
		_server_pid = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_server()
