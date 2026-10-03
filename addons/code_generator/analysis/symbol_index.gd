@tool
extends RefCounted


class TypeData:
	var kind: String = "simple"
	var name: String = ""
	var base: TypeData = null
	var generics: Array[TypeData] = []


class VariableSymbol:
	var name: String = ""
	var type: TypeData
	var is_const: bool = false
	var start_line: int = 0
	var end_line: int = 0
	var value: String = ""


class SignalSymbol:
	var name: String = ""
	var params: Dictionary = {}


class DeclarationTail:
	var type: TypeData
	var value: String = ""


class ScopeBase:
	var children: Array[ScopeBase] = []
	var locals: Array[VariableSymbol] = []
	var start_line: int = 0
	var body_start_line: int = -1
	var end_line: int = 0
	var body_indent_text: String = ""
	var parent: ScopeBase:
		get:
			return _parent_reference.get_ref() as ScopeBase if _parent_reference != null else null
	var _parent_reference: WeakRef

	func attach_to(new_parent: ScopeBase) -> void:
		_parent_reference = weakref(new_parent)
		new_parent.children.append(self)

	func first_contained_line() -> int:
		return start_line

	func accepts_declarations() -> bool:
		return body_start_line != -1

	func find_local(local_name: String, before_line: int) -> VariableSymbol:
		for index in range(locals.size() - 1, -1, -1):
			var local := locals[index]
			if local.name == local_name and local.start_line < before_line:
				return local
		return null


class FunctionScope extends ScopeBase:
	var name: String = ""
	var is_lambda: bool = false
	var params: Dictionary = {}
	var return_type: TypeData
	var return_lines: PackedInt32Array = []

	func first_contained_line() -> int:
		return body_start_line if is_lambda else start_line


class BlockScope extends ScopeBase:
	enum Kind { IF, ELIF, ELSE, FOR, WHILE, MATCH, MATCH_BRANCH, PROPERTY, OTHER }

	var kind: Kind = Kind.OTHER

	func first_contained_line() -> int:
		return body_start_line

	func accepts_declarations() -> bool:
		return kind != Kind.MATCH and kind != Kind.PROPERTY


class ClassScope extends ScopeBase:
	var name: String = ""
	var vars: Dictionary = {}
	var methods: Dictionary = {}
	var signals: Dictionary = {}
	var inner_classes: Dictionary = {}
	var extends_line: int = -1
	var inherit_type: TypeData

	func accepts_declarations() -> bool:
		return false


class SymbolIndexData:
	var root: ClassScope


class ScopeInfo:
	var line: int = 0
	var scope: ScopeBase
	var class_scope: ClassScope
	var function_scope: FunctionScope


class ArgumentInfo:
	var name: String
	var type: TypeData


class FunctionSignature:
	var name: String
	var args: Array[ArgumentInfo] = []
	var return_type: TypeData
	var line: int
	var line_text: String


static func get_base_type_name(t: TypeData) -> String:
	if t == null: return ""
	return t.name if t.kind == "simple" else t.base.name

static func type_to_string(t: TypeData) -> String:
	if t == null: return ""
	if t.kind == "simple":
		return t.name

	var base = t.base.name
	var generic_strings = []
	for g in t.generics:
		generic_strings.append(type_to_string(g))

	return "%s[%s]" % [base, ", ".join(PackedStringArray(generic_strings))]

static func parse_type(text: String) -> TypeData:
	var trimmed = text.strip_edges()
	if trimmed.is_empty():
		return null
	return _parse_single_type(trimmed)

