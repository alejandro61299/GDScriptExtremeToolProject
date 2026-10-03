extends Object 

class Foo extends RefCounted:
	
	signal foo_changed_1()
	signal foo_changed_2(param_1 : Dictionary, param_2)
	
	func get_parameter_1() -> String:
		return "default"

	func set_parameters(_param_0 : Dictionary, _param_1 : Array, _param_2 : StringName) -> void:
		pass


func signals_test() -> void:
	# User defined test
	var foo : Foo = _get_foo_test(&"input_1", "input_2", [1, 0], {}, null)
	var dict : Dictionary = _get_dict()
	foo.foo_changed_1.connect(_on_foo_changed_1)
	foo.foo_changed_2.connect(_on_foo_changed_2)
	# Godot defined test
	var animation_player : AnimationPlayer = AnimationPlayer.new()
	animation_player.animation_changed.connect(_on_animation_changed)
	animation_player.animation_changed.emit(_get_signal_param_0(), _get_signal_param_1())


func _get_dict() -> Dictionary:
	return {}


# ---------------------- DELETE START -------------------------
func _get_foo_test(_param_0: StringName, _param_1: String, _param_2: Array, _param_3: Dictionary, _null: Object) -> Foo:
	return Foo.new()


func _on_foo_changed_1() -> void:
	pass


func _on_foo_changed_2(_param_1: Dictionary, _param_2) -> void:
	pass


func _on_animation_changed(_old_name: StringName, _new_name: StringName) -> void:
	pass


func _get_signal_param_0() -> StringName:
	return &""


func _get_signal_param_1() -> StringName:
	return &""
# ----------------------- DELETE END --------------------------

const CONST_1 : Node = null
const CONST_2 : int = 1

var my_var_1 : Dictionary = {}

class EmptyClass: 
	extends Object
# ---------------------- DELETE START -------------------------
	func new_method_1(_const_1: Node, _my_var_1: Dictionary) -> void:
		pass


	func new_method_2() -> Dictionary[int, Node]:
		return {}


	func get_vector(_const_2: int) -> Vector2:
		return Vector2(0, 0)
# ----------------------- DELETE END --------------------------

func other_class_test() -> void:
	var empty_class : EmptyClass = EmptyClass.new()
	empty_class.new_method_1(CONST_1, my_var_1)
	var dict : Dictionary[int, Node] = empty_class.new_method_2()
	var vector : Vector2 = empty_class.get_vector(CONST_2)


func root_class_text() -> void:
	new_method_1(CONST_2, my_var_1)
	var dict : Dictionary[int, StringName] = new_method_2()
	var vector : Quaternion = get_quaternion(CONST_1)

# ---------------------- DELETE START -------------------------
func new_method_1(_const_2: int, _my_var_1: Dictionary) -> void:
	pass


func new_method_2() -> Dictionary[int, StringName]:
	return {}


func get_quaternion(_const_1: Node) -> Quaternion:
	return Quaternion(0, 0, 0, 1)
# ----------------------- DELETE END --------------------------


func differenes_test() -> void:
	var node : Control = Control.new()
	var lol : int = _new_get_int_method_test()
	_new_method_test(node.has_focus())
	_new_method_test_callable(node.has_focus)
	node.visibility_changed.connect(_on_visibility_changed)
	node.visibility_changed.connect(_on_visibility_changed_1())


# ---------------------- DELETE START -------------------------
func _new_get_int_method_test() -> int:
	return 0


func _on_visibility_changed_1() -> Callable:
	return Callable()


func _new_method_test(_param_0: bool) -> void:
	pass


func _new_method_test_callable(_param_0: Callable) -> void:
	pass


func _on_visibility_changed() -> void:
	pass
# ----------------------- DELETE END --------------------------
