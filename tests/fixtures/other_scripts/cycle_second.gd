extends RefCounted

const CycleFirst = preload("res://tests/fixtures/other_scripts/cycle_first.gd")

var first: CycleFirst
var second_count: int = 2


func other() -> CycleFirst:
	return first
