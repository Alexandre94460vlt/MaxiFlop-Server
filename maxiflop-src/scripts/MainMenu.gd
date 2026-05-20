extends Node2D

@onready var title_label: Label = $TitleLabel
@onready var start_button: Button = $StartButton
@onready var settings_button: Button = $SettingsButton
@onready var quit_button: Button = $QuitButton

@onready var mode_selection: VBoxContainer = $ModeSelection

func _ready() -> void:
	title_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(title_label, "modulate:a", 1.0, 0.8)
	
	start_button.modulate.a = 0.0
	settings_button.modulate.a = 0.0
	quit_button.modulate.a = 0.0
	mode_selection.modulate.a = 0.0
	mode_selection.visible = false

	await get_tree().create_timer(0.6).timeout
	var t2 := create_tween()
	t2.tween_property(start_button, "modulate:a", 1.0, 0.2)
	t2.tween_property(settings_button, "modulate:a", 1.0, 0.2)
	t2.tween_property(quit_button, "modulate:a", 1.0, 0.2)
	
	MusicManager.play_menu_music()

func _on_start_pressed() -> void:
	# Masquer les boutons principaux et montrer la sélection de mode
	start_button.visible = false
	settings_button.visible = false
	quit_button.visible = false
	
	mode_selection.visible = true
	var tween = create_tween()
	tween.tween_property(mode_selection, "modulate:a", 1.0, 0.3)

func _on_normal_mode_selected() -> void:
	GameManager.current_mode = GameManager.GameMode.NORMAL
	_transition_to_game()

func _on_br_mode_selected() -> void:
	GameManager.current_mode = GameManager.GameMode.BATTLE_ROYALE
	_transition_to_game()

func _on_back_from_modes_pressed() -> void:
	mode_selection.visible = false
	mode_selection.modulate.a = 0.0
	start_button.visible = true
	settings_button.visible = true
	quit_button.visible = true

func _transition_to_game() -> void:
	var tween := create_tween()
	tween.tween_property(self , "modulate:a", 0.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/GameScreen.tscn")

func _on_settings_pressed() -> void:
	var tween := create_tween()
	tween.tween_property(self , "modulate:a", 0.0, 0.2)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/SettingsMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _process(_delta: float) -> void:
	# Effet de rebond fluide basé sur le BPM (progression du beat)
	var prog = MusicManager.get_beat_progress()
	
	# Création d'une courbe de rebond fluide (0 -> 1 -> 0 sur un beat)
	var bounce = sin(prog * PI)
	var target_scale = 1.0 + (bounce * 0.15)
	
	# Application directe pour une fluidité maximale indexée sur le son
	title_label.scale = Vector2.ONE * target_scale
