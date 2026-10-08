# GDScript Extreme Tool

<img src="icon.svg" width="128" alt="GDScript Extreme Tool icon">

A Godot editor plugin that adds code actions to the script editor's context menu: it generates functions, variables, signal callbacks and init functions from the code under the caret, writes the types of the variables, extracts functions, reorders the members of a class and formats it.

## Actions

Press **Alt+Enter** (**Option+Return** on macOS) in the script editor to open the actions at the caret, or right-click and open the **Script Extreme Tools** submenu. Only the actions that apply to the caret position are shown, and each one is a single undo step.

The script is analyzed only when you open that menu, so a plain right-click costs nothing. To change the shortcut, search for **Show Code Actions** in **Editor Settings > Shortcuts**.

| Action | What it does |
|---|---|
| Generate Function Definition | Creates the function for an undefined call, with parameter names and types inferred from the arguments and the return type inferred from where the call is used. A call on an object or a class of another script creates the function in that script: see "Functions in other scripts". |
| Generate Local Variable | Declares the undefined identifier under the caret at the start of its scope, typed from how it is used. |
| Generate Class Variable | Declares the undefined identifier as a member variable of the class. |
| Generate Connected Function | On a signal, writes `signal.connect(_on_signal)` and creates the callback with the signal's parameters. |
| Generate Default Init Definition | Creates `_init` with one parameter for each private variable of the class and assigns them. It is not offered when the class already has `_init` or extends `Node` or `Resource`, because Godot calls their `_init` without arguments. |
| Generate Custom Init Definition... | Opens a dialog to choose the name of the function and which variables become parameters: private, public or exported. It shows the function as you change it, with the colors of the script editor, and marks a name that cannot be used. |
| Add Explicit Types | Writes the type of every variable of the script that has none, in class variables and in the local variables of every function: `var total := 0` becomes `var total: int = 0`. It does not matter how the `:=` is spaced. A variable declared with a plain `=` gets a type only when everything the script assigns to it has that type, so `var timer = 0` is left alone if the script does `timer += delta`. Variables whose type is not known are left as they are. |
| Extract Function... | With some lines of a function selected, moves them to a new function and leaves the call in their place. A dialog asks for the name and shows the whole new function and the changed one, with the colors of the script editor. The variables the code reads become parameters and the one it changes is returned; if the last line is a `return` or assigns a variable, the call takes its place. When the last line assigns a class variable you choose whether the function assigns it or returns the value. It is not offered when the result could behave differently: a `return` in the middle, a `break` of an outer loop or more than one variable to return. |
| Reorder Class Members | Sorts the members of the class under the caret: signals, constants, static variables, enums, exports, onready, public and private variables, inner classes, static functions, `_init`, engine callbacks, public and private functions. |
| Format Class Members | Normalizes blank lines between members, around comments and inside functions, lays out arrays, dictionaries and enums as the GDScript style guide does, puts the closing parenthesis of a multiline lambda argument on its own line, spaces commas and brackets as the guide does (`print(first, second)`, `table["key"]`, `if (ready)`), and removes extra spaces between tokens and at the end of lines. It never changes the order of the code. |

Inner classes, lambdas and nested blocks are handled as their own scopes. Reordering, formatting and the init actions apply to the class under the caret and do not enter its inner classes. Add Explicit Types applies to the whole script, inner classes included, wherever the caret is.

Add Explicit Types does not look at how other scripts use the script it runs on. If another script assigns a value of a different type to one of its class variables, that assignment will need the old declaration back.

## Types from other scripts

The actions read the other scripts your script uses, so the types they write are the real ones:

- Scripts loaded into a constant with `preload`, by path, by a path relative to the script or by `uid://`.
- The base script, given as `extends "base.gd"` or as a class with `class_name`, and the bases above it.
- Classes with `class_name`.

A type declared in another script is written the way your script has to write it. If `shapes.gd` has a function that returns its inner class `Circle`, and your script loads it with `const Shapes = preload("shapes.gd")`, Add Explicit Types turns the first line into the second:

```gdscript
var made := Shapes.make()
var made: Shapes.Circle = Shapes.make()
```

Every action uses the same name: the parameters and the result of an extracted function, the parameters of a generated function or signal callback, and the type of a generated variable. Enums work the same way: `Shapes.Kind.ROUND` is a `Shapes.Kind`.

Things to know:

- When no constant of your script leads to that class, the value is left without a type. The plugin does not add `preload` constants on its own.
- If the other script is open in a tab with unsaved changes, the tab is read instead of the file. Godot compiles against the saved file, so it reports an error in your script until you save the other one.
- `load()`, `get_script()`, scripts built at runtime and autoloads are not followed.

## Functions in other scripts

Generate Function Definition also works on a call to another script. With the caret on `scaled_area` here:

```gdscript
const Shapes = preload("shapes.gd")

var shapes: Shapes = Shapes.new()


func run(circle: Shapes.Circle) -> void:
	var area: float = shapes.scaled_area(circle, 2.0)
```

