extends "res://tests/fixtures/other_scripts/base_with_aliases.gd"

var derived_count: int = 2


func derived_tool() -> Tool:
	return make_tool()


func derived_mode() -> Mode:
	return base_mode
