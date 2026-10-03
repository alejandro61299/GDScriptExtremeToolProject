@tool
extends RefCounted

const SymbolApi = preload("res://addons/code_generator/analysis/symbol_index.gd")
const SymbolIndexBuilder = preload("res://addons/code_generator/analysis/symbol_index_builder.gd")
const Snippet = preload("res://addons/code_generator/editing/snippet.gd")
const EditPlan = preload("res://addons/code_generator/editing/edit_plan.gd")
const Placement = preload("res://addons/code_generator/editing/placement.gd")
const EditApplier = preload("res://addons/code_generator/editing/edit_applier.gd")
const Indentation = preload("res://addons/code_generator/editing/indentation.gd")
const Settings = preload("res://addons/code_generator/code_generator_settings.gd")
const UNNAMED_ARGUMENT_KEYWORDS : Array[String] = ["null", "true", "false", "self"]
const MethodTemplate : String = \
"""
{prefix}func {func_name}({args}) -> {return_type}:
	{body}
"""
const MethodArgTemplate : String = "{arg_name} : {arg_type}" 
const MethodArgSplit : String = ", "
const MethodReturnBodyTemplate : String = "return {return_value}"
const MethodCustomReturnBodyTemplate : String = \
"""
var output : {return type} = {return_value}
return output
"""

# ----------------- Main Generator -----------------

func generate_stub(editor: CodeEdit) -> void:
	if not editor:
		print("No active editor.")
		return
		
	var doc_text = editor.text
	if doc_text.strip_edges().is_empty():
		print("Current file is empty.")
		return
		
	var lines = doc_text.split("\n")
	var symbol_index = SymbolIndexBuilder.build(lines)
	
	var selection_text = editor.get_selected_text()
	var current_line_idx = editor.get_caret_line()
	var current_line_text = editor.get_line(current_line_idx)
	
	var scope_info = SymbolApi.get_scope_info_for_line(symbol_index, current_line_idx)
	
	var result = _build_method_stub_internal(editor, current_line_idx, current_line_text, selection_text, scope_info)
	
	if not result.errors.is_empty():
		for err in result.errors:
			printerr(err)
		return

	if result.snippet == null:
		return

	var indent_unit := Indentation.detect_unit(lines, Indentation.editor_unit(editor))
	var plan := EditPlan.new()
	plan.insert(Placement.new_method(result.target_class, scope_info, lines, indent_unit), result.snippet)
	EditApplier.apply(editor, plan)

# ----------------- Internal Logic -----------------

class MethodStubResult:
	var errors: Array[String] = []
	var snippet: Snippet
	var target_class: SymbolApi.ClassScope

class CallSite:
	var method_name: String
	var receiver_expr = null
	var method_name_start: int
	var paren_index: int

