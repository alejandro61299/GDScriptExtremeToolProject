@tool
extends RefCounted

const GDSExCliFiles = preload("res://addons/gdscript_extreme_tool/cli/cli_files.gd")
const GDSExCliSession = preload("res://addons/gdscript_extreme_tool/cli/cli_session.gd")
const GDSExCliCommands = preload("res://addons/gdscript_extreme_tool/cli/cli_commands.gd")
const GDSExCliReport = preload("res://addons/gdscript_extreme_tool/cli/cli_report.gd")
const GDSExCliTarget = preload("res://addons/gdscript_extreme_tool/cli/cli_target.gd")
const GDSExScriptLibrary = preload("res://addons/gdscript_extreme_tool/analysis/script_library.gd")

const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
const EXIT_USAGE: int = 2

const HELP_COMMAND: String = "help"
const QUIET_FLAG: String = "-q"
const DIFF_FLAG: String = "--diff"
const CHECK_FLAG: String = "--check"
const PRINT_FLAG: String = "--print"
const AS_OPTION: String = "--as"
const NTH_OPTION: String = "--nth"
const CHANGED_FLAG: String = "--changed"
const OPTION_PREFIX: String = "-"
const VALUE_SEPARATOR: String = "="
const COMMENT_PREFIX: String = "#"
const LINE_SEPARATOR: String = "\n"
const COMMAND_SEPARATOR: String = "-"
const METHOD_PREFIX: String = "run_"
const METHOD_SEPARATOR: String = "_"
const LIST_SEPARATOR: String = ", "
const STANDARD_INPUT: String = "-"
const UNLIMITED: int = -1
const GLOBAL_VALUE_OPTIONS: Array[String] = [AS_OPTION, NTH_OPTION]
const GLOBAL_FLAGS: Array[String] = [QUIET_FLAG, DIFF_FLAG, CHECK_FLAG, PRINT_FLAG]
const WHOLE_SCRIPT_FLAGS: Array[String] = [CHANGED_FLAG]
const COMMANDS: Dictionary[String, Array] = {
	"tidy": [1, UNLIMITED, ["--only"], WHOLE_SCRIPT_FLAGS],
	"types": [1, UNLIMITED, [], WHOLE_SCRIPT_FLAGS],
	"reorder": [1, UNLIMITED, [], WHOLE_SCRIPT_FLAGS],
	"format": [1, UNLIMITED, [], WHOLE_SCRIPT_FLAGS],
	"function": [1, UNLIMITED, [], []],
	"local": [1, UNLIMITED, [], []],
	"member": [1, UNLIMITED, [], []],
	"connect": [1, UNLIMITED, [], []],
	"init": [1, UNLIMITED, ["--name", "--vars"], ["--all-vars"]],
	"extract-function": [1, 1, ["--name", "--form"], []],
	"extract-variable": [1, 1, ["--name", "--place"], ["--const", "--static", "--private", "--public", "--onready"]],
	"actions": [1, UNLIMITED, [], []],
}
const UNKNOWN_COMMAND_MESSAGE: String = "Unknown command '%s'. Commands: %s. Run 'gdsex help'."
const UNKNOWN_OPTION_MESSAGE: String = "Unknown option '%s' for %s."
const MISSING_VALUE_MESSAGE: String = "%s needs a value."
const MISSING_TARGET_MESSAGE: String = "%s needs a target, such as player.gd or player.gd:42:speed."
const TOO_MANY_TARGETS_MESSAGE: String = "%s takes one target."
const NO_COMMANDS_MESSAGE: String = "No command. Run 'gdsex help'."
const WRITE_FAILED_MESSAGE: String = "Could not write %s."
const BATCH_LINE_MESSAGE: String = "line %d: %s"
const UNCLOSED_QUOTE_MESSAGE: String = "A quote is not closed."
const HELP_TEXT: String = """gdsex <command> <target>... [options]   or a batch: one command per line on stdin

Targets (lines start at 1):
  file.gd  whole script         file.gd:42  line 42        file.gd:30-38  lines 30 to 38
  file.gd:42:text  text on line 42, or up to 20 lines away   file.gd:text  its only occurrence
  folder/  every .gd inside, except addons/ and .godot/       -  the code comes from stdin

Commands:
  tidy <files|folders>        types + reorder + format. --only types,reorder,format
  types <files|folders>       writes the type of every variable that has none
  reorder <files|folders|line>  sorts class members
  format <files|folders|line>   blank lines, spacing and layout of the style guide
  function <call|file>        creates the missing function, typed; on a file, every missing one
  local <name> / member <name>  declares an undefined name as a local / class variable
  connect <signal>            writes signal.connect(_on_signal) and the callback
  init <line>                 _init assigning the private variables. --name n --vars a,b --all-vars
  extract-function <lines>    moves the lines to a new function. --name n --form return|assignment|output|plain
  extract-variable <value>    names a value. --name n --place block|function|class|script
                              --const --static --private --public --onready
  actions <target>            lists the commands that apply there

Options:
  -q  headers only   --diff  unified diff   --check  write nothing, exit 1 if anything would change
  --print  print the resulting files instead of writing them   --changed  .gd files changed in git
  --as res://path.gd  path of the code read from stdin   --nth N  Nth occurrence of the text
Exit codes: 0 done, 1 something failed or --check found changes, 2 wrong usage."""


