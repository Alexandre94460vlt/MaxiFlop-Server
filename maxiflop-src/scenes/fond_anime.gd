extends ParallaxBackground

# Tu peux modifier cette valeur pour accélérer ou ralentir le défilement global
var vitesse_defilement = 60.0 

func _process(delta):
	# Décale l'arrière-plan vers la gauche en continu
	scroll_offset.x -= vitesse_defilement * delta
