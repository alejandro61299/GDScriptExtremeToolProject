# GDScript Extreme Tool

A Godot editor plugin that adds code actions to the script editor's context menu: it generates methods, variables and signal callbacks from the code under the caret, reorders the members of a class and formats it.

## Actions

Right-click in the script editor. Only the actions that apply to the caret position are shown, and each one is a single undo step.

| Action | What it does |
|---|---|
| Generate Method Stub | Creates the method for an undefined call, with parameter names and types inferred from the arguments and the return type inferred from where the call is used. |
| Generate Local Variable | Declares the undefined identifier under the caret at the start of its scope, typed from how it is used. |
| Generate Class Variable | Declares the undefined identifier as a member variable of the class. |
| Generate Connected Function | On a signal, writes `signal.connect(_on_signal)` and creates the callback with the signal's parameters. |
| Reorder Class Members | Sorts the members of the class under the caret: signals, constants, static variables, enums, exports, onready, public and private variables, inner classes, static methods, `_init`, engine callbacks, public and private methods. |
| Format Class Members | Normalizes blank lines between members and around comments, puts the closing bracket of multiline arrays, dictionaries and lambda arguments on its own line, adds trailing commas, and removes extra spaces between tokens and at the end of lines. It never changes the order of the code. |

Inner classes, lambdas and nested blocks are handled as their own scopes. Reordering and formatting apply to the class under the caret and do not enter its inner classes.

## Requirements

Godot 4.4 or later: the plugin relies on typed dictionaries and editor context menu plugins. It is developed and tested on Godot 4.7.2; versions between 4.4 and 4.7 are untested.

## Installation

1. Copy the `addons/gdscript_extreme_tool` folder into the `addons` folder of your project. Release archives and Asset Library downloads contain only that folder.
2. Open **Project > Project Settings > Plugins** and enable **GDScript Extreme Tool**.

The folder must keep its name: the plugin loads its own scripts from `res://addons/gdscript_extreme_tool`.

## Configuration

Edit the constants in `addons/gdscript_extreme_tool/settings.gd`:

| Constant | Default | Meaning |
|---|---|---|
| `GENERATED_PARAM_FORMAT` | `p_{name}` | Name of a generated parameter when the argument has a name. |
| `FALLBACK_PARAM_FORMAT` | `param_{index}` | Name of a generated parameter otherwise. |
| `GENERATED_SIGNAL_CALLBACK_FORMAT` | `_on_{name}` | Name of a generated signal callback. |
| `BLANK_LINES_AROUND_METHODS_AND_CLASSES` | `2` | Blank lines around methods and inner classes. |
| `BLANK_LINES_BETWEEN_MEMBER_CATEGORIES` | `1` | Blank lines between members of different categories. |
| `MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY` | `1` | Blank lines kept between members of the same category. |
| `MAX_BLANK_LINES_OUTSIDE_MEMBERS` | `1` | Blank lines kept around the comments at the start and the end of a class. |
| `CLASS_MEMBER_ORDER` | see file | Order used by Reorder Class Members. |

Updating the plugin replaces this file, so keep a note of your changes.

## Footprint in your project

The plugin registers nothing global: no `class_name`, no autoloads, no project settings and no input actions. Its scripts reference each other with `preload` constants, so they do not show up in autocompletion or in the node and resource dialogs.

Every type the plugin declares is prefixed with `GDSEx`, so a global class of your project cannot shadow one of them.

## Development

This repository is a Godot project with the plugin in `addons/gdscript_extreme_tool`. The tests run headless on a real `CodeEdit`:

```
godot --headless --path . --script res://tests/run_tests.gd
```

`addons/gdscript_extreme_tool/analysis/builtin_types.gd` is generated from the engine's API dump. Regenerate it when targeting a new Godot version:

```
godot --dump-extension-api
godot --headless --path . --script res://tools/generate_builtin_types.gd -- extension_api.json
```

To build a release archive, set the version in `addons/gdscript_extreme_tool/plugin.cfg`, commit, tag and archive the tag. `.gitattributes` marks everything except the addon as `export-ignore`, so the archive contains only `addons/gdscript_extreme_tool`:

```
git tag v0.1.0
git archive --format=zip --output=gdscript_extreme_tool-0.1.0.zip v0.1.0
```

## License

MIT. See [LICENSE](LICENSE).
