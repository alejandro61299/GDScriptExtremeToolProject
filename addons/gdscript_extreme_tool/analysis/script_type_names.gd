@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExScriptLibrary = preload("res://addons/gdscript_extreme_tool/analysis/script_library.gd")

const MEMBER_ACCESS: String = "."
const MAX_INHERITANCE_DEPTH: int = 32


class GDSExPrefix:
	var is_known: bool = false
	var text: String = ""


static func name_of_class(target: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope, written_in: GDSExSymbolIndex.GDSExClassScope = null) -> String:
	var own_target := find_own_class(target, asking_class)
	var holder := own_target.parent as GDSExSymbolIndex.GDSExClassScope
	if holder == null:
		return own_target.name if _is_in_the_script_of(own_target, asking_class) else _name_of_script(own_target, asking_class, written_in)
	var prefix := _prefix_of(holder, asking_class, written_in)
	return _joined(prefix.text, own_target.name) if prefix.is_known else ""


static func name_of_enum(enum_name: String, declaring_class: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope, written_in: GDSExSymbolIndex.GDSExClassScope = null) -> String:
	var prefix := _prefix_of(find_own_class(declaring_class, asking_class), asking_class, written_in)
	return _joined(prefix.text, enum_name) if prefix.is_known else ""


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
		for candidate in class_and_bases(enclosing as GDSExSymbolIndex.GDSExClassScope):
			if candidate.inner_classes.has(type_name) or declares_enum(candidate, type_name) or loads_a_script_as(candidate, type_name):
				return candidate
		enclosing = enclosing.parent
	return null


static func find_enum_class(enum_name: String, class_scope: GDSExSymbolIndex.GDSExClassScope) -> GDSExSymbolIndex.GDSExClassScope:
	for candidate in class_and_bases(class_scope):
		if declares_enum(candidate, enum_name):
			return candidate
	return null


static func sees_names_of(asking_class: GDSExSymbolIndex.GDSExClassScope, declaring_class: GDSExSymbolIndex.GDSExClassScope) -> bool:
	var enclosing: GDSExSymbolIndex.GDSExScopeBase = asking_class
	while enclosing is GDSExSymbolIndex.GDSExClassScope:
		if class_and_bases(enclosing as GDSExSymbolIndex.GDSExClassScope).has(declaring_class):
			return true
		enclosing = enclosing.parent
	return false


static func class_and_bases(class_scope: GDSExSymbolIndex.GDSExClassScope) -> Array[GDSExSymbolIndex.GDSExClassScope]:
	var classes: Array[GDSExSymbolIndex.GDSExClassScope] = []
	var current := class_scope
	while current != null and not classes.has(current) and classes.size() < MAX_INHERITANCE_DEPTH:
		classes.append(current)
		current = find_base_class(current)
	return classes


static func find_base_class(class_scope: GDSExSymbolIndex.GDSExClassScope) -> GDSExSymbolIndex.GDSExClassScope:
	var base_path := class_scope.base_script_path
	if base_path.is_empty() and class_scope.inherit_type != null:
		var base_in_file := GDSExSymbolIndex.find_class(GDSExSymbolIndex.find_root_class(class_scope), class_scope.inherit_type.name)
		if base_in_file != null:
			return null if base_in_file == class_scope else base_in_file
		base_path = GDSExScriptLibrary.find_global_class_path(class_scope.inherit_type.name)
	var base_index := GDSExScriptLibrary.find_index(base_path)
	return null if base_index == null else base_index.root


static func declares_enum(class_scope: GDSExSymbolIndex.GDSExClassScope, enum_name: String) -> bool:
	for member in class_scope.members:
		if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.ENUM and member.name == enum_name:
			return true
	return false


static func loads_a_script_as(class_scope: GDSExSymbolIndex.GDSExClassScope, constant_name: String) -> bool:
	var constant: GDSExSymbolIndex.GDSExVariableSymbol = class_scope.vars.get(constant_name)
	return constant != null and constant.is_script_alias


static func _prefix_of(holder: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope, written_in: GDSExSymbolIndex.GDSExClassScope) -> GDSExPrefix:
	var prefix := GDSExPrefix.new()
	prefix.is_known = true
	if sees_names_of(asking_class, holder):
		return prefix
	if _is_in_the_script_of(holder, asking_class):
		prefix.text = class_path(holder)
		return prefix
	prefix.text = name_of_class(holder, asking_class, written_in)
	var heir := _find_heir(GDSExSymbolIndex.find_root_class(asking_class), holder) if prefix.text.is_empty() else null
	if heir != null:
		prefix.text = name_of_class(heir, asking_class)
	prefix.is_known = not prefix.text.is_empty()
	return prefix