static func _parse_single_type(s: String) -> TypeData:
	var str_val = s.strip_edges()
	var first_bracket = str_val.find("[")

	if first_bracket == -1 or not str_val.ends_with("]"):
		var t = TypeData.new()
		t.kind = "simple"
		t.name = str_val
		return t

	var base_name = str_val.substr(0, first_bracket).strip_edges()
	var inner = str_val.substr(first_bracket + 1, str_val.length() - first_bracket - 2).strip_edges()
	var parts = _split_generic_args(inner)

	var generics: Array[TypeData] = []
	for p in parts:
		generics.append(_parse_single_type(p))

	var t = TypeData.new()
	t.kind = "complex"
	t.base = TypeData.new()
	t.base.kind = "simple"
	t.base.name = base_name
	t.generics = generics
	return t

static func _split_generic_args(inner: String) -> PackedStringArray:
	var result = PackedStringArray()
	var depth = 0
	var start = 0

	for i in range(inner.length()):
		var ch = inner[i]
		if ch == "[": depth += 1
		elif ch == "]": depth -= 1
		elif ch == "," and depth == 0:
			result.append(inner.substr(start, i - start).strip_edges())
			start = i + 1

	var last = inner.substr(start).strip_edges()
	if not last.is_empty():
		result.append(last)
	return result


static func split_args_respecting_brackets(text: String) -> PackedStringArray:
	var result = PackedStringArray()
	var current = ""
	var depth_paren = 0
	var depth_bracket = 0
	var depth_brace = 0
	var current_quote = ""

	for i in range(text.length()):
		var ch = text[i]

		if not current_quote.is_empty():
			current += ch
			if ch == current_quote and text[i-1] != "\\":
				current_quote = ""
			continue

		if ch == '"' or ch == "'":
			current_quote = ch
			current += ch
			continue

		match ch:
			"(":
				depth_paren += 1
				current += ch
			")":
				if depth_paren > 0: depth_paren -= 1
				current += ch
			"[":
				depth_bracket += 1
				current += ch
			"]":
				if depth_bracket > 0: depth_bracket -= 1
				current += ch
			"{":
				depth_brace += 1
				current += ch
			"}":
				if depth_brace > 0: depth_brace -= 1
				current += ch
			",":
				if depth_paren == 0 and depth_bracket == 0 and depth_brace == 0:
					var trimmed = current.strip_edges()
					if not trimmed.is_empty():
						result.append(trimmed)
					current = ""
				else:
					current += ch
			_:
				current += ch

	var last = current.strip_edges()
	if not last.is_empty():
		result.append(last)
	return result

static func infer_type_from_value(value: String) -> TypeData:
	var v = value.strip_edges()
	if v.is_empty(): return null

	if v.begins_with("func(") or v.begins_with("func "):
		var t = TypeData.new(); t.name = "Callable"; return t

	if v == "null":
		var t = TypeData.new(); t.name = "Object"; return t

	if v.begins_with("&") and (v.contains('"') or v.contains("'")):
		var t = TypeData.new(); t.name = "StringName"; return t
	if v.begins_with("^") and (v.contains('"') or v.contains("'")):
		var t = TypeData.new(); t.name = "NodePath"; return t

	if (v.begins_with('"') and v.ends_with('"')) or (v.begins_with("'") and v.ends_with("'")):
		var t = TypeData.new(); t.name = "String"; return t

	if v.is_valid_float() and ("." in v or "e" in v):
		var t = TypeData.new(); t.name = "float"; return t
	if v.is_valid_int():
		var t = TypeData.new(); t.name = "int"; return t

	if v == "true" or v == "false":
		var t = TypeData.new(); t.name = "bool"; return t

	if v.begins_with("["):
		var t = TypeData.new(); t.name = "Array"; return t
	if v.begins_with("{"):
		var t = TypeData.new(); t.name = "Dictionary"; return t

	var r = RegEx.new()
	r.compile("^([A-Za-z_][A-Za-z0-9_]*)[\\(\\.].*")
	var m = r.search(v)
	if m:
		var candidate_type = m.get_string(1)
		for i in range(TYPE_MAX):
			if type_string(i) == candidate_type:
				var t = TypeData.new(); t.name = candidate_type; return t
		if ClassDB.class_exists(candidate_type):
			var t = TypeData.new(); t.name = candidate_type; return t

	return null


