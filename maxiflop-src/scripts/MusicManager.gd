extends Node

var music_player: AudioStreamPlayer
var menu_music = preload("res://assets/Chuckyy x Skrilla - Just Dance.mp3")
var bpm: float = 144.0

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	if menu_music is AudioStreamMP3:
		menu_music.loop = true
	music_player.stream = menu_music
	music_player.bus = "MenuMusic"
	add_child(music_player)
	
	music_player.volume_db = -80.0
	play_menu_music()

func play_menu_music() -> void:
	if not music_player.playing:
		music_player.play()
	fade_in()

func fade_in(duration: float = 2.0) -> void:
	var tween = create_tween()
	tween.tween_property(music_player, "volume_db", -15.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func fade_out(duration: float = 2.0) -> void:
	var tween = create_tween()
	tween.tween_property(music_player, "volume_db", -80.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func(): music_player.stop())

func get_beat_progress() -> float:
	if not music_player.playing:
		return 0.0
	
	# Temps écoulé dans le morceau
	var time = music_player.get_playback_position()
	# Nombre de battements par seconde
	var bps = bpm / 60.0
	# Position dans le temps convertie en progression de beat (0.0 à 1.0)
	var total_beats = time * bps
	return fmod(total_beats, 1.0)
