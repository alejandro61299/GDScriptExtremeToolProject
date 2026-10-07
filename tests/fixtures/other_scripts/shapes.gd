extends RefCounted

signal changed(circle: Circle, amount: int)

enum Kind { ROUND, SQUARE }

const LIMIT: int = 8

var count: int = 0
var label := "shapes"
var loose = 1
var first: Circle


class Circle:
	var radius: float = 1.0
	var center: Center
	var kind: Kind = Kind.ROUND

	func area() -> float:
		return PI * radius * radius

	func grown(amount: float) -> Circle:
		var bigger := Circle.new()
		bigger.radius = radius + amount
		return bigger


	class Center:
		var position: Vector2 = Vector2.ZERO
		var name: String = ""


static func make() -> Circle:
	return Circle.new()


static func make_all(amount: int) -> Array[Circle]:
	var circles: Array[Circle] = []
	for index in amount:
		circles.append(Circle.new())
	return circles


static func by_name() -> Dictionary[String, Circle]:
	return {}


static func kind_of(circle: Circle) -> Kind:
	return circle.kind


static func count_of(circles: Array[Circle]) -> int:
	return circles.size()


static func guess():
	return 1


func total() -> int:
	return count


func pick() -> Circle:
	return first
