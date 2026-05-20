extends Node

signal score_changed(new_score: int)
signal combo_changed(new_combo: int)
signal note_hit(result: String)
signal game_started
signal game_over
signal global_note_missed(color: int, spawn_time: float)

const SCORE_PERFECT := 10
const SCORE_GOOD := 5
const SCORE_BAD := 1
const SCORE_MISS := 0
const PENALTY_EMPTY := 5

const WINDOW_PERFECT := 0.05
const WINDOW_GOOD := 0.15
const WINDOW_BAD := 0.25
enum GameMode { NORMAL, BATTLE_ROYALE }
var current_mode: GameMode = GameMode.NORMAL

var score: int = 0
var combo: int = 0
var max_combo: int = 0
var perfect_streak: int = 0
var multiplier: float = 1.0
var is_playing: bool = false

func _ready() -> void:
	pass

func start_game() -> void:
	score = 0
	combo = 0
	max_combo = 0
	perfect_streak = 0
	multiplier = 1.0
	is_playing = true
	emit_signal("game_started")

func register_hit(timing_error: float, correct_color: bool) -> String:
	if not correct_color:
		register_miss()
		return "MISS"

	var result := ""
	var points := 0

	if timing_error <= WINDOW_PERFECT:
		result = "PERFECT"
		points = SCORE_PERFECT + (perfect_streak * 3)
		perfect_streak += 1
	elif timing_error <= WINDOW_GOOD:
		result = "GOOD"
		points = SCORE_GOOD
		perfect_streak = 0
	elif timing_error <= WINDOW_BAD:
		result = "BAD"
		points = SCORE_BAD
		perfect_streak = 0
	else:
		register_miss()
		return "MISS"

	combo += 1
	if combo > max_combo:
		max_combo = combo
		
	# On garde la variable multiplier pour la logique visuelle UI s'il y en a, 
	# mais elle n'affecte plus les points.
	if combo >= 20:
		multiplier = 4.0
	elif combo >= 10:
		multiplier = 3.0
	elif combo >= 5:
		multiplier = 2.0
	else:
		multiplier = 1.0

	var final_points := points
	score += final_points

	emit_signal("score_changed", score)
	emit_signal("combo_changed", combo)
	emit_signal("note_hit", result)
	return result

func register_miss() -> void:
	combo = 0
	perfect_streak = 0
	multiplier = 1.0
	emit_signal("combo_changed", combo)
	emit_signal("note_hit", "MISS")

func register_empty_hit() -> void:
	# Pénalité pour avoir cliqué dans le vide
	score = maxi(0, score - PENALTY_EMPTY)
	combo = 0
	perfect_streak = 0
	multiplier = 1.0
	emit_signal("score_changed", score)
	emit_signal("combo_changed", combo)

func end_game() -> void:
	is_playing = false
	emit_signal("game_over")

func get_multiplier_threshold() -> int:
	if combo >= 20: return 20
	elif combo >= 10: return 10
	elif combo >= 5: return 5
	return 0
