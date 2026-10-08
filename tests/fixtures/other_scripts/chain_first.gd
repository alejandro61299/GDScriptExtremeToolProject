extends RefCounted

const ChainSecond = preload("res://tests/fixtures/other_scripts/chain_second.gd")

var second: ChainSecond = ChainSecond.new()
var first_count: int = 1
