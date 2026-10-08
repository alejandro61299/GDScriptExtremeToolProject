@tool
extends RefCounted

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExValueFinder = preload("res://addons/gdscript_extreme_tool/analysis/value_finder.gd")
const GDSExValueNames = preload("res://addons/gdscript_extreme_tool/analysis/value_names.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")


class GDSExExtraction:
	var value: GDSExValueFinder.GDSExValue
	var scope_info: GDSExSymbolIndex.GDSExScopeInfo
	var type: GDSExSymbolIndex.GDSExTypeData
	var proposed_name: String = ""
	var value_text: String = ""


static func analyze(context: GDSExCodeContext) -> GDSExExtraction:
	var value := GDSExValueFinder.find(context.statement, context.selection_from, context.selection_to)
	if value == null:
		return null
	var scope_info := GDSExSymbolIndex.get_scope_info_for_line(context.index, value.first_position().x)
	var resolved := GDSExTypeResolver.resolve_expression(value.code, scope_info)
	if resolved.returns_nothing or resolved.is_class_reference:
		return null
	var extraction := GDSExExtraction.new()
	extraction.value = value
	extraction.scope_info = scope_info
	extraction.type = null if resolved.type == null or resolved.is_preloaded or resolved.type.name == GDSExLanguage.VARIANT_TYPE_NAME else resolved.type
	extraction.value_text = GDSExValueFinder.source_text(value, context.lines)
	extraction.proposed_name = GDSExValueNames.propose(value, context.lines, scope_info)
	return extraction
