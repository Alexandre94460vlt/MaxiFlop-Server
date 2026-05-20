extends Node2D

@onready var note_spawner: Node2D = $PlayField/NoteSpawner
@onready var hit_zone: Node2D = $PlayField/HitZone
@onready var music_player: AudioStreamPlayer = $MusicPlayer


@onready var combo_label: Label = $HUD/ComboLabel
@onready var multiplier_label: Label = $HUD/MultiplierLabel
@onready var progress_bar: ProgressBar = $HUD/ProgressBar
@onready var count_down: Label = $HUD/CountdownLabel
@onready var result_panel: Control = $HUD/ResultPanel
@onready var warmup_label: Label = $HUD/WarmupLabel
@onready var lobby_frame: PanelContainer = $HUD/LobbyFrame
@onready var lobby_qr_texture: TextureRect = $HUD/LobbyFrame/VBox/LobbyQRTexture
@onready var start_match_button: Button = $HUD/LobbyFrame/VBox/StartMatchButton
@onready var lobby_back_button: Button = $HUD/LobbyBackButton
@onready var qr_http: HTTPRequest = $HUD/RightPanel/VBox/QRHTTPRequest

@onready var right_panel: PanelContainer = $HUD/RightPanel
@onready var team_a_score_label: Label = $HUD/RightPanel/VBox/TeamAScore
@onready var team_b_score_label: Label = $HUD/RightPanel/VBox/TeamBScore
@onready var team_c_score_label: Label = $HUD/RightPanel/VBox/TeamCScore
@onready var lobby_count_label: Label = $HUD/RightPanel/VBox/LobbyCount
@onready var join_link_label: Label = $HUD/RightPanel/VBox/JoinLink
@onready var team_a_progress: ProgressBar = $HUD/RightPanel/VBox/RacePanel/TeamATrack/TeamAProgress
@onready var team_b_progress: ProgressBar = $HUD/RightPanel/VBox/RacePanel/TeamBTrack/TeamBProgress
@onready var team_c_progress: ProgressBar = $HUD/RightPanel/VBox/RacePanel/TeamCTrack/TeamCProgress
@onready var race_panel: Control = $HUD/RightPanel/VBox/RacePanel
@onready var top5_label: RichTextLabel = $HUD/RightPanel/VBox/LeaderboardPanel/LeaderboardVBox/Top5Label
@onready var error_toast: PanelContainer = $HUD/ErrorToast
@onready var error_label: Label = $HUD/ErrorToast/Label
@onready var result_team_scores_label: RichTextLabel = $HUD/ResultPanel/VBox/TeamScoresLabel
@onready var result_winner_label: Label = $HUD/ResultPanel/VBox/WinnerLabel
@onready var result_top5_label: RichTextLabel = $HUD/ResultPanel/VBox/ResultTop5Label

@export var song_duration: float = 30.0
@export var join_url_override: String = ""

var countdown_time: float = 5.0
var is_counting_down: bool = false
var is_waiting_start: bool = true
var is_game_over: bool = false
var elapsed: float = 0.0
var team_scores := {"Equipe1": 0, "Equipe2": 0, "Equipe3": 0}
var join_url_ready: bool = false
var loading_timer: float = 0.0
var players: Dictionary = {}
var player_judged_notes: Dictionary = {}
var alive_players: Array = []
var eliminated_count: int = 0
var initial_br_players: int = 0
var br_ramp_timer: float = 0.0
var br_empty_hits: Dictionary = {}
var br_miss_streak: Dictionary = {}

var voting_time: float = 15.0
var is_voting: bool = false
var selected_song: String = ""
var reveal_timer: float = 0.0

var ghost_player: AudioStreamPlayer
var phantom_bus_idx: int = -1
var voting_panel: PanelContainer
var difficulty_label: Label
var vote_stats_label: RichTextLabel
var kill_feed_label: RichTextLabel
var br_kill_feed: Array = []

func _ready() -> void:
	# --- PhantomBus Setup ---
	phantom_bus_idx = AudioServer.get_bus_index("PhantomBus")
	if phantom_bus_idx == -1:
		AudioServer.add_bus()
		phantom_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(phantom_bus_idx, "PhantomBus")
		AudioServer.set_bus_mute(phantom_bus_idx, true)
		var analyzer := AudioEffectSpectrumAnalyzer.new()
		analyzer.buffer_length = 0.1
		AudioServer.add_bus_effect(phantom_bus_idx, analyzer)
	
	ghost_player = AudioStreamPlayer.new()
	ghost_player.bus = "PhantomBus"
	add_child(ghost_player)
	
	music_player.bus = "InGameMusic"
	# ------------------------

	GameManager.combo_changed.connect(_on_combo_changed)
	GameManager.game_over.connect(_on_game_over)
	MultiplayerBridge.connected_to_server.connect(_on_host_connected)
	MultiplayerBridge.lobby_updated.connect(_on_lobby_updated)
	MultiplayerBridge.player_input_received.connect(_on_player_input_received)
	MultiplayerBridge.player_left.connect(_on_player_left)
	MultiplayerBridge.public_url_received.connect(_on_public_url_received)

	result_panel.visible = false
	combo_label.visible = false
	start_match_button.pressed.connect(_on_start_match_pressed)
	lobby_back_button.pressed.connect(_on_lobby_back_button_pressed)
	qr_http.request_completed.connect(_on_qr_downloaded)
	# qr_texture removed as requested
	lobby_frame.visible = false
	_refresh_right_panel()
	MultiplayerBridge.connect_as_host()
	MultiplayerBridge.request_lobby()
	GameManager.global_note_missed.connect(_on_global_note_missed)
	MultiplayerBridge.vote_result_received.connect(_on_vote_result)
	MultiplayerBridge.vote_update_received.connect(_on_vote_update)
	_setup_voting_ui()
	_setup_kill_feed()
	_enter_waiting_state()

