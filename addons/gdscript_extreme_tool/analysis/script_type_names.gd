@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExScriptLibrary = preload("res://addons/gdscript_extreme_tool/analysis/script_library.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const MEMBER_ACCESS: String = "."
const MAX_INHERITANCE_DEPTH: int = 32


static func name_of_class(target: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope) -> String:
	var own_target := find_own_class(target, asking_class)
	if GDSExSymbolIndex.find_index(own_target) == GDSExSymbolIndex.find_index(asking_class):
		return _name_in_the_same_script(own_target, asking_class)
	var script_name := _name_of_script(GDSExSymbolIndex.find_root_class(target), asking_class)
	var inner_path := class_path(target)
	if script_name.is_empty() or inner_path.is_empty():
		return script_name
	return script_name + MEMBER_ACCESS + inner_path


static func name_of_enum(enum_name: String, declaring_class: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope) -> String:
	var own_class := find_own_class(declaring_class, asking_class)
	var is_own := GDSExSymbolIndex.find_index(own_class) == GDSExSymbolIndex.find_index(asking_class)
	if is_own and (own_class.parent == null or sees_names_of(asking_class, own_class)):
		return enum_name
	var class_name_text := class_path(own_class) if is_own else name_of_class(declaring_class, asking_class)
	return "" if class_name_text.is_empty() else class_name_text + MEMBER_ACCESS + enum_name


static func find_own_class(target: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope) -> GDSExSymbolIndex.GDSExClassScope:
	var target_index := GDSExSymbolIndex.find_index(target)
	var asking_index := GDSExSymbolIndex.find_index(asking_class)
	if target_index == null or asking_index == null or target_index == asking_index:
		return target
	if asking_index.script_path.is_empty() or target_index.script_path != asking_index.script_path:
		return target
	var own_class := asking_index.root
	for inner_name in class_path(target).split(MEMBER_ACCESS, false):
		own_class = own_class.inner_classes.get(inner_name)
		if own_class == null:
			return target
	return own_class


static func class_path(class_scope: GDSExSymbolIndex.GDSExClassScope) -> String:
	var names := PackedStringArray()
	var current: GDSExSymbolIndex.GDSExScopeBase = class_scope
	while current != null and current.parent != null:
		names.insert(0, (current as GDSExSymbolIndex.GDSExClassScope).name)
		current = current.parent
	return MEMBER_ACCESS.join(names)


static func find_declaring_class(type_name: String, class_scope: GDSExSymbolIndex.GDSExClassScope) -> GDSExSymbolIndex.GDSExClassScope:
	var enclosing: GDSExSymbolIndex.GDSExScopeBase = class_scope
	while enclosing is GDSExSymbolIndex.GDSExClassScope:
		for candidate in class_and_bases_in_file(enclosing as GDSExSymbolIndex.GDSExClassScope):
			if candidate.inner_classes.has(type_name) or declares_enum(candidate, type_name) or _loads_a_script_as(candidate, type_name):
				return candidate
		enclosing = enclosing.parent
	return null


static func find_enum_class(enum_name: String, class_scope: GDSExSymbolIndex.GDSExClassScope) -> GDSExSymbolIndex.GDSExClassScope:
	for candidate in class_and_bases_in_file(class_scope):
		if declares_enum(candidate, enum_name):
			return candidate
	return null


static func sees_names_of(asking_class: GDSExSymbolIndex.GDSExClassScope, declaring_class: GDSExSymbolIndex.GDSExClassScope) -> bool:
	var enclosing: GDSExSymbolIndex.GDSExScopeBase = asking_class
	while enclosing is GDSExSymbolIndex.GDSExClassScope:
		if class_and_bases_in_file(enclosing as GDSExSymbolIndex.GDSExClassScope).has(declaring_class):
			return true
		enclosing = enclosing.parent
	return false


static func class_and_bases_in_file(class_scope: GDSExSymbolIndex.GDSExClassScope) -> Array[GDSExSymbolIndex.GDSExClassScope]:
	var classes: Array[GDSExSymbolIndex.GDSExClassScope] = []
	var root := GDSExSymbolIndex.find_root_class(class_scope)
	var current := class_scope
	while current != null and not classes.has(current):
		classes.append(current)
		var has_base_in_file := current.base_script_path.is_empty() and current.inherit_type != null
		current = GDSExSymbolIndex.find_class(root, current.inherit_type.name) if has_base_in_file else null
	return classes


static func declares_enum(class_scope: GDSExSymbolIndex.GDSExClassScope, enum_name: String) -> bool:
	for member in class_scope.members:
		if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.ENUM and member.name == enum_name:
			return true
	return false


static func _loads_a_script_as(class_scope: GDSExSymbolIndex.GDSExClassScope, constant_name: String) -> bool:
	var constant: GDSExSymbolIndex.GDSExVariableSymbol = class_scope.vars.get(constant_name)
	return constant != null and constant.is_script_alias


static func _name_in_the_same_script(target: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope) -> String:
	var declaring_class := target.parent as GDSExSymbolIndex.GDSExClassScope
	if declaring_class == null or declaring_class.parent == null or sees_names_of(asking_class, declaring_class):
		return target.name
	return class_path(target)


static func _name_of_script(script_root: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope) -> String:
	if not script_root.name.is_empty():
		return script_root.name
	var script_index := GDSExSymbolIndex.find_index(script_root)
	if script_index == null or script_index.script_path.is_empty():
		return ""
	var constants := _find_visible_script_constants(asking_class)
	for constant in constants:
		if constant.script_path == script_index.script_path and not _is_hidden_by_a_global_class(constant):
			return constant.name
	var name_through_a_class := _name_through_a_class(GDSExSymbolIndex.find_root_class(asking_class), script_index.script_path)
	if not name_through_a_class.is_empty():
		return name_through_a_class
	for constant in constants:
		var reached_index := GDSExScriptLibrary.find_index(constant.script_path)
		if reached_index == null or _is_hidden_by_a_global_class(constant):
			continue
		for inner_constant: GDSExSymbolIndex.GDSExVariableSymbol in reached_index.root.vars.values():
			if inner_constant.script_path == script_index.script_path:
				return constant.name + MEMBER_ACCESS + inner_constant.name
	return ""


static func _name_through_a_class(class_scope: GDSExSymbolIndex.GDSExClassScope, script_path: String) -> String:
	for inner_name: String in class_scope.inner_classes:
		var inner_class: GDSExSymbolIndex.GDSExClassScope = class_scope.inner_classes[inner_name]
		for constant: GDSExSymbolIndex.GDSExVariableSymbol in inner_class.vars.values():
			if constant.script_path == script_path:
				return class_path(inner_class) + MEMBER_ACCESS + constant.name
		var deeper_name := _name_through_a_class(inner_class, script_path)
		if not deeper_name.is_empty():
			return deeper_name
	return ""


static func _is_hidden_by_a_global_class(constant: GDSExSymbolIndex.GDSExVariableSymbol) -> bool:
	var global_path := GDSExLanguage.global_class_path(constant.name)
	return not global_path.is_empty() and global_path != constant.script_path


static func _find_visible_script_constants(asking_class: GDSExSymbolIndex.GDSExClassScope) -> Array[GDSExSymbolIndex.GDSExVariableSymbol]:
	var constants: Array[GDSExSymbolIndex.GDSExVariableSymbol] = []
	var seen_names: Dictionary[String, bool] = {}
	var enclosing: GDSExSymbolIndex.GDSExScopeBase = asking_class
	while enclosing is GDSExSymbolIndex.GDSExClassScope:
		var current := enclosing as GDSExSymbolIndex.GDSExClassScope
		for depth in MAX_INHERITANCE_DEPTH:
			if current == null:
				break
			for member: GDSExSymbolIndex.GDSExVariableSymbol in current.vars.values():
				if not seen_names.has(member.name) and not member.script_path.is_empty():
					constants.append(member)
				seen_names[member.name] = true
			current = _find_base_class(current)
		enclosing = enclosing.parent
	return constants


static func _find_base_class(class_scope: GDSExSymbolIndex.GDSExClassScope) -> GDSExSymbolIndex.GDSExClassScope:
	var base_path := class_scope.base_script_path
	if base_path.is_empty() and class_scope.inherit_type != null:
		var base_in_file := GDSExSymbolIndex.find_class(GDSExSymbolIndex.find_root_class(class_scope), class_scope.inherit_type.name)
		if base_in_file != null:
			return null if base_in_file == class_scope else base_in_file
		base_path = GDSExLanguage.global_class_path(class_scope.inherit_type.name)
	var base_index := GDSExScriptLibrary.find_index(base_path)
	return null if base_index == null else base_index.root
