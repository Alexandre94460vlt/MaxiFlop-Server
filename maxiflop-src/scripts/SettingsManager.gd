extends Node

const SETTINGS_PATH = "user://settings.cfg"

# Musique en jeu (Slider 1)
var in_game_volume: float = 100.0
# Musique du menu (Slider 2)
var menu_music_volume: float = 70.0
# Plein écran
var is_fullscreen: bool = false

func _ready() -> void:
	load_settings()

func apply_settings() -> void:
	# Volumes
	var in_game_db := linear_to_db(in_game_volume / 100.0)
	var menu_music_db := linear_to_db(menu_music_volume / 100.0)
	
	var idx_in_game = AudioServer.get_bus_index("InGameMusic")
	if idx_in_game != -1:
		AudioServer.set_bus_volume_db(idx_in_game, in_game_db)
		
	var idx_menu = AudioServer.get_bus_index("MenuMusic")
	if idx_menu != -1:
		AudioServer.set_bus_volume_db(idx_menu, menu_music_db)
	
	# Fullscreen
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "in_game", in_game_volume)
	config.set_value("audio", "menu_music", menu_music_volume)
	config.set_value("display", "fullscreen", is_fullscreen)
	config.save(SETTINGS_PATH)
	apply_settings()

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	
	if err == OK:
		in_game_volume = config.get_value("audio", "in_game", 100.0)
		menu_music_volume = config.get_value("audio", "menu_music", 70.0)
		is_fullscreen = config.get_value("display", "fullscreen", false)
	
	apply_settings()

func linear_to_db(linear: float) -> float:
	if linear <= 0.0001:
		return -80.0
	return 20.0 * log(linear) / log(10.0)
