extends Node
var _dic: Dictionary = { "hola" : 2 }


func _ready() -> void:
	_dic = _extracted_function_1()

func _extracted_function_1() -> Dictionary:
	return { "value" : 2 }

func _extracted_function_2() -> void:
	_dic = { "value" : 2 }
