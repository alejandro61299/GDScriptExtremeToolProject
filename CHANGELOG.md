# Changelog

## 0.4.0 — unreleased

### Added

- **Extract Variable...** With the caret on a value, such as `120.0`, `"text"`, `Enemy.new()`, `shapes.make()` or `$Sprite2D`, declares a variable with that value and leaves its name in its place. A dialog asks for the name and where the variable lives: in its block, in the function, in the class or, from an inner class, in the script; and whether it is a constant, static, private or `@onready`. A choice that would not compile is off and says why. A choice that compiles but computes the value at another moment, such as a class variable or a value taken out of a loop, carries a warning. See "Extract Variable" in the README.
- **Functions in other scripts.** Generate Function Definition is offered on a call to an object or a class of another script, and creates the function there: `shapes.missing()` adds `missing` to `shapes.gd`, and the menu names the file, "Generate Function Definition in shapes.gd". The function goes to the class of the object, also when it is an inner class, after its last function or variable and with the indentation of that file. It is `static` when the call is on the class. Its types are written the way that script writes them, so a `Shapes.Circle` argument becomes a `Circle` parameter inside `shapes.gd`. The other script is changed in its tab, which is opened if needed, and it is not saved. It works on any script the plugin reads, also inside `res://addons`. See "Functions in other scripts" in the README.

### Fixed

- Generate Function Definition on a call to an object of another class of the same script wrote the types as the calling class sees them. A parameter of the type `Nested`, only visible inside `Holder`, did not compile in the other class; it is now written `Holder.Nested`.
- Generate Function Definition was offered on an annotation with arguments, such as `@export_range(0, 10)` or `@warning_ignore("unused_parameter")`, as if it were a call to an undefined function.
- Generate Function Definition is no longer offered on a class written on one line, `class Empty: pass`, where the function it wrote did not compile.
- Generate Function Definition is no longer offered for the functions that every script class has, such as `Inner.can_instantiate()`.
- A number written in binary, such as `0b101`, is taken for an `int`. Add Explicit Types left `var mask := 0b101` without a type.
- In a script that extends `CharacterBody2D`, `Area2D`, `Control` or any other physics body or control, `Input` was taken for a property of the node, because the inspector has a group of properties with that title. `var direction := Input.get_axis("ui_left", "ui_right")` was not offered Add Explicit Type. The same happened with `Theme` in a `Control` and with `Time` in a particles node.
- Generate Function Definition on a call written in the `get` or `set` of a static variable now writes a `static func`. The function it wrote before could not be called from there.

## 0.3.0 — 2026-10-08

### Added

- **Extract Function...** With some lines of a function selected, moves them to a new function and leaves the call in their place. A dialog asks for the name and shows the whole new function and the changed one, with the colors of the script editor. The local variables the code reads become parameters, and the one it changes or declares for later is returned. If the selection ends in a `return` or in a line that assigns a variable, the call takes the place of that value; when that line assigns a class variable, the dialog lets you choose between that and a function that assigns it itself. The action is not offered when the result could behave differently.
- **Add Explicit Types.** Writes the type of every variable of the script that has none, in class variables and in the local variables of every function: `var total := 0` becomes `var total: int = 0` and `var mode := Mode.FAST` becomes `var mode: Mode = Mode.FAST`. The `:=` can be written in any way GDScript accepts, such as `: =`. A variable declared with a plain `=` gets a type only when everything the script assigns to it has that type, so `var timer = 0` is left alone if the script does `timer += delta`. Variables whose type is not known are left as they are.
- **Types from other scripts.** The actions read the scripts that a script loads into a constant with `preload` (by path, by a path relative to the script or by `uid://`), its base script and the classes with `class_name`. A value that comes from a function, a constant, a member, a signal, an enum or an inner class of another script has its type now, written as the current script has to write it: `var made := Shapes.make()` becomes `var made: Shapes.Circle = ...`, a function that returns `Array[Circle]` there gives an `Array[Shapes.Circle]` here, and `Shapes.Kind.ROUND` is a `Shapes.Kind`. This reaches every action: the parameters and the result of an extracted function, the parameters of a generated function or callback, and the type of a generated variable. When no constant of the script leads to that class, the value stays without a type. If the other script is open with unsaved changes, the tab is read instead of the file. See "Types from other scripts" in the README.
- Setting `format/max_blank_lines_inside_functions`, `1` by default: Format keeps at most that many blank lines in a row inside a function, and inside any other member that spans several lines. Blank lines inside a multiline string are never removed.

### Changed

- The dialog of Generate Custom Init Definition... shows the whole function it will generate, with the colors and the font of the script editor, as the dialog of Extract Function... does. Its filters show clearly which ones are on and which ones have no variables.
- Format spaces commas and brackets everywhere, not only in collections:
  - No space before a comma and one after it, in calls, parameters, signals, annotations, type hints and `match` patterns.
  - No spaces right inside parentheses and square brackets: `print( first )` becomes `print(first)`.
  - No space between a name and the bracket of its call or subscript: `print ("foo")` becomes `print("foo")`, `table ["key"]` becomes `table["key"]` and `func (value)` becomes `func(value)`.
  - One space between a keyword and a bracket: `if(ready)` becomes `if (ready)` and `return[1]` becomes `return [1]`.
- Format lays out arrays, dictionaries and enums as the GDScript style guide does, also when they are written on one line:
  - Arrays and dictionaries on one line: no space before a comma, one space after it and no trailing comma. An array has no spaces inside its brackets; a dictionary keeps one inside its braces, `{ "key" : value }`, and none when it is empty.
  - The colon of a dictionary key has one space before it and one after it: `"key" : value`.
  - Enums always have one item per line, so an enum written on one line is expanded.
  - On several lines: the items start below the opening bracket with one indentation level, comments get the indentation of the items, the blank lines between them are removed, and the closing bracket goes on its own line after a trailing comma.
  - The lines of an item that spans several lines, and the body of a lambda used as an item, move with it.

### Fixed

Types that the actions write:

- Generate Local Variable and Generate Function Definition write `0`, not `null`, as the placeholder value of an enum type. `var pressed: Key = null` and a `return null` in a function that returns an enum did not compile.
- A class or an enum nested in another class of the script is written with its full path, `Outer.Nested`, when it is used outside that class. The short name did not compile there.
- A function of a base script that returns one of the classes of that script is no longer taken for its native class, such as `RefCounted`, and the members of a base script given by a relative path, `extends "base.gd"`, are found.
- An instance of a script loaded with `preload` into a constant gets the name of the constant as its type, so `Snippet.new()` is a `Snippet`.
- A constant of a built-in type gets its real type: `Vector2.AXIS_X` is an `int`, not a `Vector2`. `PI`, `TAU`, `INF` and `NAN` are `float`.
- The value awaited from a signal is no longer taken for a `Signal`, and `load(path).new()` is no longer taken for a `Resource`: their type is not known.
- More values have a type: a string written on several lines, a variable with accessors on its own line (`var health = 10: set = _set_health`), a value of an enum of a nested class (`Outer.Mode.ON`), a value chosen between two values of an enum, a value that is an object or `null`, and an instance created through the path of a nested class (`Outer.Nested.new()`).

Format:

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
