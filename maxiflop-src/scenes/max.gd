extends AnimatedSprite2D

@export var vitesse = 100.0  
@export var direction = 1    

func _process(delta):
	# Fait avancer le blob
	position.x += vitesse * direction * delta
	
	# Si le blob sort de l'écran à droite, il revient à gauche
	if position.x > 1300:
		position.x = -100
	# S'il sort à gauche, il revient à droite
	elif position.x < -100:
		position.x = 1300
