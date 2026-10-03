@tool
extends RefCounted

# ----------------- Data Structures -----------------

class TypeData:
	var kind: String = "simple" # "simple" | "complex"
	var name: String = ""
	var base: TypeData = null
	var generics: Array[TypeData] = []

class VarScope:
	var name: String
	var type: TypeData
	var is_const: bool
	var is_private: bool
	var start_line: int
	var end_line: int
	var value: String

class SignalScope:
	var name: String
	var params: Dictionary = {} # name: TypeData

# Base class for all scopes
class ScopeBase:
	var parent: ScopeBase = null
	var children: Array[ScopeBase] = []
	var start_line: int = 0
	var end_line: int = 0
	
	func _init(p_parent: ScopeBase = null, p_start: int = 0):
		parent = p_parent
		start_line = p_start
		end_line = p_start
		if parent:
			parent.children.append(self)

class MethodScope extends ScopeBase:
	var name: String = ""
	var params: Dictionary = {}
	var locals: Dictionary = {}
	var return_type: TypeData
	var return_line: int = -1

class ClassScope extends ScopeBase:
	var name: String = ""
	var vars: Dictionary = {}
	var methods: Dictionary = {}
	var signals: Dictionary = {}
	var inner_classes: Dictionary = {}
	var extends_line: int = -1
	var inherit_type: TypeData
	var indent_count: int = 0

class SymbolIndexData:
	var root: ClassScope
	var classes_by_name: Dictionary = {}

class ScopeInfo:
	var scope: ScopeBase
	var class_scope: ClassScope
	var method_scope: MethodScope

class ArgumentInfo:
	var name: String
	var type: TypeData

class FunctionSignature:
	var name: String
	var args: Array[ArgumentInfo] = []
	var return_type: TypeData
	var line: int
	var line_text: String

# ----------------- Static API -----------------

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

# ----------------- Parsing Helpers -----------------

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
		
	# Constructor check
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
	var result = {}
	if params_text.strip_edges().is_empty():
		return result
		
	var raw_params = split_args_respecting_brackets(params_text)
	for raw in raw_params:
		var param = raw.strip_edges()
		if param.is_empty(): continue
		
		var parts = param.split("=")
		var left = parts[0].strip_edges()
		var right = ""
		if parts.size() > 1:
			right = parts[1].strip_edges()
			
		if left.is_empty(): continue
		
		var colon_idx = left.find(":")
		if colon_idx != -1:
			var name = left.substr(0, colon_idx).strip_edges()
			var typ_text = left.substr(colon_idx + 1).strip_edges()
			var t = parse_type(typ_text)
			if t: result[name] = t
			continue
			
		if not right.is_empty():
			var name = left
			var inferred = infer_type_from_value(right)
			if inferred: result[name] = inferred
		else:
			result[left] = null
			
	return result

# ----------------- ClassDB Fallback -----------------

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

# ----------------- Main Build Logic -----------------