func _build_method_stub_internal(editor: CodeEdit, current_line: int, current_line_text: String, selection_text: String, scope_info: SymbolApi.ScopeInfo) -> MethodStubResult:
	var res = MethodStubResult.new()
	var line_text = current_line_text
	var selection = selection_text.strip_edges()
	
	var all_call_sites = _find_call_sites_in_line(line_text)
	
	var call_sites = []
	if not selection.is_empty():
		for site in all_call_sites:
			if selection.contains(site.method_name):
				call_sites.append(site)
	else:
		call_sites = all_call_sites
		
	var target_class_scope: SymbolApi.ClassScope = null
	var signature: SymbolApi.FunctionSignature = null
	var chosen_site: CallSite = null
	var resolved_via_call_site = false
	
	# 1. Try to resolve standard Method Calls
	if call_sites.size() > 0:
		var unresolved = []
		
		for site in call_sites:
			if site.method_name == "new": continue
			if site.method_name == "connect": continue 
			
			var call_target_class: SymbolApi.ClassScope = null
			if site.receiver_expr == null or site.receiver_expr == "self":
				call_target_class = scope_info.class_scope
			else:
				call_target_class = _resolve_receiver_class(site.receiver_expr, scope_info)
			
			if call_target_class:
				var existing = call_target_class.methods.has(site.method_name)
				if not existing:
					unresolved.append({ "site": site, "target_class": call_target_class })
			else:
				pass
		
		if unresolved.size() == 1:
			var chosen = unresolved[0]
			target_class_scope = chosen.target_class
			chosen_site = chosen.site
			
			var end_paren = line_text.find(")", chosen_site.paren_index)
			if end_paren == -1:
				res.errors.append("Cannot parse arguments (missing ')').")
				return res
				
			var call_sub_text = line_text.substr(chosen_site.method_name_start, end_paren - chosen_site.method_name_start + 1)
			var parsed = SymbolApi.extract_function_signature(call_sub_text)
			if not parsed:
				res.errors.append("Cannot parse function call.")
				return res
				
			signature = parsed
			signature.line = current_line
			signature.line_text = line_text
			resolved_via_call_site = true
			
		elif unresolved.size() > 1:
			res.errors.append("More than one undefined function call found.")
			return res
	
	# 2. Fallback: Connection Context or Bare Word
	if not resolved_via_call_site:
		var text_to_check = selection
		if text_to_check.is_empty():
			text_to_check = _get_word_under_caret(editor)
			
		var conn_info = _resolve_connection_chain(line_text, text_to_check, scope_info)
		
		if conn_info.valid:
			signature = SymbolApi.FunctionSignature.new()
			signature.name = text_to_check
			signature.line = current_line
			signature.line_text = line_text
			
			for pname in conn_info.params:
				var ptype = conn_info.params[pname]
				var arg_info = SymbolApi.ArgumentInfo.new()
				arg_info.name = pname
				arg_info.type = ptype
				signature.args.append(arg_info)
				
			target_class_scope = scope_info.class_scope
			
		else:
			var text = selection if not selection.is_empty() else line_text
			var parsed = SymbolApi.extract_function_signature(text)
			
			if not parsed or parsed.name.is_empty():
				res.errors.append("No function call, signal connection, or definition found.")
				return res
				
			target_class_scope = scope_info.class_scope
			signature = parsed
			signature.line = current_line
			signature.line_text = line_text
		
	if not signature or not target_class_scope:
		res.errors.append("Internal error: no target class resolved.")
		return res
		
	if target_class_scope.methods.has(signature.name):
		res.errors.append("Method '%s' already defined." % signature.name)
		return res
		
	_infer_argument_types(signature, scope_info)
	_infer_return_type(signature, scope_info, chosen_site)
	_normalize_argument_names(signature)
	
	res.snippet = _build_method_snippet(signature)
	res.target_class = target_class_scope
	
	return res

# ----------------- Call Detection & Resolution -----------------

func _find_call_sites_in_line(line_text: String) -> Array[CallSite]:
	var sites: Array[CallSite] = []
	var call_pattern = RegEx.new()
	call_pattern.compile("([A-Za-z_][A-Za-z0-9_\\.]*)\\s*\\(")
	var matches = call_pattern.search_all(line_text)
	for m in matches:
		var full_expr = m.get_string(1)
		var call_start = m.get_start()
		var paren_index = m.get_end() - 1
		var before = line_text.substr(0, call_start)
		var r_func = RegEx.new(); r_func.compile("\\bfunc\\s*$")
		if r_func.search(before): continue
		var receiver_expr = null
		var method_name = full_expr
		var dot_index = full_expr.rfind(".")
		if dot_index != -1:
			receiver_expr = full_expr.substr(0, dot_index)
			method_name = full_expr.substr(dot_index + 1)
		var method_name_start = call_start + full_expr.length() - method_name.length()
		var site = CallSite.new()
		site.method_name = method_name
		site.receiver_expr = receiver_expr
		site.method_name_start = method_name_start
		site.paren_index = paren_index
		sites.append(site)
	return sites

func _get_word_under_caret(editor: CodeEdit) -> String:
	var col = editor.get_caret_column()
	var line = editor.get_line(editor.get_caret_line())
	if line.is_empty(): return ""
	var start = col
	while start > 0:
		var c = line[start - 1]
		if _is_ident_char(c): start -= 1
		else: break
	var end = col
	while end < line.length():
		var c = line[end]
		if _is_ident_char(c): end += 1
		else: break
	return line.substr(start, end - start)

