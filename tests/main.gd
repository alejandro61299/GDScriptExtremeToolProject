extends Node


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


func _add_method(value : Callable) -> void:
	print(value)

func extreme_nesting():
	var level_1 = func():
		var level_2 = func():
			var level_3 = func():
				return "¡Hello!"
			return level_3.call()
		return level_2.call()
	
	print(level_1.call())