static func build_symbol_index(lines: PackedStringArray) -> SymbolIndexData:
	var root_class = ClassScope.new(null, 0)
	var classes_by_name = {}
	
	var regex_class_name = RegEx.new(); regex_class_name.compile("^\\s*class_name\\s+(\\w+)")
	var regex_inner_class = RegEx.new(); regex_inner_class.compile("^\\s*class\\s+(\\w+)(?:\\s+extends\\s+([A-Za-z_]\\w*))?\\s*:")
	var regex_func = RegEx.new(); regex_func.compile("func(?:\\s+(\\w+))?\\s*\\(([^)]*)\\)\\s*(?:->\\s*([^:]+))?")
	var regex_signal = RegEx.new(); regex_signal.compile("^\\s*signal\\s+(\\w+)(?:\\s*\\(([^)]*)\\))?")
	var regex_extends = RegEx.new(); regex_extends.compile("^\\s*extends\\b")
	var regex_extends_extract = RegEx.new(); regex_extends_extract.compile("^\\s*extends\\s+([A-Za-z_]\\w*)")
	
	var r_var_typed_init = RegEx.new(); r_var_typed_init.compile("\\bvar\\s+(\\w+)\\s*:\\s*([^=]+?)\\s*=\\s*(.+)")
	var r_var_typed_no_init = RegEx.new(); r_var_typed_no_init.compile("\\bvar\\s+(\\w+)\\s*:\\s*([^\\s=]+)")
	var r_var_inferred = RegEx.new(); r_var_inferred.compile("\\bvar\\s+(\\w+)\\s*=\\s*(.+)")
	
	var r_const_typed_init = RegEx.new(); r_const_typed_init.compile("\\bconst\\s+(\\w+)\\s*:\\s*([^=]+?)\\s*=\\s*(.+)")
	var r_const_typed_no_init = RegEx.new(); r_const_typed_no_init.compile("\\bconst\\s+(\\w+)\\s*:\\s*([^\\s=]+)")
	var r_const_inferred = RegEx.new(); r_const_inferred.compile("\\bconst\\s+(\\w+)\\s*=\\s*(.+)")

	var context_stack = []
	context_stack.append({ "scope": root_class, "indent": -1 })
	var get_current = func(): return context_stack.back()
	var method_body_last_line = {}
	
	for line_index in range(lines.size()):
		var line = lines[line_index]
		var trimmed = line.strip_edges()
		
		var indent_match = RegEx.new(); indent_match.compile("^\\s*")
		var im = indent_match.search(line)
		var indent = 0
		if im: indent = im.get_string().length()
		
		var is_structural = trimmed.length() > 0 and not trimmed.begins_with("#")
		
		var current_ctx_before = get_current.call()
		var scope_before = current_ctx_before.scope
		
		if scope_before is MethodScope:
			var ms = scope_before as MethodScope
			var method_indent = current_ctx_before.indent
			if is_structural and indent > method_indent:
				method_body_last_line[ms] = line_index
				var r_ret = RegEx.new(); r_ret.compile("^\\s*return\\b")
				if r_ret.search(line) and ms.return_line == -1:
					ms.return_line = line_index
					
		if is_structural:
			while context_stack.size() > 1 and indent <= context_stack.back().indent:
				var ctx = context_stack.pop_back()
				var closing_scope = ctx.scope
				if closing_scope is MethodScope:
					var ms = closing_scope as MethodScope
					var body_end = -1
					if method_body_last_line.has(ms): body_end = method_body_last_line[ms]
					ms.end_line = body_end if body_end != -1 else ms.start_line
				else:
					closing_scope.end_line = line_index - 1
		
		var current_ctx = get_current.call()
		var current_scope = current_ctx.scope
		
		if regex_extends.search(line) and current_scope is ClassScope and current_scope.extends_line == -1:
			current_scope.extends_line = line_index
			var match_ext = regex_extends_extract.search(line)
			if match_ext: current_scope.inherit_type = parse_type(match_ext.get_string(1))
		
		var cn_match = regex_class_name.search(line)
		if cn_match and current_scope == root_class:
			root_class.name = cn_match.get_string(1)
			classes_by_name[root_class.name] = root_class
			continue
			
		var ic_match = regex_inner_class.search(line)
		if ic_match:
			var name = ic_match.get_string(1)
			var parent_name = ic_match.get_string(2)
			var new_class = ClassScope.new(current_scope, line_index)
			new_class.name = name
			new_class.indent_count = indent + 1
			if not parent_name.is_empty():
				new_class.extends_line = line_index
				new_class.inherit_type = parse_type(parent_name)
			if current_scope is ClassScope:
				current_scope.inner_classes[name] = new_class
			classes_by_name[name] = new_class
			context_stack.append({ "scope": new_class, "indent": indent })
			continue
			
		var func_match = regex_func.search(line)
		if func_match:
			var method_name = func_match.get_string(1) 
			var params_text = func_match.get_string(2)
			var ret_text = func_match.get_string(3)
			var ms = MethodScope.new(current_scope, line_index)
			ms.name = method_name
			ms.params = parse_func_parameters(params_text)
			if not ret_text.is_empty(): ms.return_type = parse_type(ret_text)
			if not method_name.is_empty() and current_scope is ClassScope:
				if not current_scope.methods.has(method_name): current_scope.methods[method_name] = []
				current_scope.methods[method_name].append(ms)
			context_stack.append({ "scope": ms, "indent": indent })
			continue
			
		var sig_match = regex_signal.search(line)
		if sig_match:
			var sig_name = sig_match.get_string(1)
			var sig_args = sig_match.get_string(2)
			var ss = SignalScope.new()
			ss.name = sig_name
			ss.params = parse_func_parameters(sig_args if sig_args else "")
			if current_scope is ClassScope: current_scope.signals[sig_name] = ss
			continue
			
		var target_var_scope = null
		if current_scope is MethodScope: target_var_scope = current_scope.locals
		elif current_scope is ClassScope: target_var_scope = current_scope.vars
			
		if target_var_scope != null:
			var m : RegExMatch
			m = r_var_typed_init.search(line)
			if m:
				_add_var(target_var_scope, m.get_string(1), parse_type(m.get_string(2)), m.get_string(3), false, line_index)
				continue
			m = r_var_typed_no_init.search(line)
			if m:
				_add_var(target_var_scope, m.get_string(1), parse_type(m.get_string(2)), "", false, line_index)
				continue
			m = r_var_inferred.search(line)
			if m:
				_add_var(target_var_scope, m.get_string(1), infer_type_from_value(m.get_string(2)), m.get_string(2), false, line_index)
				continue
			m = r_const_typed_init.search(line)
			if m:
				_add_var(target_var_scope, m.get_string(1), parse_type(m.get_string(2)), m.get_string(3), true, line_index)
				continue
			m = r_const_typed_no_init.search(line)
			if m:
				_add_var(target_var_scope, m.get_string(1), parse_type(m.get_string(2)), "", true, line_index)
				continue
			m = r_const_inferred.search(line)
			if m:
				_add_var(target_var_scope, m.get_string(1), infer_type_from_value(m.get_string(2)), m.get_string(2), true, line_index)
				continue

	var last_line_idx = max(0, lines.size() - 1)
	while context_stack.size() > 0:
		var ctx = context_stack.pop_back()
		if ctx.scope is MethodScope:
			var ms = ctx.scope as MethodScope
			var body_end = -1
			if method_body_last_line.has(ms): body_end = method_body_last_line[ms]
			ms.end_line = body_end if body_end != -1 else ms.start_line
		else:
			ctx.scope.end_line = last_line_idx

	_finalize_class_end_lines(root_class)
	var index_data = SymbolIndexData.new()
	index_data.root = root_class
	index_data.classes_by_name = classes_by_name
	return index_data