func _is_ident_char(c) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"

func _resolve_connection_chain(line_text: String, target_method: String, scope_info: SymbolApi.ScopeInfo) -> Dictionary:
	if target_method.is_empty(): return { "valid": false }
	var r = RegEx.new()
	var pattern = "([\\w\\.\\(\\)\"']+)\\.connect\\s*\\(\\s*%s\\s*\\)" % target_method
	r.compile(pattern)
	var m = r.search(line_text)
	if not m: return { "valid": false }
	var full_chain_str = m.get_string(1).strip_edges()
	var tokens = _split_chain_tokens(full_chain_str)
	if tokens.is_empty(): return { "valid": false }
	var signal_name = tokens.pop_back()
	var owner_type_data = _resolve_type_from_tokens(tokens, scope_info)
	if not owner_type_data: return { "valid": false }
	var current_type_name = SymbolApi.get_base_type_name(owner_type_data)
	if current_type_name.is_empty(): return { "valid": false }
	var resolved_params = {}
	var found = false
	if scope_info.scope:
		var root = _find_root_class(scope_info.class_scope)
		var cls = _find_class_by_name(root, current_type_name)
		if cls and cls.signals.has(signal_name):
			resolved_params = cls.signals[signal_name].params
			found = true
	if not found:
		if ClassDB.class_exists(current_type_name):
			resolved_params = SymbolApi.resolve_signal_via_classdb(current_type_name, signal_name)
			found = true
	if found:
		return { "valid": true, "params": resolved_params }
	return { "valid": false }

func _resolve_type_from_tokens(tokens: Array, scope_info: SymbolApi.ScopeInfo) -> SymbolApi.TypeData:
	if tokens.is_empty():
		var t = SymbolApi.TypeData.new(); t.name = scope_info.class_scope.name; return t
	var current_type_data: SymbolApi.TypeData = null
	var first = tokens[0]
	if first == "self":
		current_type_data = SymbolApi.TypeData.new(); current_type_data.name = scope_info.class_scope.name
	else:
		current_type_data = SymbolApi.resolve_variable_type(first, scope_info)
		if not current_type_data:
			if ClassDB.class_exists(first):
				current_type_data = SymbolApi.TypeData.new(); current_type_data.name = first
	if not current_type_data: return null
	
	for i in range(1, tokens.size()):
		var prop_or_method = tokens[i]
		var is_method = "(" in prop_or_method
		var clean_name = prop_or_method.split("(")[0].strip_edges()
		var current_type_name = SymbolApi.get_base_type_name(current_type_data)
		var next_type_data: SymbolApi.TypeData = null
		
		var root = _find_root_class(scope_info.class_scope)
		var cls = _find_class_by_name(root, current_type_name)
		
		if cls:
			if is_method:
				var ms = SymbolApi.resolve_method_scope(cls, clean_name)
				if ms and ms.return_type: next_type_data = ms.return_type
			else:
				if cls.vars.has(clean_name): 
					next_type_data = cls.vars[clean_name].type
				elif cls.methods.has(clean_name):
					var t = SymbolApi.TypeData.new(); t.name = "Callable"; next_type_data = t
		
		if not next_type_data:
			if is_method:
				next_type_data = SymbolApi.resolve_type_via_classdb(current_type_name, clean_name)
			else:
				var props = ClassDB.class_get_property_list(current_type_name)
				for p in props:
					if p.name == clean_name:
						var t_name = type_string(p.type)
						if p.hint == PROPERTY_HINT_RESOURCE_TYPE and not p.hint_string.is_empty(): t_name = p.hint_string
						next_type_data = SymbolApi.TypeData.new(); next_type_data.name = t_name; break
				
				if not next_type_data:
					var signals = ClassDB.class_get_signal_list(current_type_name)
					for s in signals:
						if s.name == clean_name:
							next_type_data = SymbolApi.TypeData.new(); next_type_data.name = "Signal"; break
				
				if not next_type_data:
					if ClassDB.class_has_method(current_type_name, clean_name):
						next_type_data = SymbolApi.TypeData.new(); next_type_data.name = "Callable"
				
		if not next_type_data: return null 
		current_type_data = next_type_data
		
	return current_type_data

