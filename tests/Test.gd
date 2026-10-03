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

var _one_line_dict : Dictionary = {"Dictionaru" : 2, "Hello" : 3}

# Dictionaryyyy
# With several keys
var _multiline_1 : Dictionary = {
	"Dictionaru" : 2,
	"Hello" : 3,
}

var _multiline_2 : Dictionary = {
	"Dictionaru" : 2,
	"Hello" : 3,
}

var _multiline_3 : Dictionary = {
	"Dictionaru" : 2,
	"Hello" : 3,
}


class Propietario extends  RefCounted:
	func _init() -> void:
		var my_callable : Callable = 	func(x):
			var local : int = 2
			var a : int = 4
			return a


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
