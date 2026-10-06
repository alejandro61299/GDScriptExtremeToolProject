extends Node


class Panchito extends RefCounted:
	

	# Comentario
	var _life : int = 0
	
	
	var time : float = 0.0
	


	func _init(p_life: int) -> void:
		_life = p_life
	
	

class PanchitoResultado extends RefCounted:
	# Comentario
	var _life : int = 0
	
	var time : float = 0.0
	
	
	func _init(p_life: int) -> void:
		_life = p_life

# Called when the node enters the scene tree for the first time.
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