func _split_chain_tokens(chain: String) -> Array:
	var tokens = []
	var current = ""
	var depth = 0
	for i in range(chain.length()):
		var c = chain[i]
		if c == "(": depth += 1
		elif c == ")": depth -= 1
		if c == "." and depth == 0:
			if not current.strip_edges().is_empty(): tokens.append(current.strip_edges())
			current = ""
		else:
			current += c
	if not current.strip_edges().is_empty(): tokens.append(current.strip_edges())
	return tokens

func _find_root_class(scope: SymbolApi.ClassScope) -> SymbolApi.ClassScope:
	var current = scope
	while current.parent is SymbolApi.ClassScope: current = current.parent
	return current

func _find_class_by_name(root: SymbolApi.ClassScope, name: String) -> SymbolApi.ClassScope:
	if root.name == name: return root
	for child_name in root.inner_classes:
		var child = root.inner_classes[child_name]
		var res = _find_class_by_name(child, name)
		if res: return res
	return null

func _resolve_receiver_class(receiver_expr: String, scope_info: SymbolApi.ScopeInfo) -> SymbolApi.ClassScope:
	var tokens = receiver_expr.split(".")
	var clean_tokens = []
	for t in tokens:
		var tr = t.strip_edges()
		if not tr.is_empty(): clean_tokens.append(tr)
	if clean_tokens.is_empty(): return null
	var root = _find_root_class(scope_info.class_scope)
	var current_class: SymbolApi.ClassScope = null
	var index = 0
	var first = clean_tokens[0]
	if first == "self":
		current_class = scope_info.class_scope
		index = 1
	else:
		var t = SymbolApi.resolve_variable_type(first, scope_info)
		if not t: return null
		var base = SymbolApi.get_base_type_name(t)
		current_class = _find_class_by_name(root, base)
		if not current_class: return null
		index = 1
	for i in range(index, clean_tokens.size()):
		var prop = clean_tokens[i]
		if not current_class.vars.has(prop): return null
		var vs = current_class.vars[prop]
		if not vs.type: return null
		var base = SymbolApi.get_base_type_name(vs.type)
		var next_class = _find_class_by_name(root, base)
		if not next_class: return null
		current_class = next_class
	return current_class

func _resolve_signal_or_class_signal(expr: String, scope_info: SymbolApi.ScopeInfo) -> SymbolApi.SignalSymbol:
	var receiver_obj = "self"
	var signal_name = expr
	if "." in expr:
		var last_dot = expr.rfind(".")
		receiver_obj = expr.substr(0, last_dot)
		signal_name = expr.substr(last_dot + 1)
	var cls = _resolve_receiver_class(receiver_obj, scope_info)
	if not cls: return null
	if cls.signals.has(signal_name): return cls.signals[signal_name]
	return null

# ----------------- Inference -----------------

func _infer_type_from_expr(expr: String, scope_info: SymbolApi.ScopeInfo) -> SymbolApi.TypeData:
	var text = expr.strip_edges()
	if text.is_empty(): return null
	var lit = SymbolApi.infer_type_from_value(text)
	if lit: return lit
	if text == "null":
		var t = SymbolApi.TypeData.new(); t.name = "Object"; return t
	if scope_info.class_scope and scope_info.class_scope.signals.has(text):
		var t = SymbolApi.TypeData.new(); t.name = "Signal"; return t
	var tokens = _split_chain_tokens(text)
	if not tokens.is_empty():
		var t = _resolve_type_from_tokens(tokens, scope_info)
		if t: return t
	return null

