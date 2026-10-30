extends MainLoop

const GDSExCli = preload("res://addons/gdscript_extreme_tool/cli/cli.gd")
const GDSExCliFiles = preload("res://addons/gdscript_extreme_tool/cli/cli_files.gd")

const WORKING_FOLDER_OPTION: String = "--cwd"
const STATUS_FILE_OPTION: String = "--status-file"
const WORKING_FOLDER_VARIABLE: String = "PWD"
const STANDARD_INPUT: String = "-"
const READ_SIZE: int = 65536


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var working_folder := _take_option(arguments, WORKING_FOLDER_OPTION)
	if working_folder.is_empty():
		working_folder = OS.get_environment(WORKING_FOLDER_VARIABLE)
	var status_file := _take_option(arguments, STATUS_FILE_OPTION)
	var request := GDSExCli.parse_request(arguments, true)
	var reads_input := request.error.is_empty() and (request.command.is_empty() or request.targets.has(STANDARD_INPUT))
	var result := GDSExCli.run(arguments, _read_standard_input() if reads_input else "", GDSExCliFiles.new(), working_folder)
	if not result.output.is_empty():
		print(result.output)
	if not result.error_output.is_empty():
		printerr(result.error_output)
	if not status_file.is_empty():
		var file := FileAccess.open(status_file, FileAccess.WRITE)
		if file != null:
			file.store_string(str(result.exit_code))
			file.close()


func _process(_delta: float) -> bool:
	return true


func _take_option(arguments: PackedStringArray, option: String) -> String:
	var index := arguments.find(option)
	if index == -1 or index + 1 >= arguments.size():
		return ""
	var value := arguments[index + 1]
	arguments.remove_at(index + 1)
	arguments.remove_at(index)
	return value


func _read_standard_input() -> String:
	var type := OS.get_stdin_type()
	if type != OS.STD_HANDLE_PIPE and type != OS.STD_HANDLE_FILE:
		return ""
	var data := PackedByteArray()
	while true:
		var chunk := OS.read_buffer_from_stdin(READ_SIZE)
		if chunk.is_empty():
			break
		data.append_array(chunk)
	return data.get_string_from_utf8()