class GDSExResult:
	var output: String = ""
	var error_output: String = ""
	var exit_code: int = EXIT_OK


static func run(arguments: PackedStringArray, standard_input: String, files: GDSExCliFiles, working_folder: String) -> GDSExResult:
	var result := GDSExResult.new()
	var invocation := parse_request(arguments, true)
	if invocation.command == HELP_COMMAND:
		result.output = HELP_TEXT
		return result
	if not invocation.error.is_empty():
		return _usage_error(result, invocation.error)
	var requests: Array[GDSExCliCommands.GDSExRequest] = []
	var batch_errors := PackedStringArray()
	if invocation.command.is_empty():
		var line_number := 0
		for line in standard_input.split(LINE_SEPARATOR):
			line_number += 1
			var stripped := line.strip_edges()
			if stripped.is_empty() or stripped.begins_with(COMMENT_PREFIX):
				continue
			var tokens := split_line(stripped)
			var request := parse_request(tokens, false) if not tokens.is_empty() else null
			if tokens.is_empty():
				batch_errors.append(BATCH_LINE_MESSAGE % [line_number, UNCLOSED_QUOTE_MESSAGE])
				continue
			if not request.error.is_empty():
				batch_errors.append(BATCH_LINE_MESSAGE % [line_number, request.error])
				continue
			_merge_invocation(request, invocation)
			requests.append(request)
		if requests.is_empty() and batch_errors.is_empty():
			return _usage_error(result, NO_COMMANDS_MESSAGE)
	else:
		requests.append(invocation)

	GDSExScriptLibrary.clear()
	GDSExScriptLibrary.scans_for_global_classes = true
	var session := GDSExCliSession.new(files, working_folder)
	var commands := GDSExCliCommands.new(session)
	commands.standard_input = standard_input
	if invocation.values.has(AS_OPTION):
		commands.standard_input_path = session.local_path(invocation.values[AS_OPTION])
	for error in batch_errors:
		session.add_error(error)
	var prints := invocation.has_flag(PRINT_FLAG)
	for request in requests:
		if request.targets.has(STANDARD_INPUT):
			prints = true
		if request.values.has(AS_OPTION):
			commands.standard_input_path = session.local_path(request.values[AS_OPTION])
		commands.call(METHOD_PREFIX + request.command.replace(COMMAND_SEPARATOR, METHOD_SEPARATOR), request)
	GDSExScriptLibrary.scans_for_global_classes = false
	GDSExScriptLibrary.clear()

	var mode := GDSExCliReport.GDSExMode.LINES
	if invocation.has_flag(DIFF_FLAG):
		mode = GDSExCliReport.GDSExMode.DIFF
	elif invocation.has_flag(QUIET_FLAG):
		mode = GDSExCliReport.GDSExMode.SUMMARY
	var checks := invocation.has_flag(CHECK_FLAG)
	if not checks and not prints:
		for failed in session.write_changes():
			session.add_error(WRITE_FAILED_MESSAGE % failed)
	if prints:
		var printed: Array[GDSExCliSession.GDSExDocument] = []
		printed.assign(session.documents.values())
		result.output = GDSExCliReport.render_files(session, printed)
		result.error_output = GDSExCliReport.render(session, mode)
	else:
		result.output = GDSExCliReport.render(session, mode)
	if session.has_errors() or (checks and not session.changed_documents().is_empty()):
		result.exit_code = EXIT_FAILED
	return result