static func _find_heir(class_scope: GDSExSymbolIndex.GDSExClassScope, holder: GDSExSymbolIndex.GDSExClassScope) -> GDSExSymbolIndex.GDSExClassScope:
	for inner_name: String in class_scope.inner_classes:
		var inner_class: GDSExSymbolIndex.GDSExClassScope = class_scope.inner_classes[inner_name]
		if class_and_bases(inner_class).has(holder):
			return inner_class
		var deeper_heir := _find_heir(inner_class, holder)
		if deeper_heir != null:
			return deeper_heir
	return null


static func _is_in_the_script_of(class_scope: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope) -> bool:
	return GDSExSymbolIndex.find_index(class_scope) == GDSExSymbolIndex.find_index(asking_class)


static func _joined(prefix_text: String, member_name: String) -> String:
	return member_name if prefix_text.is_empty() else prefix_text + MEMBER_ACCESS + member_name


static func _name_of_script(script_root: GDSExSymbolIndex.GDSExClassScope, asking_class: GDSExSymbolIndex.GDSExClassScope, written_in: GDSExSymbolIndex.GDSExClassScope) -> String:
	var constants := _find_visible_script_constants(asking_class)
	var direct_name := _direct_name_of_script(script_root, constants)
	var script_index := GDSExSymbolIndex.find_index(script_root)
	if not direct_name.is_empty() or script_index == null or script_index.script_path.is_empty():
		return direct_name
	var name_through_a_class := _name_through_a_class(GDSExSymbolIndex.find_root_class(asking_class), script_index.script_path)
	if not name_through_a_class.is_empty():
		return name_through_a_class
	for constant in constants:
		var reached_index := GDSExScriptLibrary.find_index(constant.script_path)
		if reached_index != null and not _is_hidden_by_a_global_class(constant):
			var constant_name := _find_constant_name(reached_index.root, script_index.script_path)
			if not constant_name.is_empty():
				return constant.name + MEMBER_ACCESS + constant_name
	var written_in_root := GDSExSymbolIndex.find_root_class(written_in) if written_in != null else null
	var written_in_name := "" if written_in_root == null else _direct_name_of_script(written_in_root, constants)
	var written_constant_name := "" if written_in_name.is_empty() else _find_constant_name(written_in_root, script_index.script_path)
	return "" if written_constant_name.is_empty() else written_in_name + MEMBER_ACCESS + written_constant_name


static func _direct_name_of_script(script_root: GDSExSymbolIndex.GDSExClassScope, constants: Array[GDSExSymbolIndex.GDSExVariableSymbol]) -> String:
	if not script_root.name.is_empty():
		return script_root.name
	var script_index := GDSExSymbolIndex.find_index(script_root)
	if script_index == null or script_index.script_path.is_empty():
		return ""
	for constant in constants:
		if constant.script_path == script_index.script_path and not _is_hidden_by_a_global_class(constant):
			return constant.name
	return ""


static func _find_constant_name(class_scope: GDSExSymbolIndex.GDSExClassScope, script_path: String) -> String:
	for constant: GDSExSymbolIndex.GDSExVariableSymbol in class_scope.vars.values():
		if constant.script_path == script_path:
			return constant.name
	return ""


static func _name_through_a_class(class_scope: GDSExSymbolIndex.GDSExClassScope, script_path: String) -> String:
	for inner_name: String in class_scope.inner_classes:
		var inner_class: GDSExSymbolIndex.GDSExClassScope = class_scope.inner_classes[inner_name]
		var constant_name := _find_constant_name(inner_class, script_path)
		if not constant_name.is_empty():
			return class_path(inner_class) + MEMBER_ACCESS + constant_name
		var deeper_name := _name_through_a_class(inner_class, script_path)
		if not deeper_name.is_empty():
			return deeper_name
	return ""


static func _is_hidden_by_a_global_class(constant: GDSExSymbolIndex.GDSExVariableSymbol) -> bool:
	var global_path := GDSExScriptLibrary.find_global_class_path(constant.name)
	return not global_path.is_empty() and global_path != constant.script_path


static func _find_visible_script_constants(asking_class: GDSExSymbolIndex.GDSExClassScope) -> Array[GDSExSymbolIndex.GDSExVariableSymbol]:
	var constants: Array[GDSExSymbolIndex.GDSExVariableSymbol] = []
	var seen_names: Dictionary[String, bool] = {}
	var enclosing: GDSExSymbolIndex.GDSExScopeBase = asking_class
	while enclosing is GDSExSymbolIndex.GDSExClassScope:
		for visible_class in class_and_bases(enclosing as GDSExSymbolIndex.GDSExClassScope):
			for member: GDSExSymbolIndex.GDSExVariableSymbol in visible_class.vars.values():
				if not seen_names.has(member.name) and not member.script_path.is_empty():
					constants.append(member)
				seen_names[member.name] = true
		enclosing = enclosing.parent
	return constants
