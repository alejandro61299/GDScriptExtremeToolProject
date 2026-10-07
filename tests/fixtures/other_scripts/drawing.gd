extends RefCounted

const Shapes = preload("res://tests/fixtures/other_scripts/shapes.gd")

var shapes: Shapes = Shapes.new()
var main: Shapes.Circle
var title: String = "drawing"


static func create() -> Shapes:
	return Shapes.new()


static func default_circle() -> Shapes.Circle:
	return Shapes.make()


static func default_kind() -> Shapes.Kind:
	return Shapes.Kind.SQUARE


func circles() -> Array[Shapes.Circle]:
	return Shapes.make_all(shapes.count)
