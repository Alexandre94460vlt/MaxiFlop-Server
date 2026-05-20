extends ParallaxBackground

var vitesse_defilement = 60.0 

func _process(delta):
	scroll_offset.x -= vitesse_defilement * delta
