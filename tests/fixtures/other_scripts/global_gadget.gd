class_name GDSExTestGadget
extends RefCounted

enum Size { SMALL, BIG }

const Shapes = preload("res://tests/fixtures/other_scripts/shapes.gd")
const LIMIT: int = 5

var weight: float = 1.0
var size: Size = Size.SMALL
var part: Part
var loose = 2


class Part:
	var length: int = 3


static func create() -> GDSExTestGadget:
	return GDSExTestGadget.new()


static func make_part() -> Part:
	return Part.new()


static func circle() -> Shapes.Circle:
	return Shapes.make()


static func guess():
	return 1


func parts() -> Array[Part]:
	return []