func _infer_argument_types(signature: SymbolApi.FunctionSignature, scope_info: SymbolApi.ScopeInfo):
	for i in range(signature.args.size()):
		var arg = signature.args[i]
		if arg.type: continue
		var raw = arg.name
		if raw.is_empty(): continue
		var t = _infer_type_from_expr(raw, scope_info)
		if t: arg.type = t

func _infer_return_type(signature: SymbolApi.FunctionSignature, scope_info: SymbolApi.ScopeInfo, call_site: CallSite):
	var func_name = signature.name
	var call_line = signature.line
	var call_line_text = signature.line_text
	var ms = scope_info.function_scope
	
	if ms and ms.return_type and ms.return_lines.has(call_line):
		var r_ret = RegEx.new(); r_ret.compile("^\\s*return\\s+.*\\b" + func_name + "\\s*\\(")
		if r_ret.search(call_line_text): signature.return_type = ms.return_type; return
			
	var method_name_idx = -1
	if call_site: method_name_idx = call_site.method_name_start
	else: method_name_idx = call_line_text.find(func_name + "(")
		
	if method_name_idx != -1:
		var idx = method_name_idx - 1
		var paren_depth = 0; var comma_count = 0; var found_outer = false
		while idx >= 0:
			var ch = call_line_text[idx]
			if ch == ')': paren_depth += 1
			elif ch == '(':
				if paren_depth > 0: paren_depth -= 1
				else: found_outer = true; break
			elif ch == ',' and paren_depth == 0: comma_count += 1
			idx -= 1
			
		if found_outer:
			var look_back_idx = idx - 1
			while look_back_idx >= 0:
				var c = call_line_text[look_back_idx]
				if c == " " or c == "\t": look_back_idx -= 1
				else: break
			var ref_end = look_back_idx + 1
			while look_back_idx >= 0:
				var c = call_line_text[look_back_idx]
				if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '.': look_back_idx -= 1
				else: break
			var ref_start = look_back_idx + 1
			var outer_ref = call_line_text.substr(ref_start, ref_end - ref_start)
			
			if not outer_ref.is_empty():
				var outer_recv = "self"; var outer_method = outer_ref
				var last_dot = outer_ref.rfind(".")
				if last_dot != -1:
					outer_recv = outer_ref.substr(0, last_dot)
					outer_method = outer_ref.substr(last_dot + 1)
				
				# --- 1. HANDLE CONNECT() ARGUMENTS ---
				if outer_method == "connect":
					# If we are inside connect(), check if the receiver is a Signal.
					var is_signal = false
					var sig = _resolve_signal_or_class_signal(outer_recv, scope_info)
					if sig: is_signal = true
					
					if not is_signal:
						# Try built-in signals
						var tokens = _split_chain_tokens(outer_recv)
						var type_data = _resolve_type_from_tokens(tokens, scope_info)
						if type_data and SymbolApi.get_base_type_name(type_data) == "Signal":
							is_signal = true
					
					# If receiver is a Signal, the first argument must be a Callable.
					if is_signal and comma_count == 0:
						var t = SymbolApi.TypeData.new(); t.name = "Callable"
						signature.return_type = t
						return

				# --- 2. HANDLE EMIT() ARGUMENTS ---
				elif outer_method == "emit":
					var sig = _resolve_signal_or_class_signal(outer_recv, scope_info)
					if sig and comma_count < sig.params.size():
						var p_key = sig.params.keys()[comma_count]
						signature.return_type = sig.params[p_key]
						return
					if not sig:
						var last_dot_sig = outer_recv.rfind(".")
						if last_dot_sig != -1:
							var sig_owner_expr = outer_recv.substr(0, last_dot_sig)
							var sig_name = outer_recv.substr(last_dot_sig + 1)
							var tokens = _split_chain_tokens(sig_owner_expr)
							var type_data = _resolve_type_from_tokens(tokens, scope_info)
							var base_type = ""
							if type_data: base_type = SymbolApi.get_base_type_name(type_data)
							elif ClassDB.class_exists(sig_owner_expr): base_type = sig_owner_expr
							if not base_type.is_empty() and ClassDB.class_exists(base_type):
								var db_sig = SymbolApi.resolve_signal_via_classdb(base_type, sig_name)
								if not db_sig.is_empty() and comma_count < db_sig.size():
									signature.return_type = db_sig.values()[comma_count]
									return
				
				# --- 3. HANDLE REGULAR METHOD ARGUMENTS ---
				var outer_cls = _resolve_receiver_class(outer_recv, scope_info)
				if outer_cls:
					var outer_ms = SymbolApi.resolve_method_scope(outer_cls, outer_method)
					if outer_ms:
						var params = outer_ms.params
						if comma_count < params.size():
							signature.return_type = params.values()[comma_count]
							return
				
				if not outer_cls:
					var tokens = _split_chain_tokens(outer_recv)
					var type_data = _resolve_type_from_tokens(tokens, scope_info)
					var builtin_type_name = ""
					if type_data: builtin_type_name = SymbolApi.get_base_type_name(type_data)
					elif ClassDB.class_exists(outer_recv): builtin_type_name = outer_recv
					if not builtin_type_name.is_empty() and ClassDB.class_exists(builtin_type_name):
						var methods = ClassDB.class_get_method_list(builtin_type_name)
						for m in methods:
							if m.name == outer_method:
								if comma_count < m.args.size():
									var arg_info = m.args[comma_count]
									var t_new = SymbolApi.TypeData.new()
									if arg_info.class_name != &"": t_new.name = String(arg_info.class_name)
									else: t_new.name = type_string(arg_info.type)
									signature.return_type = t_new
									return
	
	var declaration := SymbolApi.find_variable_declared_at(scope_info, call_line)
	if declaration != null and declaration.type != null and declaration.value.contains(func_name + "("):
		signature.return_type = declaration.type