static func _add_var(target_dict: Dictionary, name: String, type: TypeData, val: String, is_const: bool, line: int):
	var vs = VarScope.new()
	vs.name = name; vs.type = type; vs.is_const = is_const; vs.start_line = line; vs.end_line = line; vs.value = val
	vs.is_private = name.begins_with("m_") or name.begins_with("_m_")
	target_dict[name] = vs

static func _finalize_class_end_lines(scope: ClassScope):
	for child in scope.children: if child is ClassScope: _finalize_class_end_lines(child)
	var max_end = scope.end_line
	for v_name in scope.vars:
		var vs = scope.vars[v_name]
		if vs.end_line > max_end: max_end = vs.end_line
	for child in scope.children:
		if child.end_line > max_end: max_end = child.end_line
	scope.end_line = max_end

# ----------------- Scoping & Resolution -----------------

static func get_scope_info_for_line(index: SymbolIndexData, line: int) -> ScopeInfo:
	var found_scope = _find_scope_for_line_recursive(index.root, line)
	if found_scope == null: found_scope = index.root
	var info = ScopeInfo.new()
	info.scope = found_scope
	var p = found_scope
	while p:
		if p is MethodScope and info.method_scope == null: info.method_scope = p
		if p is ClassScope and info.class_scope == null: info.class_scope = p
		p = p.parent
	if info.class_scope == null: info.class_scope = index.root
	return info

static func _find_scope_for_line_recursive(current: ScopeBase, line: int) -> ScopeBase:
	if line < current.start_line or line > current.end_line: return null
	for child in current.children:
		var found = _find_scope_for_line_recursive(child, line)
		if found: return found
	return current

static func resolve_variable_type(name: String, scope_info: ScopeInfo) -> TypeData:
	var current = scope_info.scope
	var is_current_class = true
	while current:
		if current is MethodScope:
			var ms = current as MethodScope
			if ms.params.has(name): return ms.params[name]
			if ms.locals.has(name) and ms.locals[name].type: return ms.locals[name].type
		elif current is ClassScope:
			var cs = current as ClassScope
			if cs.vars.has(name):
				var vs = cs.vars[name]
				if vs.type and (is_current_class or vs.is_const): return vs.type
			is_current_class = false
		current = current.parent
	return null

static func resolve_method_scope(class_scope: ClassScope, method_name: String) -> MethodScope:
	if class_scope.methods.has(method_name):
		var arr = class_scope.methods[method_name]
		if not arr.is_empty(): return arr[0]
	return null

# ----------------- Function Signature -----------------

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

# ----------------- Defaults -----------------

static func get_default_return_value(t: TypeData) -> String:
	var base = get_base_type_name(t)
	if base == "void": 
		return ""
	
	# 1. Built-in Variant Types
	for i in range(TYPE_MAX):
		if type_string(i) == base:
			var default_val = type_convert(null, i)
			if default_val != null:
				return var_to_str(default_val)
			break
			
	# 2. Check ClassDB (Built-in Classes e.g. Node, Resource, Texture)
	if ClassDB.class_exists(base):
		if ClassDB.can_instantiate(base):
			return "%s.new()" % base
		return "null"
		
	# 3. User Classes (Script Classes)
	return "%s.new()" % base