the menu shows **Generate Function Definition in shapes.gd**. It opens the tab of `shapes.gd`, adds this after the last function or variable of the class and selects the body:

```gdscript
func scaled_area(p_circle: Circle, param_1: float) -> float:
	return 0.0
```

- The function goes to the class of the object the call is made on: the script or one of its inner classes. It is `static` when the call is on the class (`Shapes.missing()`) and not on an instance.
- The types are written the way that script has to write them: `Circle` and not `Shapes.Circle`. A class that script has no name for leaves the parameter without a type; the plugin does not add `preload` constants to it.
- The other script is changed in its tab and it is not saved. Godot compiles against the saved file, so the call stays marked as an error until you save that tab. Undo in that tab removes the function, and the back button of the script editor returns to the call.
- It works on any script the plugin can read, also one inside `res://addons`. What you add to an addon you did not write is lost when you update it.
- It is not offered for a class of the engine, for `super`, or when Godot is set to open scripts in an external editor.

## Requirements

Godot 4.4 or later: the plugin relies on typed dictionaries and editor context menu plugins. It is developed and tested on Godot 4.7.2; versions between 4.4 and 4.7 are untested.

## Installation

1. Copy the `addons/gdscript_extreme_tool` folder into the `addons` folder of your project. Release archives and Asset Library downloads contain only that folder.
2. Open **Project > Project Settings > Plugins** and enable **GDScript Extreme Tool**.

The folder must keep its name: the plugin loads its own scripts from `res://addons/gdscript_extreme_tool`.

## Configuration

Open **Project > Project Settings** and look for the **GDScript Extreme Tool** section. Changes apply the next time an action runs.

| Setting | Default | Meaning |
|---|---|---|
| `naming/generated_param_format` | `p_{name}` | Name of a generated parameter when the argument has a name. |
| `naming/fallback_param_format` | `param_{index}` | Name of a generated parameter otherwise. |
| `naming/generated_signal_callback_format` | `_on_{name}` | Name of a generated signal callback. |
| `naming/alternative_init_function_name` | `initialize` | Name proposed for a custom init function when `_init` is not suitable. |
| `format/blank_lines_around_functions_and_classes` | `2` | Blank lines around functions and inner classes. |
| `format/blank_lines_between_member_categories` | `1` | Blank lines between members of different categories. |
| `format/max_blank_lines_inside_member_category` | `1` | Blank lines kept between members of the same category. |
| `format/max_blank_lines_outside_members` | `1` | Blank lines kept around the comments at the start and the end of a class. |
| `format/max_blank_lines_inside_functions` | `1` | Blank lines kept in a row inside a function or any other member that spans several lines. |
| `order/class_member_order` | see `plugin_project_settings.gd` | Order used by Reorder Class Members. A category missing from the list goes last. |

Only the values you change are saved, in the `[gdscript_extreme_tool]` section of `project.godot`, so they are shared with the project and survive plugin updates. You can also edit that section by hand:

```ini
[gdscript_extreme_tool]

naming/generated_param_format="arg_{name}"
format/blank_lines_around_functions_and_classes=1
```

The defaults are the `DEFAULT_` constants in `addons/gdscript_extreme_tool/plugin_project_settings.gd`. A value of the wrong type is ignored and its default is used.

## Footprint in your project

The plugin registers nothing global besides its own section in Project Settings: no `class_name`, no autoloads and no input actions. Its scripts reference each other with `preload` constants, so they do not show up in autocompletion or in the node and resource dialogs.

Every type the plugin declares is prefixed with `GDSEx`, so a global class of your project cannot shadow one of them.

## Development

This repository is a Godot project with the plugin in `addons/gdscript_extreme_tool`. The tests run headless on a real `CodeEdit`:

```
godot --headless --path . --script res://tests/run_tests.gd
```

Some cases use the scripts in `tests/fixtures`, and two of those declare a global class. Godot has to know them: open the project once in the editor, or run `godot --headless --path . --import`. Until then the cases that need them are reported as pending.

`addons/gdscript_extreme_tool/analysis/builtin_types.gd` is generated from the engine's API dump. Regenerate it when targeting a new Godot version:

```
godot --dump-extension-api
godot --headless --path . --script res://tools/generate_builtin_types.gd -- extension_api.json
```

To build a release archive, set the version in `addons/gdscript_extreme_tool/plugin.cfg`, add its notes to `CHANGELOG.md`, commit, tag and archive the tag. `.gitattributes` marks everything except the addon as `export-ignore`, so the archive contains only `addons/gdscript_extreme_tool`:

```
git tag v0.3.0
git archive --format=zip --output=gdscript_extreme_tool-0.3.0.zip v0.3.0
```

## License

MIT. See [LICENSE](LICENSE).

The icon is based on the Godot Engine logo by Andrea Calabró, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
