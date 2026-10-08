extends RefCounted

signal third_changed(third: ChainThird, size: float)

const ChainThird = preload("res://tests/fixtures/other_scripts/chain_third.gd")

var third: ChainThird = ChainThird.new()
var parts: Array[ChainThird] = []
var second_label: String = "second"


func make_third() -> ChainThird:
	return ChainThird.new()
