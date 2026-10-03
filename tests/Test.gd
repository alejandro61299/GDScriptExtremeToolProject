# Clase que hace cosas

extends Node

# Mamawebazoo
@export var main_test : MainTest = null

# AAAA
var a : int = 1
# Bdas
var b : int  = 2
# CCCC
var c : int = a + b


class Propietario extends  RefCounted:
	func _init() -> void:
		pass


# Clase
class Panchito extends RefCounted:
	# Signal
	signal panchito_debasted(data : Dictionary[Propietario, int])


	func _init() -> void:
		panchito_debasted.connect(_on_panchito_debasted)


	func _on_panchito_debasted(p_data: Dictionary[Propietario, int]) -> void:
		pass

	# Final de la clase


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	main_test.my_signal.connect(_on_my_signal)


func _on_panchito_debasted(p_data: Dictionary[Propietario, int]) -> void:
	pass


func _on_my_signal(p_array: Array[int]) -> void:
	var panchito : Panchito = Panchito.new()
	panchito.panchito_debasted.connect(_on_panchito_debasted)
# Se acabó la clase
