extends ParallaxBackground

@export var vitesse_defilement : float = 150.0 

func _process(delta):
	scroll_offset.y += vitesse_defilement * delta
