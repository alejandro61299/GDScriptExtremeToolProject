# Changelog

## Unreleased

### Added

- **Extract Function...** With some lines of a function selected, moves them to a new function and leaves the call in their place. A dialog asks for the name and shows the whole new function and the changed one, with the colors of the script editor. The local variables the code reads become parameters, and the one it changes or declares for later is returned. If the selection ends in a `return` or in a line that assigns a variable, the call takes the place of that value; when that line assigns a class variable, the dialog lets you choose between that and a function that assigns it itself. The action is not offered when the result could behave differently.
- **Add Explicit Types.** Writes the type of every variable of the script that has none, in class variables and in the local variables of every function: `var total := 0` becomes `var total: int = 0` and `var mode := Mode.FAST` becomes `var mode: Mode = Mode.FAST`. The `:=` can be written in any way GDScript accepts, such as `: =`. A variable declared with a plain `=` gets a type only when everything the script assigns to it has that type, so `var timer = 0` is left alone if the script does `timer += delta`. Variables whose type is not known are left as they are.
- **Types from other scripts.** The actions read the scripts that a script loads with `preload`, its base script and the classes with `class_name`. A value that comes from a function, a constant, a member, a signal, an enum or an inner class of another script has its type now, written as the current script has to write it: `var made := Shapes.make()` becomes `var made: Shapes.Circle = ...`, a function that returns `Array[Circle]` there gives an `Array[Shapes.Circle]` here, and `Shapes.Kind.ROUND` is a `Shapes.Kind`. This reaches every action: the parameters and the result of an extracted function, the parameters of a generated function or callback, and the type of a generated variable. When no constant of the script leads to that class, the value stays without a type. If the other script is open with unsaved changes, the tab is read instead of the file. See "Types from other scripts" in the README.
- Setting `format/max_blank_lines_inside_functions`, `1` by default: Format keeps at most that many blank lines in a row inside a function, and inside any other member that spans several lines. Blank lines inside a multiline string are never removed.

### Changed

- The dialog of Generate Custom Init Definition... shows the whole function it will generate, with the colors and the font of the script editor, as the dialog of Extract Function... does. Its filters show clearly which ones are on and which ones have no variables.
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

- A constant of a built-in type gets its real type: `Vector2.AXIS_X` is an `int`, not a `Vector2`. `PI`, `TAU`, `INF` and `NAN` are `float`.
- The value awaited from a signal is no longer taken for a `Signal`, and `load(path).new()` is no longer taken for a `Resource`: their type is not known.
- A string written on several lines is a `String`, and a variable with accessors on its own line, `var health = 10: set = _set_health`, gets the type of its value.
- An instance of a script loaded with `preload` into a constant gets the name of the constant as its type, so `GDSExSnippet.new()` is a `GDSExSnippet`, also when the constant comes from the base script.
- A constant that loads a script by `uid://` counts as that script, like one that loads it by path.
- The members of a base script given by a relative path, `extends "base.gd"`, are found.
- A member inherited from a base script has its real type. A function of the base script that returns one of its own classes was taken for its native class, such as `RefCounted`.
- A class with `class_name` is known when it is used by its name: `Gadget.new()` is a `Gadget`.
- Generate Local Variable and Generate Function Definition write `0`, not `null`, as the placeholder value of an enum type. `var pressed: Key = null` and a `return null` in a function that returns an enum did not compile.
- A value chosen between two values of an enum, `Mode.ON if ready else Mode.OFF`, has that enum as its type, and so does a value of an enum of a nested class, `Outer.Mode.ON`.
- A value that is an object or `null`, `node if ready else null`, has the type of the object.
- A class or an enum nested in another class of the script is written with its full path, `Outer.Nested`, when it is used outside that class. The short name did not compile there.
- A value created through the path of a nested class, `Outer.Nested.new()`, has that class as its type.
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
