extends Node2D

@export var hit_y: float = 560.0
@export var note_spawner: NodePath

@onready var spawner: Node2D = get_node_or_null(note_spawner)

@onready var btn_blue := get_node_or_null("../HitCircleBlue")
@onready var btn_yellow := get_node_or_null("../HitCircleYellow")
@onready var btn_red := get_node_or_null("../HitCircleRed")

func _ready() -> void:
	pass

func press_button(col: int) -> void:
	match col:
		0: _try_hit(0, btn_blue)
		1: _try_hit(1, btn_yellow)
		2: _try_hit(2, btn_red)

func _try_hit(col: int, btn: Node) -> void:
	_flash_button(btn, col)

	if spawner == null:
		spawner = get_node_or_null(note_spawner)
	if spawner == null:
		return

	var notes_nearby = spawner.get_notes_near_hit(col, hit_y)
	if notes_nearby.is_empty():
		# Aucune note proche : pénalité pour clic dans le vide
		GameManager.register_empty_hit()
		return

	var closest_note = notes_nearby[0]
	var timing_error: float = abs(closest_note.position.y - hit_y) / 560.0
	var result := GameManager.register_hit(timing_error, true)
	closest_note.hit_animation(result)

func _flash_button(btn: Node, _col: int) -> void:
	if btn == null:
		return
	btn.scale = Vector2(1.0, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	# Depress animation
	tween.tween_property(btn, "scale", Vector2(0.9, 0.9), 0.05)
	# Flash animation (btn is a PanelContainer now)
	tween.tween_property(btn, "modulate:a", 2.0, 0.05)
	
	tween.chain().tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1)
	tween.parallel().tween_property(btn, "modulate:a", 1.0, 0.1)
