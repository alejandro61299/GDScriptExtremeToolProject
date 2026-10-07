# Changelog

## Unreleased

### Changed

- Format lays out arrays, dictionaries and enums as the GDScript style guide does:
  - On one line: no spaces inside the brackets or before a comma, one space after each comma and no trailing comma.
  - On several lines: the items start below the opening bracket with one indentation level, comments get the indentation of the items, the blank lines between them are removed, and the closing bracket goes on its own line after a trailing comma.
  - The lines of an item that spans several lines, and the body of a lambda used as an item, move with it.
  - The colon of a dictionary key gets one space after it. Before it, each dictionary keeps the style most of its keys use, `"key": value` or `"key" : value`, and `"key": value` when they are tied.
- Format now applies these rules to enums too, and to collections written on one line.

### Fixed

- Items of a collection written at the indentation of their statement are no longer taken for separate statements.
- The closing parenthesis of a lambda argument no longer gets an indentation that GDScript rejects when its call starts on a continuation line.

## 0.2.0 — 2026-10-06

### Added

- **Actions on demand.** Press Alt+Enter (Option+Return on macOS) to open the actions at the caret, or use the new **Script Extreme Tools** submenu of the context menu. The script is analyzed only when that menu opens. The shortcut can be changed in Editor Settings > Shortcuts.
- **Generate Default Init Definition.** Creates `_init` with one parameter for each private variable of the class.
- **Generate Custom Init Definition...** Opens a dialog to choose the function name and the variables, with a preview of the signature and validation of the name.
- Setting `naming/alternative_init_function_name`.

### Changed

- "Generate Method Stub" is now "Generate Function Definition".
- Settings and member categories say "functions" instead of "methods": `format/blank_lines_around_functions_and_classes`, `public_functions`, `engine_functions` and so on. Values saved with the old names are ignored.
- Blank lines inside an inner class keep the indentation of the class, in generated code and in Format and Reorder.
- Format removes the blank lines right below the header of an inner class and after its last member, and no longer empties the indentation-only lines inside a function body.
- Generated functions take their blank lines from the format settings.

### Fixed

- A caret on an indented blank line now belongs to the class or function it is indented in.
- The names of global enums such as `Key` or `Error` are no longer offered as undefined identifiers.

## 0.1.0 — 2026-10-04

First release, internal. Code actions in the script editor's context menu: Generate Method Stub, Generate Local Variable, Generate Class Variable, Generate Connected Function, Reorder Class Members and Format Class Members, configured from Project Settings.