static func parse_func_parameters(params_text: String) -> Dictionary:
	var result := {}
	for raw_param in split_args_respecting_brackets(params_text):
		var param := raw_param.strip_edges()
		var name_end := 0
		while name_end < param.length() and _is_identifier_character(param[name_end]):
			name_end += 1
		if name_end == 0:
			continue
		result[param.substr(0, name_end)] = parse_declaration_tail(param.substr(name_end)).type
	return result


static func parse_declaration_tail(tail: String) -> DeclarationTail:
	var result := DeclarationTail.new()
	var text := tail.strip_edges()
	var type_text := ""
	if text.begins_with(":="):
		result.value = text.substr(2).strip_edges()
	elif text.begins_with(":"):
		var assignment := _find_top_level(text, "=", 1)
		var accessor := _find_top_level(text, ":", 1)
		var type_end := text.length()
		if assignment != -1:
			type_end = assignment
		if accessor != -1 and accessor < type_end:
			type_end = accessor
		type_text = text.substr(1, type_end - 1).strip_edges()
		if assignment != -1 and assignment == type_end:
			result.value = text.substr(assignment + 1).strip_edges()
	elif text.begins_with("="):
		result.value = text.substr(1).strip_edges()
	result.type = infer_type_from_value(result.value) if type_text.is_empty() else parse_type(type_text)
	return result


static func _find_top_level(text: String, character: String, from: int) -> int:
	var depth := 0
	for index in range(from, text.length()):
		var current := text[index]
		if current == "(" or current == "[" or current == "{":
			depth += 1
		elif current == ")" or current == "]" or current == "}":
			depth -= 1
		elif current == character and depth == 0:
			return index
	return -1