func _normalize_argument_names(signature: SymbolApi.FunctionSignature) -> void:
	var used_names: Array[String] = []
	for i in range(signature.args.size()):
		var arg := signature.args[i]
		var generated := _format_param_name(arg.name)
		if generated.is_empty() or used_names.has(generated):
			generated = Settings.FALLBACK_PARAM_FORMAT.format({"index": i})
		used_names.append(generated)
		arg.name = generated

func _format_param_name(source_name: String) -> String:
	var r_ident := RegEx.create_from_string("^[A-Za-z_]\\w*$")
	if not r_ident.search(source_name) or UNNAMED_ARGUMENT_KEYWORDS.has(source_name):
		return ""
	var base_name := source_name.to_lower().lstrip("_")
	if base_name.is_empty():
		return ""
	if _matches_param_format(base_name):
		return base_name
	return Settings.GENERATED_PARAM_FORMAT.format({"name": base_name})

func _matches_param_format(param_name: String) -> bool:
	var affixes := Settings.GENERATED_PARAM_FORMAT.split("{name}")
	var prefix := affixes[0]
	var suffix := affixes[1] if affixes.size() > 1 else ""
	if prefix.is_empty() and suffix.is_empty():
		return false
	if param_name.length() <= prefix.length() + suffix.length():
		return false
	return param_name.begins_with(prefix) and param_name.ends_with(suffix)

# ----------------- Generator -----------------

func _build_method_snippet(signature: SymbolApi.FunctionSignature) -> Snippet:
	var arg_strings := PackedStringArray()
	for arg in signature.args:
		var type_text := SymbolApi.type_to_string(arg.type)
		arg_strings.append(arg.name if type_text.is_empty() else "%s: %s" % [arg.name, type_text])

	var return_type := signature.return_type
	var returns_value := return_type != null and SymbolApi.get_base_type_name(return_type) != "void"
	var return_text := SymbolApi.type_to_string(return_type) if returns_value else "void"
	var body := ("return %s" % SymbolApi.get_default_return_value(return_type)) if returns_value else "pass"

	var snippet := Snippet.new()
	snippet.add_line(0, "func %s(%s) -> %s:" % [signature.name, ", ".join(arg_strings), return_text])
	snippet.add_line(1, body)
	snippet.select_line(1)
	return snippet