func _setup_voting_ui() -> void:
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(center)
	
	voting_panel = PanelContainer.new()
	var style = right_panel.get_theme_stylebox("panel").duplicate()
	style.content_margin_left = 60
	style.content_margin_right = 60
	style.content_margin_top = 40
	style.content_margin_bottom = 40
	voting_panel.add_theme_stylebox_override("panel", style)
	center.add_child(voting_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	voting_panel.add_child(vbox)
	
	# Reparent labels existants
	warmup_label.reparent(vbox)
	count_down.reparent(vbox)
	
	difficulty_label = Label.new()
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_label.add_theme_font_size_override("font_size", 40)
	vbox.add_child(difficulty_label)
	
	warmup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_down.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_down.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	
	warmup_label.custom_minimum_size = Vector2(600, 0)
	count_down.custom_minimum_size = Vector2(600, 0)
	
	vote_stats_label = RichTextLabel.new()
	vote_stats_label.bbcode_enabled = true
	vote_stats_label.fit_content = true
	vote_stats_label.custom_minimum_size = Vector2(600, 0)
	vote_stats_label.add_theme_font_size_override("normal_font_size", 28)
	vbox.add_child(vote_stats_label)
	
	# Largeur fixe pour forcer le retour à la ligne automatique (autowrap)
	voting_panel.custom_minimum_size = Vector2(600, 350) # Plus grand pour le top 3
	voting_panel.clip_contents = true
	
	voting_panel.visible = false

func _setup_kill_feed() -> void:
	# Créer le label du kill feed dans le même parent que top5_label
	var leaderboard_vbox = top5_label.get_parent()
	kill_feed_label = RichTextLabel.new()
	kill_feed_label.bbcode_enabled = true
	kill_feed_label.fit_content = true
	kill_feed_label.scroll_active = false
	kill_feed_label.custom_minimum_size = Vector2(0, 0)
	kill_feed_label.add_theme_font_size_override("normal_font_size", 18)
	kill_feed_label.visible = false
	leaderboard_vbox.add_child(kill_feed_label)

func _refresh_kill_feed() -> void:
	if kill_feed_label == null:
		return
	if br_kill_feed.is_empty():
		kill_feed_label.text = "[center][color=gray]Aucune élimination[/color][/center]"
		return
	var lines: Array = ["[b]ÉLIMINATIONS[/b]"]
	for entry in br_kill_feed:
		var t = int(entry.get("time", 0))
		var mins = t / 60
		var secs = t % 60
		lines.append("[color=#ff5555]%s[/color] [color=gray](%d:%02d)[/color]" % [str(entry.get("name", "?")), mins, secs])
	kill_feed_label.text = "\n".join(lines)

func _enter_waiting_state() -> void:
	result_panel.visible = false
	is_waiting_start = true
	is_counting_down = false
	is_game_over = false
	warmup_label.visible = true
	warmup_label.text = "Salle d'attente"
	lobby_frame.visible = true
	start_match_button.visible = true
	start_match_button.disabled = false
	lobby_back_button.visible = true
	count_down.visible = false
	
	# Masquer le race panel SEULEMENT en BR
	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
		race_panel.visible = false
	else:
		race_panel.visible = true
	var extra = {"gameMode": "NORMAL"}
	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
		extra = {"gameMode": "BATTLE_ROYALE"}
	MultiplayerBridge.send_game_phase("lobby", 0, extra)

func _start_voting() -> void:
	is_waiting_start = false
	is_counting_down = false
	is_voting = true
	# Reset local timer and UI state immediately
	voting_time = 15.0
	voting_panel.visible = true
	lobby_frame.visible = false
	lobby_back_button.visible = false
	difficulty_label.visible = false
	warmup_label.visible = true
	warmup_label.text = "VOTE POUR LA MUSIQUE"
	vote_stats_label.text = "[center][color=gray]Aucun vote pour le moment[/color][/center]"
	vote_stats_label.visible = true
	count_down.visible = true
	count_down.text = "15"
	count_down.add_theme_font_size_override("font_size", 120)
	start_match_button.visible = false
	
	# Lister les musiques (DirAccess fonctionne en éditeur, pas toujours en export PCK)
	var musics := []
	var dir = DirAccess.open("res://assets/musics")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				if file_name.ends_with(".mp3"):
					var name = file_name.replace(".mp3", "")
					if not musics.has(name):
						musics.append(name)
				elif file_name.ends_with(".mp3.import"):
					var name = file_name.replace(".mp3.import", "")
					if not musics.has(name):
						musics.append(name)
			file_name = dir.get_next()
	
	# Fallback : lire la liste pré-générée (fiable en export)
	if musics.is_empty():
		print("[GameScreen] DirAccess vide, lecture de music_list.txt...")
		var f = FileAccess.open("res://assets/musics/music_list.txt", FileAccess.READ)
		if f:
			while not f.eof_reached():
				var line = f.get_line().strip_edges()
				if line != "" and not musics.has(line):
					musics.append(line)
			f.close()
			print("[GameScreen] %d musiques chargées depuis music_list.txt" % musics.size())
		else:
			push_error("[GameScreen] ERREUR : Aucune musique trouvée ! Ni DirAccess ni music_list.txt.")
	
	
	# Trier les musiques par difficulté
	var diff_priority := {"EASY": 0, "MEDIUM": 1, "HARD": 2, "EXTREME": 3}
	musics.sort_custom(func(a: String, b: String):
		var p_a = 99
		var p_b = 99
		var up_a = a.to_upper()
		var up_b = b.to_upper()
		for d in diff_priority:
			if up_a.ends_with(d): p_a = diff_priority[d]
			if up_b.ends_with(d): p_b = diff_priority[d]
		
		if p_a != p_b:
			return p_a < p_b
		return a < b # tri alphabétique si même difficulté
	)
	
	MultiplayerBridge.send_music_list(musics)
	# Petit délai pour laisser le serveur traiter la liste avant le changement de phase
	await get_tree().create_timer(0.1).timeout
	MultiplayerBridge.send_game_phase("voting")
	_refresh_right_panel()

func _start_countdown() -> void:
	is_waiting_start = false
	is_voting = false
	is_counting_down = true
	is_game_over = false
	countdown_time = 5.0
	voting_panel.visible = true
	vote_stats_label.visible = false
	lobby_frame.visible = false
	lobby_back_button.visible = false
	warmup_label.visible = true
	warmup_label.text = "PRÊT ?"
	start_match_button.visible = false
	count_down.visible = true
	count_down.text = "5"
	count_down.scale = Vector2.ONE
	count_down.add_theme_font_size_override("font_size", 200)
	MultiplayerBridge.send_game_phase("countdown")
	_refresh_right_panel()
	
	if GameManager.current_mode != GameManager.GameMode.BATTLE_ROYALE:
		race_panel.visible = true
	
	# Fondus sonore : la musique du menu disparaît pour laisser place au jeu
	MusicManager.fade_out(1.5)
	
	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
		if music_player.stream:
			music_player.stream.loop = true

func _process(delta: float) -> void:
	if not join_url_ready and is_waiting_start:
		loading_timer += delta
		if loading_timer > 20.0:
			join_url_ready = true
			_set_join_url()
			_load_qr_code()
			_refresh_right_panel()
		else:
			var dots := ""
			for i in range(int(loading_timer * 3) % 4):
				dots += "."
			if loading_timer < 5.0:
				join_link_label.text = "Démarrage du serveur" + dots
			else:
				join_link_label.text = "Attente du tunnel" + dots

	if is_waiting_start:
		return

	if is_voting:
		voting_time -= delta
		var display := ceili(voting_time)
		if display > 0:
			count_down.text = str(display)
		else:
			# Temps écoulé, mais on reste en is_voting=true jusqu'au vote_result_received
			# On n'envoie "reveal" qu'une seule fois via l'idantifiant du timer
			if voting_time > -1.0: # Petit buffer pour ne pas spammer
				count_down.text = "!"
				if voting_time + delta > 0: # C'est la première fois qu'on passe en dessous de 0
					MultiplayerBridge.send_game_phase("reveal")
		return

	if reveal_timer > 0:
		reveal_timer -= delta
		if reveal_timer <= 0:
			if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
				# En BR, on relaxe la vérification d'équilibrage
				_start_countdown()
			else:
				_start_countdown()
		return

	if is_counting_down:
		countdown_time -= delta
		var display := ceili(countdown_time)
		if display > 0:
			count_down.text = str(display)
		else:
			count_down.text = "GO !"
			if countdown_time <= -0.4:
				_begin_game()
		return

	elapsed += delta
	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
		progress_bar.visible = false
	else:
		progress_bar.visible = true
		progress_bar.value = clamp((elapsed / song_duration) * 100.0, 0, 100)

	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE and GameManager.is_playing:
		# Accélération exponentielle : courbe pow(1.3) pour une montée progressive puis explosive
		var difficulty_factor = 1.0 + pow(elapsed / 60.0, 1.3)
		note_spawner.set_difficulty_scaling(difficulty_factor)
		
		# Timer affiché sur le panel de droite
		team_c_score_label.text = "Temps : %d s" % int(elapsed)
		
		# Feedback optionnel dans la console (toutes les quelques secondes)
		if int(elapsed) % 15 == 0 and elapsed > 0 and int(elapsed * 10) % 10 == 0:
			print("[BR Mode] Difficulté crescendo: %.2f (cooldown: %.3f, threshold: %.5f)" % [difficulty_factor, note_spawner._actual_cooldown_calculated, note_spawner._actual_threshold_calculated])
	else:
		# Fade out progressif sur les 3 dernieres secondes si le track est cut
		var fade_start := song_duration - 3.0
		if elapsed >= fade_start:
			var fade_factor = clamp((elapsed - fade_start) / 3.0, 0.0, 1.0)
			music_player.volume_db = lerp(0.0, -80.0, fade_factor)

		if elapsed >= song_duration:
			GameManager.end_game()

func _begin_game() -> void:
	is_counting_down = false
	count_down.visible = false
	voting_panel.visible = false
	
	var extra = {"gameMode": "NORMAL"}
	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
		extra = {"gameMode": "BATTLE_ROYALE"}
		# Initialiser les survivants à partir des joueurs réels présents
		alive_players = players.keys().duplicate()
		initial_br_players = alive_players.size()
		eliminated_count = 0
		br_ramp_timer = 0.0
		br_empty_hits.clear()
		br_miss_streak.clear()
		br_kill_feed.clear()
		_refresh_kill_feed()
		print("[BR] Match lance avec ", initial_br_players, " survivants.")
		_refresh_right_panel()
		
	MultiplayerBridge.send_game_phase("playing", 0, extra)
	player_judged_notes.clear()
	elapsed = 0.0
	progress_bar.value = 0.0
	music_player.volume_db = 0.0 # reset volume in case of quick restart
	if music_player.stream != null:
		var stream_len = float(music_player.stream.get_length())
		if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
			song_duration = stream_len # Pas de limite en BR
			note_spawner.is_looping = true
		else:
			song_duration = min(120.0, stream_len)
			note_spawner.is_looping = false
			
		ghost_player.stop() # Securite
		ghost_player.stream = music_player.stream
		
	note_spawner.song_duration = song_duration
	note_spawner.start_spectrum(phantom_bus_idx)
	GameManager.start_game()
	
	if music_player.stream != null:
		music_player.play(0.0)
		ghost_player.play(note_spawner.approach_time)

func _on_vote_result(song_name: String) -> void:
	# On accepte le résultat même si le timer local est à 0 (is_voting est toujours true)
	if not is_voting: return
	is_voting = false
	
	selected_song = song_name
	vote_stats_label.visible = false
	warmup_label.text = "MUSIQUE SÉLECTIONNÉE :"
	
	# Extraire la difficulté du nom du fichier (ex: "- EASY")
	var display_name = song_name
	var diff_text = ""
	var diff_color = Color.WHITE
	
	if song_name.to_upper().ends_with("EASY"):
		diff_text = "DIFFICULTÉ : FACILE"
		diff_color = Color.GREEN
		display_name = song_name.left(song_name.length() - 7).strip_edges()
	elif song_name.to_upper().ends_with("MEDIUM"):
		diff_text = "DIFFICULTÉ : MOYEN"
		diff_color = Color.ORANGE
		display_name = song_name.left(song_name.length() - 9).strip_edges()
	elif song_name.to_upper().ends_with("HARD"):
		diff_text = "DIFFICULTÉ : DIFFICILE"
		diff_color = Color.RED
		display_name = song_name.left(song_name.length() - 7).strip_edges()
	elif song_name.to_upper().ends_with("EXTREME"):
		diff_text = "DIFFICULTÉ : EXTRÊME"
		diff_color = Color.BLACK
		display_name = song_name.left(song_name.length() - 10).strip_edges()
	
	count_down.text = display_name
	count_down.add_theme_font_size_override("font_size", 48)
	
	difficulty_label.text = diff_text
	difficulty_label.add_theme_color_override("font_color", diff_color)
	difficulty_label.visible = !diff_text.is_empty()
	
	# Appliquer la difficulté au spawner de notes
	note_spawner.set_difficulty(song_name)
	
	# Charger la musique
	var path = "res://assets/musics/" + song_name + ".mp3"
	var stream = load(path)
	if stream:
		music_player.stream = stream
		song_duration = float(stream.get_length())
	
	reveal_timer = 4.0
	
	# Animation visuelle
	# On centre le pivot pour que le scale se fasse depuis le milieu du texte
	count_down.pivot_offset = count_down.size / 2
	var tween = create_tween()
	tween.tween_property(count_down, "scale", Vector2(1.2, 1.2), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(3.5) # On attend un peu plus pour couvrir le reveal_timer
	tween.tween_callback(func(): count_down.scale = Vector2.ONE)

#Signaux


func _on_combo_changed(new_combo: int) -> void:
	if new_combo > 1:
		combo_label.visible = true
		combo_label.text = "x%d COMBO" % new_combo

		var tween := create_tween()
		tween.tween_property(combo_label, "scale", Vector2(1.2, 1.2), 0.05)
		tween.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.1)
	else:
		combo_label.visible = false

	if GameManager.multiplier > 1.0:
		multiplier_label.text = "x%.0f" % GameManager.multiplier
		multiplier_label.visible = true
	else:
		multiplier_label.visible = false

func _on_game_over() -> void:
	note_spawner.stop()
	music_player.stop()
	if ghost_player:
		ghost_player.stop()
	lobby_frame.visible = false
	MultiplayerBridge.send_game_phase("ended")
	is_waiting_start = true
	is_counting_down = false
	is_game_over = true
	
	if music_player.stream:
		music_player.stream.loop = false
		
	start_match_button.visible = true
	start_match_button.disabled = false
	lobby_back_button.visible = true
	warmup_label.visible = true
	warmup_label.text = "Partie terminee"
	result_panel.visible = true
	
	# Relancer la musique de menu avec un fondu à la fin de la partie
	MusicManager.play_menu_music()
	
	_refresh_result_panel()
	_refresh_right_panel()

#btn hitzone

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_btn_blue_pressed() -> void: hit_zone.press_button(0)
func _on_btn_yellow_pressed() -> void: hit_zone.press_button(1)
func _on_btn_red_pressed() -> void: hit_zone.press_button(2)
func _refresh_result_panel() -> void:
	var score_a := int(team_scores.get("Equipe1", 0))
	var score_b := int(team_scores.get("Equipe2", 0))
	var score_c := int(team_scores.get("Equipe3", 0))
	
	var count_a = 0
	var count_b = 0
	var count_c = 0
	for p_id in players:
		var t: String = str(players[p_id].get("team", ""))
		if t == "Equipe1": count_a += 1
		elif t == "Equipe2": count_b += 1
		elif t == "Equipe3": count_c += 1
	
	var label_text := "[center]"
	label_text += "[b][font_size=24][color=#5fcde4]Musique : %s[/color][/font_size][/b]\n\n" % selected_song
	label_text += "[b][color=#5fcde4]Equipe Bleue  :[/color][/b]  %d points (%dj)\n" % [score_a, count_a]
	label_text += "[b][color=#ff7081]Equipe Rouge :[/color][/b]  %d points (%dj)\n" % [score_b, count_b]
	label_text += "[b][color=#f0e040]Equipe Jaune :[/color][/b]  %d points (%dj)" % [score_c, count_c]
	label_text += "[/center]"
	
	result_team_scores_label.text = label_text

	# Couleur équipe bleue = cyan, rouge = rose, jaune = jaune
	var color_a := Color("#5fcde4")
	var color_b := Color("#ff7081")
	var color_c := Color("#f0e040")
	var max_score = max(score_a, max(score_b, score_c))

	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
		if alive_players.size() > 0:
			var winner_id = alive_players[0]
			var winner_name = players[winner_id].get("name", "Inconnu")
			result_winner_label.text = "VAINQUEUR : %s !" % winner_name.to_upper()
			result_winner_label.add_theme_color_override("font_color", Color.GOLD)
		else:
			if initial_br_players <= 1:
				result_winner_label.text = "Fin de l'entrainement !"
				result_winner_label.add_theme_color_override("font_color", Color.AQUAMARINE)
			else:
				result_winner_label.text = "Tout le monde est mort..."
				result_winner_label.add_theme_color_override("font_color", Color.GRAY)
		
		# Masquer le détail des équipes en BR
		result_team_scores_label.text = "[center][b]MODE BATTLE ROYALE[/b]\nMusique : %s[/center]" % selected_song
	else:
		if score_a == max_score and score_b < max_score and score_c < max_score:
			result_winner_label.text = "L'équipe bleue remporte la partie !"
			result_winner_label.add_theme_color_override("font_color", color_a)
		elif score_b == max_score and score_a < max_score and score_c < max_score:
			result_winner_label.text = "L'équipe rouge remporte la partie !"
			result_winner_label.add_theme_color_override("font_color", color_b)
		elif score_c == max_score and score_a < max_score and score_b < max_score:
			result_winner_label.text = "L'équipe jaune remporte la partie !"
			result_winner_label.add_theme_color_override("font_color", color_c)
		else:
			result_winner_label.text = "Egalité !"
			result_winner_label.add_theme_color_override("font_color", Color.WHITE)

	var ranked := _get_sorted_players()
	var lines := ["[center][b]TOP 5 JOUEURS[/b][/center]"]
	var max_lines := mini(5, ranked.size())
	for i in max_lines:
		var p: Dictionary = ranked[i]
		var team := str(p.get("team", "Equipe1"))
		var color := "#5fcde4" if team == "Equipe1" else ("#ff7081" if team == "Equipe2" else "#f0e040")
		lines.append("[center]%d. [color=%s]%s[/color] - %d[/center]" % [i + 1, color, str(p.get("name", "Player")), int(p.get("score", 0))])
	result_top5_label.text = "\n".join(lines)

func _on_restart_pressed() -> void:
	_enter_waiting_state()
	
func _on_menu_pressed() -> void: get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_host_connected() -> void:
	_refresh_right_panel()

func _on_lobby_updated(remote_players: Array, remote_team_scores: Dictionary) -> void:
	players.clear()
	for p in remote_players:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var player_id := str(p.get("id", ""))
		if player_id.is_empty():
			continue
		players[player_id] = {
			"id": player_id,
			"name": str(p.get("pseudo", p.get("name", "Player"))),
			"team": str(p.get("team", "Equipe1")),
			"score": int(p.get("score", 0)),
			"combo": int(p.get("combo", 0)),
			"perfect_streak": int(p.get("perfect_streak", 0))
		}
	for team_key in remote_team_scores.keys():
		team_scores[team_key] = int(remote_team_scores.get(team_key, 0))
	_refresh_right_panel()

func _on_player_left(player_id: String) -> void:
	if players.has(player_id):
		players.erase(player_id)
	if player_judged_notes.has(player_id):
		player_judged_notes.erase(player_id)
	_recompute_team_scores()
	_refresh_right_panel()

func _on_player_input_received(payload: Dictionary) -> void:
	if not GameManager.is_playing:
		return

	var player_id := str(payload.get("playerId", ""))
	var color := int(payload.get("color", -1))
	if player_id.is_empty() or color < 0 or color > 2:
		return
	if not players.has(player_id):
		return

	var result := _evaluate_remote_hit(player_id, color)
	if result.has("note_key"):
		var note_key := str(result.get("note_key", ""))
		if _already_judged_note(player_id, note_key):
			return
		_mark_judged_note(player_id, note_key)
			
	_apply_remote_result(player_id, result)

func _evaluate_remote_hit(player_id: String, color: int) -> Dictionary:
	# Fenêtre étendue à 0.8s pour le réseau
	var best: Dictionary = note_spawner.get_best_note_for_timing(color, elapsed, 0.8)
	if best.is_empty():
		return {"result": "MISS", "points": 0, "empty": true}

	var note = best.get("note", null)
	var timing_error := float(best.get("timing_error", 999.0))
	var result := "BAD" # Par défaut si hors des fenêtres classiques mais trouvé par le 0.8s
	var base_points := 0

	if timing_error <= GameManager.WINDOW_PERFECT:
		result = "PERFECT"
		base_points = GameManager.SCORE_PERFECT
	elif timing_error <= GameManager.WINDOW_GOOD:
		result = "GOOD"
		base_points = GameManager.SCORE_GOOD
	elif timing_error <= GameManager.WINDOW_BAD:
		result = "BAD"
		base_points = GameManager.SCORE_BAD
	else:
		# Note trouvée dans la fenêtre de lag (0.25 - 0.8s) : Coup BAD mais valide
		result = "BAD"
		base_points = GameManager.SCORE_BAD

	var player_data: Dictionary = players[player_id]
	var next_combo := int(player_data.get("combo", 0)) + 1
	var next_perfect_streak := int(player_data.get("perfect_streak", 0))

	var points := base_points
	if result == "PERFECT":
		points += (next_perfect_streak * 3)
		next_perfect_streak += 1
	else:
		next_perfect_streak = 0

	var note_key := "%d:%d" % [color, int(round(float(note.spawn_time) * 1000.0))]
	return {
		"result": result,
		"points": points,
		"combo": next_combo,
		"perfect_streak": next_perfect_streak,
		"note_key": note_key
	}

func _on_global_note_missed(color: int, spawn_time: float) -> void:
	if not GameManager.is_playing:
		return
	var note_key := "%d:%d" % [color, int(round(spawn_time * 1000.0))]
	for p_id in players.keys():
		# Ignorer les joueurs déjà éliminés
		if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE and not alive_players.has(p_id):
			continue
		var judged: Dictionary = player_judged_notes.get(p_id, {})
		if not judged.has(note_key):
			_apply_remote_result(p_id, {"result": "MISS", "timeout": true, "note_key": note_key})

func _apply_remote_result(player_id: String, result_payload: Dictionary) -> void:
	if not players.has(player_id):
		return

	var player_data: Dictionary = players[player_id]
	var result := str(result_payload.get("result", "MISS"))
	var points := int(result_payload.get("points", 0))
	var combo := int(player_data.get("combo", 0))
	var perfect_streak := int(player_data.get("perfect_streak", 0))

	if result == "MISS":
		combo = 0
		perfect_streak = 0
		points = - GameManager.PENALTY_EMPTY
		
		# Logique Battle Royale : Élimination
		if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
			if result_payload.get("timeout", false):
				# Note ratée (timeout) — reset du compteur de spam vide
				br_empty_hits[player_id] = 0
				var note_key = result_payload.get("note_key", "")
				get_tree().create_timer(0.6).timeout.connect(func():
					if not GameManager.is_playing:
						return
					var judged = player_judged_notes.get(player_id, {})
					if not judged.has(note_key):
						if alive_players.has(player_id):
							print("[BR] Elimination par note ratée: ", player_id, " note_key=", note_key)
							_finalize_elimination(player_id)
				)
			elif result_payload.get("empty", false):
				# Clic dans le vide : on incrémente le compteur de spam
				var count = br_empty_hits.get(player_id, 0) + 1
				br_empty_hits[player_id] = count
				if count >= 2:
					# 2 clics consécutifs dans le vide = élimination
					if alive_players.has(player_id):
						print("[BR] Elimination par spam dans le vide : ", player_id, " (count=", count, ")")
						_finalize_elimination(player_id)
			# else: cas impossible, on ignore
	else:
		# Succes ! On marque la note comme jugee
		var note_key = result_payload.get("note_key", "")
		if not note_key.is_empty():
			_mark_judged_note(player_id, note_key)
		
		# Reset du compteur de spam dans le vide (le joueur a touché une note)
		if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
			br_empty_hits[player_id] = 0
			br_miss_streak[player_id] = 0
		
		combo = int(result_payload.get("combo", combo + 1))
		perfect_streak = int(result_payload.get("perfect_streak", perfect_streak))

	var score := maxi(0, int(player_data.get("score", 0)) + points)
	player_data["combo"] = combo
	player_data["perfect_streak"] = perfect_streak
	player_data["score"] = score
	players[player_id] = player_data

	_recompute_team_scores()

	var sorted_players := _get_sorted_players()
	var rank := 1
	for i in sorted_players.size():
		var p: Dictionary = sorted_players[i]
		if str(p.get("id", "")) == player_id:
			rank = i + 1
			break

	MultiplayerBridge.send_feedback(player_id, result, points, combo, score, rank)
	MultiplayerBridge.send_scoreboard(_build_player_array(), team_scores)
	_refresh_right_panel()

func _finalize_elimination(player_id: String) -> void:
	if not alive_players.has(player_id): return
	
	alive_players.erase(player_id)
	eliminated_count += 1
	MultiplayerBridge.send_elimination(player_id)
	print("[BR] Elimination confirmee : ", player_id)
	
	# Kill feed : ajouter le joueur éliminé
	var player_name = "Inconnu"
	if players.has(player_id):
		player_name = str(players[player_id].get("name", "Inconnu"))
	br_kill_feed.insert(0, {"name": player_name, "time": int(elapsed)})
	if br_kill_feed.size() > 8:
		br_kill_feed.resize(8)
	_refresh_kill_feed()
	_refresh_right_panel()
	
	_check_br_victory()

func _build_player_array() -> Array:
	var arr: Array = []
	for k in players.keys():
		arr.append(players[k])
	return arr

func _get_sorted_players() -> Array:
	var arr := _build_player_array()
	arr.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	return arr

func _recompute_team_scores() -> void:
	team_scores["Equipe1"] = 0
	team_scores["Equipe2"] = 0
	team_scores["Equipe3"] = 0
	for p_id in players:
		var p: Dictionary = players[p_id]
		var t: String = str(p.get("team", "Equipe1"))
		if team_scores.has(t):
			team_scores[t] += int(p.get("score", 0))

func _refresh_right_panel() -> void:
	var in_lobby: bool = is_waiting_start and not is_game_over
	
	if not in_lobby:
		if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
			team_a_score_label.text = "Survivants : %d" % alive_players.size()
			team_b_score_label.text = "Éliminés : %d" % eliminated_count
			team_c_score_label.text = "Temps : %d s" % int(elapsed)
			lobby_count_label.text = "Musique: %s" % selected_song
		else:
			team_a_score_label.text = "Equipe bleue: %d" % int(team_scores.get("Equipe1", 0))
			team_b_score_label.text = "Equipe rouge: %d" % int(team_scores.get("Equipe2", 0))
			team_c_score_label.text = "Equipe jaune: %d" % int(team_scores.get("Equipe3", 0))
			lobby_count_label.text = "Musique: %s" % selected_song
	else:
		if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
			team_a_score_label.text = ""
			team_b_score_label.text = ""
			team_c_score_label.text = ""
			race_panel.visible = false
		else:
			var count_a = 0
			var count_b = 0
			var count_c = 0
			for p_id in players:
				var t: String = str(players[p_id].get("team", ""))
				if t == "Equipe1": count_a += 1
				elif t == "Equipe2": count_b += 1
				elif t == "Equipe3": count_c += 1
			team_a_score_label.text = "Joueurs équipe bleue : %d" % count_a
			team_b_score_label.text = "Joueurs équipe rouge : %d" % count_b
			team_c_score_label.text = "Joueurs équipe jaune : %d" % count_c
			race_panel.visible = true
			
		lobby_count_label.text = "Joueurs connectes: %d" % players.size()
	var total := float(int(team_scores.get("Equipe1", 0)) + int(team_scores.get("Equipe2", 0)) + int(team_scores.get("Equipe3", 0)))
	if total <= 0.0:
		team_a_progress.value = 0.0
		team_b_progress.value = 0.0
		team_c_progress.value = 0.0
	else:
		team_a_progress.value = (float(int(team_scores.get("Equipe1", 0))) / total) * 100.0
		team_b_progress.value = (float(int(team_scores.get("Equipe2", 0))) / total) * 100.0
		team_c_progress.value = (float(int(team_scores.get("Equipe3", 0))) / total) * 100.0

	# En lobby : afficher QR code + lien, masquer classement
	# En jeu ou Resultat : afficher classement
	lobby_qr_texture.visible = (is_waiting_start or is_game_over) and join_url_ready
	join_link_label.visible = is_waiting_start or is_game_over
	
	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE and not is_waiting_start:
		top5_label.visible = false
		if kill_feed_label: kill_feed_label.visible = true
	else:
		top5_label.visible = not is_waiting_start
		if kill_feed_label: kill_feed_label.visible = false

	var ranked := _get_sorted_players()
	var lines := ["[b]TOP 5 JOUEURS[/b]"]
	var max_lines := mini(5, ranked.size())
	for i in max_lines:
		var p: Dictionary = ranked[i]
		var team := str(p.get("team", "Equipe1"))
		var color := "#5fcde4" if team == "Equipe1" else ("#ff7081" if team == "Equipe2" else "#f0e040")
		lines.append("%d. [color=%s]%s[/color] - %d" % [i + 1, color, str(p.get("name", "Player")), int(p.get("score", 0))])
	top5_label.text = "\n".join(lines)

func _load_qr_code() -> void:
	var url := join_url_override.strip_edges()
	var local_ip := _get_preferred_lan_ip()
	if url.is_empty():
		url = "http://%s:3000" % local_ip
	print("=== Génération du QR Code ===")
	print("Adresse IP locale détectée : ", local_ip)
	print("URL intégrée dans le QR Code : ", url)
	print("===============================")
	
	var encoded := url.uri_encode()
	qr_http.request("https://quickchart.io/qr?size=180&format=png&text=" + encoded)

func _on_public_url_received(url: String) -> void:
	print("Tunnel public recu depuis Node.js : ", url)
	print("URL intégrée dans le QR Code : ", url)
	join_url_ready = true
	join_url_override = url
	join_link_label.text = "Adresse: %s" % url
	qr_http.cancel_request()
	var encoded := url.uri_encode()
	qr_http.request("https://quickchart.io/qr?size=180&format=png&text=" + encoded)
	_refresh_right_panel()

func _on_qr_downloaded(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var img := Image.new()
	if img.load_png_from_buffer(body) == OK:
		var tex = ImageTexture.create_from_image(img)
		lobby_qr_texture.texture = tex

func _set_join_url() -> void:
	var join_url := join_url_override.strip_edges()
	var local_ip := _get_preferred_lan_ip()
	if join_url.is_empty():
		join_url = "http://%s:3000" % local_ip
	print("Set Join URL - IP Locale : ", local_ip)
	print("Set Join URL - URL finale : ", join_url)
	join_link_label.text = "Adresse: %s" % join_url

func _already_judged_note(player_id: String, note_key: String) -> bool:
	if not player_judged_notes.has(player_id):
		return false
	var judged: Dictionary = player_judged_notes[player_id]
	return judged.has(note_key)

func _mark_judged_note(player_id: String, note_key: String) -> void:
	var judged: Dictionary = {}
	if player_judged_notes.has(player_id):
		judged = player_judged_notes[player_id]
	judged[note_key] = true
	player_judged_notes[player_id] = judged

func _get_preferred_lan_ip() -> String:
	var fallback := "127.0.0.1"
	# Passe 1 : chercher uniquement 192.168.x ou 10.x (Wi-Fi / LAN physique)
	for addr in IP.get_local_addresses():
		if addr.contains(":"): # Exclure IPv6
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
	# Passe 2 : fallback sur toute IPv4 non-loopback non-link-local non-172
	for addr in IP.get_local_addresses():
		if addr.contains(":"):
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254.") or addr.begins_with("172."):
			continue
		if fallback == "127.0.0.1":
			fallback = addr
	return fallback

func _on_start_match_pressed() -> void:
	if GameManager.is_playing:
		return
		
	# Vérification spécifique au mode Battle Royale
	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE:
		if players.size() < 1:
			_show_error("Il faut au moins 1 joueur !")
			return
	else:
		# Mode Normal : Vérification de l'équilibre des équipes
		if not _verifier_equilibrage():
			if players.size() == 0:
				_show_error("Pas assez de joueurs !")
			else:
				_show_error("Equipes desequilibrees !")
			return
		
	warmup_label.remove_theme_color_override("font_color")
	
	result_panel.visible = false
	# Réinitialiser les scores
	team_scores["Equipe1"] = 0
	team_scores["Equipe2"] = 0
	team_scores["Equipe3"] = 0
	player_judged_notes.clear()
	for player_id in players.keys():
		var player_data: Dictionary = players[player_id]
		player_data["score"] = 0
		player_data["combo"] = 0
		players[player_id] = player_data
	MultiplayerBridge.send_scoreboard(_build_player_array(), team_scores)
	_refresh_right_panel()
	_start_voting()

func _on_lobby_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_vote_update(stats: Array) -> void:
	if not is_voting: return
	
	# DEBUG : Compte les votes totaux
	var total_debug := 0
	for s in stats: total_debug += int(s.get("votes", 0))
	print("[DEBUG] GameScreen received ", stats.size(), " items. Total votes: ", total_debug)

	if stats.is_empty():
		vote_stats_label.text = "[center][color=gray]Aucun vote pour le moment[/color][/center]"
		return
		
	var text = "[center][b]CLASSEMENT ACTUEL :[/b]\n\n"
	for i in range(stats.size()):
		var entry = stats[i]
		var color = "yellow" if i == 0 else "white"
		text += "[color=%s]%d. %s - %d%%[/color]\n" % [color, i + 1, entry.songName, entry.percentage]
	
	text += "[/center]"
	vote_stats_label.text = text

func _verifier_equilibrage() -> bool:
	var team_counts := {"Equipe1": 0, "Equipe2": 0, "Equipe3": 0}
	for p_id in players:
		var p: Dictionary = players[p_id]
		var team: String = str(p.get("team", ""))
		if team_counts.has(team):
			team_counts[team] += 1
			
	var nb_actives = 0
	for count in team_counts.values():
		if count > 0:
			nb_actives += 1
			
	if nb_actives < 1:
		return false
		
	var max_s = -1
	var min_s = 9999
	for count in team_counts.values():
		if count > max_s: max_s = count
		if count < min_s: min_s = count
		
	if max_s - min_s > 2:
		return false
		
	return true

func _check_br_victory() -> void:
	if GameManager.current_mode == GameManager.GameMode.BATTLE_ROYALE and GameManager.is_playing:
		var current_alive = alive_players.size()
		
		# Cas Entraînement (Solo) : on s'arrête quand on meurt
		if initial_br_players <= 1:
			if current_alive == 0:
				print("[BR] Entrainement solo termine (Erreur).")
				GameManager.end_game()
		else:
			# Cas Compétition : le dernier gagne
			if current_alive <= 1:
				print("[BR] Victoire ! Un seul survivant.")
				GameManager.end_game()

func _show_error(message: String) -> void:
	error_label.text = message
	error_toast.visible = true
	error_toast.modulate.a = 0.0
	error_toast.position.y = -50
	
	var err_tween = create_tween()
	err_tween.set_parallel(true)
	err_tween.tween_property(error_toast, "position:y", 20.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	err_tween.tween_property(error_toast, "modulate:a", 1.0, 0.2)
	
	var seq_tween = create_tween()
	seq_tween.tween_interval(3.0)
	seq_tween.tween_property(error_toast, "modulate:a", 0.0, 0.3)
	seq_tween.chain().tween_callback(func(): error_toast.visible = false)
