extends RefCounted

const CycleSecond = preload("res://tests/fixtures/other_scripts/cycle_second.gd")

var second: CycleSecond
var first_name: String = "first"


class Item:
	var weight: float = 1.0


func other() -> CycleSecond:
	return second
