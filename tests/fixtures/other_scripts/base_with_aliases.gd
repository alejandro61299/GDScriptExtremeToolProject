extends RefCounted

const Shapes = preload("res://tests/fixtures/other_scripts/shapes.gd")
const Drawing = preload("drawing.gd")

var base_circle: Shapes.Circle
var base_name: String = "base"


func base_kind() -> Shapes.Kind:
	return Shapes.Kind.ROUND


func base_made() -> Shapes.Circle:
	return Shapes.make()
