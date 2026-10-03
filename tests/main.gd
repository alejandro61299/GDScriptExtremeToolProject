class_name MainTest extends Node

signal my_signal(array : Array[int])


	
func _test_methods() -> void:
	var nested_method = func(value: bool) -> float:
		value = !value
		return value
	# Add lambda / anonymous method.
	_add_method(func():
		var a = 10
		var b = 20
		return a + b
	)
	# Add nested method
	_add_method(nested_method)


func _add_method(p_nested_method: Callable) -> void:
	pass


func extreme_nesting():
	var level_1 = func():
		var level_2 = func():
			var level_3 = func():
				return "¡Hello!"
			return level_3.call()
		return level_2.call()
	hola(level_1.call())
	print(level_1.call())


func hola(param_0: String) -> void:
	pass
