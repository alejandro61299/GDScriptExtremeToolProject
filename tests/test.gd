extends Node

var pepe: Array = []

var array_in_line_1 : Array = [ 1 , 	2, 3	, 	4, 		5	,]
var array_in_line_2 : Array = [1, 3, 4, 5]

var array_multiline_1 : Array = 	[
		
			1 ,
		3, 
	
	4  
		
	]
var array_multiline_2 : Array = [
	1,
	3,
	4,
]

var dict_inline_1 : Dictionary = {"Name" :	 "Bob", "Age" : 	27	,}
var dict_inline_2 : Dictionary = {"Name" : "Bob", "Age" : 27}

var dict_multiline_1 = {
	# Comentario
		"Name"	: "Bob",
				# Comentario 2
			"Age":	 27,
			
		"Job": "	Mechanic"	
		
	}
var dict_multiline_2 = {
	# Comentario
	"Name": "Bob",
	# Comentario 2
	"Age": 27,
	"Job": "Mechanic",
}

enum EnumInline1 {OPTION_1,	 OPTION_2,	 OPTION_3,}
enum EnumInline2 {  OPTION_1,	  OPTION_2,		 OPTION_3}

enum EnumMultiline1 		{
	
			# Comentario
		
		OPTION_1,
	
# Comentario 2
	OPTION_2,
	
			OPTION_3,
	}
enum EnumMultiline2 {
	# Comentario
	OPTION_1,
	# Comentario 2
	OPTION_2,
	OPTION_3,
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_addd(pepe)


func _addd(p_pepe : Array) -> void:
	pass
