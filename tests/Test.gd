extends Node

@export var main_test : MainTest = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	main_test.my_signal.connect(_on_my_signal)


func _on_my_signal(p_array: Array[int]) -> void:
	var panchito : Panchito = Panchito.new()
	panchito.panchito_debasted.connect(_on_panchito_debasted)
	

func _on_panchito_debasted(p_data: Dictionary[Propietario, int]) -> void:
	pass


class Propietario extends  RefCounted:
	func _init() -> void:
		pass


class Panchito extends RefCounted:
	signal panchito_debasted(data : Dictionary[Propietario, int])
	
	func _init() -> void:
		panchito_debasted.connect(_on_panchito_debasted)


	func _on_panchito_debasted(p_data: Dictionary[Propietario, int]) -> void:
		pass
