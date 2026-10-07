# Changelog

## Unreleased

### Added

- Setting `format/max_blank_lines_inside_functions`, `1` by default: Format keeps at most that many blank lines in a row inside a function, and inside any other member that spans several lines. Blank lines inside a multiline string are never removed.

### Changed

- Format spaces commas and brackets everywhere, not only in collections:
  - No space before a comma and one after it, in calls, parameters, signals, annotations, type hints and `match` patterns.
  - No spaces right inside parentheses and square brackets: `print( first )` becomes `print(first)`.
  - No space between a name and the bracket of its call or subscript: `print ("foo")` becomes `print("foo")`, `table ["key"]` becomes `table["key"]` and `func (value)` becomes `func(value)`.
  - One space between a keyword and a bracket: `if(ready)` becomes `if (ready)` and `return[1]` becomes `return [1]`.
- Format lays out arrays, dictionaries and enums as the GDScript style guide does:
  - Arrays and dictionaries on one line: no space before a comma, one space after it and no trailing comma. An array has no spaces inside its brackets; a dictionary keeps one inside its braces, `{ "key": value }`, and none when it is empty.
  - Enums always have one item per line, so an enum written on one line is expanded.
  - On several lines: the items start below the opening bracket with one indentation level, comments get the indentation of the items, the blank lines between them are removed, and the closing bracket goes on its own line after a trailing comma.
  - The lines of an item that spans several lines, and the body of a lambda used as an item, move with it.
  - The colon of a dictionary key has one space before it and one after it: `"key" : value`.
- Format now applies these rules to collections written on one line too.

### Fixed

- Items of a collection written at the indentation of their statement are no longer taken for separate statements.
- The closing parenthesis of a lambda argument no longer gets an indentation that GDScript rejects when its call starts on a continuation line.
- Running Format a second time no longer moves the description of the class to the first member. A comment that belongs to the header is now written right below it, without a blank line above, as the comments of a member are.

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
