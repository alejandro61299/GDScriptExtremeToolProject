extends RefCounted

signal base_changed(tool: Tool, circle: Shapes.Circle)

enum Mode { OFF, ON }

const Shapes = preload("res://tests/fixtures/other_scripts/shapes.gd")
const Drawing = preload("drawing.gd")

var base_circle: Shapes.Circle
var base_name: String = "base"
var base_mode: Mode = Mode.OFF
var base_tool: Tool
var base_loose = 1


class Tool:
	var power: float = 2.0


func base_kind() -> Shapes.Kind:
	return Shapes.Kind.ROUND


func base_made() -> Shapes.Circle:
	return Shapes.make()


func make_tool() -> Tool:
	return Tool.new()


func base_tools() -> Array[Tool]:
	return []


func base_guess():
	return 1
