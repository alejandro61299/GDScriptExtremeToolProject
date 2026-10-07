extends RefCounted

const CycleSecond = preload("res://tests/fixtures/other_scripts/cycle_second.gd")

var second: CycleSecond
var first_name: String = "first"


func other() -> CycleSecond:
	return second
