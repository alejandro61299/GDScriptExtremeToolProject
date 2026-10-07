extends Node

var _dic: = { "hola" : 2 }
var _valu_1 : = []


func _ready() -> void:
	extracted_function()


func extracted_function() -> void:
	var adasdas : = true
	_dic = { "value" : 2 }


func initialize(p_dic: Dictionary, p_valu_1: Array) -> void:
	_dic = p_dic
	_valu_1 = p_valu_1
