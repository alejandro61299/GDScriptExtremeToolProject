@tool
extends RefCounted

const GENERATED_PARAM_FORMAT : String = "p_{name}"
const FALLBACK_PARAM_FORMAT : String = "param_{index}"
const GENERATED_SIGNAL_CALLBACK_FORMAT : String = "_on_{name}"
const CLASS_MEMBER_ORDER : Array[String] = [
	"signals",
	"constants",
	"static_variables",
	"enums",
	"exports",
	"onready_variables",
	"public_variables",
	"private_variables",
	"inner_classes",
	"static_public_methods",
	"static_private_methods",
	"init",
	"engine_methods",
	"public_methods",
	"private_methods",
]
