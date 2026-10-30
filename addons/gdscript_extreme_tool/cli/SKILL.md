---
name: gdsex
description: Write, refactor and tidy GDScript (.gd) in this Godot project with the gdsex CLI instead of typing the code yourself - one command types, sorts and formats a whole script; others create typed functions, variables, signal callbacks and _init, and extract functions or variables. Use it whenever you create or change .gd files.
---

# gdsex

Run `gdsex <command> <target> [options]` from anywhere inside the project. If `gdsex` is not found, run `sh addons/gdscript_extreme_tool/cli/gdsex` instead. It edits the files in place and prints only what you need.

## The one to remember

`gdsex tidy <files or folders>` writes the type of every variable, sorts the members of every class and formats the script as the style guide says. `gdsex tidy --changed` does it to every .gd file changed in git. Run it once you have finished a file; it never changes what the code does.

## Targets

`file.gd` the whole script · `file.gd:42` line 42 · `file.gd:30-38` lines 30 to 38 · `file.gd:42:text` that text on line 42, also found up to 20 lines away if it moved · `file.gd:text` its only occurrence in the file · `folder/` every .gd inside, except `addons/` · `-` code from stdin, the result goes to stdout. Lines start at 1, as Read shows them. Quote a target that has spaces.

## Commands

- `function <call>` creates the missing function with typed parameters and return type, also in another script. `function file.gd` creates every missing one.
- `local <name>` / `member <name>` declare an undefined name as a local / class variable, typed from its use.
- `connect <signal>` writes `signal.connect(_on_signal)` and the callback with the signal's parameters.
- `init <line>` writes `_init` assigning the private variables. `--name n`, `--vars a,b`, `--all-vars`.
- `extract-function <lines> --name n` moves the lines to a new function and leaves the call.
- `extract-variable <value> --name n` names a value. `--place block|function|class|script`, `--const`, `--static`, `--private`, `--public`, `--onready`.
- `types`, `reorder`, `format` are the three parts of `tidy`.
- `actions <target>` lists the commands that apply there.

## Spend fewer tokens

- Write loosely: `:=` and untyped `var`, calls to functions that do not exist yet, members in any order, any blank lines. Then `gdsex function file.gd` and `gdsex tidy file.gd` write the signatures, types and layout.
- Never retype code to move it: use `extract-function` and `extract-variable`.
- Put several commands in one call. Their line numbers refer to the files before the call:

```bash
gdsex <<'EOF'
function player.gd:42:take_damage
member player.gd:50:speed
tidy player.gd
EOF
```

- Run `tidy` after your last edit of a file: gdsex rewrites the file, so edit it again only after reading the lines it printed.
- `tidy` prints the variables it could not type (`untyped 2: data 40, loaded 52`); type those yourself if they matter.

## Output

`path summary`, then `N<TAB>line` for the lines you need, `! warning` when the code would run at another moment, `error: ...` with exit code 1. Options for the whole call: `-q` headers only, `--diff` a unified diff, `--check` change nothing and exit 1 if something would change, `--print` print the files instead of writing them.