static func parse_request(tokens: PackedStringArray, allows_missing_command: bool) -> GDSExCliCommands.GDSExRequest:
	var request := GDSExCliCommands.GDSExRequest.new()
	var index := 0
	var pending: Array[String] = []
	while index < tokens.size():
		var token := tokens[index]
		if not request.command.is_empty() or not _is_option(token):
			break
		pending.append(token)
		if GLOBAL_VALUE_OPTIONS.has(token) and index + 1 < tokens.size():
			index += 1
			pending.append(tokens[index])
		index += 1
	if index < tokens.size():
		request.command = tokens[index]
		index += 1
	if request.command.is_empty() and not allows_missing_command:
		request.error = NO_COMMANDS_MESSAGE
		return request
	if not request.command.is_empty() and request.command != HELP_COMMAND and not COMMANDS.has(request.command):
		request.error = UNKNOWN_COMMAND_MESSAGE % [request.command, LIST_SEPARATOR.join(COMMANDS.keys())]
		return request
	var spec: Array = COMMANDS.get(request.command, [0, UNLIMITED, [], []])
	var options: Array[String] = pending
	for rest in range(index, tokens.size()):
		options.append(tokens[rest])
	var position := 0
	while position < options.size():
		var token := options[position]
		position += 1
		if not _is_option(token):
			request.targets.append(token)
			continue
		var option_name := token.get_slice(VALUE_SEPARATOR, 0)
		var inline_value := token.substr(option_name.length() + 1) if token.contains(VALUE_SEPARATOR) else ""
		if GLOBAL_VALUE_OPTIONS.has(option_name) or (spec[2] as Array).has(option_name):
			if token.contains(VALUE_SEPARATOR):
				request.values[option_name] = inline_value
			elif position < options.size():
				request.values[option_name] = options[position]
				position += 1
			else:
				request.error = MISSING_VALUE_MESSAGE % option_name
				return request
		elif GLOBAL_FLAGS.has(option_name) or (spec[3] as Array).has(option_name):
			request.flags[option_name] = true
		else:
			request.error = UNKNOWN_OPTION_MESSAGE % [option_name, request.command if not request.command.is_empty() else "gdsex"]
			return request
	if request.command.is_empty() or request.command == HELP_COMMAND:
		return request
	if request.targets.is_empty() and not request.has_flag(CHANGED_FLAG) and int(spec[0]) > 0:
		request.error = MISSING_TARGET_MESSAGE % request.command
	elif int(spec[1]) != UNLIMITED and request.targets.size() > int(spec[1]):
		request.error = TOO_MANY_TARGETS_MESSAGE % request.command
	return request


static func split_line(line: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var current := ""
	var quote := ""
	var has_token := false
	var index := 0
	while index < line.length():
		var character := line[index]
		index += 1
		if not quote.is_empty():
			if character == quote:
				quote = ""
			elif character == "\\" and quote == "\"" and index < line.length():
				current += line[index]
				index += 1
			else:
				current += character
			continue
		if character == "\"" or character == "'":
			quote = character
			has_token = true
		elif character == " " or character == "\t":
			if has_token:
				tokens.append(current)
				current = ""
				has_token = false
		else:
			current += character
			has_token = true
	if not quote.is_empty():
		return PackedStringArray()
	if has_token:
		tokens.append(current)
	return tokens


static func _merge_invocation(request: GDSExCliCommands.GDSExRequest, invocation: GDSExCliCommands.GDSExRequest) -> void:
	for flag in invocation.flags:
		if not request.flags.has(flag):
			request.flags[flag] = invocation.flags[flag]
	for option in invocation.values:
		if not request.values.has(option):
			request.values[option] = invocation.values[option]


static func _is_option(token: String) -> bool:
	return token.begins_with(OPTION_PREFIX) and token != STANDARD_INPUT


static func _usage_error(result: GDSExResult, message: String) -> GDSExResult:
	result.output = GDSExCliReport.ERROR_TEMPLATE % message
	result.exit_code = EXIT_USAGE
	return result
