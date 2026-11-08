## GDScript Extreme Tool 1.0.0

A Godot editor plugin that adds code actions to the script editor. This release runs every action from a terminal, without opening the editor, adds a skill that lets coding agents use it, and fixes two types that did not compile and the indentation of blank lines inside inner classes.

### Changelog

**Added**

* **Command line.** `addons/gdscript_extreme_tool/cli/gdsex` runs every action from a terminal, without opening the editor, edits the files in place and prints only what changed.
  * `gdsex tidy <files or folders>` adds explicit types, reorders and formats every class of each script, inner classes included, in one command. `--changed` takes the scripts changed in git.
  * The other commands run one action at a target such as `player.gd:42:take_damage`: `function`, `local`, `member`, `connect`, `init`, `extract-function`, `extract-variable`, `types`, `reorder` and `format`. `actions` lists the ones that apply there, as the Alt+Enter menu does.
  * Several commands can go in one call, one per line on the standard input. Their line numbers refer to the files as they were when the call started, and each file is written once at the end.
  * `--check` writes nothing and exits with 1 when something would change, and `--diff` prints a unified diff, so it can run in a pre-commit hook or in CI.
* **Skill for coding agents.** `gdsex install` copies a Claude Code skill to `.claude/skills/gdsex/SKILL.md`. It tells the agent to write code loosely and let `gdsex` write the types, the signatures and the layout, to spend fewer tokens.

**Changed**

* The actions no longer compile the base script of a class to know which engine class it extends: they read the chain of `extends` in the source. Compiling a script runs the initializers of its static variables.

**Fixed**

* A value with several subscripts gets the type of its last one. With `var seconds: Array[PackedFloat32Array]`, Add Explicit Types wrote `var to_middle: PackedFloat32Array = seconds[from][middle]`, which did not compile; it is now a `float`. When the type of a level is not known, as in an `Array[Array]`, the variable is left without a type.
* A property of an engine class that accepts several classes gets the class it is declared with. `var material := (piece.mesh as BoxMesh).material` became `var material: BaseMaterial3D, ShaderMaterial = ...`, which did not compile; it is now a `Material`.
* The blank lines that Format and Reorder write inside an inner class are empty, as they are outside it. They kept the indentation of the class, so a line with only a tab was left after `extends` and between the members.

### Actions

* **Generate Function Definition**: creates the function for an undefined call, with parameter names and types inferred from the arguments and the return type inferred from where the call is used. A call on an object or a class of another script creates the function in that script.
* **Generate Local Variable**: declares the undefined identifier under the caret at the start of its scope, typed from how it is used.
* **Generate Class Variable**: declares the undefined identifier as a member variable of the class.
* **Generate Connected Function**: on a signal, writes `signal.connect(_on_signal)` and creates the callback with the signal's parameters.
* **Generate Default Init Definition**: creates `_init` with one parameter for each private variable of the class and assigns them. It is not offered when the class already has `_init` or extends `Node` or `Resource`, because Godot calls their `_init` without arguments.
* **Generate Custom Init Definition...**: opens a dialog to choose the name of the function and which variables become parameters: private, public or exported.
* **Add Explicit Types**: writes the type of every variable of the script that has none: `var total := 0` becomes `var total: int = 0`.
* **Extract Function...**: moves the selected lines to a new function and leaves the call in their place. The variables the code reads become parameters and the one it changes is returned. It is not offered when the result could behave differently.
* **Extract Variable...**: declares a variable with the value under the caret and leaves its name in its place.
* **Reorder Class Members**: sorts the members of the class under the caret into a configurable order.
* **Format Class Members**: normalizes blank lines, lays out arrays, dictionaries and enums as the GDScript style guide does, and spaces commas and brackets. It never changes the order of the code.

Only the actions that apply to the caret position are shown, and each one is a single undo step. Inner classes, lambdas and nested blocks are handled as their own scopes.

The actions read the other scripts your script uses (loaded with `preload`, the base script, classes with `class_name`), so the types they write are the real ones, written as your script has to write them: `var made: Shapes.Circle = Shapes.make()`.

### Command line

```bash
sh addons/gdscript_extreme_tool/cli/gdsex tidy scripts/
```

```
scripts/player.gd typed 12, reordered, formatted
scripts/enemy.gd formatted
4 unchanged
```

* It finds Godot by itself: `$GODOT`, then `godot`, `godot4` and `Godot` in the `PATH`, then `/Applications/Godot.app`.
* It does not run the code of your project: Godot starts without a scene tree, so autoloads are not created, and the scripts it needs are read, not loaded.
* It uses the same settings as the editor, from `project.godot`.
* The exit code is 0 when everything was done, 1 when something failed or `--check` found changes, 2 for a wrong command and 3 when Godot or the project cannot be found.

Every command and option is in "Command line and AI agents" in the README.

### Configuration

Ten settings in **Project > Project Settings**, section **GDScript Extreme Tool**: naming formats for generated parameters, signal callbacks and init functions, blank lines used by the formatter, and the member order used when reordering. Only the values you change are saved in `project.godot`, so they are shared with the project and survive plugin updates.

To open the actions, press Alt+Enter (Option+Return on macOS) or use the **Script Extreme Tools** submenu of the context menu. To change the shortcut, search for **Show Code Actions** in **Editor Settings > Shortcuts**.

### Footprint

The plugin registers nothing global besides its settings section and its editor shortcut: no `class_name`, no autoloads and no input actions. Every type it declares is prefixed with `GDSEx`, so a global class of your project cannot shadow one of them.

The command line writes only the scripts it changes, except `gdsex install`, which copies the skill to `.claude/skills/gdsex/` and `gdsex` to `~/.local/bin` when that folder is in your `PATH`.

### Requirements

Godot 4.4 or later. Developed and tested on Godot 4.7.2; versions between 4.4 and 4.7 are untested.

The command line needs `sh`. On Windows that means Git Bash or another POSIX shell, which has not been tested yet.

### Installation

1. Unzip `gdscript_extreme_tool-1.0.0.zip` into your project. It contains only `addons/gdscript_extreme_tool`.
2. Enable **GDScript Extreme Tool** in **Project > Project Settings > Plugins**.
3. Optionally, run `sh addons/gdscript_extreme_tool/cli/gdsex install` to add the skill for Claude Code.

The folder must keep its name. To upgrade from 0.4.0, replace the folder.

### Known limitations

* The command line reads and writes the files on disk. If the editor has the same script open with unsaved changes, Godot asks which version to keep when you go back to it.
* Only functions are created in other scripts. Variables are always declared in the current script.
* In the editor, a function created in another script is left unsaved in its tab, and Godot marks the call as an error until you save it. It is not offered when Godot is set to open scripts in an external editor.
* Extract Variable takes numbers, texts, `true` and `false`, calls and nodes. Operations without brackets (`a + b`) and member reads (`player.health`) are not offered, and it replaces the value under the caret, not every equal value.
* Extract Variable is not offered on a call whose result cannot be kept: a function that returns nothing, a function that waits with `await`, and the `range(...)` of a `for`.
* `load()`, `get_script()`, scripts built at runtime and autoloads are not followed to find a type, and the plugin never adds `preload` constants on its own.
* Add Explicit Types does not look at how other scripts use the script it runs on.
* In the editor, reordering, formatting and the init actions apply to the class under the caret and do not enter its inner classes. `gdsex tidy` does.
* One shortcut opens the menu; the individual actions have no shortcuts of their own.

Full list in the [changelog](https://github.com/alejandro61299/GDScriptExtremeToolProject/blob/v1.0.0/CHANGELOG.md).
