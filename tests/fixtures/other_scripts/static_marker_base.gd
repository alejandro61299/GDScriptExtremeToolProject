extends Node

static var marker: int = _mark()


static func _mark() -> int:
	Engine.set_meta("gdsex_fixture_static_value_ran", true)
	return 1


func base_speed() -> float:
	return 1.0