static func _is_identifier_character(character: String) -> bool:
	return character == "_" or (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9")


static func resolve_type_via_classdb(_class_name: String, property_name: String) -> TypeData:
	if not ClassDB.class_exists(_class_name):
		return null

	var props = ClassDB.class_get_property_list(_class_name)
	for p in props:
		if p.name == property_name:
			var t_name = type_string(p.type)
			if p.hint == PROPERTY_HINT_RESOURCE_TYPE and not p.hint_string.is_empty():
				t_name = p.hint_string
			var t = TypeData.new(); t.name = t_name; return t

	var methods = ClassDB.class_get_method_list(_class_name)
	for m in methods:
		if m.name == property_name:
			var ret_info = m.return
			var t_name = type_string(ret_info.type)
			if ret_info.hint == PROPERTY_HINT_RESOURCE_TYPE and not ret_info.hint_string.is_empty():
				t_name = ret_info.hint_string
			elif ret_info.class_name != &"":
				t_name = String(ret_info.class_name)
			var t = TypeData.new(); t.name = t_name; return t

	var signals = ClassDB.class_get_signal_list(_class_name)
	for s in signals:
		if s.name == property_name:
			var t = TypeData.new(); t.name = "Signal"; return t

	return null

static func resolve_signal_via_classdb(_class_name: String, signal_name: String) -> Dictionary:
	if not ClassDB.class_exists(_class_name):
		return {}

	var signals = ClassDB.class_get_signal_list(_class_name)
	for s in signals:
		if s.name == signal_name:
			var result = {}
			for arg in s.args:
				var t_name = type_string(arg.type)
				if arg.class_name != &"":
					t_name = String(arg.class_name)
				var t = TypeData.new(); t.name = t_name
				result[arg.name] = t
			return result
	return {}


static func get_scope_info_for_line(index: SymbolIndexData, line: int) -> ScopeInfo:
	var info := ScopeInfo.new()
	info.line = line
	info.scope = _find_innermost_scope(index.root, line)
	var current := info.scope
	while current != null:
		if current is FunctionScope and info.function_scope == null:
			info.function_scope = current
		if current is ClassScope and info.class_scope == null:
			info.class_scope = current
		current = current.parent
	return info


static func _find_innermost_scope(scope: ScopeBase, line: int) -> ScopeBase:
	for child in scope.children:
		if line >= child.first_contained_line() and line <= child.end_line:
			return _find_innermost_scope(child, line)
	return scope


static func resolve_variable_type(name: String, scope_info: ScopeInfo) -> TypeData:
	var current := scope_info.scope
	var is_current_class := true
	while current != null:
		if current is ClassScope:
			var class_scope := current as ClassScope
			if class_scope.vars.has(name):
				var member: VariableSymbol = class_scope.vars[name]
				if member.type != null and (is_current_class or member.is_const):
					return member.type
			is_current_class = false
		else:
			if current is FunctionScope and (current as FunctionScope).params.has(name):
				return (current as FunctionScope).params[name]
			var local := current.find_local(name, scope_info.line)
			if local != null and local.type != null:
				return local.type
		current = current.parent
	return null


static func find_variable_declared_at(scope_info: ScopeInfo, line: int) -> VariableSymbol:
	var current := scope_info.scope
	while current != null:
		var candidates: Array = (current as ClassScope).vars.values() if current is ClassScope else current.locals
		for candidate: VariableSymbol in candidates:
			if line >= candidate.start_line and line <= candidate.end_line:
				return candidate
		current = current.parent
	return null


static func resolve_method_scope(class_scope: ClassScope, method_name: String) -> FunctionScope:
	if class_scope.methods.has(method_name):
		var overloads: Array = class_scope.methods[method_name]
		if not overloads.is_empty():
			return overloads[0]
	return null


static func extract_function_signature(text: String) -> FunctionSignature:
	var def_regex = RegEx.new(); def_regex.compile("func(?:\\s+(\\w+))?\\s*\\(([^)]*)\\)\\s*(?:->\\s*([^:]+))?")
	var call_regex = RegEx.new(); call_regex.compile("([A-Za-z_]\\w*)\\s*\\(([^)]*)\\)")
	var func_name = ""; var raw_args = ""; var ret: TypeData = null; var is_def = false
	var m = def_regex.search(text)
	if m:
		is_def = true; func_name = m.get_string(1); raw_args = m.get_string(2).strip_edges()
		if not m.get_string(3).is_empty(): ret = parse_type(m.get_string(3))
	else:
		m = call_regex.search(text)
		if not m: return null
		func_name = m.get_string(1); raw_args = m.get_string(2).strip_edges()

	var args: Array[ArgumentInfo] = []
	if not raw_args.is_empty():
		var parts = split_args_respecting_brackets(raw_args)
		if is_def:
			for part in parts:
				part = part.strip_edges()
				if part.is_empty(): continue
				var arg_name = ""; var arg_type: TypeData = null
				if ":" in part:
					var split1 = part.split(":", true, 1)
					arg_name = split1[0].strip_edges()
					var type_default = split1[1].split("=")
					arg_type = parse_type(type_default[0])
				else:
					var split2 = part.split("=")
					arg_name = split2[0].strip_edges()
				if not arg_name.is_empty():
					var info = ArgumentInfo.new(); info.name = arg_name; info.type = arg_type; args.append(info)
		else:
			for part in parts:
				var expr = part.strip_edges()
				if expr.is_empty(): continue
				var info = ArgumentInfo.new(); info.name = expr; info.type = null; args.append(info)

	var sig = FunctionSignature.new()
	sig.name = func_name; sig.args = args; sig.return_type = ret
	return sig


static func get_default_return_value(t: TypeData) -> String:
	var base = get_base_type_name(t)
	if base == "void":
		return ""

	for i in range(TYPE_MAX):
		if type_string(i) == base:
			var default_val = type_convert(null, i)
			if default_val != null:
				return var_to_str(default_val)
			break

	if ClassDB.class_exists(base):
		if ClassDB.can_instantiate(base):
			return "%s.new()" % base
		return "null"

	return "%s.new()" % base
